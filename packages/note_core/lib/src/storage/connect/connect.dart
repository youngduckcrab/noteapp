// lib/src/storage/connect/connect.dart (internal) — CORE 6.11 connection, 7.4.3 names.
//
// Each file provides:
//   Future<(QueryExecutor, StorageInfo)> openNoteDatabaseExecutor(NoteStoreConfig config);
//   Future<void> deleteLocalData(NoteStoreConfig config);
// (openBlobStore / createContentHasher arrive with CORE T13.)
export 'connect_stub.dart'
    if (dart.library.js_interop) 'connect_browser.dart'
    if (dart.library.ffi) 'connect_native.dart';
