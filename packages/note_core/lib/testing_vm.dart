// package:note_core/testing_vm.dart — VM tests only (lib_exceptions, 7.4.2)
/// VM-only test helper of note_core (contract 00-overview 7.6, CORE 4.10). Import from
/// `test/` only; it uses `dart:io` / `package:drift/native.dart`.
library;

import 'dart:io';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';

import 'src/common/ids.dart';
import 'src/repo/note_store.dart';
import 'src/repo/status.dart';
import 'src/storage/connect/connect.dart';
import 'src/storage/drift_note_store.dart';

/// Real CORE on NativeDatabase (filePath null = in-memory). deviceNodeId fixes the HLC node.
/// storageInfo: value reported by NoteStore.storageInfo; null = the real backend
/// (in-memory → nativeMemory → notDurable banner).
/// CORE: two-device tests (SYNC T16, CORE 6.10 counterexample) pass different deviceNodeIds.
/// CORE: the database runs on the test isolate (NativeDatabase, no background isolate).
/// CORE: asset chunks / thumbnails live in an in-memory IndexedDB (idb_shim), kept per
/// filePath for the process so a reopened file store finds its blobs.
/// CORE: several stores open at once are intended (two devices) and every call has an
/// executor of its own, so this turns off drift's debug-only warning about the database
/// class being created more than once (driftRuntimeOptions.dontWarnAboutMultipleDatabases,
/// for the isolate — test code outside note_core has no drift dependency to do it).
/// CORE: a file database keeps SQLite's default rollback journal (no WAL, unlike
/// openNoteStore): moving the open file away makes its commits fail and be retried until it
/// is back (6.9). SYNC's S-20 integration tests rely on it; open_test_store_test pins it.
Future<NoteStore> openTestNoteStore({
  Clock? clock,
  IdGenerator? ids,
  OwnerId ownerId = kLocalOwnerId,
  String? filePath,
  String? deviceNodeId,
  bool seedDefaultPenPresets = true,
  StorageInfo? storageInfo,
}) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final config = NoteStoreConfig(
    ownerId: ownerId,
    nativeDatabasePath: filePath,
    inMemory: filePath == null,
    seedDefaultPenPresets: seedDefaultPenPresets,
    clock: clock,
    idGenerator: ids,
  );
  return DriftNoteStore.open(
    executor: filePath == null
        ? NativeDatabase.memory()
        : NativeDatabase(File(filePath)),
    storageInfo:
        storageInfo ??
        StorageInfo(
          backend: filePath == null
              ? StorageBackend.nativeMemory
              : StorageBackend.nativeFile,
        ),
    config: config,
    deviceNodeId: deviceNodeId,
    blobFactory: blobIdbFactory(config),
  );
}
