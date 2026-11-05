// T14: the Riverpod providers (4.7, 6.16) in the override combinations the app shell and the
// tests use (contract 7.3.3): nothing configured → AuthStatus.unavailable / SyncPhase.disabled;
// auth without a backend factory → still disabled; the fake connection → live; the status
// providers start at the engine's current value; the engine's clock is CORE clockProvider;
// one AuthService for the UI and the engine. Virtual time (fakeAsync) throughout.
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart' as core_testing;
import 'package:riverpod/misc.dart'
    show Override, ProviderBase, ProviderListenable;
import 'package:riverpod/riverpod.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'support/local_writes.dart';

final DateTime _start = DateTime.utc(2026, 11, 1);
const _user = AuthUser(uid: 'user-1', email: 'one@example.com');
const _node = '00000000000000aa';

/// One device's worth of fakes on [async]'s virtual time (6.16 '테스트' override list).
final class _Rig {
  _Rig(this.async) : clock = async.getClock(_start) {
    server = FakeSyncServer(clock: clock);
    store = FakeLocalStore(nodeId: _node, clock: clock);
  }

  final FakeAsync async;
  final Clock clock;
  late final FakeSyncServer server;
  late final FakeLocalStore store;
  final FakeNetworkLink link = FakeNetworkLink();
  int connects = 0;

  /// The local store and the clock only: Firebase not configured.
  List<Override> base({Clock? engineClock}) => [
    syncLocalStoreProvider.overrideWithValue(store),
    clockProvider.overrideWithValue(engineClock ?? clock),
  ];

  /// The fake connection: signed-in auth backend + backend factory over the fake server.
  List<Override> connected({FakeAuthBackend? auth, Clock? engineClock}) => [
    ...base(engineClock: engineClock),
    authBackendProvider.overrideWithValue(auth ?? FakeAuthBackend(user: _user)),
    syncBackendFactoryProvider.overrideWithValue((u) async {
      connects++;
      return server.connect(uid: u.uid, link: link);
    }),
  ];

  ProviderContainer container(List<Override> overrides) =>
      ProviderContainer(overrides: overrides);

  /// Virtual time for the engine to connect, exchange and go idle.
  void run([Duration d = const Duration(seconds: 30)]) => async.elapse(d);
}

/// Disposes [container] (the engine and auth service dispose themselves, not awaited) and
/// runs the microtasks.
void _dispose(FakeAsync async, ProviderContainer container) {
  container.dispose();
  async.flushMicrotasks();
}

/// Every value [provider] gives from now on, the current one first.
List<AsyncValue<T>> _values<T>(
  ProviderContainer container,
  ProviderListenable<AsyncValue<T>> provider,
) {
  final out = <AsyncValue<T>>[];
  container.listen<AsyncValue<T>>(
    provider,
    (_, next) => out.add(next),
    fireImmediately: true,
  );
  return out;
}

List<T> _data<T>(List<AsyncValue<T>> values) => [
  for (final v in values)
    if (v case AsyncData(:final value)) value,
];

void main() {
  group('nothing configured (app shell before M4 / Firebase missing)', () {
    test('AuthStatus.unavailable and SyncPhase.disabled; the status '
        'providers give those as their first values', () {
      fakeAsync((async) {
        final rig = _Rig(async);
        final c = rig.container(rig.base());
        final auth = _values(c, authStateProvider);
        final statuses = _values(c, syncStatusProvider);
        async.flushMicrotasks();

        final engine = c.read(syncEngineProvider);
        expect(c.read(authBackendProvider), isNull);
        expect(c.read(syncBackendFactoryProvider), isNull);
        expect(c.read(syncConfigProvider), const SyncConfig());
        expect(c.read(connectivitySignalProvider), isA<AlwaysOnlineSignal>());
        expect(c.read(authServiceProvider).isAvailable, isFalse);
        expect(c.read(authServiceProvider).state, AuthState.unavailable);
        expect(engine.isStarted, isTrue, reason: 'the provider starts it');
        expect(engine.status.phase, SyncPhase.disabled);
        expect(engine.status.display, SyncDisplayState.off);

        rig.run();
        expect(_data(auth), [AuthState.unavailable]);
        expect(_data(statuses), [engine.status]);
        expect(_data(statuses).single.phase, SyncPhase.disabled);
        expect(rig.link.callCount(FakeOp.any), 0);
        _dispose(async, c);
      });
    });

    test('a signed-in auth backend without a backend factory: signed in, '
        'sync still disabled', () {
      fakeAsync((async) {
        final rig = _Rig(async);
        final c = rig.container([
          ...rig.base(),
          authBackendProvider.overrideWithValue(FakeAuthBackend(user: _user)),
        ]);
        final engine = c.read(syncEngineProvider);
        rig.run();
        expect(c.read(authServiceProvider).state.status, AuthStatus.signedIn);
        expect(engine.status.phase, SyncPhase.disabled);
        expect(rig.connects, 0);
        _dispose(async, c);
      });
    });

    test('syncLocalStoreProvider defaults to CoreSyncLocalStore over '
        'noteStoreProvider (the app shell overrides only the store)', () {
      fakeAsync((async) {
        final store = core_testing.createFakeNoteStore(
          clock: async.getClock(_start),
        );
        final c = ProviderContainer(
          overrides: [noteStoreProvider.overrideWithValue(store)],
        );
        expect(c.read(syncLocalStoreProvider), isA<CoreSyncLocalStore>());
        // CORE clockProvider = NoteStore.clock: the engine's clock (6.16).
        expect(c.read(clockProvider), same(store.clock));
        _dispose(async, c);
      });
    });
  });

  group('the fake connection', () {
    test('signed in + backend factory → live: the local edit reaches the '
        'server, InitialSyncCompleted on syncNoticesProvider', () {
      fakeAsync((async) {
        final rig = _Rig(async);
        final c = rig.container(rig.connected());
        final notices = _values(c, syncNoticesProvider);
        final statuses = _values(c, syncStatusProvider);
        rig.run();

        final engine = c.read(syncEngineProvider);
        expect(engine.status.phase, SyncPhase.live);
        expect(engine.status.user, _user);
        expect(rig.connects, 1);
        expect(_data(notices).whereType<InitialSyncCompleted>(), hasLength(1));
        final phases = [for (final s in _data(statuses)) s.phase];
        // signedOut while AuthService initializes, then the attach (6.8.2).
        expect(phases.toSet().toList(), [
          SyncPhase.signedOut,
          SyncPhase.connecting,
          SyncPhase.initialSync,
          SyncPhase.live,
        ]);
        expect(_data(statuses).last, engine.status);

        rig.store.localWrite([noteWrite('n1', title: 'from the provider')]);
        rig.run();
        expect(
          rig.server.mergedState('user-1'),
          contains(const EntityRef(EntityKind.note, 'n1')),
        );
        expect(engine.status.pendingUploads, 0);
        _dispose(async, c);
      });
    });

    test(
      'a late listener of syncStatusProvider starts at the current status',
      () {
        fakeAsync((async) {
          final rig = _Rig(async);
          final c = rig.container(rig.connected());
          final engine = c.read(syncEngineProvider);
          rig.run();
          expect(engine.status.phase, SyncPhase.live);

          final late = _values(c, syncStatusProvider);
          async.flushMicrotasks();
          expect(_data(late), [engine.status]);
          _dispose(async, c);
        });
      },
    );

    test('the engine clock is CORE clockProvider: lastSyncedAt and the clock '
        'skew follow it, not the store clock', () {
      fakeAsync((async) {
        final rig = _Rig(async);
        // 3 h ahead of the server: a warning only (2 min ~ 24 h, 6.2.4).
        final ahead = Clock(
          () => rig.clock.now().add(const Duration(hours: 3)),
        );
        final c = rig.container(rig.connected(engineClock: ahead));
        final engine = c.read(syncEngineProvider);
        rig.run();
        expect(engine.status.phase, SyncPhase.live);
        rig.store.localWrite([noteWrite('n1')]);
        rig.run();

        final syncedAt = engine.status.lastSyncedAt!;
        final aheadNow = ahead.now().millisecondsSinceEpoch;
        expect(syncedAt, inInclusiveRange(aheadNow - 60000, aheadNow));
        final skew = engine.status.clockSkew!;
        expect(
          (skew + const Duration(hours: 3)).inSeconds.abs(),
          lessThan(5),
          reason: 'server - local ≈ -3 h, measured on the clockProvider clock',
        );
        expect(
          engine.status.issues.map((i) => i.code),
          contains(SyncIssueCode.clockSkewWarning),
        );
        _dispose(async, c);
      });
    });

    test('one AuthService for the UI and the engine: signing in through '
        'authServiceProvider attaches the engine', () {
      fakeAsync((async) {
        final rig = _Rig(async);
        final fakeAuth = FakeAuthBackend()..nextSignInUser = _user;
        final c = rig.container(rig.connected(auth: fakeAuth));
        final engine = c.read(syncEngineProvider);
        final auth = _values(c, authStateProvider);
        rig.run();
        expect(engine.status.phase, SyncPhase.signedOut);
        expect(rig.connects, 0);

        unawaited(c.read(authServiceProvider).signInWithGoogle());
        rig.run();
        expect(engine.status.phase, SyncPhase.live);
        expect(engine.status.user, _user);
        expect(rig.connects, 1);
        expect(
          [for (final s in _data(auth)) s.status],
          [
            AuthStatus.initializing,
            AuthStatus.signedOut,
            AuthStatus.signingIn,
            AuthStatus.signedIn,
          ],
        );
        _dispose(async, c);
      });
    });

    test('syncAssetServiceProvider = engine.assets, syncUsageProvider = '
        'engine.usage(), assetAvailabilityProvider follows the service', () {
      fakeAsync((async) {
        final rig = _Rig(async);
        final c = rig.container(rig.connected());
        final engine = c.read(syncEngineProvider);
        rig.run();
        expect(c.read(syncAssetServiceProvider), same(engine.assets));

        final usage = _values(c, syncUsageProvider);
        rig.run(const Duration(seconds: 1));
        final value = _data(usage).single;
        expect(value.uploadedAssetCount, 0);
        expect(value.localOnlyAssetCount, 0);

        final availability = _values(c, assetAvailabilityProvider('ab' * 32));
        rig.run(const Duration(seconds: 1));
        expect(_data(availability).last.state, AssetAvailabilityState.unknown);
        _dispose(async, c);
      });
    });

    test(
      'disposing the container disposes the auth service (its states end)',
      () {
        fakeAsync((async) {
          final rig = _Rig(async);
          final c = rig.container(rig.connected());
          final service = c.read(authServiceProvider);
          c.read(syncEngineProvider);
          rig.run();
          var done = false;
          service.states.listen(null, onDone: () => done = true);
          _dispose(async, c);
          rig.run(const Duration(seconds: 1));
          expect(done, isTrue);
        });
      },
    );
  });

  test('every provider: name: == its variable name (contract 7.4.4)', () {
    final providers = <String, ProviderBase<Object?>>{
      'syncConfigProvider': syncConfigProvider,
      'authBackendProvider': authBackendProvider,
      'syncBackendFactoryProvider': syncBackendFactoryProvider,
      'connectivitySignalProvider': connectivitySignalProvider,
      'syncLocalStoreProvider': syncLocalStoreProvider,
      'authServiceProvider': authServiceProvider,
      'authStateProvider': authStateProvider,
      'syncEngineProvider': syncEngineProvider,
      'syncStatusProvider': syncStatusProvider,
      'syncNoticesProvider': syncNoticesProvider,
      'syncAssetServiceProvider': syncAssetServiceProvider,
      'syncUsageProvider': syncUsageProvider,
    };
    for (final MapEntry(key: name, value: provider) in providers.entries) {
      expect(provider.name, name);
    }
    expect(assetAvailabilityProvider.name, 'assetAvailabilityProvider');
    expect(assetAvailabilityProvider('a').name, 'assetAvailabilityProvider');
  });
}
