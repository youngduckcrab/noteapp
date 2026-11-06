// lib/src/export/export_memory.dart — ExportMemoryLedger and the JPEG byte cache
// (m5-7/06-pdf 6.2.10). Internal (not in the barrel), web-safe.
//
// One ledger per export counts the image memory Dart holds at once: RGBA made by the resolver
// (decode · rasters — until its part is sent), read image bytes `encoded` (slow path: until the
// decode ends; fast path JPEG: until its part is sent) and the JPEG `cache`. Their sum stays
// ≤ PdfTuning.exportImageTempBytes (16 MiB — contract 7.4.5): before anything is held the
// ledger evicts cache entries oldest first (the cache only uses the room that is left — it can
// shrink to 0). Only a slow path input outside M-3 (> 12 MiB) goes over; that is counted in
// [overBudget] (CP-PDF-14 ②). The native worker copy (`copy`, CP-PDF-14 ①) is held apart with
// [holdCopy]: it is outside the budget, [makeRoom], [peakBytes] and [overBudget] and only shows
// in [peakCopyBytes] / [peakTotalBytes]. Integer additions only — kept in release builds.
import 'dart:collection';
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;

import '../tuning.dart';

/// The budget kinds (6.2.10 ⓐ ⓑ ⓒ).
enum ExportMemoryKind { rgba, encoded, cache }

/// What one [ExportMemoryLedger.hold] / [ExportMemoryLedger.holdCopy] took. Releasing twice is a
/// no-op.
final class ExportMemoryHandle {
  ExportMemoryHandle._(this.kind, this.bytes);

  /// null = the native worker copy (outside the budget).
  final ExportMemoryKind? kind;
  final int bytes;
  bool _released = false;
  bool get isReleased => _released;

  @override
  String toString() =>
      'ExportMemoryHandle(${kind?.name ?? 'copy'}, $bytes B'
      '${_released ? ', released' : ''})';
}

/// Drops the oldest cache entry (releasing its handle); false when the cache is empty.
typedef ExportCacheEvictor = bool Function();

final class ExportMemoryLedger {
  ExportMemoryLedger({this.budgetBytes = PdfTuning.exportImageTempBytes});

  final int budgetBytes;

  /// Set by [ExportJpegCache] (one cache per ledger).
  ExportCacheEvictor? _evictor;

  final Map<ExportMemoryKind, int> _bytes = {
    for (final k in ExportMemoryKind.values) k: 0,
  };
  int _held = 0, _count = 0, _copy = 0;
  int _peakBytes = 0, _peakCount = 0, _overBudget = 0;
  int _peakCopyBytes = 0, _peakTotalBytes = 0;

  /// rgba + encoded + cache held now.
  int get heldBytes => _held;
  int bytesOf(ExportMemoryKind kind) => _bytes[kind]!;

  /// Budget handles held now.
  int get heldCount => _count;
  int get copyBytes => _copy;

  /// The highest rgba + encoded + cache sum.
  int get peakBytes => _peakBytes;

  /// The most budget handles held at once.
  int get peakCount => _peakCount;

  /// How many times the budget sum went from ≤ [budgetBytes] to above it.
  int get overBudget => _overBudget;
  int get peakCopyBytes => _peakCopyBytes;

  /// The highest sum of all four kinds (budget + copy).
  int get peakTotalBytes => _peakTotalBytes;

  /// Whether [bytes] more fit in the budget once the whole cache is evicted.
  bool fitsWithoutCache(int bytes) =>
      _held - bytesOf(ExportMemoryKind.cache) + bytes <= budgetBytes;

  /// Evicts cache entries, oldest first, until held + [bytes] ≤ [budgetBytes] or the cache is
  /// empty.
  void makeRoom(int bytes) {
    final evict = _evictor;
    if (evict == null) return;
    while (_held + bytes > budgetBytes && bytesOf(ExportMemoryKind.cache) > 0) {
      if (!evict()) break;
    }
  }

  /// Takes [bytes] of [kind] after [makeRoom] — except for `cache`, which never evicts (the
  /// cache makes its own room, [ExportJpegCache.offer]).
  ExportMemoryHandle hold(ExportMemoryKind kind, int bytes) {
    if (bytes < 0) throw ArgumentError.value(bytes, 'bytes');
    if (kind != ExportMemoryKind.cache) makeRoom(bytes);
    final before = _held;
    _held += bytes;
    _bytes[kind] = _bytes[kind]! + bytes;
    _count++;
    if (before <= budgetBytes && _held > budgetBytes) _overBudget++;
    if (_held > _peakBytes) _peakBytes = _held;
    if (_count > _peakCount) _peakCount = _count;
    _notePeakTotal();
    return ExportMemoryHandle._(kind, bytes);
  }

  /// The native worker copy of a part being sent (outside the budget — CP-PDF-14 ①).
  ExportMemoryHandle holdCopy(int bytes) {
    if (bytes < 0) throw ArgumentError.value(bytes, 'bytes');
    _copy += bytes;
    if (_copy > _peakCopyBytes) _peakCopyBytes = _copy;
    _notePeakTotal();
    return ExportMemoryHandle._(null, bytes);
  }

  void release(ExportMemoryHandle handle) {
    if (handle._released) return;
    handle._released = true;
    final kind = handle.kind;
    if (kind == null) {
      _copy -= handle.bytes;
      return;
    }
    _held -= handle.bytes;
    _bytes[kind] = _bytes[kind]! - handle.bytes;
    _count--;
  }

  void _notePeakTotal() {
    final total = _held + _copy;
    if (total > _peakTotalBytes) _peakTotalBytes = total;
  }

  @override
  String toString() =>
      'ExportMemoryLedger(held $_held B / $budgetBytes B, peak $_peakBytes B, '
      'count $_count (peak $_peakCount), overBudget $_overBudget, copy $_copy B '
      '(peak $_peakCopyBytes B), peakTotal $_peakTotalBytes B)';
}

/// The fast path JPEG bytes kept for reuse in the same export (6.2.4 · 6.2.10 ②): LRU by asset,
/// counted as `cache`, only in the room the ledger has left. An entry being sent in a part is
/// taken out ([take]) and counted once as `encoded` by its holder; it comes back with [offer]
/// after the part was sent.
final class ExportJpegCache {
  ExportJpegCache(this.ledger) {
    if (ledger._evictor != null) {
      throw StateError('The ledger already has a cache');
    }
    ledger._evictor = evictOldest;
  }

  final ExportMemoryLedger ledger;
  final LinkedHashMap<core.AssetId, ({Uint8List bytes, ExportMemoryHandle h})>
  _entries = LinkedHashMap();

  int get length => _entries.length;
  Iterable<core.AssetId> get assetIds => _entries.keys;
  bool contains(core.AssetId id) => _entries.containsKey(id);

  /// Removes [id] from the cache (its `cache` bytes are released) and returns its bytes; the
  /// caller holds them as `encoded` while they are sent. null = not cached.
  Uint8List? take(core.AssetId id) {
    final entry = _entries.remove(id);
    if (entry == null) return null;
    ledger.release(entry.h);
    return entry.bytes;
  }

  /// Keeps [bytes] for [id] as the newest entry when they fit in the budget once older entries
  /// are evicted; otherwise drops them (false).
  bool offer(core.AssetId id, Uint8List bytes) {
    final old = _entries.remove(id);
    if (old != null) ledger.release(old.h);
    if (!ledger.fitsWithoutCache(bytes.length)) return false;
    while (ledger.heldBytes + bytes.length > ledger.budgetBytes) {
      if (!evictOldest()) return false;
    }
    _entries[id] = (
      bytes: bytes,
      h: ledger.hold(ExportMemoryKind.cache, bytes.length),
    );
    return true;
  }

  bool evictOldest() {
    if (_entries.isEmpty) return false;
    final id = _entries.keys.first;
    ledger.release(_entries.remove(id)!.h);
    return true;
  }

  void clear() {
    while (evictOldest()) {}
  }
}
