/// Firebase adapters of sync_engine (07-sync 4.10): `FirebaseSyncBindings`,
/// `FirebaseSyncOptions`, `FirebaseSyncBackend`, `FirebaseAuthBackend`,
/// `FirebaseBlobStore` and the error mappers.
///
/// Not pure Dart: imports the Flutter Firebase plugins. Only the app shell
/// imports it, when sync is wired in at M4 (contract 00-overview 7.3.3). The
/// app does not depend on sync_engine in this scope (contract 7.1).
///
/// Foundation step B7 (00-overview 7.6): empty frame. The exports are added
/// during concurrent development (07-sync 8).
library;
