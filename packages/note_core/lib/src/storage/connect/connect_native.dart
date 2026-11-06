// lib/src/storage/connect/connect_native.dart (internal) — VM tests and the native apps.
// (v2) m5-7/02-core 6.15.3 (공통-1): a durable native store needs both nativeDatabasePath and
// nativeAssetDirectoryPath — a file database plus file blobs.
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:idb_shim/idb_client_memory.dart'
    show IdbFactory, newIdbFactoryMemory;
import 'package:sqlite3/sqlite3.dart';

import '../../assets/blob_store.dart';
import '../../assets/file_blob_store_native.dart';
import '../../common/errors.dart';
import '../../repo/note_store.dart';
import '../../repo/status.dart';
import '../v1_copy/v1_copy_file.dart' show v1CopyPathOf, v1CopyTempPathOf;

/// (v2) 6.15.3: in memory, or a file database whose parent directory CORE makes when it is
/// missing. Without both native paths → storageUnavailable; so is a parent directory that
/// cannot be made.
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
  if (path == null || config.nativeAssetDirectoryPath == null) {
    throw const NoteStoreOpenException(
      NoteStoreOpenFailure.storageUnavailable,
      'NoteStoreConfig.nativeDatabasePath and nativeAssetDirectoryPath are both '
      'required off the web (or inMemory: true).',
    );
  }
  final file = File(path);
  try {
    await file.parent.create(recursive: true);
  } on FileSystemException catch (e) {
    throw NoteStoreOpenException(
      NoteStoreOpenFailure.storageUnavailable,
      'The directory of the database file cannot be made: ${e.message} '
      '(${e.path})',
      cause: e,
    );
  }
  return (
    NativeDatabase.createInBackground(file, setup: _setup),
    const StorageInfo(backend: StorageBackend.nativeFile),
  );
}

/// (v2) 6.15.3: the file blobs under nativeAssetDirectoryPath of a durable native config
/// (null in memory or without that path — openNoteDatabaseExecutor refuses such a config).
/// A root or a subdirectory that cannot be made or written → storageUnavailable.
Future<BlobDatabase?> openFileBlobDatabase(NoteStoreConfig config) async {
  final root = config.nativeAssetDirectoryPath;
  if (config.inMemory || root == null) return null;
  try {
    return await FileBlobDatabase.open(root);
  } on FileSystemException catch (e) {
    throw NoteStoreOpenException(
      NoteStoreOpenFailure.storageUnavailable,
      'The blob directory cannot be used: ${e.message} (${e.path})',
      cause: e,
    );
  }
}

/// Deletes the database file and its -wal / -shm files, (v2) the v1 copy made before the
/// upgrade and its temporary file (6.12.4), and the blobs of that store: the 'blobs' and
/// 'thumbs' directories under nativeAssetDirectoryPath (6.15.3 — the root itself stays),
/// or the in-memory blob database of a test file store (openTestNoteStore).
Future<void> deleteLocalData(NoteStoreConfig config) async {
  if (config.inMemory) return;
  final path = config.nativeDatabasePath;
  if (path != null) {
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
  final root = config.nativeAssetDirectoryPath;
  if (root != null) {
    for (final name in [kFileBlobsDirectory, kFileThumbnailsDirectory]) {
      final dir = Directory('$root/$name');
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  }
}

/// In-memory blob factories of file databases opened without file blobs
/// (openTestNoteStore), kept for the process so a store reopened on the same file finds
/// its blobs.
final Map<String, IdbFactory> _blobFactories = {};

/// The blob IndexedDB factory of [config]: a fresh in-memory one for an in-memory
/// database, the process-wide one of the file otherwise (not used when the config has
/// file blobs — openFileBlobDatabase).
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
