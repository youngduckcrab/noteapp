// lib/src/storage/connect/connect_browser.dart (internal) — web (drift WasmDatabase).
import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:idb_shim/idb_browser.dart';
import 'package:meta/meta.dart';

import '../../assets/blob_store.dart';
import '../../common/errors.dart';
import '../../repo/note_store.dart';
import '../../repo/status.dart';

/// (v2) [initialDatabaseBytes] (tests — m5-7/02-core 6.12.3 V7): the bytes of a database
/// file that drift writes when no database of this name exists yet (WasmDatabase.open
/// initializeDatabase); the V7 browser test starts a new web database from the fixture.
Future<(QueryExecutor, StorageInfo)> openNoteDatabaseExecutor(
  NoteStoreConfig config, {
  @visibleForTesting FutureOr<Uint8List?> Function()? initialDatabaseBytes,
}) async {
  final WasmDatabaseResult result;
  try {
    result = await WasmDatabase.open(
      databaseName: config.databaseName,
      sqlite3Uri: Uri.base.resolve(config.web.sqlite3WasmPath),
      driftWorkerUri: Uri.base.resolve(config.web.driftWorkerPath),
      initializeDatabase: initialDatabaseBytes,
    );
  } on Object catch (e) {
    throw NoteStoreOpenException(
      NoteStoreOpenFailure.storageUnavailable,
      'The web database could not be started ($e).',
      cause: e,
    );
  }
  final missing = [for (final f in result.missingFeatures) f.name]..sort();
  return (
    result.resolvedExecutor,
    StorageInfo(
      backend: _backendOf(result.chosenImplementation),
      missingBrowserFeatures: List.unmodifiable(missing),
    ),
  );
}

/// The blob IndexedDB factory (6.13): the browser's IndexedDB (memory when the
/// browser has none); in memory for NoteStoreConfig.inMemory.
IdbFactory blobIdbFactory(NoteStoreConfig config) =>
    config.inMemory ? newIdbFactoryMemory() : idbFactoryBrowser;

/// (v2) The web keeps its blobs in IndexedDB (6.15.3 — file blobs are native only).
Future<BlobDatabase?> openFileBlobDatabase(NoteStoreConfig config) async =>
    null;

/// How long the web reset waits while another tab keeps a database open (6.18).
const Duration deleteBlockedTimeout = Duration(seconds: 10);

/// Deletes every stored database with this name (IndexedDB or OPFS) and the blob
/// IndexedDB (6.18). A deletion blocked by another tab's open connection throws
/// TimeoutException after [timeout] (the browser keeps the request pending).
Future<void> deleteLocalData(
  NoteStoreConfig config, {
  @visibleForTesting Duration timeout = deleteBlockedTimeout,
}) => _deleteAll(config).timeout(
  timeout,
  onTimeout: () => throw TimeoutException(
    'The local databases of "${config.databaseName}" are still open in '
    'another tab',
    timeout,
  ),
);

Future<void> _deleteAll(NoteStoreConfig config) async {
  await idbFactoryBrowser.deleteDatabase(config.web.blobDatabaseName);
  final probe = await WasmDatabase.probe(
    sqlite3Uri: Uri.base.resolve(config.web.sqlite3WasmPath),
    driftWorkerUri: Uri.base.resolve(config.web.driftWorkerPath),
    databaseName: config.databaseName,
  );
  for (final existing in probe.existingDatabases) {
    if (existing.$2 == config.databaseName) {
      await probe.deleteDatabase(existing);
    }
  }
}

StorageBackend _backendOf(WasmStorageImplementation impl) => switch (impl) {
  WasmStorageImplementation.opfsShared => StorageBackend.webOpfsShared,
  WasmStorageImplementation.opfsLocks => StorageBackend.webOpfsLocks,
  WasmStorageImplementation.sharedIndexedDb =>
    StorageBackend.webSharedIndexedDb,
  WasmStorageImplementation.unsafeIndexedDb =>
    StorageBackend.webUnsafeIndexedDb,
  WasmStorageImplementation.inMemory => StorageBackend.webInMemory,
};
