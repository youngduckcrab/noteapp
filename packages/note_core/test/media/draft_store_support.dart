// Helpers of the CORE T31 draft store tests on the VM (not a test file): a SQLite file
// database plus an in-memory IndexedDB blob factory — opened again over the same two, a store
// sees the same rows and chunks (and runs its first-use orphan cleanup).
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';

import '../storage/storage_support.dart';

/// A store over [path] and [blobs] (the same data when opened again).
Future<DriftNoteStore> openDraftStore(
  String path,
  IdbFactory blobs, {
  Clock? clock,
}) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return DriftNoteStore.open(
    executor: NativeDatabase(File(path)),
    storageInfo: const StorageInfo(backend: StorageBackend.nativeFile),
    config: NoteStoreConfig(
      nativeDatabasePath: path,
      seedDefaultPenPresets: false,
      clock: clock,
      idGenerator: SequentialIdGenerator(),
    ),
    deviceNodeId: kTestNode,
    blobFactory: blobs,
  );
}
