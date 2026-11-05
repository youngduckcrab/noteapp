// Web compile check of the Firebase and platform entry points (07-sync 8 T1,
// 9.1.3; 5.2 I-7). The app does not depend on sync_engine in this scope
// (contract 00-overview 7.1), so this test is what catches web compile errors
// in the Firebase plugins, connectivity_plus and the package:web conditional
// export. It only references types and tear-offs (T17: every adapter's
// constructor and members): Firebase is never initialised and nothing talks to
// the network.
@TestOn('browser')
library;

import 'dart:typed_data';

// cloud_firestore 7.1.0 exports its own `Type` (pipeline expressions).
import 'package:cloud_firestore/cloud_firestore.dart' hide Type;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/firebase.dart';
import 'package:sync_engine/platform.dart';
import 'package:sync_engine/src/firebase/display_mode.dart';
import 'package:sync_engine/sync_engine.dart';

void main() {
  test('firebase.dart and platform.dart compile for the web', () {
    final types = <Type>[
      FirebaseSyncBindings,
      FirebaseSyncOptions,
      WebSignInMode,
      NativeGoogleSignIn,
      FirebaseSyncBackend,
      FirestoreChunkMapper,
      FirebaseBlobStore,
      FirebaseAuthBackend,
      ConnectivityPlusSignal,
      SyncBackend,
      AuthBackend,
      ConnectivitySignal,
    ];
    expect(types.toSet(), hasLength(types.length));
    expect(FirestoreChunkMapper.collection, 'changes');
    expect(const FirebaseSyncOptions().webSignInMode, WebSignInMode.auto);
    final Object mappers = [mapFirebaseError, mapSignInError];
    expect(mappers, hasLength(2));
  });

  test('every adapter constructor and member compiles for the web (T17)', () {
    // Tear-offs and closures that are never called: they keep the adapter
    // bodies reachable for the web compiler.
    final refs = <Object>[
      FirebaseSyncBindings.new,
      (FirebaseSyncBindings b) => [b.authBackend, b.backendFactory],
      FirebaseSyncBackend.new,
      FirestoreChunkMapper.toFirestore,
      FirestoreChunkMapper.fromFirestore,
      FirebaseBlobStore.new,
      (FirebaseBlobStore s, Uint8List bytes) => [
        s.pathFor(''),
        s.stat(''),
        s.upload('', bytes, contentType: '', metadata: const {}),
        s.download('', maxBytes: 1),
      ],
      FirebaseAuthBackend.new,
      (FirebaseAuthBackend a) => [
        a.currentUser,
        a.authStateChanges(),
        a.supportsGoogleSignIn,
        a.signInWithGoogle(),
        a.completePendingSignIn(),
        a.refreshSession(),
        a.signOut(),
      ],
      ConnectivityPlusSignal.new,
      (ConnectivityPlusSignal c) => [c.isOnline, c.changes, c.dispose()],
      (FirebaseAuth auth) => auth.signInWithRedirect(GoogleAuthProvider()),
      (FirebaseAuth auth) =>
          auth.signInWithCredential(GoogleAuthProvider.credential(idToken: '')),
      (User user) => user.getIdToken(true),
      (Reference ref) => [ref.getMetadata(), ref.getData(1)],
      (UploadTask task) => [task.snapshotEvents, task.cancel()],
      () => const Settings(persistenceEnabled: false),
    ];
    expect(refs, hasLength(17));
  });

  test('the plugin APIs the adapters build on compile for the web', () {
    // Tear-offs and closures that are never called.
    final refs = <Object>[
      Firebase.initializeApp,
      FirebaseFirestore.instanceFor,
      FieldValue.serverTimestamp,
      Blob.new,
      () => FieldPath.documentId,
      (Query<Map<String, dynamic>> query) => query.count().get(),
      (Query<Map<String, dynamic>> query) => query.snapshots(),
      (WriteBatch batch) => batch.commit(),
      FirebaseAuth.instanceFor,
      (FirebaseAuth auth) => auth.signInWithPopup(GoogleAuthProvider()),
      (FirebaseAuth auth) => auth.getRedirectResult(),
      FirebaseStorage.instanceFor,
      (Reference ref, Uint8List bytes) => ref.putData(
        bytes,
        SettableMetadata(customMetadata: const {'sha256': ''}),
      ),
      Connectivity.new,
      (Connectivity c) => c.onConnectivityChanged,
    ];
    expect(refs, hasLength(15));
  });

  test('the display-mode conditional export picks the browser file', () {
    // Headless test page: not a home-screen web app.
    expect(isStandaloneDisplayMode(), isFalse);
  });
}
