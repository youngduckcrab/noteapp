// T14: AuthService (4.3) — initialize() takes the web redirect result once
// (completePendingSignIn) and then follows authStateChanges; a failed sign-in is kept in
// lastError until the next attempt; states emit the current state on listen and then distinct
// changes in order. (2nd round, S2-14 — 07-sync 4.2, CP-S7) idToken: the backend's token
// (forceRefresh passed on), null when signed out, without a backend or after dispose, and
// null plus one log line (the error, never a token) when the backend throws. Virtual time
// (fakeAsync): nothing waits on the real clock.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/src/auth/auth_log.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/fake_time.dart';

const _alice = AuthUser(uid: 'alice', email: 'alice@example.com');
const _bob = AuthUser(uid: 'bob');

/// An AuthBackend whose answers the test scripts: completePendingSignIn returns [pending]
/// (or throws [pendingError]) like Firebase getRedirectResult, signInWithGoogle waits on
/// [signIn] when set.
final class _ScriptedBackend implements AuthBackend {
  _ScriptedBackend({this._user});

  AuthUser? _user;
  AuthUser? pending;
  Object? pendingError;
  Completer<AuthUser>? signIn;
  int pendingCalls = 0, signInCalls = 0, signOutCalls = 0, listens = 0;
  final StreamController<AuthUser?> _changes = StreamController.broadcast();

  void setUser(AuthUser? user) {
    _user = user;
    _changes.add(user);
  }

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> authStateChanges() => Stream.multi((controller) {
    listens++;
    controller.add(_user);
    final sub = _changes.stream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });

  @override
  bool get supportsGoogleSignIn => true;

  @override
  Future<AuthUser?> completePendingSignIn() async {
    pendingCalls++;
    final error = pendingError;
    if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
    final user = pending;
    // Firebase: the redirect result is also the current user from now on.
    if (user != null) _user = user;
    return user;
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    signInCalls++;
    final user = await (signIn?.future ?? Future.value(_bob));
    setUser(user);
    return user;
  }

  @override
  Future<void> refreshSession() async {}

  @override
  Future<void> signOut() async {
    signOutCalls++;
    setUser(null);
  }

  /// idToken: throws [tokenError] when set, else a token of the current user (null when
  /// signed out). [tokenCalls] records each forceRefresh.
  Object? tokenError;
  final List<bool> tokenCalls = [];

  @override
  Future<String?> idToken({bool forceRefresh = false}) async {
    tokenCalls.add(forceRefresh);
    final error = tokenError;
    if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
    final user = _user;
    return user == null
        ? null
        : 'token-${user.uid}${forceRefresh ? '-new' : ''}';
  }
}

/// Every state [service] emits from now on.
List<AuthState> _record(AuthService service) {
  final out = <AuthState>[];
  service.states.listen(out.add);
  return out;
}

/// Disposes [service] and runs the microtasks. Not awaited: cancelling a broadcast
/// subscription completes on the root zone's microtask queue, outside fakeAsync.
void _dispose(FakeAsync async, AuthService service) {
  unawaited(service.dispose());
  async.flushMicrotasks();
}

List<AuthStatus> _statuses(List<AuthState> states) => [
  for (final s in states) s.status,
];

void main() {
  group('no backend (Firebase not configured)', () {
    test('unavailable forever: initialize is a no-op, sign-in throws '
        'misconfigured and is reported in lastError', () {
      fakeAsync((async) {
        final service = AuthService(null);
        final states = _record(service);
        expect(service.isAvailable, isFalse);
        expect(service.state, AuthState.unavailable);
        runFake(async, service.initialize());
        expect(service.state.status, AuthStatus.unavailable);

        final error = runFakeError(async, service.signInWithGoogle());
        expect(
          error,
          isA<SignInException>().having(
            (e) => e.code,
            'code',
            SignInErrorCode.misconfigured,
          ),
        );
        expect(service.state.status, AuthStatus.unavailable);
        expect(service.state.user, isNull);
        expect(service.state.lastError, same(error));
        runFake(async, service.signOut());
        expect(service.state.status, AuthStatus.unavailable);
        expect(_statuses(states), [
          AuthStatus.unavailable,
          AuthStatus.unavailable,
        ]);
        _dispose(async, service);
      });
    });
  });

  group('initialize', () {
    test('initializing until the redirect result is in, then signedIn with '
        'the pending user; completePendingSignIn is called once', () {
      fakeAsync((async) {
        final backend = _ScriptedBackend()..pending = _alice;
        final service = AuthService(backend);
        final states = _record(service);
        expect(service.isAvailable, isTrue);
        expect(service.state.status, AuthStatus.initializing);

        final first = service.initialize();
        final second = service.initialize();
        expect(second, same(first));
        runFake(async, first);
        runFake(async, service.initialize());

        expect(backend.pendingCalls, 1);
        expect(backend.listens, 1);
        expect(
          service.state,
          const AuthState(status: AuthStatus.signedIn, user: _alice),
        );
        expect(_statuses(states), [
          AuthStatus.initializing,
          AuthStatus.signedIn,
        ]);
        _dispose(async, service);
      });
    });

    test('no redirect result: the current user decides (signed in / out)', () {
      fakeAsync((async) {
        final signedIn = AuthService(_ScriptedBackend(user: _alice));
        runFake(async, signedIn.initialize());
        expect(signedIn.state.status, AuthStatus.signedIn);
        expect(signedIn.state.user, _alice);

        final signedOut = AuthService(_ScriptedBackend());
        runFake(async, signedOut.initialize());
        expect(signedOut.state, const AuthState(status: AuthStatus.signedOut));
        _dispose(async, signedIn);
        _dispose(async, signedOut);
      });
    });

    test('a failed redirect sign-in → signedOut with lastError (any error '
        'becomes a SignInException)', () {
      fakeAsync((async) {
        const cancelled = SignInException(
          SignInErrorCode.cancelled,
          'closed by the user',
        );
        final backend = _ScriptedBackend()..pendingError = cancelled;
        final service = AuthService(backend);
        runFake(async, service.initialize());
        expect(service.state.status, AuthStatus.signedOut);
        expect(service.state.lastError, same(cancelled));

        final odd = StateError('plugin failure');
        final other = AuthService(_ScriptedBackend()..pendingError = odd);
        runFake(async, other.initialize());
        expect(other.state.status, AuthStatus.signedOut);
        expect(other.state.lastError?.code, SignInErrorCode.unknown);
        expect(other.state.lastError?.cause, same(odd));
        _dispose(async, service);
        _dispose(async, other);
      });
    });

    test(
      'then follows authStateChanges (token revoked, signed in elsewhere)',
      () {
        fakeAsync((async) {
          final backend = _ScriptedBackend(user: _alice);
          final service = AuthService(backend);
          final states = _record(service);
          runFake(async, service.initialize());
          backend.setUser(null);
          async.flushMicrotasks();
          expect(service.state, const AuthState(status: AuthStatus.signedOut));
          backend.setUser(_bob);
          async.flushMicrotasks();
          expect(
            service.state,
            const AuthState(status: AuthStatus.signedIn, user: _bob),
          );
          expect(_statuses(states), [
            AuthStatus.initializing,
            AuthStatus.signedIn,
            AuthStatus.signedOut,
            AuthStatus.signedIn,
          ]);
          expect(states[1].user, _alice);
          expect(states[3].user, _bob);
          _dispose(async, service);
        });
      },
    );
  });

  group('signInWithGoogle', () {
    test('signedOut → signingIn → signedIn; the backend event during the '
        'attempt does not add a state', () {
      fakeAsync((async) {
        final backend = _ScriptedBackend()..signIn = Completer();
        final service = AuthService(backend);
        runFake(async, service.initialize());
        final states = _record(service);

        final result = service.signInWithGoogle();
        async.flushMicrotasks();
        expect(service.state, const AuthState(status: AuthStatus.signingIn));
        backend.signIn!.complete(_alice);
        expect(runFake(async, result), _alice);

        expect(
          service.state,
          const AuthState(status: AuthStatus.signedIn, user: _alice),
        );
        expect(_statuses(states), [
          AuthStatus.signedOut,
          AuthStatus.signingIn,
          AuthStatus.signedIn,
        ]);
        _dispose(async, service);
      });
    });

    test(
      'a second call while signing in joins the first (one backend call)',
      () {
        fakeAsync((async) {
          final backend = _ScriptedBackend()..signIn = Completer();
          final service = AuthService(backend);
          runFake(async, service.initialize());
          final a = service.signInWithGoogle();
          final b = service.signInWithGoogle();
          expect(b, same(a));
          backend.signIn!.complete(_alice);
          expect(runFake(async, a), _alice);
          expect(backend.signInCalls, 1);

          // Done: the next call is a new attempt.
          backend.signIn = null;
          runFake(async, service.signOut());
          expect(runFake(async, service.signInWithGoogle()), _bob);
          expect(backend.signInCalls, 2);
          _dispose(async, service);
        });
      },
    );

    test('failure: signedOut with lastError (the thrown exception), cleared '
        'by the next attempt', () {
      fakeAsync((async) {
        final fake = FakeAuthBackend();
        final service = AuthService(fake);
        runFake(async, service.initialize());
        final states = _record(service);

        const popupBlocked = SignInException(
          SignInErrorCode.popupBlocked,
          'popup blocked',
        );
        fake.failNextSignIn(popupBlocked);
        final error = runFakeError(async, service.signInWithGoogle());
        expect(error, same(popupBlocked));
        expect(service.state.status, AuthStatus.signedOut);
        expect(service.state.lastError, same(popupBlocked));

        // Same failure again = a new exception object = a new state.
        const again = SignInException(
          SignInErrorCode.popupBlocked,
          'popup blocked',
        );
        fake.failNextSignIn(again);
        runFakeError(async, service.signInWithGoogle());
        expect(service.state.lastError, same(again));

        expect(
          runFake(async, service.signInWithGoogle()),
          const AuthUser(uid: 'user-1'),
        );
        expect(service.state.lastError, isNull);
        expect(_statuses(states), [
          AuthStatus.signedOut,
          AuthStatus.signingIn,
          AuthStatus.signedOut,
          AuthStatus.signingIn,
          AuthStatus.signedOut,
          AuthStatus.signingIn,
          AuthStatus.signedIn,
        ]);
        // The signingIn states carry no lastError (cleared on the attempt).
        expect(states[1].lastError, isNull);
        expect(states[2].lastError, same(popupBlocked));
        expect(states[4].lastError, same(again));
        _dispose(async, service);
      });
    });

    test('failure while signed in (switching account) keeps the signed-in '
        'user and reports lastError', () {
      fakeAsync((async) {
        final fake = FakeAuthBackend(user: _alice);
        final service = AuthService(fake);
        runFake(async, service.initialize());
        const network = SignInException(SignInErrorCode.network, 'offline');
        fake.failNextSignIn(network);
        runFakeError(async, service.signInWithGoogle());
        expect(service.state.status, AuthStatus.signedIn);
        expect(service.state.user, _alice);
        expect(service.state.lastError, same(network));
        _dispose(async, service);
      });
    });

    test('a non-SignInException from the backend → SignInErrorCode.unknown, '
        'never stuck in signingIn', () {
      fakeAsync((async) {
        final backend = _ScriptedBackend()..signIn = Completer();
        final service = AuthService(backend);
        runFake(async, service.initialize());
        final result = service.signInWithGoogle();
        final odd = ArgumentError('bad provider');
        backend.signIn!.completeError(odd);
        final error = runFakeError(async, result);
        expect(
          error,
          isA<SignInException>()
              .having((e) => e.code, 'code', SignInErrorCode.unknown)
              .having((e) => e.cause, 'cause', same(odd)),
        );
        expect(service.state.status, AuthStatus.signedOut);
        expect(service.state.lastError, same(error));
        _dispose(async, service);
      });
    });
  });

  group('signOut and states', () {
    test('signOut: signedIn → signedOut through the backend', () {
      fakeAsync((async) {
        final backend = _ScriptedBackend(user: _alice);
        final service = AuthService(backend);
        runFake(async, service.initialize());
        runFake(async, service.signOut());
        expect(backend.signOutCalls, 1);
        expect(service.state, const AuthState(status: AuthStatus.signedOut));
        _dispose(async, service);
      });
    });

    test('states: the current state on listen, then distinct changes only; '
        'a late listener starts at the current state', () {
      fakeAsync((async) {
        final backend = _ScriptedBackend(user: _alice);
        final service = AuthService(backend);
        final early = _record(service);
        runFake(async, service.initialize());
        // The same user again (e.g. token refresh event): no new state.
        backend.setUser(_alice);
        async.flushMicrotasks();
        final late = _record(service);
        async.flushMicrotasks();
        backend.setUser(null);
        async.flushMicrotasks();

        expect(_statuses(early), [
          AuthStatus.initializing,
          AuthStatus.signedIn,
          AuthStatus.signedOut,
        ]);
        expect(_statuses(late), [AuthStatus.signedIn, AuthStatus.signedOut]);
        _dispose(async, service);
      });
    });

    test('dispose closes states and stops following the backend', () {
      fakeAsync((async) {
        final backend = _ScriptedBackend(user: _alice);
        final service = AuthService(backend);
        runFake(async, service.initialize());
        var done = false;
        final states = <AuthState>[];
        service.states.listen(states.add, onDone: () => done = true);
        _dispose(async, service);
        _dispose(async, service); // idempotent
        expect(done, isTrue);
        backend.setUser(null);
        async.flushMicrotasks();
        expect(service.state.status, AuthStatus.signedIn);
        expect(_statuses(states), [AuthStatus.signedIn]);
      });
    });

    test(
      'dispose before initialize finishes: no state change, no listener',
      () {
        fakeAsync((async) {
          final backend = _ScriptedBackend(user: _alice);
          final service = AuthService(backend);
          final init = service.initialize();
          _dispose(async, service);
          runFake(async, init);
          expect(service.state.status, AuthStatus.initializing);
          expect(backend.listens, 0);
        });
      },
    );
  });

  group('idToken (2nd round, CP-S7)', () {
    late List<(String, Object?)> logs;
    setUp(() {
      logs = [];
      authLogHook = (message, error) => logs.add((message, error));
    });
    tearDown(() => authLogHook = null);

    test('signed in: the backend\'s token, forceRefresh passed on', () {
      fakeAsync((async) {
        final backend = _ScriptedBackend(user: _alice);
        final service = AuthService(backend);
        runFake(async, service.initialize());
        expect(runFake(async, service.idToken()), 'token-alice');
        expect(
          runFake(async, service.idToken(forceRefresh: true)),
          'token-alice-new',
        );
        expect(backend.tokenCalls, [false, true]);
        expect(logs, isEmpty);
        _dispose(async, service);
      });
    });

    test('signed out: null', () {
      fakeAsync((async) {
        final backend = _ScriptedBackend();
        final service = AuthService(backend);
        runFake(async, service.initialize());
        expect(service.state.status, AuthStatus.signedOut);
        expect(runFake(async, service.idToken()), isNull);
        backend.setUser(_alice);
        async.flushMicrotasks();
        expect(runFake(async, service.idToken()), 'token-alice');
        runFake(async, service.signOut());
        expect(runFake(async, service.idToken(forceRefresh: true)), isNull);
        expect(logs, isEmpty);
        _dispose(async, service);
      });
    });

    test('no backend (unavailable): null, no log', () {
      fakeAsync((async) {
        final service = AuthService(null);
        expect(runFake(async, service.idToken()), isNull);
        expect(runFake(async, service.idToken(forceRefresh: true)), isNull);
        expect(logs, isEmpty);
        _dispose(async, service);
      });
    });

    for (final error in <Object>[
      const SyncBackendException(SyncErrorCode.network, 'offline'),
      const SyncBackendException(SyncErrorCode.unauthenticated, 'revoked'),
      StateError('plugin failure'),
    ]) {
      test('the backend throws $error: null and one log line with the error, '
          'never a throw', () {
        fakeAsync((async) {
          final backend = _ScriptedBackend(user: _alice);
          final service = AuthService(backend);
          runFake(async, service.initialize());
          expect(runFake(async, service.idToken()), 'token-alice');
          backend.tokenError = error;
          expect(runFake(async, service.idToken(forceRefresh: true)), isNull);
          expect(logs, hasLength(1));
          expect(logs.single.$1, 'idToken failed');
          expect(logs.single.$2, same(error));
          expect(logs.single.$1, isNot(contains('token-alice')));
          expect(
            service.state.status,
            AuthStatus.signedIn,
            reason:
                'no '
                'state change',
          );
          backend.tokenError = null;
          expect(runFake(async, service.idToken()), 'token-alice');
          _dispose(async, service);
        });
      });
    }

    test('after dispose: null without asking the backend', () {
      fakeAsync((async) {
        final backend = _ScriptedBackend(user: _alice);
        final service = AuthService(backend);
        runFake(async, service.initialize());
        _dispose(async, service);
        expect(runFake(async, service.idToken()), isNull);
        expect(backend.tokenCalls, isEmpty);
      });
    });

    test('FakeAuthBackend: a token per user, a new one on forceRefresh, null '
        'when signed out', () {
      fakeAsync((async) {
        final backend = FakeAuthBackend(user: _alice);
        final service = AuthService(backend);
        runFake(async, service.initialize());
        final first = runFake(async, service.idToken());
        expect(first, 'fake-id-token:alice:1');
        expect(runFake(async, service.idToken()), first);
        expect(
          runFake(async, service.idToken(forceRefresh: true)),
          'fake-id-token:alice:2',
        );
        backend.setUser(null);
        async.flushMicrotasks();
        expect(runFake(async, service.idToken()), isNull);
        _dispose(async, service);
      });
    });
  });
}
