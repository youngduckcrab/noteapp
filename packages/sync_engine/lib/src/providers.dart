// package:riverpod 3.4.3, no code generation (contract 7.4.4). Every provider: top-level
// final, name: == the variable name. Stream providers turn automatic retry off (noRetry).
import 'dart:async';

import 'package:note_core/note_core.dart';
import 'package:riverpod/riverpod.dart';

import 'assets/sync_asset_service.dart';
import 'auth/auth_backend.dart';
import 'auth/auth_service.dart';
import 'config.dart';
import 'engine/connectivity.dart';
import 'engine/sync_engine.dart';
import 'local/core_sync_local_store.dart';
import 'local/sync_local_store.dart';
import 'status/sync_notice.dart';
import 'status/sync_status.dart';

// ── App shell overrides (INFRA SyncModule, M4 — contract 7.3.3) ───────────
final syncConfigProvider = Provider<SyncConfig>(
  (ref) => const SyncConfig(),
  name: 'syncConfigProvider',
);

/// null = Firebase not configured → AuthStatus.unavailable, SyncPhase.disabled.
final authBackendProvider = Provider<AuthBackend?>(
  (ref) => null,
  name: 'authBackendProvider',
);
final syncBackendFactoryProvider = Provider<SyncBackendFactory?>(
  (ref) => null,
  name: 'syncBackendFactoryProvider',
);
final connectivitySignalProvider = Provider<ConnectivitySignal>(
  (ref) => const AlwaysOnlineSignal(),
  name: 'connectivitySignalProvider',
);

// ── Local store (tests override it; the app shell does not) ──────────────
/// Default adapter over CORE (4.9). Tests override with FakeLocalStore.
final syncLocalStoreProvider = Provider<SyncLocalStore>(
  (ref) => CoreSyncLocalStore(ref.watch(noteStoreProvider)),
  name: 'syncLocalStoreProvider',
);

// ── Account ───────────────────────────────────────────────────────────────
final authServiceProvider = Provider<AuthService>((ref) {
  final service = AuthService(ref.watch(authBackendProvider));
  ref.onDispose(service.dispose);
  unawaited(service.initialize());
  return service;
}, name: 'authServiceProvider');
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authServiceProvider).states,
  retry: noRetry,
  name: 'authStateProvider',
);

// ── Engine ────────────────────────────────────────────────────────────────
/// The app shell must read this once at startup (eager init, 5.2 I-2).
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(
    local: ref.watch(syncLocalStoreProvider),
    auth: ref.watch(authServiceProvider),
    backendFactory: ref.watch(syncBackendFactoryProvider),
    config: ref.watch(syncConfigProvider),
    connectivity: ref.watch(connectivitySignalProvider),
    // CORE clockProvider (= NoteStore.clock, 7.2.14).
    clock: ref.watch(clockProvider),
    // log: not passed (null) in this scope — the app-shell slot is SYNC-CP7 (12.2, deferred).
  );
  ref.onDispose(engine.dispose);
  unawaited(engine.start());
  return engine;
}, name: 'syncEngineProvider');

final syncStatusProvider = StreamProvider<SyncStatus>(
  (ref) => ref.watch(syncEngineProvider).statusStream,
  retry: noRetry,
  name: 'syncStatusProvider',
);
final syncNoticesProvider = StreamProvider<SyncNotice>(
  (ref) => ref.watch(syncEngineProvider).notices,
  retry: noRetry,
  name: 'syncNoticesProvider',
);
final syncAssetServiceProvider = Provider<SyncAssetService>(
  (ref) => ref.watch(syncEngineProvider).assets,
  name: 'syncAssetServiceProvider',
);
final assetAvailabilityProvider = StreamProvider.autoDispose
    .family<AssetAvailability, AssetId>(
      (ref, id) => ref.watch(syncAssetServiceProvider).watch(id),
      retry: noRetry,
      name: 'assetAvailabilityProvider',
    );
final syncUsageProvider = FutureProvider.autoDispose<SyncUsage>(
  (ref) => ref.watch(syncEngineProvider).usage(),
  retry: noRetry,
  name: 'syncUsageProvider',
);
// Removed in revision 1: syncDisplayStateProvider (badges read core.syncBadgeProvider, which
// INFRA overrides with syncBadgeOf — contract 7.3.3) and syncClockProvider (core.clockProvider).
