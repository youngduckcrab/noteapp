import 'dart:math';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../assets/sync_asset_service.dart';
import '../auth/auth_service.dart';
import '../auth/auth_user.dart';
import '../backend/sync_backend.dart';
import '../common/server_cursor.dart';
import '../config.dart';
import '../local/sync_local_store.dart';
import '../status/sync_notice.dart';
import '../status/sync_status.dart';
import 'connectivity.dart';
import 'engine_controller.dart';

typedef SyncBackendFactory = Future<SyncBackend> Function(AuthUser user);

enum SyncLifecycle { foreground, background }

enum SyncLogLevel { debug, info, warning, error }

typedef SyncLogSink = void Function(
  SyncLogLevel level,
  String message, {
  Object? error,
});

@immutable
final class SyncUsage {
  const SyncUsage({
    required this.uploadedAssetCount,
    required this.uploadedAssetBytes,
    required this.localOnlyAssetCount,
    required this.localOnlyAssetBytes,
  });

  /// Sum of CORE Asset.size with storagePath.
  final int uploadedAssetCount, uploadedAssetBytes;
  final int localOnlyAssetCount, localOnlyAssetBytes;
}

final class SyncEngine {
  SyncEngine({
    required SyncLocalStore local,
    required AuthService auth,
    SyncBackendFactory? backendFactory, // null → phase disabled
    SyncConfig config = const SyncConfig(),
    ConnectivitySignal connectivity = const AlwaysOnlineSignal(),
    Clock clock = const Clock(),
    Random? random, // backoff jitter; tests pass Random(seed)
    /// Monotonic elapsed time for the server-clock estimate (6.2.4); null → Stopwatch.new.
    /// Tests pass the harness base clock's stopwatch (device clock offsets do not move it).
    Stopwatch Function()? stopwatch,
    SyncLogSink? log,
  }) : _c = EngineController(
         local: local,
         auth: auth,
         backendFactory: backendFactory,
         config: config,
         connectivity: connectivity,
         clock: clock,
         random: random ?? Random(),
         stopwatch: stopwatch ?? Stopwatch.new,
         log: log,
       ) {
    _c.bind(this);
  }

  final EngineController _c;

  SyncStatus get status => _c.status;

  /// Emits current status on listen, then changes (throttled to
  /// SyncConfig.statusThrottle, phase/display changes are emitted immediately).
  /// A value equal (==) to the last emitted one is not emitted again.
  Stream<SyncStatus> get statusStream => _c.statusStream;

  /// Broadcast.
  Stream<SyncNotice> get notices => _c.notices;

  SyncAssetService get assets => throw UnimplementedError('SYNC T12');

  bool get isStarted => _c.isStarted;

  /// Idempotent. Follows auth state: signed in → attach (6.10), signed out → detach.
  Future<void> start() => _c.start();

  /// Skips the debounce: push everything pending and pull once. Completes when
  /// that cycle ends (success or recorded failure). No-op unless phase == live.
  Future<void> syncNow() => _c.syncNow();

  Future<void> setPaused(bool paused) => _c.setPaused(paused);

  /// background → flush pending uploads (no debounce); foreground after
  /// > 30 s in background → reconnect listener (catch-up from cursor).
  void setLifecycle(SyncLifecycle lifecycle) => _c.setLifecycle(lifecycle);

  /// Pushes until the outbox is empty or [timeout] (default
  /// SyncConfig.backgroundFlushTimeout). True if nothing is left pending.
  Future<bool> flushPendingUploads({Duration? timeout}) =>
      _c.flushPendingUploads(timeout: timeout);

  Future<SyncUsage> usage() => throw UnimplementedError('SYNC T12');

  Future<void> dispose() => _c.dispose();

  @visibleForTesting
  SyncEngineDebug get debug => _c.debug;
}

/// Counters for tests and the developer overlay.
@immutable
final class SyncEngineDebug {
  const SyncEngineDebug({
    required this.pushCycles,
    required this.commits,
    required this.chunksSent,
    required this.recordsSent,
    required this.chunksReceived,
    required this.recordsApplied,
    required this.recordsKept,
    required this.ownChunksSkipped,
    required this.repairsWritten,
    this.cursor,
    required this.quarantined,
    required this.heldChunks,
    this.lastPushLatency,
    this.lastRemoteApplyLatency,
  });
  final int pushCycles, commits, chunksSent, recordsSent;

  /// ownChunksSkipped: this device's own delta chunks only — its own snapshot chunks
  /// (compaction) are decoded and applied like any other chunk (6.6.3 step 2).
  final int chunksReceived,
      recordsApplied,
      recordsKept,
      ownChunksSkipped,
      repairsWritten;
  final ServerCursor? cursor;
  final Set<EntityRef> quarantined;

  /// sync.held entries (6.2.5 K1).
  final int heldChunks;

  /// Local commit → server commit.
  final Duration? lastPushLatency;

  /// Chunk serverTime → local apply done.
  final Duration? lastRemoteApplyLatency;
}
