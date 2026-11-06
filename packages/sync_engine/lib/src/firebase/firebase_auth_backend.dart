// The Firebase Auth adapter of AuthBackend (6.10). Web: Google sign-in with firebase_auth
// only (popup / redirect / auto, 6.10.1). Native: an injected NativeGoogleSignIn gives the
// Google id token for signInWithCredential (6.10.2); without it there is no Google sign-in.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_backend.dart';
import '../auth/auth_user.dart';
import '../common/errors.dart';
import 'display_mode.dart';
import 'firebase_bindings.dart';
import 'firebase_error_mapper.dart';

final class FirebaseAuthBackend implements AuthBackend {
  FirebaseAuthBackend({
    required this._auth,
    WebSignInMode webSignInMode = WebSignInMode.auto,
    this._native,
    this._isWeb = kIsWeb,
    bool Function()? isStandaloneWebApp,
  }) : _mode = webSignInMode,
       _isStandaloneWebApp = isStandaloneWebApp ?? isStandaloneDisplayMode;

  final FirebaseAuth _auth;
  final WebSignInMode _mode;
  final NativeGoogleSignIn? _native;
  final bool _isWeb;
  final bool Function() _isStandaloneWebApp;

  /// Popup failures that switch auto mode to redirect (6.10.1).
  static const Set<SignInErrorCode> _redirectFallback = {
    SignInErrorCode.popupBlocked,
    SignInErrorCode.unsupportedPlatform,
  };

  /// getRedirectResult codes that only mean "no redirect sign-in pending".
  static const Set<String> _noRedirectResult = {'no-auth-event'};

  static AuthUser? _userOf(User? user) => user == null
      ? null
      : AuthUser(
          uid: user.uid,
          email: user.email,
          displayName: user.displayName,
          photoUrl: user.photoURL,
        );

  static GoogleAuthProvider get _provider =>
      GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'});

  @override
  AuthUser? get currentUser => _userOf(_auth.currentUser);

  /// The current user first, then Firebase's changes without repeats (Firebase itself
  /// also reports the current user right after listen).
  @override
  Stream<AuthUser?> authStateChanges() => Stream.multi((controller) {
    var last = currentUser;
    controller.add(last);
    final sub = _auth.authStateChanges().listen(
      (user) {
        final next = _userOf(user);
        if (next == last) return;
        last = next;
        controller.add(next);
      },
      onError: controller.addError,
      onDone: controller.close,
    );
    controller
      ..onPause = sub.pause
      ..onResume = sub.resume
      // Not returned: first / firstWhere complete without waiting for this cancel.
      ..onCancel = () => unawaited(sub.cancel());
  });

  @override
  bool get supportsGoogleSignIn => _isWeb || _native != null;

  @override
  Future<AuthUser> signInWithGoogle() async {
    if (!_isWeb) return _signInNative();
    final mode = switch (_mode) {
      WebSignInMode.auto =>
        _isStandaloneWebApp() ? WebSignInMode.redirect : WebSignInMode.popup,
      final explicit => explicit,
    };
    if (mode == WebSignInMode.redirect) return _signInWithRedirect();
    try {
      return await _signInWithPopup();
    } on SignInException catch (e) {
      if (_mode != WebSignInMode.auto || !_redirectFallback.contains(e.code)) {
        rethrow;
      }
      return _signInWithRedirect();
    }
  }

  Future<AuthUser> _signInWithPopup() async {
    final UserCredential credential;
    try {
      credential = await _auth.signInWithPopup(_provider);
    } on Object catch (e) {
      throw mapSignInError(e);
    }
    return _signedIn(credential.user);
  }

  /// The page navigates away; after the reload the result arrives through
  /// [completePendingSignIn]. If the page stays (no navigation), the future completes
  /// with the next signed-in user Firebase reports.
  Future<AuthUser> _signInWithRedirect() async {
    try {
      await _auth.signInWithRedirect(_provider);
      final user = await authStateChanges().firstWhere((u) => u != null);
      return user!;
    } on Object catch (e) {
      throw mapSignInError(e);
    }
  }

  Future<AuthUser> _signInNative() async {
    final native = _native;
    if (native == null) {
      throw const SignInException(
        SignInErrorCode.unsupportedPlatform,
        'Google sign-in on this platform needs a NativeGoogleSignIn',
      );
    }
    final UserCredential credential;
    try {
      final idToken = await native.obtainIdToken();
      credential = await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    } on Object catch (e) {
      throw mapSignInError(e);
    }
    return _signedIn(credential.user);
  }

  static AuthUser _signedIn(User? user) {
    final signedIn = _userOf(user);
    if (signedIn == null) {
      throw const SignInException(
        SignInErrorCode.unknown,
        'sign-in finished without a user',
      );
    }
    return signedIn;
  }

  /// Web: the redirect sign-in result (getRedirectResult also waits for Firebase to
  /// restore the saved session). Popup-only web and native have no pending result.
  @override
  Future<AuthUser?> completePendingSignIn() async {
    if (!_isWeb || _mode == WebSignInMode.popup) return null;
    try {
      final credential = await _auth.getRedirectResult();
      return _userOf(credential.user);
    } on FirebaseAuthException catch (e) {
      final code = e.code.substring(e.code.lastIndexOf('/') + 1);
      if (_noRedirectResult.contains(code)) return null;
      throw mapSignInError(e);
    } on Object catch (e) {
      throw mapSignInError(e);
    }
  }

  /// Forces a new id token (6.10.5).
  @override
  Future<void> refreshSession() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const SyncBackendException(
        SyncErrorCode.unauthenticated,
        'signed out',
      );
    }
    try {
      await user.getIdToken(true);
    } on Object catch (e, s) {
      throw mapFirebaseError(e, stackTrace: s);
    }
  }

  /// (2nd round, P-C — CP-S7) User.getIdToken(forceRefresh); null when signed out. Errors
  /// go through mapFirebaseError (network-request-failed → network, user-token-expired /
  /// user-disabled → unauthenticated).
  @override
  Future<String?> idToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      return await user.getIdToken(forceRefresh);
    } on Object catch (e, s) {
      throw mapFirebaseError(e, stackTrace: s);
    }
  }

  @override
  Future<void> signOut() async {
    final native = _native;
    if (!_isWeb && native != null) await native.signOut();
    await _auth.signOut();
  }
}
