// Internal (not exported). The live subscription (6.6.1 last steps, 6.6.4): watchChunks from
// the cursor, handing every batch to the engine (which applies it on its serial executor),
// rolled over to a fresh query after listenerRolloverChunks chunks or
// listenerRolloverInterval. A stream error or end goes to [onError] (→ catchingUp, 6.8.2).
import 'dart:async';

import '../backend/remote_chunk.dart';
import '../backend/sync_backend.dart';
import '../common/server_cursor.dart';
import '../config.dart';

final class LiveListener {
  LiveListener({
    required this.backend,
    required this.config,
    required this.cursor,
    required this.onBatch,
    required this.onError,
  });

  final SyncBackend backend;
  final SyncConfig config;

  /// The pipeline cursor (DownloadPipeline.cursor) at the time a query opens.
  final ServerCursor? Function() cursor;

  /// Every batch, initial result included, in arrival order. Not awaited: the engine queues
  /// it (duplicates across the rollover overlap are dropped by the session LRU).
  final void Function(List<RemoteChunk> batch) onBatch;

  /// The query failed or ended; the listener has stopped.
  final void Function(Object error) onError;

  StreamSubscription<List<RemoteChunk>>? _subscription;
  Timer? _timer;
  int _chunksSinceOpen = 0;
  bool _initialPending = false;
  int _rollovers = 0;

  bool get isRunning => _subscription != null;

  /// Rollovers so far (tests, debug).
  int get rollovers => _rollovers;

  /// Opens the query at cursor − cursorOverlap (6.6.1). No-op while running.
  void start() {
    if (_subscription != null) return;
    _open(cursor()?.minus(config.cursorOverlap));
  }

  /// Stops at once: no batch or error is delivered after this. The subscription's cancel is
  /// not awaited (its future may belong to another zone — nothing depends on it).
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final sub = _subscription;
    _subscription = null;
    if (sub != null) unawaited(sub.cancel());
  }

  /// Opens a new query at cursor − listenerRolloverOverlap, then closes the old one (6.6.4).
  Future<void> rollover() async {
    final old = _subscription;
    if (old == null) return;
    _rollovers++;
    _open(cursor()?.minus(config.listenerRolloverOverlap));
    unawaited(old.cancel());
  }

  void _open(ServerCursor? since) {
    _timer?.cancel();
    _chunksSinceOpen = 0;
    _initialPending = true;
    late final StreamSubscription<List<RemoteChunk>> sub;
    sub = backend
        .watchChunks(since: since)
        .listen(
          (batch) => _onData(sub, batch),
          onError: (Object e) => _fail(sub, e),
          onDone: () => _fail(sub, StateError('watchChunks ended')),
          cancelOnError: true,
        );
    _subscription = sub;
    _timer = Timer(
      config.listenerRolloverInterval,
      () => unawaited(rollover()),
    );
  }

  void _onData(
    StreamSubscription<List<RemoteChunk>> sub,
    List<RemoteChunk> batch,
  ) {
    final current = identical(sub, _subscription);
    if (current) {
      // The initial result is mostly a re-read (LRU) — it does not count toward a rollover.
      if (_initialPending) {
        _initialPending = false;
      } else {
        _chunksSinceOpen += batch.length;
      }
    }
    onBatch(batch);
    if (current && _chunksSinceOpen >= config.listenerRolloverChunks) {
      unawaited(rollover());
    }
  }

  void _fail(StreamSubscription<List<RemoteChunk>> sub, Object error) {
    if (!identical(sub, _subscription)) return; // an old query after a rollover
    _timer?.cancel();
    _timer = null;
    _subscription = null;
    onError(error);
  }
}
