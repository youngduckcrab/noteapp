import 'package:meta/meta.dart';

import '../common/errors.dart';
import 'auth_backend.dart';
import 'auth_user.dart';

enum AuthStatus { unavailable, initializing, signedOut, signingIn, signedIn }

@immutable
final class AuthState {
  const AuthState({required this.status, this.user, this.lastError});
  static const AuthState unavailable = AuthState(
    status: AuthStatus.unavailable,
  );
  final AuthStatus status;

  /// Non-null iff status == signedIn.
  final AuthUser? user;

  /// Last failed sign-in, cleared on next attempt.
  final SignInException? lastError;

  /// (contract 7.2.20 v1.1) Value equality: status, user (AuthUser ==), and lastError by
  /// identity (each failed attempt is a new exception object = a real change).
  @override
  bool operator ==(Object other) =>
      other is AuthState &&
      other.status == status &&
      other.user == user &&
      identical(other.lastError, lastError);

  @override
  int get hashCode => Object.hash(status, user, identityHashCode(lastError));

  @override
  String toString() => 'AuthState(${status.name}, $user)';
}

/// Thin state holder used by UI (login / settings) and by the engine.
final class AuthService {
  /// [backend] null → AuthStatus.unavailable forever (Firebase not configured).
  AuthService(AuthBackend? backend);

  AuthState get state => throw UnimplementedError('SYNC T14');

  /// Emits current state on listen, then distinct changes.
  Stream<AuthState> get states => throw UnimplementedError('SYNC T14');

  bool get isAvailable => throw UnimplementedError('SYNC T14');

  /// Calls backend.completePendingSignIn() once, then follows authStateChanges.
  Future<void> initialize() => throw UnimplementedError('SYNC T14');

  /// Throws SignInException (state.lastError is also set).
  Future<AuthUser> signInWithGoogle() => throw UnimplementedError('SYNC T14');

  Future<void> signOut() => throw UnimplementedError('SYNC T14');

  Future<void> dispose() => throw UnimplementedError('SYNC T14');
}
