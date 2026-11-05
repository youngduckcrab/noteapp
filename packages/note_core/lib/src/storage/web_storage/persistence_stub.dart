// lib/src/storage/web_storage/persistence_stub.dart (internal) — off the web there
// is no navigator.storage: StorageInfo keeps persistGranted / usage / quota null.
import 'storage_query.dart';

StorageQuery? platformStorageQuery() => null;
