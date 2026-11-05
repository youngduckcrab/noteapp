/// Firebase adapters of sync_engine (07-sync 4.10): `FirebaseSyncBindings`,
/// `FirebaseSyncOptions`, `FirebaseSyncBackend`, `FirebaseAuthBackend`,
/// `FirebaseBlobStore` and the error mappers.
///
/// Not pure Dart: imports the Flutter Firebase plugins. Only the app shell
/// imports it, when sync is wired in at M4 (contract 00-overview 7.3.3). The
/// app does not depend on sync_engine in this scope (contract 7.1).
///
/// Exports the 4.10 adapter files (07-sync 4.0 table). display_mode*.dart
/// stays internal.
library;

export 'src/firebase/firebase_auth_backend.dart';
export 'src/firebase/firebase_bindings.dart';
export 'src/firebase/firebase_blob_store.dart';
export 'src/firebase/firebase_error_mapper.dart';
export 'src/firebase/firebase_sync_backend.dart';
export 'src/firebase/firestore_chunk_mapper.dart';
