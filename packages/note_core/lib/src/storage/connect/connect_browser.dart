// lib/src/storage/connect/connect_browser.dart (internal) — web (drift WasmDatabase).
import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:idb_shim/idb_browser.dart';

import '../../common/errors.dart';
import '../../repo/note_store.dart';
import '../../repo/status.dart';

Future<(QueryExecutor, StorageInfo)> openNoteDatabaseExecutor(
  NoteStoreConfig config,
) async {
  final WasmDatabaseResult result;
  try {
    result = await WasmDatabase.open(
      databaseName: config.databaseName,
      sqlite3Uri: Uri.base.resolve(config.web.sqlite3WasmPath),
      driftWorkerUri: Uri.base.resolve(config.web.driftWorkerPath),
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

/// Deletes every stored database with this name (IndexedDB or OPFS) and the blob
/// IndexedDB (6.18).
Future<void> deleteLocalData(NoteStoreConfig config) async {
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
