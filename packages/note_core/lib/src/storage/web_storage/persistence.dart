// lib/src/storage/web_storage/persistence.dart (internal) — CORE 6.12.
//
// Each file provides:
//   StorageQuery? platformStorageQuery();   // navigator.storage on the web, null elsewhere
export 'persistence_stub.dart'
    if (dart.library.js_interop) 'persistence_browser.dart';
