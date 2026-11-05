// Helpers of the CORE T16 browser tests (not a test file): fresh database names
// per test, and the real web store (drift WasmDatabase in drift_worker.js, blobs
// in the browser IndexedDB). The default WebStorageConfig paths resolve against
// the test page, i.e. test/web/sqlite3.wasm and test/web/drift_worker.js
// (tool/prepare_web_test.dart).
import 'package:clock/clock.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/connect/connect_browser.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:test/test.dart';

var _serial = 0;

/// A config of a database no other test uses (names are unique per run).
NoteStoreConfig freshWebConfig(
  String tag, {
  bool requestPersistentStorage = false,
  bool seedDefaultPenPresets = true,
  Clock? clock,
  IdGenerator? ids,
}) {
  final name =
      'core_t16_${tag}_${DateTime.now().microsecondsSinceEpoch}_${_serial++}';
  return NoteStoreConfig(
    databaseName: name,
    web: WebStorageConfig(blobDatabaseName: '${name}_blobs'),
    requestPersistentStorage: requestPersistentStorage,
    seedDefaultPenPresets: seedDefaultPenPresets,
    clock: clock,
    idGenerator: ids,
  );
}

/// Deletes the databases of [config] after the test (stores must be closed by
/// then: register this before the store's own close tear-down — tear-downs run
/// last registered first).
void dropAfterTest(NoteStoreConfig config) =>
    addTearDown(() => deleteLocalNoteData(config));

/// Closes [store] and deletes the databases of [config] after the test, ahead of
/// tear-downs registered earlier (a group's tearDown runs after this; closing
/// twice is a no-op).
void closeAndDropAfterTest(NoteStore store, NoteStoreConfig config) =>
    addTearDown(() async {
      await store.close();
      await deleteLocalNoteData(config);
    });

/// The web store with a fixed HLC node (openNoteStore picks a random one): the
/// same connection as openNoteStore, through DriftNoteStore.open.
Future<NoteStore> openWebStoreWithNode(
  NoteStoreConfig config,
  String deviceNodeId,
) async {
  final (executor, info) = await openNoteDatabaseExecutor(config);
  return DriftNoteStore.open(
    executor: executor,
    storageInfo: info,
    config: config,
    deviceNodeId: deviceNodeId,
    blobFactory: blobIdbFactory(config),
  );
}

/// The web backends a durable browser database may use (6.12).
const durableWebBackends = {
  StorageBackend.webOpfsShared,
  StorageBackend.webOpfsLocks,
  StorageBackend.webSharedIndexedDb,
  StorageBackend.webUnsafeIndexedDb,
};
