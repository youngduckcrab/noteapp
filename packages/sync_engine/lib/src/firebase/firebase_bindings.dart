import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:meta/meta.dart';

import '../auth/auth_backend.dart';
import '../auth/auth_user.dart';
import '../engine/sync_engine.dart';
import 'firebase_auth_backend.dart';

enum WebSignInMode { auto, popup, redirect }

@immutable
final class FirebaseSyncOptions {
  const FirebaseSyncOptions({
    this.webSignInMode = WebSignInMode.auto,
    this.disableFirestorePersistence = true,
    this.storageBucket,
  });
  final WebSignInMode webSignInMode;

  /// D8.
  final bool disableFirestorePersistence;

  /// null = app default bucket.
  final String? storageBucket;
}

/// Built by the app shell after Firebase.initializeApp (5.2 I-1).
final class FirebaseSyncBindings {
  FirebaseSyncBindings(
    FirebaseApp app, {
    FirebaseSyncOptions options = const FirebaseSyncOptions(),
    NativeGoogleSignIn? native,
  }) : authBackend = FirebaseAuthBackend(
         auth: FirebaseAuth.instanceFor(app: app),
         webSignInMode: options.webSignInMode,
         native: native,
       ),
       backendFactory = _unimplementedFactory;

  final AuthBackend authBackend;
  final SyncBackendFactory backendFactory;
}

Future<Never> _unimplementedFactory(AuthUser user) =>
    throw UnimplementedError('SYNC T17');

/// Native Google sign-in (iOS/Android) — implemented at the native transition
/// with google_sign_in 7.x: authenticate() → idToken.
abstract interface class NativeGoogleSignIn {
  /// Throws SignInException.
  Future<String> obtainIdToken();

  Future<void> signOut();
}
