import 'auth_user.dart';

abstract interface class AuthBackend {
  AuthUser? get currentUser;

  /// Emits the current user on listen, then every change.
  Stream<AuthUser?> authStateChanges();

  bool get supportsGoogleSignIn;

  /// Throws SignInException. On web this may navigate away (redirect mode);
  /// the result then arrives via [completePendingSignIn] after reload.
  Future<AuthUser> signInWithGoogle();

  /// Web redirect result after reload; null if none. Never throws for "no result".
  Future<AuthUser?> completePendingSignIn();

  /// Refreshes the id token. Throws SyncBackendException(unauthenticated) if the
  /// session can no longer be refreshed.
  Future<void> refreshSession();

  Future<void> signOut();

  /// (2nd round, P-C — CP-S7) Firebase ID token of the signed-in user (null when signed
  /// out). [forceRefresh] → new token.
  /// Errors: SyncBackendException (network → network, revoked → unauthenticated).
  Future<String?> idToken({bool forceRefresh = false});
}
