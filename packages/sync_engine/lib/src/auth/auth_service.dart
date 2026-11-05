import 'dart:async';

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
  AuthService(AuthBackend? backend)
    : _backend = backend,
      _state = backend == null
          ? AuthState.unavailable
          : const AuthState(status: AuthStatus.initializing);

  final AuthBackend? _backend;
  AuthState _state;
  final StreamController<AuthState> _changes = StreamController.broadcast();
  StreamSubscription<AuthUser?>? _subscription;
  Future<void>? _initializing;
  bool _disposed = false;

  AuthState get state => _state;

  /// Emits current state on listen, then distinct changes.
  Stream<AuthState> get states => Stream.multi((controller) {
    var last = _state;
    controller.add(last);
    final sub = _changes.stream.listen((s) {
      if (s == last) return;
      last = s;
      controller.add(s);
    }, onDone: controller.close);
    controller.onCancel = sub.cancel;
  });

  bool get isAvailable => _backend != null;

  /// Calls backend.completePendingSignIn() once, then follows authStateChanges.
  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    final backend = _backend;
    if (backend == null || _disposed) return;
    SignInException? error;
    try {
      await backend.completePendingSignIn();
    } on SignInException catch (e) {
      error = e;
    }
    if (_disposed) return;
    final user = backend.currentUser;
    _emit(
      user == null
          ? AuthState(status: AuthStatus.signedOut, lastError: error)
          : AuthState(status: AuthStatus.signedIn, user: user),
    );
    _subscription = backend.authStateChanges().listen(_onUser);
  }

  void _onUser(AuthUser? user) {
    // While signInWithGoogle runs, its result decides the state.
    if (_state.status == AuthStatus.signingIn) return;
    _emit(
      user == null
          ? AuthState(status: AuthStatus.signedOut, lastError: _state.lastError)
          : AuthState(status: AuthStatus.signedIn, user: user),
    );
  }

  /// Throws SignInException (state.lastError is also set).
  Future<AuthUser> signInWithGoogle() async {
    final backend = _backend;
    if (backend == null) {
      throw const SignInException(
        SignInErrorCode.misconfigured,
        'sign-in is not configured',
      );
    }
    final before = _state;
    _emit(const AuthState(status: AuthStatus.signingIn));
    try {
      final user = await backend.signInWithGoogle();
      _emit(AuthState(status: AuthStatus.signedIn, user: user));
      return user;
    } on SignInException catch (e) {
      final user = backend.currentUser;
      _emit(
        user == null || before.status != AuthStatus.signedIn
            ? AuthState(status: AuthStatus.signedOut, lastError: e)
            : AuthState(status: AuthStatus.signedIn, user: user, lastError: e),
      );
      rethrow;
    }
  }

  Future<void> signOut() async {
    final backend = _backend;
    if (backend == null) return;
    await backend.signOut();
    _emit(const AuthState(status: AuthStatus.signedOut));
  }

  /// The engine's session refresh (6.5.4, 6.10.5): AuthBackend.refreshSession. Throws
  /// SyncBackendException(unauthenticated) when there is no backend or the session can no
  /// longer be refreshed.
  @internal
  Future<void> refreshSession() async {
    final backend = _backend;
    if (backend == null) {
      throw const SyncBackendException(
        SyncErrorCode.unauthenticated,
        'no auth backend',
      );
    }
    await backend.refreshSession();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _changes.close();
  }

  void _emit(AuthState next) {
    if (_disposed || next == _state) return;
    _state = next;
    _changes.add(next);
  }
}
