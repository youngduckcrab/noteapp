// The backend factory of FirebaseSyncBindings (4.10, internal): one Firestore and one
// Storage per bindings, Firestore persistence off before its first use (D8 — the engine
// keeps its own cursor and CORE keeps the data), a FirebaseSyncBackend per signed-in user.
// cloud_firestore 7.1.0 exports its own `Type` (pipeline expressions).
import 'package:cloud_firestore/cloud_firestore.dart' hide Type;
import 'package:firebase_storage/firebase_storage.dart';

import '../engine/sync_engine.dart';
import 'firebase_blob_store.dart';
import 'firebase_sync_backend.dart';

/// [firestore] and [storage] are called once, at the first sign-in.
SyncBackendFactory firebaseBackendFactory({
  required FirebaseFirestore Function() firestore,
  required FirebaseStorage Function() storage,
  required bool disablePersistence,
}) {
  FirebaseFirestore? db;
  FirebaseStorage? blobs;
  return (user) async {
    final store = db ??= () {
      final created = firestore();
      if (disablePersistence) {
        created.settings = const Settings(persistenceEnabled: false);
      }
      return created;
    }();
    return FirebaseSyncBackend(
      firestore: store,
      blobs: FirebaseBlobStore(storage: blobs ??= storage(), uid: user.uid),
      uid: user.uid,
    );
  };
}
