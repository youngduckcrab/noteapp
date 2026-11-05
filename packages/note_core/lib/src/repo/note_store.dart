// lib/src/repo/note_store.dart — contract 00-overview 7.2.12 / CORE 4.8.1, 6.18.
// Contract comments are kept verbatim (they contain <placeholders>).
// ignore_for_file: unintended_html_in_doc_comment
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show QueryExecutor;
import 'package:meta/meta.dart';

import '../assets/asset_store.dart';
import '../common/ids.dart';
import '../session/note_session.dart';
import '../storage/connect/connect.dart';
import '../storage/drift_note_store.dart';
import '../storage/open_errors.dart';
import '../sync/sync_store.dart';
import 'content_reader.dart';
import 'events.dart';
import 'library_repository.dart';
import 'pen_preset_repository.dart';
import 'settings_repository.dart';
import 'status.dart';
import 'trash_repository.dart';

/// (v1.1) Paths are resolved with Uri.base.resolve(path), so an absolute URL is used as is.
/// In production the app shell ALWAYS passes absolute URLs resolved against
/// document.baseURI (01-infra 6.4) — dart2js Uri.base is location.href, which breaks
/// relative paths on deep links such as /notes/<id>. Relative paths are for tests only.
@immutable
final class WebStorageConfig {
  const WebStorageConfig({
    this.sqlite3WasmPath = 'sqlite3.wasm',
    this.driftWorkerPath = 'drift_worker.js',
    this.blobDatabaseName = 'noteapp_blobs',
  });

  // Uri.base.resolve(path); absolute URLs pass through
  final String sqlite3WasmPath;
  final String driftWorkerPath; // same rule
  final String blobDatabaseName; // IndexedDB database for assets/thumbnails

  @override
  bool operator ==(Object other) =>
      other is WebStorageConfig &&
      other.sqlite3WasmPath == sqlite3WasmPath &&
      other.driftWorkerPath == driftWorkerPath &&
      other.blobDatabaseName == blobDatabaseName;

  @override
  int get hashCode =>
      Object.hash(sqlite3WasmPath, driftWorkerPath, blobDatabaseName);
}

@immutable
final class NoteStoreConfig {
  const NoteStoreConfig({
    this.databaseName = 'noteapp',
    this.ownerId = kLocalOwnerId,
    this.web = const WebStorageConfig(),
    this.nativeDatabasePath, // native only (later); VM tests: file path
    this.inMemory = false, // VM tests
    this.trashRetention = const Duration(days: 30),
    this.requestPersistentStorage = true,
    this.seedDefaultPenPresets = true,
    this.clock, // tests
    this.idGenerator, // tests
  });

  final String databaseName;

  /// Used only when a NEW database is created; a persisted owner (after reassignOwner) wins.
  final OwnerId ownerId;
  final WebStorageConfig web;
  final String? nativeDatabasePath;

  /// (v1.1) inMemory: true reports StorageBackend.nativeMemory → isDurable == false →
  /// storageWarningOf == notDurable, i.e. the storage banner shows (tests expect it).
  final bool inMemory;
  final Duration trashRetention;

  /// Web: persist() is called during open and awaited at most 1 s; the result goes to
  /// StorageInfo.persistGranted.
  final bool requestPersistentStorage;
  final bool seedDefaultPenPresets;
  final Clock? clock;
  final IdGenerator? idGenerator;
}

abstract interface class NoteStore {
  OwnerId get ownerId; // current owner (switches at runtime on reassignOwner)
  LibraryRepository get library;
  TrashRepository get trash;
  PenPresetRepository get penPresets;
  SettingsRepository get settings;
  NoteContentReader get content;
  AssetStore get assets;
  ThumbnailCache get thumbnails;
  SyncStore get sync;
  Stream<ChangeBatch> get changes;
  PersistenceStatus get persistenceStatus;

  /// (v1.1) Emits the current persistenceStatus ONCE right after each listen, then on every
  /// change (same rule as the watch streams, LIBRARY C-1). The fake store does the same.
  Stream<PersistenceStatus> get persistenceStatusStream;
  StorageInfo get storageInfo; // latest value (updated by refreshStorageInfo)
  IdGenerator get ids; // the store's generator (UUIDv7 in production)
  Clock get clock; // package:clock
  Future<StorageInfo> refreshStorageInfo(); // re-query persisted() / estimate()

  /// One live session per note, reference-counted (7.2.8 N-5, N-6).
  Future<NoteSession> openSession(
    NoteId noteId, {
    NoteSessionOptions options = const NoteSessionOptions(),
  });

  /// Every queued write committed; pending (no error) while a commit is retried
  /// (4.5 head, 7.2.9 v1.2).
  Future<void> flush();
  Future<void> close();

  /// (v1.1) Backup (7.8, CORE 6.17): every active and trashed entity as CORE 6.3 JSON with
  /// field versions + asset metadata, NO asset bytes, no device settings / sync meta /
  /// thumbnails. One UTF-8 JSON document, deterministic order. Flushes first.
  Future<Uint8List> exportBackupJson();
}

/// Opens (and migrates) the database. Throws NoteStoreOpenException.
/// CORE: 6.18 — every failure is classified; the connection is closed before throwing.
Future<NoteStore> openNoteStore(NoteStoreConfig config) async {
  final QueryExecutor executor;
  final StorageInfo info;
  try {
    (executor, info) = await openNoteDatabaseExecutor(config);
  } on Object catch (e, s) {
    Error.throwWithStackTrace(classifyOpenError(e), s);
  }
  return DriftNoteStore.open(
    executor: executor,
    storageInfo: info,
    config: config,
  );
}

/// Drops the SQLite DB and the blob IndexedDB of [config] (startup error screen reset).
/// CORE: 6.18 — StateError while a store of the same database is open in this process.
Future<void> deleteLocalNoteData(NoteStoreConfig config) async {
  if (isStoreOpen(config)) {
    throw StateError(
      'deleteLocalNoteData: close the open NoteStore of this database first',
    );
  }
  await deleteLocalData(config);
}
