// Internal (not exported). The engine's state machine (6.8.2) behind SyncEngine: account
// attach (6.10.3), receive first (6.6.1), live listener, pushes (6.5), retries and backoff
// (6.5.4, 6.8), the clock guard (6.2.4, 6.2.5 K1–K4), pause, lifecycle and the status
// (6.12). All store and backend work runs on one SerialExecutor (6.1); timers, the listener
// and auth / connectivity events only enqueue. Every interruption (offline, halt, pause,
// sign-out, reconnect) bumps an epoch: work started before it ends without effect.
import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../assets/engine_asset_service.dart';
import '../auth/auth_service.dart';
import '../auth/auth_user.dart';
import '../backend/blob_store.dart';
import '../backend/profile.dart';
import '../backend/remote_chunk.dart';
import '../backend/sync_backend.dart';
import '../common/errors.dart';
import '../common/server_cursor.dart';
import '../compaction/compactor.dart';
import '../config.dart';
import '../local/sync_local_store.dart';
import '../merge/folder_cycles.dart';
import '../merge/merge_recorder.dart';
import '../merge/page_resurrection.dart';
import '../merge/purge_guard.dart';
import '../merge/purged_set.dart';
import '../status/status_builder.dart';
import '../status/sync_issue.dart';
import '../status/sync_notice.dart';
import '../status/sync_status.dart';
import 'backoff.dart';
import 'connectivity.dart';
import 'download_pipeline.dart';
import 'held_records.dart';
import 'live_listener.dart';
import 'meta_keys.dart';
import 'push_scheduler.dart';
import 'serial_executor.dart';
import 'server_clock.dart';
import 'sync_engine.dart';
import 'upload_pipeline.dart';

/// Issue keys of the StatusBuilder (one active issue per key).
abstract final class _Keys {
  static String halt(SyncIssueCode code) => 'halt:${code.name}';
  static const String haltPrefix = 'halt:';
  static const String quota = 'quota';
  static const String clockWarning = 'clock:warning';
  static const String k3 = 'clock:k3';
  static const String k4 = 'clock:k4';
  static const String k1Prefix = 'clock:k1:';
  static const String quarantinePrefix = 'q:';
  static String quarantine(EntityRef ref) =>
      '$quarantinePrefix${ref.kind.name}:${ref.id}';
  static String apply(SyncIssue issue) =>
      'apply:${issue.code.name}:${issue.ref?.kind.name}:${issue.ref?.id}';
  static String asset(SyncIssueCode code, AssetId id) =>
      'asset:${code.name}:$id';
}

/// One signed-in account's attachment (6.10.3).
final class _Session {
  _Session(this.user);
  AuthUser user;
  _EngineBackend? backend;
  late PurgedSet purged;
  late UploadPipeline upload;
  late DownloadPipeline download;
  late LiveListener listener;
  late PageResurrection resurrection;
  late FolderCycleDetector cycles;
  late PurgeGuard guard;
  late Compactor compactor;

  /// Scope → wall ms before which a failed compaction is not tried again (6.13).
  final Map<String, int> compactRetryAt = {};

  /// Cycle rechecks waiting for cycleRepairGrace (6.7.2).
  final Set<Timer> cycleTimers = {};

  /// Steps 2–4 done (bound uid, owner).
  bool accountDone = false;

  /// Step 5 tried (profile, device / first clock sample).
  bool profileDone = false, deviceDone = false;

  /// Step 6: purged set and pipeline meta read.
  bool loaded = false;

  /// (S-13 — 07-sync 6.3.4) The held records of kinds this app knows were re-applied in
  /// this session. Outside the [loaded] block: a failed re-apply is tried again at the next
  /// connection of the same session.
  bool heldReapplied = false;
}

final class EngineController {
  EngineController({
    required this.local,
    required this.auth,
    required this.backendFactory,
    required this.config,
    required this.connectivity,
    required this.clock,
    required Random random,
    required Stopwatch Function() stopwatch,
    this.log,
  }) : _random = random,
       _monotonic = stopwatch()..start(),
       _serverClock = ServerClock(
         now: clock.now,
         stopwatch: stopwatch,
         warning: config.clockSkewWarning,
         limit: config.clockSkewLimit,
       ),
       _pushBackoff = Backoff(config: config, random: random),
       _pullBackoff = Backoff(config: config, random: random) {
    _status = StatusBuilder(
      phase: backendFactory == null ? SyncPhase.disabled : SyncPhase.signedOut,
      throttle: config.statusThrottle,
      nowMillis: _wallMillis,
    );
    _scheduler = PushScheduler(
      debounce: config.debounce,
      maxBatchDelay: config.maxBatchDelay,
      run: () => _enqueue('push', _pushOnce),
      onError: (e, s) => _log(SyncLogLevel.error, 'push failed', e),
    );
    assets = EngineAssetService(
      assets: local.assets,
      config: config,
      random: random,
      nowMillis: _wallMillis,
      onSummary: (summary) => _status.assets = summary,
      report: _assetIssue,
      onError: (what, e) => _log(SyncLogLevel.warning, '$what failed', e),
    );
  }

  static final Expando<EngineController> _byEngine = Expando(
    'EngineController',
  );

  /// The controller behind [engine] (test helpers: TestDevice, SyncTestHarness).
  static EngineController of(SyncEngine engine) => _byEngine[engine]!;

  void bind(SyncEngine engine) => _byEngine[engine] = this;

  final SyncLocalStore local;
  final AuthService auth;
  final SyncBackendFactory? backendFactory;
  final SyncConfig config;
  final ConnectivitySignal connectivity;
  final Clock clock;
  final SyncLogSink? log;

  /// Consecutive local-store failures that make localStoreFailure (6.5.4).
  static const int storeFailureLimit = 5;

  /// K2 release check while live (6.6.1); also the compaction trigger check (6.13).
  static const Duration releaseInterval = Duration(minutes: 1);

  /// Wait after a compaction that failed on a backend call (6.13).
  static const Duration compactionRetry = Duration(minutes: 10);

  final Random _random;
  final Stopwatch _monotonic;
  final ServerClock _serverClock;
  final Backoff _pushBackoff, _pullBackoff;
  late final StatusBuilder _status;
  late final PushScheduler _scheduler;

  /// SyncEngine.assets (6.9).
  late final EngineAssetService assets;
  final SerialExecutor _exec = SerialExecutor();
  final StreamController<SyncNotice> _notices = StreamController.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions = [];

  _Session? _session;
  bool _started = false, _disposed = false, _paused = false;

  /// 6.2.5 K3: this device's clock is off by more than clockSkewLimit.
  bool _k3 = false;
  int _epoch = 0;
  int _connFailures = 0, _storeFailures = 0;
  bool _refreshed = false;
  Duration? _backgroundSince;
  int? _pendingSince;

  Timer? _retryTimer, _pushRetryTimer, _k4Timer;
  Timer? _releaseTimer, _heartbeatTimer, _sampleTimer, _compactTimer;

  // Debug counters (SyncEngineDebug).
  int _pushCycles = 0, _commits = 0, _chunksSent = 0, _recordsSent = 0;
  int _chunksReceived = 0, _recordsApplied = 0, _recordsKept = 0;
  int _ownChunksSkipped = 0, _repairsWritten = 0, _groupRecords = 0;
  int _reappliedChunks = 0, _reappliedRecords = 0;
  Duration? _lastPushLatency, _lastRemoteApplyLatency;

  // ---- SyncEngine surface ---------------------------------------------------------------

  SyncStatus get status => _status.status;

  Stream<SyncStatus> get statusStream => Stream.multi((controller) {
    var last = _status.status;
    controller.add(last);
    final sub = _status.published.listen((s) {
      if (s == last) return;
      last = s;
      controller.add(s);
    }, onDone: controller.close);
    controller.onCancel = sub.cancel;
  });

  Stream<SyncNotice> get notices => _notices.stream;

  bool get isStarted => _started;

  /// (2nd round, S-13 — 07-sync 6.3.8) Kinds this engine's codec knows; null = every
  /// EntityKind. Fewer kinds make the engine behave like an older app (records of the other
  /// kinds are not applied). Set before [start] (StateError afterwards); SyncTestHarness
  /// .device / .restart(knownKinds:) set it. Test hook: @internal (not @visibleForTesting)
  /// because the harness in lib/src/testing sets it.
  @internal
  Set<EntityKind>? get debugKnownKinds => _knownKinds;
  @internal
  set debugKnownKinds(Set<EntityKind>? kinds) {
    if (_started) {
      throw StateError('debugKnownKinds must be set before start()');
    }
    _knownKinds = kinds == null ? null : Set.unmodifiable(kinds);
  }

  Set<EntityKind>? _knownKinds;

  /// (2nd round, S-13 — 07-sync 6.3.8, 6.7.1 S27 (c)) Held-record limits of the download
  /// pipeline built at the next attach; null = HeldRecords.defaultMaxPartBytes /
  /// defaultMaxTotalBytes. Unlike [debugKnownKinds] it may be set after [start] — a device
  /// made signed out sets it before it signs in. Test hook: @internal (scenario tests).
  @internal
  ({int maxPartBytes, int maxTotalBytes})? debugHeldRecordsLimits;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    if (backendFactory == null) {
      _setPhase(SyncPhase.disabled);
      return;
    }
    _status.isOnline = connectivity.isOnline;
    _subscriptions
      ..add(
        local.sync.watchPendingCount().listen(
          (n) => _status.pendingUploads = n,
          onError: (Object e) =>
              _log(SyncLogLevel.warning, 'pending count failed', e),
        ),
      )
      ..add(
        local.localChanges.listen((_) {
          _pendingSince ??= _wallMillis();
          _scheduler.trigger();
        }),
      )
      ..add(connectivity.changes.listen(_onConnectivity))
      ..add(auth.states.listen(_onAuth));
    await auth.initialize();
  }

  Future<void> syncNow() async {
    if (_disposed || _status.phase != SyncPhase.live) return;
    _cancelPushRetry();
    _scheduler.trigger(immediate: true);
    await _scheduler.drain();
    if (_status.phase != SyncPhase.live) return;
    await _enqueue('pull', _pullOnce);
  }

  Future<void> setPaused(bool paused) async {
    if (_disposed || _paused == paused) return;
    _paused = paused;
    final s = _session;
    if (!_started || backendFactory == null || s == null) return;
    if (paused) {
      _interrupt();
      _setPhase(SyncPhase.paused);
    } else {
      _setPhase(s.accountDone ? SyncPhase.catchingUp : SyncPhase.connecting);
      unawaited(_enqueue('resume', _connect));
    }
  }

  void setLifecycle(SyncLifecycle lifecycle) {
    if (_disposed) return;
    switch (lifecycle) {
      case SyncLifecycle.background:
        _backgroundSince ??= _monotonic.elapsed;
        if (_status.phase == SyncPhase.live) {
          _cancelPushRetry();
          _scheduler.trigger(immediate: true);
        }
      case SyncLifecycle.foreground:
        final since = _backgroundSince;
        _backgroundSince = null;
        if (since == null || _session == null) return;
        if (_k3 && _status.phase == SyncPhase.error) {
          _interrupt();
          unawaited(_enqueue('clock recheck', _connect));
          return;
        }
        final away = _monotonic.elapsed - since;
        if (away > config.reconnectAfterBackground &&
            _status.phase == SyncPhase.live) {
          _interrupt();
          _setPhase(SyncPhase.catchingUp);
          unawaited(_enqueue('foreground', _connect));
        }
    }
  }

  Future<bool> flushPendingUploads({Duration? timeout}) async {
    if (_disposed || backendFactory == null) return false;
    if (_status.phase == SyncPhase.live) {
      _cancelPushRetry();
      _scheduler.trigger(immediate: true);
      final done = Completer<void>();
      final timer = Timer(timeout ?? config.backgroundFlushTimeout, () {
        if (!done.isCompleted) done.complete();
      });
      unawaited(
        _scheduler.drain().then((_) {
          if (!done.isCompleted) done.complete();
        }),
      );
      await done.future;
      timer.cancel();
    }
    return (await local.sync.pendingChanges(limit: 1)).isEmpty;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    final s = _session;
    _interrupt();
    _disposed = true;
    _session = null;
    // Cancelled at once and not awaited: a cancel Future of a subscription without onCancel
    // work is completed in the root zone (Future._nullFuture), so awaiting it would hold
    // dispose in any other zone — fake_async's included (SyncTestHarness.restart, S2-4b).
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    _subscriptions.clear();
    _scheduler.dispose();
    _exec.close();
    await assets.close();
    if (s != null) await _closeSession(s);
    await _status.close();
    await _notices.close();
  }

  SyncEngineDebug get debug {
    final s = _session;
    final pipelines = s != null && s.backend != null;
    final held = pipelines ? s.download.held : null;
    return SyncEngineDebug(
      pushCycles: _pushCycles,
      commits: _commits,
      chunksSent: _chunksSent,
      recordsSent: _recordsSent,
      chunksReceived: _chunksReceived,
      recordsApplied: _recordsApplied,
      recordsKept: _recordsKept,
      ownChunksSkipped: _ownChunksSkipped,
      repairsWritten: _repairsWritten,
      cursor: pipelines ? s.download.cursor : null,
      quarantined: pipelines ? s.upload.quarantined.keys.toSet() : const {},
      heldChunks: held == null
          ? 0
          : held.entries.length + (held.collapsed == null ? 0 : 1),
      lastPushLatency: _lastPushLatency,
      lastRemoteApplyLatency: _lastRemoteApplyLatency,
      heldRecords: pipelines ? s.download.heldRecordCount : 0,
      heldRecordsMarked: pipelines && s.download.heldRecordsMarked,
      reappliedChunks: _reappliedChunks,
      reappliedRecords: _reappliedRecords,
    );
  }

  Future<SyncUsage> usage() => assets.usage();

  // ---- test helpers ---------------------------------------------------------------------

  /// The pipeline cursor of the attached account (null before the first sync).
  ServerCursor? get cursor {
    final s = _session;
    return s == null || s.backend == null ? null : s.download.cursor;
  }

  /// The account attached now.
  String? get attachedUid => _session?.user.uid;

  /// Why the engine still has work to do, or null when idle (SyncTestHarness.settle): work
  /// running or queued on the executor (an offline probe or a retry included); connecting
  /// or downloading; live with a push running or due, or entries waiting that are neither
  /// quarantined nor held by K4. Otherwise offline, error, paused, signed out and disabled
  /// engines are idle (their timers wait).
  String? get busyReason {
    if (!_started || _disposed) return null;
    final status = _status.status;
    if (_exec.isBusy || _exec.queueLength > 0) {
      return '${status.phase.name}, working (${_exec.currentLabel ?? 'queued'})';
    }
    switch (status.phase) {
      case SyncPhase.connecting ||
          SyncPhase.initialSync ||
          SyncPhase.catchingUp:
        return status.phase.name;
      case SyncPhase.live:
        if (_scheduler.isRunning || status.isPushing) return 'pushing';
        if (_scheduler.hasWindow) return 'push scheduled';
        if (_pushRetryTimer != null) return 'push retry scheduled';
        final s = _session;
        final held = s == null || s.backend == null
            ? 0
            : s.upload.clockHeld.length;
        final waiting =
            status.pendingUploads - status.quarantinedUploads - held;
        if (waiting > 0) return '$waiting uploads pending';
        if (_compactTimer != null) return 'compaction scheduled';
        return assets.busyReason;
      default:
        return null;
    }
  }

  // ---- auth, connectivity ---------------------------------------------------------------

  void _onAuth(AuthState state) {
    if (_disposed) return;
    switch (state.status) {
      case AuthStatus.signedIn:
        final user = state.user!;
        final s = _session;
        if (s != null && s.user.uid == user.uid) {
          s.user = user;
          _status.user = user;
          if (_status.issue(_Keys.halt(SyncIssueCode.reauthRequired)) != null) {
            // Signed in again after the session expired (6.10.5).
            _status.clearIssue(_Keys.halt(SyncIssueCode.reauthRequired));
            _refreshed = false;
            _resume();
          }
          return;
        }
        if (s != null) _detach();
        _attach(user);
      case AuthStatus.signedOut || AuthStatus.unavailable:
        if (_session != null) _detach();
      case AuthStatus.initializing || AuthStatus.signingIn:
        break;
    }
  }

  void _attach(AuthUser user) {
    _session = _Session(user);
    _status.batch(() {
      _status.user = user;
      _setPhase(_paused ? SyncPhase.paused : SyncPhase.connecting);
    });
    if (_paused) return;
    if (!connectivity.isOnline) {
      _goOffline();
      return;
    }
    unawaited(_enqueue('attach', _connect));
  }

  /// Sign-out (6.10.3 last note): listener, timers and running work stop; local data, the
  /// outbox and sync.boundUid stay.
  void _detach() {
    final s = _session;
    _interrupt();
    _session = null;
    _k3 = false;
    _refreshed = false;
    assets.detach();
    if (s != null) unawaited(_closeSession(s));
    _status.batch(() {
      _setPhase(SyncPhase.signedOut);
      _status.user = null;
      _status.quarantinedUploads = 0;
      _status.clearIssues((_, _) => true);
    });
  }

  Future<void> _closeSession(_Session s) async {
    final backend = s.backend;
    if (backend == null) return;
    for (final t in s.cycleTimers) {
      t.cancel();
    }
    s.cycleTimers.clear();
    await s.listener.stop();
    await s.purged.dispose();
    try {
      await backend.close();
    } on Object catch (e) {
      _log(SyncLogLevel.debug, 'backend close failed', e);
    }
  }

  void _onConnectivity(bool online) {
    if (_disposed || _session == null) {
      _status.isOnline = online;
      return;
    }
    final phase = _status.phase;
    if (!online) {
      if (phase == SyncPhase.connecting ||
          phase == SyncPhase.initialSync ||
          phase == SyncPhase.catchingUp ||
          phase == SyncPhase.live) {
        _goOffline();
      } else {
        _setPhase(phase);
      }
      return;
    }
    _setPhase(phase);
    if (phase == SyncPhase.offline) {
      _connFailures = 0;
      _pullBackoff.reset();
      _resume();
    } else if (_k3 && phase == SyncPhase.error) {
      _interrupt();
      unawaited(_enqueue('clock recheck', _connect));
    }
  }

  /// Back to connecting / catchingUp and run the connect cycle now.
  void _resume() {
    final s = _session;
    if (s == null || _paused) return;
    _interrupt();
    _setPhase(s.accountDone ? SyncPhase.catchingUp : SyncPhase.connecting);
    unawaited(_enqueue('connect', _connect));
  }

  // ---- the connect cycle (6.10.3, 6.6.1) ------------------------------------------------

  Future<void> _connect(int epoch) async {
    final s = _session;
    if (s == null || _stale(epoch) || _paused) return;
    try {
      if (!s.accountDone) {
        if (_status.phase != SyncPhase.error) _setPhase(SyncPhase.connecting);
        if (!await _attachAccount(s, epoch) || _stale(epoch)) return;
      }
      final backend = s.backend!;
      if (!s.profileDone) {
        await _tolerant(
          'profile write',
          () => backend.upsertProfile(
            UserProfile(
              uid: s.user.uid,
              email: s.user.email,
              displayName: s.user.displayName,
            ),
          ),
        );
        if (_stale(epoch)) return;
        s.profileDone = true;
      }
      if (!s.deviceDone || _k3) {
        final measured = await _measure(s);
        if (_stale(epoch)) return;
        s.deviceDone = true;
        if (_k3 && !measured) {
          _enterK3();
          return;
        }
      }
      if (_checkClock()) return;
      if (_k3) {
        _k3 = false;
        _status.clearIssue(_Keys.k3);
      }
      if (!s.loaded) {
        await s.purged.load();
        await s.download.load();
        if (_stale(epoch)) return;
        s.loaded = true;
      }
      // S-13 (contract 7.2.8 ⑤): load → re-apply → catchUp → releaseHeld.
      if (!s.heldReapplied) {
        final reapplied = await s.download.reapplyHeldRecords();
        if (_stale(epoch)) return;
        _absorbApply(s, reapplied);
        if (!reapplied.succeeded) {
          _pullFailed(reapplied.error!);
          return;
        }
        s.heldReapplied = true;
      }
      final first = s.download.cursor == null;
      final startedAt = _wallMillis();
      final recordsBefore = _groupRecords;
      _status.batch(() {
        _setPhase(first ? SyncPhase.initialSync : SyncPhase.catchingUp);
        _status.nextRetryAt = null;
        _status.initialSync = first
            ? InitialSyncProgress(
                chunksApplied: 0,
                recordsApplied: 0,
                startedAt: startedAt,
              )
            : null;
      });
      final result = await s.download.catchUp(
        onProgress: first
            ? (chunks, total) {
                if (_stale(epoch)) return;
                _status.initialSync = InitialSyncProgress(
                  chunksApplied: chunks,
                  estimatedTotalChunks: total,
                  recordsApplied: _groupRecords - recordsBefore,
                  startedAt: startedAt,
                );
              }
            : null,
      );
      if (_stale(epoch)) return;
      _absorbApply(s, result);
      if (!result.succeeded) {
        _pullFailed(result.error!);
        return;
      }
      final released = await s.download.releaseHeld();
      if (_stale(epoch)) return;
      _absorbApply(s, released);
      if (!released.succeeded) {
        _pullFailed(released.error!);
        return;
      }
      _connectedOk();
      final now = _wallMillis();
      _status.lastSyncedAt = now;
      if (first) {
        _notices.add(
          InitialSyncCompleted(
            at: now,
            records: result.applied,
            took: Duration(milliseconds: now - startedAt),
          ),
        );
      }
      _goLive(s);
    } on Object catch (e) {
      if (_stale(epoch)) return;
      _pullFailed(e);
    }
  }

  /// 6.10.3 steps 1–4. False when the account cannot be attached (accountMismatch).
  Future<bool> _attachAccount(_Session s, int epoch) async {
    var backend = s.backend;
    if (backend == null) {
      final inner = await backendFactory!(s.user);
      if (_session != s) {
        unawaited(inner.close());
        return false;
      }
      backend = s.backend = _EngineBackend(
        inner,
        _serverClock,
        config.operationTimeout,
      );
      _buildPipelines(s, backend);
    }
    final sync = local.sync;
    final uid = s.user.uid;
    final bound = MetaKeys.present(await sync.readMeta(MetaKeys.boundUid));
    if (_stale(epoch)) return false;
    if (bound != null && bound != uid) {
      _mismatch(bound, uid);
      return false;
    }
    if (sync.ownerId == kLocalOwnerId) {
      // First sign-in on this device (contract 7.2.10).
      await sync.reassignOwner(from: kLocalOwnerId, to: uid);
    } else if (sync.ownerId != uid) {
      _mismatch(sync.ownerId, uid);
      return false;
    }
    if (_stale(epoch)) return false;
    if (bound == null) await sync.writeMeta({MetaKeys.boundUid: uid});
    s.accountDone = true;
    if (_session == s && !_disposed) assets.attach(backend.blobs);
    return true;
  }

  void _buildPipelines(_Session s, _EngineBackend backend) {
    final sync = local.sync;
    s.purged = PurgedSet(sync: sync, localChanges: local.localChanges);
    s.resurrection = PageResurrection(sync: sync);
    s.cycles = FolderCycleDetector(sync: sync);
    s.guard = PurgeGuard(
      sync: sync,
      titleSuffix: config.recoveredNoteTitleSuffix,
      window: config.purgeGuardWindow,
      nowMillis: _wallMillis,
    );
    s.upload = UploadPipeline(
      sync: sync,
      backend: backend,
      config: config,
      serverNowMillis: _serverClock.serverNowMillis,
      refreshSession: auth.refreshSession,
      isClockBlocked: () => _k3,
      onPurgesCommitted: (purges) =>
          s.purged.addCommitted(purges, nowMillis: _wallMillis()),
      onScopesCommitted: s.guard.scopesSent,
      onAssetsCommitted: assets.onAssetsPushed,
      onPushNeeded: () => _scheduler.trigger(),
    );
    s.download = DownloadPipeline(
      sync: sync,
      backend: backend,
      config: config,
      purged: s.purged,
      wallMillis: _wallMillis,
      serverNowMillis: _serverClock.serverNowMillis,
      onOwnChunk: (c) => _serverClock.onOwnChunk(c.id, c.serverTime),
      purgeGuard: (purges) async {
        for (final notice in await s.guard.guard(purges)) {
          _notices.add(notice);
        }
      },
      // (v2.17-md, C217M-07 L2 — 08-markdown 5.3) keep the losing text of a concurrent
      // MD 문서 edit before the received bodies are applied.
      markdownGuard: (bodies) async {
        for (final r in bodies) {
          final change = r.toRemoteChange();
          final body = change.entity;
          if (body is! MarkdownText) continue;
          final copy = await sync.keepMarkdownConflictCopy(
            body,
            change.versions,
          );
          if (copy == null) continue;
          _notices.add(
            MarkdownConflictCopied(
              at: _wallMillis(),
              noteId: body.noteId,
              copyNoteId: copy,
            ),
          );
        }
      },
      afterGroup: (outcomes) => _afterGroup(s, outcomes),
      knownKinds: _knownKinds,
      heldRecordsMaxPartBytes:
          debugHeldRecordsLimits?.maxPartBytes ??
          HeldRecords.defaultMaxPartBytes,
      heldRecordsMaxTotalBytes:
          debugHeldRecordsLimits?.maxTotalBytes ??
          HeldRecords.defaultMaxTotalBytes,
      onWarning: (message) => _log(SyncLogLevel.warning, message),
    );
    s.compactor = Compactor(
      sync: sync,
      backend: backend,
      config: config,
      purged: s.purged,
      knownKinds: _knownKinds,
    );
    s.listener = LiveListener(
      backend: backend,
      config: config,
      cursor: () => s.download.cursor,
      onBatch: _onLiveBatch,
      onError: _onListenerError,
    );
  }

  void _mismatch(String bound, String uid) => _halt(
    SyncIssueCode.accountMismatch,
    'this device is bound to account $bound; signed in as $uid',
  );

  /// A profile / device write: connection and session errors go to the caller (retry /
  /// offline / refresh); any other backend error is only logged (6.10.3 step 5).
  Future<bool> _tolerant(String what, Future<void> Function() call) async {
    try {
      await call();
      return true;
    } on SyncBackendException catch (e) {
      if (e.code.isConnectivity || e.code == SyncErrorCode.unauthenticated) {
        rethrow;
      }
      _log(SyncLogLevel.warning, '$what failed', e);
      return false;
    }
  }

  /// upsertDevice = clock sample ① (6.2.4). False when the write failed (no sample).
  Future<bool> _measure(_Session s) async {
    final backend = s.backend!;
    final probe = _serverClock.begin();
    late final ServerCursor serverTime;
    final ok = await _tolerant('device write', () async {
      serverTime = await backend.upsertDevice(
        DeviceInfo(
          nodeId: local.sync.deviceNodeId,
          platform: config.platform,
          appVersion: config.appVersion,
          cursor: s.download.cursor,
        ),
      );
    });
    if (!ok) return false;
    _serverClock.complete(probe, serverTime);
    if (_k3) _serverClock.keepLatestSample();
    _status.clockSkew = _serverClock.skew;
    return true;
  }

  /// The 6.2.4 verdict into issues; true when K3 is (still) in force.
  bool _checkClock() {
    _status.clockSkew = _serverClock.skew;
    switch (_serverClock.verdict) {
      case ClockVerdict.blocked:
        _enterK3();
        return true;
      case ClockVerdict.warning:
        _status.setIssue(
          _Keys.clockWarning,
          SyncIssueCode.clockSkewWarning,
          'device clock differs from the server by ${_serverClock.skew}',
        );
      case ClockVerdict.ok:
        _status.clearIssue(_Keys.clockWarning);
    }
    return false;
  }

  /// 6.2.5 K3: no push, no receive; re-measured every clockSkewRecheck, on foreground and
  /// on a connectivity change.
  void _enterK3() {
    _k3 = true;
    _interrupt();
    final recheck = config.clockSkewRecheck;
    _status.batch(() {
      _setPhase(SyncPhase.error);
      _status.clearIssue(_Keys.clockWarning);
      _status.setIssue(
        _Keys.k3,
        SyncIssueCode.clockSkew,
        'this device clock is off by ${_serverClock.skew} (more than '
        '${config.clockSkewLimit}): uploads and remote apply paused',
        nodeId: local.sync.deviceNodeId,
      );
      _status.nextRetryAt = _wallMillis() + recheck.inMilliseconds;
    });
    _retryTimer = Timer(
      recheck,
      () => unawaited(_enqueue('clock recheck', _connect)),
    );
  }

  void _goLive(_Session s) {
    _status.batch(() {
      _setPhase(SyncPhase.live);
      _status.initialSync = null;
      _status.nextRetryAt = null;
    });
    s.listener.start();
    _scheduler.setLive(true);
    _scheduler.trigger(immediate: true);
    assets.setLive(true);
    _releaseTimer = Timer.periodic(releaseInterval, (_) {
      unawaited(_enqueue('release held', _releaseHeld));
      _scheduleCompaction();
    });
    _heartbeatTimer = Timer.periodic(
      config.deviceHeartbeat,
      (_) => unawaited(_enqueue('heartbeat', _remeasure)),
    );
    if (!_serverClock.hasSample) {
      _sampleTimer = Timer.periodic(
        config.offlineProbeInterval,
        (_) => unawaited(_enqueue('clock sample', _remeasure)),
      );
    }
  }

  void _connectedOk() {
    _connFailures = 0;
    _storeFailures = 0;
    _refreshed = false;
    _pullBackoff.reset();
    _status.clearIssues(
      (key, _) =>
          (key.startsWith(_Keys.haltPrefix) &&
              key != _Keys.halt(SyncIssueCode.accountMismatch)) ||
          key == _Keys.quota,
    );
  }

  // ---- receiving while live -------------------------------------------------------------

  void _onLiveBatch(List<RemoteChunk> batch) =>
      unawaited(_enqueue('apply', (epoch) => _applyLive(epoch, batch)));

  Future<void> _applyLive(int epoch, List<RemoteChunk> batch) async {
    final s = _session;
    if (s == null || _stale(epoch) || _status.phase != SyncPhase.live) return;
    final ApplyResult result;
    try {
      result = await s.download.applyChunks(batch);
    } on Object catch (e) {
      if (!_stale(epoch)) _livePullFailed(e);
      return;
    }
    _absorbApply(s, result);
    if (_stale(epoch)) return;
    if (!result.succeeded) {
      _livePullFailed(result.error!);
      return;
    }
    _connFailures = 0;
    _storeFailures = 0;
    if (result.chunks > 0) _status.lastSyncedAt = _wallMillis();
    _checkClock();
  }

  void _onListenerError(Object error) {
    if (_disposed || _status.phase != SyncPhase.live) return;
    _livePullFailed(error);
  }

  /// syncNow's pull: one catch-up from the cursor while live.
  Future<void> _pullOnce(int epoch) async {
    final s = _session;
    if (s == null || _stale(epoch) || _status.phase != SyncPhase.live) return;
    try {
      final result = await s.download.catchUp();
      _absorbApply(s, result);
      if (_stale(epoch)) return;
      if (!result.succeeded) {
        _livePullFailed(result.error!);
        return;
      }
      _status.lastSyncedAt = _wallMillis();
      _checkClock();
    } on Object catch (e) {
      if (!_stale(epoch)) _livePullFailed(e);
    }
  }

  Future<void> _releaseHeld(int epoch) async {
    final s = _session;
    if (s == null || _stale(epoch) || _status.phase != SyncPhase.live) return;
    if (s.download.held.isEmpty && !s.download.heldRecordsAwaitRelease) return;
    try {
      final result = await s.download.releaseHeld();
      _absorbApply(s, result);
      if (_stale(epoch)) return;
      if (!result.succeeded) _livePullFailed(result.error!);
    } on Object catch (e) {
      if (!_stale(epoch)) _livePullFailed(e);
    }
  }

  /// Heartbeat (deviceHeartbeat) and the no-sample retry (6.2.5: every 30 s).
  Future<void> _remeasure(int epoch) async {
    final s = _session;
    if (s == null || _stale(epoch) || _status.phase != SyncPhase.live) return;
    final hadSample = _serverClock.hasSample;
    try {
      await _measure(s);
    } on Object catch (e) {
      _log(SyncLogLevel.warning, 'device write failed', e);
      return;
    }
    if (_stale(epoch)) return;
    if (_checkClock()) return;
    if (_serverClock.hasSample) {
      _sampleTimer?.cancel();
      _sampleTimer = null;
      if (!hadSample) _scheduler.trigger(immediate: true);
    }
  }

  void _livePullFailed(Object error) {
    _interrupt();
    _setPhase(SyncPhase.catchingUp);
    _pullFailed(error);
  }

  /// Step 8 of 6.6.3 for one apply group: folder cycles (6.7.2) and page resurrection
  /// (6.7.3) over the committed outcomes.
  Future<void> _afterGroup(
    _Session s,
    Map<EntityRef, MergeOutcomeKind> outcomes,
  ) async {
    _groupRecords += outcomes.length;
    for (final kind in outcomes.values) {
      if (kind == MergeOutcomeKind.kept) _recordsKept++;
    }
    final assetIds = [
      for (final ref in outcomes.keys)
        if (ref.kind == EntityKind.asset) ref.id,
    ];
    if (assetIds.isNotEmpty) assets.onRemoteAssets(assetIds);
    final cycles = await s.cycles.check(outcomes);
    await _repairCycles(s, [
      for (final r in cycles)
        if (r.ownMove) r,
    ]);
    final later = [
      for (final r in cycles)
        if (!r.ownMove) r,
    ];
    if (later.isNotEmpty) {
      // Another device made the losing move: it repairs at once; check again after the
      // grace and repair only if the loop is still there (fewer duplicate writes).
      late final Timer timer;
      timer = Timer(config.cycleRepairGrace, () {
        s.cycleTimers.remove(timer);
        unawaited(_enqueue('cycle recheck', (_) => _recheckCycles(s, later)));
      });
      s.cycleTimers.add(timer);
    }
    final pages = await s.resurrection.check(outcomes);
    if (pages.isEmpty) return;
    await s.upload.commitRepairs([for (final r in pages) r.write]);
    _repairsWritten += pages.length;
    final at = _wallMillis();
    for (final r in pages) {
      _notices.add(PageRestored(at: at, pageId: r.pageId, noteId: r.noteId));
    }
  }

  Future<void> _recheckCycles(_Session s, List<CycleRepair> waiting) async {
    if (_session != s || _disposed) return;
    final cycles = await s.cycles.findCycles({
      for (final r in waiting) ...r.cycle.members,
    });
    await _repairCycles(s, await s.cycles.repairsOf(cycles));
  }

  Future<void> _repairCycles(_Session s, List<CycleRepair> repairs) async {
    if (repairs.isEmpty) return;
    await s.upload.commitRepairs([for (final r in repairs) r.write]);
    _repairsWritten += repairs.length;
    final at = _wallMillis();
    for (final r in repairs) {
      _notices.add(
        FolderCycleResolved(
          at: at,
          folderId: r.folderId,
          cycle: r.cycle.members,
        ),
      );
    }
  }

  void _absorbApply(_Session s, ApplyResult r) {
    _chunksReceived += r.chunks;
    _recordsApplied += r.applied;
    _ownChunksSkipped += r.ownSkipped;
    _reappliedChunks += r.reappliedChunks;
    _reappliedRecords += r.reappliedRecords;
    final latest = r.latestServerTime;
    if (latest != null && r.applied > 0) {
      final micros = clock.now().microsecondsSinceEpoch - latest.micros;
      _lastRemoteApplyLatency = Duration(microseconds: micros < 0 ? 0 : micros);
    }
    _status.batch(() {
      for (final issue in r.issues) {
        _status.raiseIssue(
          _Keys.apply(issue),
          issue.code,
          issue.message,
          ref: issue.ref,
          assetId: issue.assetId,
          nodeId: issue.nodeId,
        );
      }
      _syncHeld(s);
      _status.clockSkew = _serverClock.skew;
    });
  }

  /// K1 issues (6.2.5): one clockSkew issue per author of a held chunk.
  void _syncHeld(_Session s) {
    final held = s.download.held;
    final keys = <String, String?>{
      for (final node in held.authorNodes) '${_Keys.k1Prefix}$node': node,
      if (held.collapsed != null) '${_Keys.k1Prefix}*': null,
    };
    _status.clearIssues(
      (key, _) => key.startsWith(_Keys.k1Prefix) && !keys.containsKey(key),
    );
    for (final MapEntry(:key, value: node) in keys.entries) {
      _status.setIssue(
        key,
        SyncIssueCode.clockSkew,
        node == null
            ? 'records more than ${config.clockSkewLimit} ahead are held'
            : 'records of device $node are more than '
                  '${config.clockSkewLimit} ahead: held until their time comes',
        nodeId: node,
      );
    }
  }

  // ---- pushing (6.5) --------------------------------------------------------------------

  Future<void> _pushOnce(int epoch) async {
    final s = _session;
    if (s == null ||
        _stale(epoch) ||
        _status.phase != SyncPhase.live ||
        _k3 ||
        s.backend == null) {
      return;
    }
    final upload = s.upload;
    final PushResult result;
    _status.isPushing = true;
    try {
      result = await upload.runOnce();
    } on Object catch (e) {
      _status.isPushing = false;
      if (!_stale(epoch)) _pushFailed(e);
      return;
    }
    _pushCycles++;
    _commits += result.commits;
    _chunksSent += result.chunksSent;
    _recordsSent += result.recordsSent;
    _status.batch(() {
      _status.isPushing = false;
      _syncQuarantine(upload);
    });
    if (_stale(epoch) || result.skipped != null) return;
    if (result.reauthRequired) {
      _halt(SyncIssueCode.reauthRequired, 'session expired: sign in again');
      return;
    }
    final error = result.error;
    if (error != null) {
      _pushFailed(error);
      return;
    }
    _pushBackoff.reset();
    _connFailures = 0;
    _storeFailures = 0;
    _status.clearIssue(_Keys.quota);
    if (result.commits > 0 || result.acked > 0) {
      final now = _wallMillis();
      _status.lastSyncedAt = now;
      final since = _pendingSince;
      if (result.commits > 0 && since != null) {
        _lastPushLatency = Duration(milliseconds: now - since);
      }
      _pendingSince = null;
    }
    _syncK4(upload, result);
    if (result.hasMore) _scheduler.trigger(immediate: true);
  }

  void _syncQuarantine(UploadPipeline upload) {
    final quarantined = upload.quarantined;
    final keys = {for (final ref in quarantined.keys) _Keys.quarantine(ref)};
    _status.quarantinedUploads = upload.quarantinedCount;
    _status.clearIssues(
      (key, _) => key.startsWith(_Keys.quarantinePrefix) && !keys.contains(key),
    );
    for (final MapEntry(key: ref, value: code) in quarantined.entries) {
      _status.setIssue(
        _Keys.quarantine(ref),
        code,
        '${ref.kind.name} ${ref.id} kept on this device (${code.name})',
        ref: ref,
      );
    }
  }

  /// K4 (6.2.5): entries whose records are ahead of server time + 24 h stay in the outbox;
  /// the push is tried again when the earliest of them may go.
  void _syncK4(UploadPipeline upload, PushResult result) {
    _k4Timer?.cancel();
    _k4Timer = null;
    final held = upload.clockHeld;
    if (held.isEmpty) {
      _status.clearIssue(_Keys.k4);
      return;
    }
    _status.setIssue(
      _Keys.k4,
      SyncIssueCode.clockSkew,
      '${held.length} local changes are more than ${config.clockSkewLimit} '
      'ahead of the server time: kept until it catches up',
      nodeId: local.sync.deviceNodeId,
    );
    final at = result.heldUntilServerMillis;
    final now = _serverClock.serverNowMillis();
    if (at == null || now == null) return;
    final wait = Duration(milliseconds: at > now ? at - now : 0);
    _k4Timer = Timer(wait, () {
      _k4Timer = null;
      _scheduler.trigger(immediate: true);
    });
  }

  void _pushFailed(Object error) {
    _log(SyncLogLevel.warning, 'push failed', error);
    if (error is SyncBackendException) {
      final code = error.code;
      if (code.isConnectivity) {
        _connFailures++;
        if (_connFailures >= config.offlineAfterFailures) {
          _goOffline();
        } else {
          _retryPush(_pushBackoff.next(code));
        }
        return;
      }
      switch (code) {
        case SyncErrorCode.permissionDenied:
          _halt(
            SyncIssueCode.permissionDenied,
            'the server denied the upload: $error',
            retry: _pushBackoff.next(code),
          );
        case SyncErrorCode.failedPrecondition:
          _halt(
            SyncIssueCode.backendMisconfigured,
            'the backend is not set up: $error',
            retry: _pushBackoff.next(code),
          );
        case SyncErrorCode.unauthenticated:
          _halt(SyncIssueCode.reauthRequired, 'session expired: sign in again');
        case SyncErrorCode.resourceExhausted:
          _status.setIssue(
            _Keys.quota,
            SyncIssueCode.quotaExceeded,
            'quota exceeded: slowing down',
          );
          _retryPush(_pushBackoff.next(code));
        default:
          _retryPush(_pushBackoff.next(code));
      }
      return;
    }
    _storeFailures++;
    if (_storeFailures >= storeFailureLimit) {
      _halt(
        SyncIssueCode.localStoreFailure,
        'the local store failed $_storeFailures times in a row: $error',
        retry: _pushBackoff.next(),
      );
    } else {
      _retryPush(_pushBackoff.next());
    }
  }

  void _retryPush(Duration delay) {
    _cancelPushRetry();
    _status.nextRetryAt = _wallMillis() + delay.inMilliseconds;
    _pushRetryTimer = Timer(delay, () {
      _pushRetryTimer = null;
      _status.nextRetryAt = null;
      _scheduler.trigger(immediate: true);
    });
  }

  void _cancelPushRetry() {
    if (_pushRetryTimer == null) return;
    _pushRetryTimer!.cancel();
    _pushRetryTimer = null;
    _status.nextRetryAt = null;
  }

  // ---- failures, offline, halts (6.5.4, 6.8) --------------------------------------------

  /// A connect / receive step failed.
  void _pullFailed(Object error) {
    _log(SyncLogLevel.warning, 'receive failed', error);
    if (error is SyncBackendException) {
      final code = error.code;
      if (code.isConnectivity) {
        _connFailures++;
        if (_connFailures >= config.offlineAfterFailures) {
          _goOffline();
        } else {
          _retryConnect(_pullBackoff.next(code));
        }
        return;
      }
      switch (code) {
        case SyncErrorCode.unauthenticated:
          if (_refreshed) {
            _halt(
              SyncIssueCode.reauthRequired,
              'session expired: sign in again',
            );
          } else {
            _refreshed = true;
            _interrupt();
            unawaited(_enqueue('refresh', _refreshThenConnect));
          }
        case SyncErrorCode.permissionDenied:
          _halt(
            SyncIssueCode.permissionDenied,
            'the server denied access: $error',
            retry: _pullBackoff.next(code),
          );
        case SyncErrorCode.failedPrecondition:
          _halt(
            SyncIssueCode.backendMisconfigured,
            'the backend is not set up: $error',
            retry: _pullBackoff.next(code),
          );
        case SyncErrorCode.resourceExhausted:
          _status.setIssue(
            _Keys.quota,
            SyncIssueCode.quotaExceeded,
            'quota exceeded: slowing down',
          );
          _retryConnect(_pullBackoff.next(code));
        default:
          _retryConnect(_pullBackoff.next(code));
      }
      return;
    }
    _storeFailures++;
    if (_storeFailures >= storeFailureLimit) {
      _halt(
        SyncIssueCode.localStoreFailure,
        'the local store failed $_storeFailures times in a row: $error',
        retry: _pullBackoff.next(),
      );
    } else {
      _retryConnect(_pullBackoff.next());
    }
  }

  /// unauthenticated (6.5.4, 6.10.5): refreshSession once, then the cycle again at once.
  Future<void> _refreshThenConnect(int epoch) async {
    if (_stale(epoch)) return;
    try {
      await auth.refreshSession();
    } on Object catch (e) {
      if (_stale(epoch)) return;
      _halt(
        SyncIssueCode.reauthRequired,
        'session expired: sign in again ($e)',
      );
      return;
    }
    if (_stale(epoch)) return;
    await _connect(epoch);
  }

  void _retryConnect(Duration delay) {
    final phase = _status.phase;
    _interrupt();
    _status.batch(() {
      if (phase == SyncPhase.live) _setPhase(SyncPhase.catchingUp);
      _status.nextRetryAt = _wallMillis() + delay.inMilliseconds;
    });
    _retryTimer = Timer(delay, () => unawaited(_enqueue('connect', _connect)));
  }

  /// Offline (6.8.2): connectivity failures in a row or the signal; probed every
  /// offlineProbeInterval, reconnected at once when the signal comes back.
  void _goOffline() {
    _interrupt();
    final probe = config.offlineProbeInterval;
    _status.batch(() {
      _setPhase(SyncPhase.offline);
      _status.nextRetryAt = _wallMillis() + probe.inMilliseconds;
    });
    _retryTimer = Timer(probe, () => unawaited(_enqueue('probe', _probe)));
  }

  Future<void> _probe(int epoch) async {
    final s = _session;
    if (s == null || _stale(epoch) || _status.phase != SyncPhase.offline) {
      return;
    }
    final backend = s.backend;
    if (backend != null) {
      try {
        await backend.fetchChunks(limit: 1);
      } on Object catch (e) {
        if (_stale(epoch)) return;
        _log(SyncLogLevel.debug, 'offline probe failed', e);
        _goOffline();
        return;
      }
      if (_stale(epoch)) return;
      _connFailures = 0;
      _pullBackoff.reset();
      _setPhase(s.accountDone ? SyncPhase.catchingUp : SyncPhase.connecting);
    }
    await _connect(epoch);
  }

  /// Phase error with a blocking issue (6.8.2): sync stops; retried after [retry] (none for
  /// accountMismatch and reauthRequired — those wait for the user).
  void _halt(SyncIssueCode code, String message, {Duration? retry}) {
    _interrupt();
    _status.batch(() {
      _setPhase(SyncPhase.error);
      _status.setIssue(_Keys.halt(code), code, message);
      if (retry != null) {
        _status.nextRetryAt = _wallMillis() + retry.inMilliseconds;
      }
    });
    if (retry != null) {
      _retryTimer = Timer(retry, () => unawaited(_enqueue('retry', _connect)));
    }
  }

  /// Stops the current state's work: listener, timers, pushes; work already running ends
  /// without effect (epoch).
  void _interrupt() {
    _epoch++;
    for (final t in [
      _retryTimer,
      _pushRetryTimer,
      _k4Timer,
      _releaseTimer,
      _heartbeatTimer,
      _sampleTimer,
      _compactTimer,
    ]) {
      t?.cancel();
    }
    _retryTimer = _pushRetryTimer = _k4Timer = null;
    _releaseTimer = _heartbeatTimer = _sampleTimer = _compactTimer = null;
    _scheduler.setLive(false);
    assets.setLive(false);
    final s = _session;
    if (s != null && s.backend != null) unawaited(s.listener.stop());
    _status.batch(() {
      _status.nextRetryAt = null;
      _status.initialSync = null;
    });
  }

  // ---- compaction (6.13) ------------------------------------------------------------------

  /// The engine part of the trigger: enabled, live, nothing pending, foreground, no
  /// collapsed hold, no deferred format (the scope statistics are Compactor.dueScopes).
  bool _compactionAllowed(_Session? s) =>
      config.compaction.enabled &&
      !_disposed &&
      s != null &&
      s.backend != null &&
      _status.phase == SyncPhase.live &&
      _status.pendingUploads == 0 &&
      _backgroundSince == null &&
      s.download.held.collapsed == null &&
      s.download.deferredFrom == null;

  /// Due scopes of [s] now, without those waiting after a failure.
  List<String> _dueScopes(_Session s) {
    final now = _wallMillis();
    return [
      for (final scope in Compactor.dueScopes(
        s.download.scopeStats,
        config.compaction,
        nowMillis: now,
      ))
        if ((s.compactRetryAt[scope] ?? 0) <= now) scope,
    ];
  }

  /// While live (every releaseInterval and after a compaction): when a scope is due, runs
  /// one compaction after random(0..startJitterMax) and a recheck.
  void _scheduleCompaction() {
    final s = _session;
    if (_compactTimer != null || !_compactionAllowed(s)) return;
    if (_dueScopes(s!).isEmpty) return;
    final jitter = config.compaction.startJitterMax.inMilliseconds;
    _compactTimer = Timer(
      Duration(milliseconds: jitter <= 0 ? 0 : _random.nextInt(jitter + 1)),
      () {
        _compactTimer = null;
        unawaited(_enqueue('compact', _compactOnce));
      },
    );
  }

  Future<void> _compactOnce(int epoch) async {
    final s = _session;
    if (s == null || _stale(epoch) || !_compactionAllowed(s)) return;
    final due = _dueScopes(s);
    if (due.isEmpty) return;
    final scope = due.first;
    try {
      final result = await s.compactor.compact(
        scope,
        held: s.download.held,
        deferredFrom: s.download.deferredFrom,
      );
      if (_stale(epoch)) return;
      final now = _wallMillis();
      if (result.error != null) {
        _log(SyncLogLevel.warning, 'compaction of $scope failed', result.error);
        s.compactRetryAt[scope] = now + compactionRetry.inMilliseconds;
      } else if (result.completed) {
        _log(SyncLogLevel.info, 'compacted: $result');
        await s.download.markCompacted(
          scope,
          snapshotChunks: result.snapshotChunks,
          atMillis: now,
        );
      } else if (result.fetched > 0) {
        _log(SyncLogLevel.info, 'compaction skipped: $result');
        await s.download.markCompactionAttempted(scope, atMillis: now);
      }
    } on Object catch (e) {
      if (_stale(epoch)) return;
      _log(SyncLogLevel.warning, 'compaction of $scope failed', e);
      s.compactRetryAt[scope] = _wallMillis() + compactionRetry.inMilliseconds;
    }
    if (!_stale(epoch)) _scheduleCompaction();
  }

  // ---- helpers ----------------------------------------------------------------------------

  bool _stale(int epoch) => _disposed || epoch != _epoch;

  int _wallMillis() => clock.now().millisecondsSinceEpoch;

  void _setPhase(SyncPhase phase) => _status.batch(() {
    _status.phase = phase;
    _status.isOnline = phase != SyncPhase.offline && connectivity.isOnline;
  });

  /// Runs [body] on the serial executor with the epoch of now. Never throws.
  Future<void> _enqueue(String label, Future<void> Function(int epoch) body) {
    if (_exec.isClosed || _disposed) return Future.value();
    final epoch = _epoch;
    return _exec
        .run(() => body(epoch), label: label)
        .catchError((Object e) => _log(SyncLogLevel.error, '$label failed', e));
  }

  /// Asset issues (6.9): one per code and asset; a null [message] clears it.
  void _assetIssue(SyncIssueCode code, AssetId id, String? message) {
    if (_disposed) return;
    final key = _Keys.asset(code, id);
    if (message == null) {
      _status.clearIssue(key);
    } else {
      _status.setIssue(key, code, message, assetId: id);
    }
  }

  void _log(SyncLogLevel level, String message, [Object? error]) =>
      log?.call(level, message, error: error);
}

/// The engine's view of a SyncBackend: an operationTimeout on every call
/// (deadlineExceeded, 6.5.4) and the own-commit bookkeeping of the clock (6.2.4 ②).
final class _EngineBackend implements SyncBackend {
  _EngineBackend(this._inner, this._clock, this._timeout);

  final SyncBackend _inner;
  final ServerClock _clock;
  final Duration _timeout;

  Future<T> _timed<T>(Future<T> call) => call.timeout(
    _timeout,
    onTimeout: () => throw SyncBackendException(
      SyncErrorCode.deadlineExceeded,
      'no answer within $_timeout',
    ),
  );

  @override
  String get uid => _inner.uid;

  @override
  RemoteBlobStore get blobs => _inner.blobs;

  @override
  Future<void> commitChunks(List<ChunkWrite> chunks) async {
    final ids = [for (final c in chunks) c.id];
    final probe = _clock.beginCommit(ids);
    try {
      await _timed(_inner.commitChunks(chunks));
    } on Object {
      _clock.abortCommit(ids);
      rethrow;
    }
    _clock.endCommit(probe);
  }

  @override
  Future<ChunkPage> fetchChunks({
    ServerCursor? since,
    Object? pageToken,
    int limit = 50,
  }) => _timed(
    _inner.fetchChunks(since: since, pageToken: pageToken, limit: limit),
  );

  @override
  Stream<List<RemoteChunk>> watchChunks({ServerCursor? since}) =>
      _inner.watchChunks(since: since);

  @override
  Future<int?> countChunks({ServerCursor? since}) =>
      _timed(_inner.countChunks(since: since));

  @override
  Future<ChunkPage> fetchScope(
    String scope, {
    Object? pageToken,
    int limit = 50,
  }) => _timed(_inner.fetchScope(scope, pageToken: pageToken, limit: limit));

  @override
  Future<void> deleteChunks(List<String> ids) =>
      _timed(_inner.deleteChunks(ids));

  @override
  Future<void> upsertProfile(UserProfile profile) =>
      _timed(_inner.upsertProfile(profile));

  @override
  Future<ServerCursor> upsertDevice(DeviceInfo device) =>
      _timed(_inner.upsertDevice(device));

  @override
  Future<List<RemoteChunk>> getChunks(List<String> ids) =>
      _timed(_inner.getChunks(ids));

  @override
  Future<void> close() => _inner.close();
}
