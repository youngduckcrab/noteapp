// lib/src/record/draft_writer.dart — m5-7/06-pdf 6.8.5 (D13, M-2; v2.1 PDF-M5, review S-5).
// Internal.
//
// Writes the web recorder's chunks to RecordingDraftStore in order, ONE append at a time:
//  - FIFO queue; activeMs is read when each append starts.
//  - While paused (user, hidden tab or storage backlog) an EMPTY chunk goes out every
//    keepAliveMs, only when nothing is queued — CORE then only refreshes activeMs / updatedAt,
//    so the recording tab's draft always looks 'recently updated' and another tab's
//    pendingDrafts() leaves it out (6.10.2).
//  - An append that throws (blob write failure; a commit retry is not an exception — it just
//    does not complete) keeps the chunk as 'unsaved' at the head and reports storageFailed;
//    the next chunk (or the next keep-alive tick, or drain) writes the unsaved chunks first,
//    and the first success reports storageRecovered.
//  - queued + unsaved bytes over backlogMaxBytes (8 MiB — 7.4.5) reports backlogFull once per
//    crossing; the service then pauses with reason storageBacklog.
//  - StateError (unknown draftId: another tab recovered or discarded the draft) reports
//    draftLost, drops everything in memory and writes nothing more.
//  - drain(): waits for the append in flight, writes what is left once more and returns what
//    still could not be written (the stop path joins it after readAll — 6.6.3).
import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;

import '../tuning.dart';

enum DraftWriterSignal {
  storageFailed,
  storageRecovered,
  backlogFull,
  draftLost,
}

final class DraftWriter {
  DraftWriter({
    required this.drafts,
    required this.draftId,
    required this.activeMs,
    required int keepAliveMs,
    this.backlogMaxBytes = MediaTuning.webMemoryBacklogMaxBytes,
    this.onSignal,
  }) : _keepAlive = Duration(milliseconds: keepAliveMs);

  final core.RecordingDraftStore drafts;
  final String draftId;

  /// Read when each append starts (the recording clock).
  final int Function() activeMs;
  final Duration _keepAlive;
  final int backlogMaxBytes;
  final void Function(DraftWriterSignal signal, Object? error)? onSignal;

  final Queue<_Chunk> _pending = Queue();
  Future<void>? _pumping;
  Timer? _keepAliveTimer;
  Object? _error;
  bool _lost = false, _closed = false, _overBacklog = false;
  int _queuedBytes = 0, _unsavedBytes = 0;

  /// Bytes waiting that were never tried.
  int get queuedBytes => _queuedBytes;

  /// Bytes whose append failed at least once (still in memory, written first next time).
  int get unsavedBytes => _unsavedBytes;

  /// queued + unsaved — what the 8 MiB limit counts.
  int get backlogBytes => _queuedBytes + _unsavedBytes;

  /// The last storage error while unsaved chunks remain; null after a success.
  Object? get error => _error;

  /// The draft was recovered or discarded elsewhere (StateError); nothing more is written.
  bool get isLost => _lost;

  /// Nothing in flight and nothing waiting.
  bool get isIdle => _pumping == null && _pending.isEmpty;

  /// Keep-alive empty chunks every keepAliveMs while true.
  bool get paused => _keepAliveTimer != null;
  set paused(bool value) {
    if (value == paused) return;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = value && !_lost && !_closed
        ? Timer.periodic(_keepAlive, (_) => _tick())
        : null;
  }

  /// Queues [chunk] (split at 4 MiB) and starts writing. Ignored once lost or closed.
  void add(Uint8List chunk) {
    if (_lost || _closed || chunk.isEmpty) return;
    for (var o = 0; o < chunk.length; o += MediaTuning.draftChunkMaxBytes) {
      final end = o + MediaTuning.draftChunkMaxBytes < chunk.length
          ? o + MediaTuning.draftChunkMaxBytes
          : chunk.length;
      final part = o == 0 && end == chunk.length
          ? chunk
          : Uint8List.sublistView(chunk, o, end);
      _pending.add(_Chunk(part));
      _queuedBytes += part.length;
    }
    _checkBacklog();
    _start();
  }

  /// Waits for the append in flight, writes the rest once more and returns the chunks that are
  /// still not written, in order (empty when all are durable or the draft was lost). No time
  /// limit: while CORE retries a commit this waits (06-pdf 6.8.5).
  Future<List<Uint8List>> drain() async {
    while (_pumping != null) {
      await _pumping;
    }
    if (_lost || _closed) return const [];
    if (_pending.isNotEmpty) await _start();
    return [for (final c in _pending) c.bytes];
  }

  /// Stops the keep-alive and drops what is in memory. An append in flight still completes;
  /// its result is ignored.
  void close() {
    _closed = true;
    paused = false;
    _dropAll();
  }

  Future<void> _start() {
    final running = _pumping;
    if (running != null || _lost || _closed) return running ?? Future.value();
    final pump = _pump();
    _pumping = pump;
    return pump;
  }

  Future<void> _pump() async {
    try {
      while (_pending.isNotEmpty && !_lost && !_closed) {
        final chunk = _pending.first;
        try {
          await drafts.append(draftId, chunk.bytes, activeMs: activeMs());
        } on StateError catch (e) {
          _lose(e);
          return;
        } catch (e) {
          if (_closed) return;
          if (!chunk.failed) {
            chunk.failed = true;
            _queuedBytes -= chunk.bytes.length;
            _unsavedBytes += chunk.bytes.length;
          }
          final first = _error == null;
          _error = e;
          if (first) onSignal?.call(DraftWriterSignal.storageFailed, e);
          return;
        }
        if (_closed) return;
        _pending.removeFirst();
        if (chunk.failed) {
          _unsavedBytes -= chunk.bytes.length;
        } else {
          _queuedBytes -= chunk.bytes.length;
        }
        _checkBacklog();
        if (_error != null && _unsavedBytes == 0) {
          _error = null;
          onSignal?.call(DraftWriterSignal.storageRecovered, null);
        }
      }
    } finally {
      _pumping = null;
    }
  }

  void _tick() {
    if (_lost || _closed || _pumping != null) return;
    if (_pending.isNotEmpty) {
      _start(); // retry the unsaved chunks
      return;
    }
    final pump = _keepAliveAppend();
    _pumping = pump;
  }

  /// One empty chunk (only refreshes activeMs / updatedAt). A failure other than StateError
  /// loses no audio and is left to the next tick.
  Future<void> _keepAliveAppend() async {
    try {
      await drafts.append(draftId, Uint8List(0), activeMs: activeMs());
    } on StateError catch (e) {
      _lose(e);
    } catch (_) {
      // nothing to keep
    } finally {
      _pumping = null;
    }
  }

  void _checkBacklog() {
    final over = backlogBytes > backlogMaxBytes;
    if (over && !_overBacklog) {
      _overBacklog = true;
      onSignal?.call(DraftWriterSignal.backlogFull, null);
    } else if (!over) {
      _overBacklog = false;
    }
  }

  void _lose(StateError e) {
    _lost = true;
    paused = false;
    _dropAll();
    onSignal?.call(DraftWriterSignal.draftLost, e);
  }

  void _dropAll() {
    _pending.clear();
    _queuedBytes = 0;
    _unsavedBytes = 0;
    _error = null;
  }
}

final class _Chunk {
  _Chunk(this.bytes);
  final Uint8List bytes;
  bool failed = false;
}
