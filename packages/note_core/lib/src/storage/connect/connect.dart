// lib/src/storage/connect/connect.dart (internal) — CORE 6.11 connection, 7.4.3 names.
//
// Each file provides:
//   Future<(QueryExecutor, StorageInfo)> openNoteDatabaseExecutor(NoteStoreConfig config);
//   Future<void> deleteLocalData(NoteStoreConfig config);   // SQLite DB + blob IndexedDB
//   IdbFactory blobIdbFactory(NoteStoreConfig config);       // asset chunks / thumbnails (6.13)
//   Future<BlobDatabase?> openFileBlobDatabase(NoteStoreConfig config);
//       // (v2) native file blobs (m5-7/02-core 6.15.3); null on the web, in memory, stub
export 'connect_stub.dart'
    if (dart.library.js_interop) 'connect_browser.dart'
    if (dart.library.ffi) 'connect_native.dart';
