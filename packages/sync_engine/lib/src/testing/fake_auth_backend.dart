import 'dart:async';

import '../auth/auth_backend.dart';
import '../auth/auth_user.dart';
import '../common/errors.dart';

final class FakeAuthBackend implements AuthBackend {
  FakeAuthBackend({AuthUser? user, this.supportsGoogleSignIn = true})
    : _user = user,
      nextSignInUser = user ?? const AuthUser(uid: 'user-1');

  @override
  final bool supportsGoogleSignIn;

  /// signInWithGoogle() resolves to this user.
  AuthUser nextSignInUser;

  AuthUser? _user;
  SignInException? _signInFailure;
  bool _refreshFails = false;
  final StreamController<AuthUser?> _changes = StreamController.broadcast();

  void failNextSignIn(SignInException error) => _signInFailure = error;

  /// refreshSession → unauthenticated.
  void failNextRefresh() => _refreshFails = true;

  /// External change (e.g. token revoked).
  void setUser(AuthUser? user) {
    if (user == _user) return;
    _user = user;
    _changes.add(user);
  }

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> authStateChanges() => Stream.multi((controller) {
    controller.add(_user);
    final sub = _changes.stream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });

  @override
  Future<AuthUser> signInWithGoogle() async {
    final failure = _signInFailure;
    if (failure != null) {
      _signInFailure = null;
      throw failure;
    }
    final user = nextSignInUser;
    setUser(user);
    return user;
  }

  @override
  Future<AuthUser?> completePendingSignIn() async => null;

  @override
  Future<void> refreshSession() async {
    if (_refreshFails) {
      _refreshFails = false;
      throw const SyncBackendException(
        SyncErrorCode.unauthenticated,
        'session cannot be refreshed (fake)',
      );
    }
    if (_user == null) {
      throw const SyncBackendException(
        SyncErrorCode.unauthenticated,
        'not signed in (fake)',
      );
    }
  }

  @override
  Future<void> signOut() async => setUser(null);

  int _tokenSerial = 1;

  /// (2nd round, P-C — CP-S7) `'fake-id-token:<uid>:<n>'` of the signed-in user (null when
  /// signed out); [forceRefresh] gives the next n. Not a JWT — fake backends only.
  @override
  Future<String?> idToken({bool forceRefresh = false}) async {
    final user = _user;
    if (user == null) return null;
    if (forceRefresh) _tokenSerial++;
    return 'fake-id-token:${user.uid}:$_tokenSerial';
  }
}
