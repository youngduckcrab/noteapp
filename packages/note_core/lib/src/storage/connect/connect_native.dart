// lib/src/storage/connect/connect_native.dart (internal) — VM tests, later native apps.
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../common/errors.dart';
import '../../repo/note_store.dart';
import '../../repo/status.dart';

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

/// Deletes the database file and its -wal / -shm files (6.18).
Future<void> deleteLocalData(NoteStoreConfig config) async {
  final path = config.nativeDatabasePath;
  if (config.inMemory || path == null) return;
  for (final p in [path, '$path-wal', '$path-shm']) {
    final f = File(p);
    if (f.existsSync()) await f.delete();
  }
}

void _setup(Database db) {
  db
    ..execute('PRAGMA journal_mode = WAL')
    ..execute('PRAGMA synchronous = NORMAL');
}
