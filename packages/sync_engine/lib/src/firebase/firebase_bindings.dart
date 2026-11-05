// cloud_firestore 7.1.0 exports its own `Type` (pipeline expressions).
import 'package:cloud_firestore/cloud_firestore.dart' hide Type;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:meta/meta.dart';

import '../auth/auth_backend.dart';
import '../engine/sync_engine.dart';
import 'backend_factory.dart';
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
       backendFactory = firebaseBackendFactory(
         firestore: () => FirebaseFirestore.instanceFor(app: app),
         storage: () => FirebaseStorage.instanceFor(
           app: app,
           bucket: options.storageBucket,
         ),
         disablePersistence: options.disableFirestorePersistence,
       );

  final AuthBackend authBackend;

  /// A FirebaseSyncBackend on the Firestore of the app (persistence off by default, D8)
  /// and its Storage bucket, both set up at the first sign-in.
  final SyncBackendFactory backendFactory;
}

/// Native Google sign-in (iOS/Android) — implemented at the native transition
/// with google_sign_in 7.x: authenticate() → idToken.
abstract interface class NativeGoogleSignIn {
  /// Throws SignInException.
  Future<String> obtainIdToken();

  Future<void> signOut();
}
