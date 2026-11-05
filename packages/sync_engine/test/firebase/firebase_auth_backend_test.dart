// T17: FirebaseAuthBackend on firebase_auth_mocks (6.10): popup sign-in (Google provider,
// select_account), cancelled / blocked popups → SignInException, the auto mode (standalone
// web app → redirect, else popup; a blocked popup falls back to redirect), the redirect
// result after reload, authStateChanges (current user first, no repeats), sign-out,
// refreshSession (forced id token, unauthenticated), native sign-in through
// NativeGoogleSignIn, and AuthService on top of it. The mock has no redirect API, so a
// subclass records signInWithRedirect / getRedirectResult.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/firebase.dart';
import 'package:sync_engine/sync_engine.dart';

// ignore: must_be_immutable
final class _User extends MockUser {
  _User({super.uid, super.email, super.displayName, super.photoURL});

  final List<bool> tokenRequests = [];
  Exception? tokenError;

  @override
  Future<String> getIdToken([bool forceRefresh = false]) async {
    tokenRequests.add(forceRefresh);
    final error = tokenError;
    if (error != null) throw error;
    return 'token';
  }
}

final class _NoUserCredential implements UserCredential {
  @override
  User? get user => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Auth extends MockFirebaseAuth {
  /// The mock's broadcast stream buffers events until its first listener (then replays
  /// them, stale); Firebase does not. A listener from the start keeps only live events.
  _Auth({super.signedIn, super.mockUser}) {
    authStateChanges().listen((_) {});
  }

  final List<AuthProvider> popups = [];
  final List<AuthProvider> redirects = [];
  final List<AuthCredential?> credentials = [];
  int redirectResults = 0;
  Exception? popupError;
  Exception? redirectError;
  Exception? redirectResultError;

  /// getRedirectResult signs this user in (the redirect came back).
  bool redirectPending = false;

  @override
  Future<UserCredential> signInWithPopup(AuthProvider provider) {
    popups.add(provider);
    final error = popupError;
    if (error != null) return Future.error(error);
    return super.signInWithPopup(provider);
  }

  @override
  Future<void> signInWithRedirect(AuthProvider provider) async {
    redirects.add(provider);
    final error = redirectError;
    if (error != null) throw error;
  }

  @override
  Future<UserCredential> getRedirectResult() async {
    redirectResults++;
    final error = redirectResultError;
    if (error != null) throw error;
    if (!redirectPending) return _NoUserCredential();
    redirectPending = false;
    return signInWithCredential(null);
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential? credential) {
    credentials.add(credential);
    return super.signInWithCredential(credential);
  }
}

final class _Native implements NativeGoogleSignIn {
  Exception? error;
  int signOuts = 0;

  @override
  Future<String> obtainIdToken() async {
    final e = error;
    if (e != null) throw e;
    return 'google-id-token';
  }

  @override
  Future<void> signOut() async => signOuts++;
}

_User _alice() => _User(
  uid: 'alice-uid',
  email: 'alice@example.com',
  displayName: 'Alice',
  photoURL: 'https://example.com/a.png',
);

const _aliceUser = AuthUser(
  uid: 'alice-uid',
  email: 'alice@example.com',
  displayName: 'Alice',
  photoUrl: 'https://example.com/a.png',
);

FirebaseAuthBackend _web(
  _Auth auth, {
  WebSignInMode mode = WebSignInMode.auto,
  bool standalone = false,
}) => FirebaseAuthBackend(
  auth: auth,
  webSignInMode: mode,
  isWeb: true,
  isStandaloneWebApp: () => standalone,
);

Future<SignInException> _signInError(FirebaseAuthBackend backend) async {
  try {
    await backend.signInWithGoogle();
  } on SignInException catch (e) {
    return e;
  }
  fail('signInWithGoogle did not throw');
}

void _expectGoogle(AuthProvider provider) {
  expect(provider, isA<GoogleAuthProvider>());
  expect((provider as GoogleAuthProvider).parameters, {
    'prompt': 'select_account',
  });
}

void main() {
  group('web popup', () {
    test(
      'success: the Google provider with select_account, the user',
      () async {
        final auth = _Auth(mockUser: _alice());
        final backend = _web(auth, mode: WebSignInMode.popup);
        expect(backend.supportsGoogleSignIn, isTrue);
        expect(backend.currentUser, isNull);

        expect(await backend.signInWithGoogle(), _aliceUser);
        expect(auth.popups, hasLength(1));
        _expectGoogle(auth.popups.single);
        expect(auth.redirects, isEmpty);
        expect(backend.currentUser, _aliceUser);
      },
    );

    test('closed / cancelled popups → SignInException(cancelled), with or '
        'without the web "auth/" prefix', () async {
      for (final code in [
        'popup-closed-by-user',
        'auth/popup-closed-by-user',
        'cancelled-popup-request',
      ]) {
        final auth = _Auth(mockUser: _alice())
          ..popupError = FirebaseAuthException(code: code);
        final error = await _signInError(_web(auth));
        expect(error.code, SignInErrorCode.cancelled, reason: code);
        expect(error.cause, isA<FirebaseAuthException>());
        expect(auth.redirects, isEmpty, reason: code);
        expect(auth.currentUser, isNull);
      }
    });

    test('other popup failures map with mapSignInError', () async {
      const table = {
        'network-request-failed': SignInErrorCode.network,
        'unauthorized-domain': SignInErrorCode.misconfigured,
        'user-disabled': SignInErrorCode.accountDisabled,
        'something-new': SignInErrorCode.unknown,
      };
      for (final MapEntry(:key, :value) in table.entries) {
        final auth = _Auth()..popupError = FirebaseAuthException(code: key);
        expect((await _signInError(_web(auth))).code, value, reason: key);
      }
      final auth = _Auth()..popupError = Exception('boom');
      expect((await _signInError(_web(auth))).code, SignInErrorCode.unknown);
    });

    test(
      'explicit popup mode: a blocked popup is an error, no redirect',
      () async {
        final auth = _Auth(mockUser: _alice())
          ..popupError = FirebaseAuthException(code: 'popup-blocked');
        final error = await _signInError(_web(auth, mode: WebSignInMode.popup));
        expect(error.code, SignInErrorCode.popupBlocked);
        expect(auth.redirects, isEmpty);
      },
    );
  });

  group('web auto / redirect', () {
    test('auto: a browser tab uses the popup, a standalone web app the '
        'redirect', () async {
      final tab = _Auth(mockUser: _alice());
      expect(await _web(tab).signInWithGoogle(), _aliceUser);
      expect(tab.popups, hasLength(1));
      expect(tab.redirects, isEmpty);

      fakeAsync((async) {
        final app = _Auth(mockUser: _alice());
        AuthUser? result;
        unawaited(
          _web(
            app,
            standalone: true,
          ).signInWithGoogle().then((u) => result = u),
        );
        async.flushMicrotasks();
        expect(app.popups, isEmpty);
        expect(app.redirects, hasLength(1));
        _expectGoogle(app.redirects.single);
        // The page would navigate away now; the future stays pending.
        expect(result, isNull);
      });
    });

    test('auto: popup-blocked / operation-not-supported → redirect', () {
      for (final code in [
        'popup-blocked',
        'auth/operation-not-supported-in-this-environment',
      ]) {
        fakeAsync((async) {
          final auth = _Auth(mockUser: _alice())
            ..popupError = FirebaseAuthException(code: code);
          unawaited(_web(auth).signInWithGoogle());
          async.flushMicrotasks();
          expect(auth.popups, hasLength(1), reason: code);
          expect(auth.redirects, hasLength(1), reason: code);
        });
      }
    });

    test('redirect: if the page does not navigate away, the next signed-in '
        'user completes the sign-in', () {
      fakeAsync((async) {
        final auth = _Auth(mockUser: _alice());
        AuthUser? result;
        unawaited(
          _web(
            auth,
            mode: WebSignInMode.redirect,
          ).signInWithGoogle().then((u) => result = u),
        );
        async.flushMicrotasks();
        expect(auth.redirects, hasLength(1));
        expect(result, isNull);
        unawaited(auth.signInWithCredential(null));
        async.elapse(const Duration(milliseconds: 1));
        expect(result, _aliceUser);
      });
    });

    test('a failing redirect → SignInException', () async {
      final auth = _Auth()
        ..redirectError = FirebaseAuthException(code: 'unauthorized-domain');
      final error = await _signInError(
        _web(auth, mode: WebSignInMode.redirect),
      );
      expect(error.code, SignInErrorCode.misconfigured);
    });

    test('completePendingSignIn: the redirect result after reload, null when '
        'there is none', () async {
      final auth = _Auth(mockUser: _alice())..redirectPending = true;
      final backend = _web(auth);
      expect(await backend.completePendingSignIn(), _aliceUser);
      expect(backend.currentUser, _aliceUser);
      expect(await backend.completePendingSignIn(), isNull);
      expect(auth.redirectResults, 2);

      final redirectMode = _Auth(mockUser: _alice())..redirectPending = true;
      expect(
        await _web(
          redirectMode,
          mode: WebSignInMode.redirect,
        ).completePendingSignIn(),
        _aliceUser,
      );

      final none = _Auth()
        ..redirectResultError = FirebaseAuthException(
          code: 'auth/no-auth-event',
        );
      expect(await _web(none).completePendingSignIn(), isNull);
    });

    test(
      'completePendingSignIn: a failed redirect → SignInException',
      () async {
        final auth = _Auth()
          ..redirectResultError = FirebaseAuthException(
            code: 'web-context-cancelled',
          );
        await expectLater(
          _web(auth).completePendingSignIn(),
          throwsA(
            isA<SignInException>().having(
              (e) => e.code,
              'code',
              SignInErrorCode.cancelled,
            ),
          ),
        );
      },
    );

    test('completePendingSignIn: popup mode and native never ask for a '
        'redirect result', () async {
      final auth = _Auth(mockUser: _alice())..redirectPending = true;
      expect(
        await _web(auth, mode: WebSignInMode.popup).completePendingSignIn(),
        isNull,
      );
      expect(
        await FirebaseAuthBackend(
          auth: auth,
          isWeb: false,
        ).completePendingSignIn(),
        isNull,
      );
      expect(auth.redirectResults, 0);
    });
  });

  group('state', () {
    test('authStateChanges: the current user on listen, then changes without '
        'repeats', () async {
      final auth = _Auth(mockUser: _alice());
      final backend = _web(auth, mode: WebSignInMode.popup);
      final seen = <AuthUser?>[];
      final sub = backend.authStateChanges().listen(seen.add);
      await pumpEventQueue();
      expect(seen, [null]);

      await backend.signInWithGoogle();
      await pumpEventQueue();
      expect(seen, [null, _aliceUser]);

      // A late listener starts with the signed-in user.
      expect(await backend.authStateChanges().first, _aliceUser);

      await backend.signOut();
      await pumpEventQueue();
      expect(seen, [null, _aliceUser, null]);
      expect(backend.currentUser, isNull);
      await sub.cancel();
    });

    test('signed in at start: currentUser and the first event', () async {
      final auth = _Auth(signedIn: true, mockUser: _alice());
      final backend = _web(auth);
      expect(backend.currentUser, _aliceUser);
      expect(await backend.authStateChanges().first, _aliceUser);
    });

    test('refreshSession forces a new id token; signed out or a rejected '
        'token → SyncBackendException(unauthenticated)', () async {
      final user = _alice();
      final auth = _Auth(mockUser: user);
      final backend = _web(auth);
      await expectLater(
        backend.refreshSession(),
        throwsA(
          isA<SyncBackendException>().having(
            (e) => e.code,
            'code',
            SyncErrorCode.unauthenticated,
          ),
        ),
      );

      await backend.signInWithGoogle();
      await backend.refreshSession();
      expect(user.tokenRequests, [true]);

      user.tokenError = FirebaseAuthException(code: 'user-token-expired');
      await expectLater(
        backend.refreshSession(),
        throwsA(
          isA<SyncBackendException>().having(
            (e) => e.code,
            'code',
            SyncErrorCode.unauthenticated,
          ),
        ),
      );
      user.tokenError = FirebaseAuthException(code: 'network-request-failed');
      await expectLater(
        backend.refreshSession(),
        throwsA(
          isA<SyncBackendException>().having(
            (e) => e.code,
            'code',
            SyncErrorCode.network,
          ),
        ),
      );
    });
  });

  group('native', () {
    test('without NativeGoogleSignIn: no Google sign-in', () async {
      final auth = _Auth(mockUser: _alice());
      final backend = FirebaseAuthBackend(auth: auth, isWeb: false);
      expect(backend.supportsGoogleSignIn, isFalse);
      expect(
        (await _signInError(backend)).code,
        SignInErrorCode.unsupportedPlatform,
      );
      expect(auth.popups, isEmpty);
      expect(auth.credentials, isEmpty);
    });

    test('with NativeGoogleSignIn: the id token → signInWithCredential; '
        'signOut signs out of both', () async {
      final auth = _Auth(mockUser: _alice());
      final native = _Native();
      final backend = FirebaseAuthBackend(
        auth: auth,
        isWeb: false,
        native: native,
      );
      expect(backend.supportsGoogleSignIn, isTrue);
      expect(await backend.signInWithGoogle(), _aliceUser);
      final credential = auth.credentials.single;
      expect(credential, isA<OAuthCredential>());
      expect((credential! as OAuthCredential).idToken, 'google-id-token');
      expect(credential.providerId, 'google.com');
      expect(auth.popups, isEmpty);

      await backend.signOut();
      expect(native.signOuts, 1);
      expect(backend.currentUser, isNull);
    });

    test('a cancelled native sign-in passes through', () async {
      final native = _Native()
        ..error = const SignInException(SignInErrorCode.cancelled, 'closed');
      final auth = _Auth(mockUser: _alice());
      final backend = FirebaseAuthBackend(
        auth: auth,
        isWeb: false,
        native: native,
      );
      expect((await _signInError(backend)).code, SignInErrorCode.cancelled);
      expect(auth.credentials, isEmpty);
    });
  });

  test('AuthService on FirebaseAuthBackend: redirect result at start, '
      'sign-out, popup sign-in', () async {
    final auth = _Auth(mockUser: _alice())..redirectPending = true;
    final service = AuthService(_web(auth));
    final states = <AuthStatus>[];
    final sub = service.states.listen((s) => states.add(s.status));
    await service.initialize();
    await pumpEventQueue();
    expect(service.state.status, AuthStatus.signedIn);
    expect(service.state.user, _aliceUser);

    await service.signOut();
    await pumpEventQueue();
    expect(service.state.status, AuthStatus.signedOut);

    expect(await service.signInWithGoogle(), _aliceUser);
    await pumpEventQueue();
    expect(service.state.status, AuthStatus.signedIn);
    expect(states, [
      AuthStatus.initializing,
      AuthStatus.signedIn,
      AuthStatus.signedOut,
      AuthStatus.signingIn,
      AuthStatus.signedIn,
    ]);
    await sub.cancel();
    await service.dispose();
  });
}
