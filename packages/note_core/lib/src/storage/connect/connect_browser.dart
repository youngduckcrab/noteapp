// lib/src/storage/connect/connect_browser.dart (internal) — web (drift WasmDatabase).
import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

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

/// Deletes every stored database with this name (IndexedDB or OPFS, 6.18).
/// The blob IndexedDB is added with CORE T13 / T16.
Future<void> deleteLocalData(NoteStoreConfig config) async {
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
