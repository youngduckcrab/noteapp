import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_backend.dart';
import '../auth/auth_user.dart';
import 'display_mode.dart';
import 'firebase_bindings.dart';

final class FirebaseAuthBackend implements AuthBackend {
  FirebaseAuthBackend({
    required FirebaseAuth auth,
    WebSignInMode webSignInMode = WebSignInMode.auto,
    NativeGoogleSignIn? native,
    bool isWeb = kIsWeb,
    bool Function()? isStandaloneWebApp,
  }) : _isStandaloneWebApp = isStandaloneWebApp ?? isStandaloneDisplayMode;

  // ignore: unused_field
  final bool Function() _isStandaloneWebApp;

  @override
  AuthUser? get currentUser => throw UnimplementedError('SYNC T17');

  @override
  Stream<AuthUser?> authStateChanges() => throw UnimplementedError('SYNC T17');

  @override
  bool get supportsGoogleSignIn => throw UnimplementedError('SYNC T17');

  @override
  Future<AuthUser> signInWithGoogle() => throw UnimplementedError('SYNC T17');

  @override
  Future<AuthUser?> completePendingSignIn() =>
      throw UnimplementedError('SYNC T17');

  @override
  Future<void> refreshSession() => throw UnimplementedError('SYNC T17');

  @override
  Future<void> signOut() => throw UnimplementedError('SYNC T17');
}
