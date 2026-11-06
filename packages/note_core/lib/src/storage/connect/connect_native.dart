// lib/src/storage/connect/connect_native.dart (internal) — VM tests, later native apps.
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:idb_shim/idb_client_memory.dart'
    show IdbFactory, newIdbFactoryMemory;
import 'package:sqlite3/sqlite3.dart';

import '../../common/errors.dart';
import '../../repo/note_store.dart';
import '../../repo/status.dart';
import '../v1_copy/v1_copy_file.dart' show v1CopyPathOf, v1CopyTempPathOf;

Future<(QueryExecutor, StorageInfo)> openNoteDatabaseExecutor(
  NoteStoreConfig config,
) async {
  if (config.inMemory) {
    return (
      NativeDatabase.memory(setup: _setup),
      const StorageInfo(backend: StorageBackend.nativeMemory),
    );
  }
  final path = config.nativeDatabasePath;
  if (path == null) {
    throw const NoteStoreOpenException(
      NoteStoreOpenFailure.storageUnavailable,
      'NoteStoreConfig.nativeDatabasePath is required off the web '
      '(or inMemory: true).',
    );
  }
  return (
    NativeDatabase.createInBackground(File(path), setup: _setup),
    const StorageInfo(backend: StorageBackend.nativeFile),
  );
}

/// Deletes the database file and its -wal / -shm files, (v2) the v1 copy made before the
/// upgrade and its temporary file (6.12.4), and the blob database of that file (6.18).
Future<void> deleteLocalData(NoteStoreConfig config) async {
  final path = config.nativeDatabasePath;
  if (config.inMemory || path == null) return;
  for (final p in [
    path,
    '$path-wal',
    '$path-shm',
    v1CopyPathOf(path),
    v1CopyTempPathOf(path),
  ]) {
    final f = File(p);
    if (f.existsSync()) await f.delete();
  }
  _blobFactories.remove(path);
}

/// In-memory blob factories of file databases, kept for the process so a store
/// reopened on the same file finds its blobs (native file blobs come later, 1.3).
final Map<String, IdbFactory> _blobFactories = {};

/// The blob IndexedDB factory of [config]: a fresh in-memory one for an in-memory
/// database, the process-wide one of the file otherwise.
IdbFactory blobIdbFactory(NoteStoreConfig config) {
  final path = config.nativeDatabasePath;
  if (config.inMemory || path == null) return newIdbFactoryMemory();
  return _blobFactories.putIfAbsent(path, newIdbFactoryMemory);
}

void _setup(Database db) {
  db
    ..execute('PRAGMA journal_mode = WAL')
    ..execute('PRAGMA synchronous = NORMAL');
}
