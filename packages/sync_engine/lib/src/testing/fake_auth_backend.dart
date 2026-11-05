import '../auth/auth_backend.dart';
import '../auth/auth_user.dart';
import '../common/errors.dart';

final class FakeAuthBackend implements AuthBackend {
  FakeAuthBackend({AuthUser? user, this.supportsGoogleSignIn = true})
    : nextSignInUser = user ?? const AuthUser(uid: 'user-1');

  @override
  final bool supportsGoogleSignIn;

  /// signInWithGoogle() resolves to this user.
  AuthUser nextSignInUser;

  void failNextSignIn(SignInException error) =>
      throw UnimplementedError('SYNC T10');

  /// refreshSession → unauthenticated.
  void failNextRefresh() => throw UnimplementedError('SYNC T10');

  /// External change (e.g. token revoked).
  void setUser(AuthUser? user) => throw UnimplementedError('SYNC T10');

  @override
  AuthUser? get currentUser => throw UnimplementedError('SYNC T10');

  @override
  Stream<AuthUser?> authStateChanges() => throw UnimplementedError('SYNC T10');

  @override
  Future<AuthUser> signInWithGoogle() => throw UnimplementedError('SYNC T10');

  @override
  Future<AuthUser?> completePendingSignIn() =>
      throw UnimplementedError('SYNC T10');

  @override
  Future<void> refreshSession() => throw UnimplementedError('SYNC T10');

  @override
  Future<void> signOut() => throw UnimplementedError('SYNC T10');
}
