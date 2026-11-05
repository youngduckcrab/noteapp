// lib/src/storage/drift_note_store.dart (internal) — the SQLite NoteStore (CORE 6.1, 6.18).
//
// T6 opens the database, classifies open errors and keeps the per-device kv
// values (device node, HLC, owner); T7 the write queue; T8 the library and the
// content reader; T9 the trash; T10 note sessions; T12 pen presets and settings;
// T13 assets and thumbnails (blob IndexedDB); T14 the sync window; T19 the backup export.
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:meta/meta.dart';

import '../assets/asset_store_impl.dart';
import '../assets/blob_store.dart';
import '../assets/idb_blob_store.dart';
import '../assets/thumbnail_cache_impl.dart';
import '../backup/backup_export.dart';
import '../common/hlc.dart';
import '../common/ids.dart';
import '../migration/note_migrator.dart';
import '../model/sync_entity.dart';
import '../repo/content_reader.dart';
import '../repo/events.dart';
import '../repo/note_store.dart';
import '../repo/status.dart';
import '../session/note_session.dart';
import 'change_bus.dart';
import 'db/note_database.dart';
import 'drift_content_reader.dart';
import 'drift_library_repository.dart';
import 'drift_pen_preset_repository.dart';
import 'drift_sessions.dart';
import 'drift_settings_repository.dart';
import 'drift_sync_store.dart';
import 'drift_trash_repository.dart';
import 'kv_keys.dart';
import 'open_errors.dart';
import 'row_mappers.dart';
import 'watch_hub.dart';
import 'write_queue.dart';

/// Open stores per durable database in this process (deleteLocalNoteData refuses
/// to delete an open one, 6.18). In-memory stores are not counted.
final Map<String, int> _openStoreCounts = {};

/// The identity of the durable database of [config]; null for in-memory.
String? storeKeyOf(NoteStoreConfig config) => config.inMemory
    ? null
    : (config.nativeDatabasePath != null
          ? 'file:${config.nativeDatabasePath}'
          : 'name:${config.databaseName}');

/// Whether a store for the database of [config] is open in this process.
bool isStoreOpen(NoteStoreConfig config) {
  final key = storeKeyOf(config);
  return key != null && _openStoreCounts.containsKey(key);
}

final class DriftNoteStore implements NoteStore {
  DriftNoteStore._({
    required this.db,
    required this.config,
    required this._storageInfo,
    required this.nodeId,
    required this.hlc,
    required this._ownerId,
    required this.clock,
    required this.ids,
    required this._storeKey,
    required String? persistedHlc,
    required this.blobs,
    BlobStore? assetChunks,
  }) {
    queue = WriteQueue(
      db: db,
      hlc: hlc,
      clock: clock,
      bus: bus,
      watches: watches,
      persistedHlc: persistedHlc,
    );
    library = DriftLibraryRepository(this);
    trash = DriftTrashRepository(this);
    penPresets = DriftPenPresetRepository(this);
    settings = DriftSettingsRepository(this);
    content = DriftContentReader(db);
    thumbnails = ThumbnailCacheImpl(blobs.thumbnails);
    assets = AssetStoreImpl(
      this,
      chunks: assetChunks ?? blobs.chunks,
      thumbnailBytes: thumbnails.totalBytes,
    );
    sync = DriftSyncStore(this);
    sessions = DriftSessions(this);
    queue.onCommitted = sessions.committed;
    _noteMigrator = NoteMigrator(kNoteMigrationSteps, store: this);
  }

  /// Opens [executor] as a note database: runs the schema steps (6.15), reads or
  /// creates the kv values and returns the store. Every failure is a
  /// NoteStoreOpenException (6.18) and closes the executor first.
  ///
  /// [deviceNodeId] fixes the HLC node (openTestNoteStore); null = the stored
  /// node, or a new random one for a new database. [autoPurge] starts the trash
  /// clean-up timers (openNoteStore, 6.8). [blobFactory]: the IndexedDB factory of
  /// asset chunks and thumbnails (null = a fresh in-memory one, 6.13); the blob
  /// database opens on first use. [assetChunks] replaces the chunk store (tests).
  static Future<DriftNoteStore> open({
    required QueryExecutor executor,
    required StorageInfo storageInfo,
    required NoteStoreConfig config,
    String? deviceNodeId,
    bool autoPurge = false,
    IdbFactory? blobFactory,
    @visibleForTesting BlobStore? assetChunks,
    @visibleForTesting NoteDatabase Function(QueryExecutor)? databaseFactory,
  }) async {
    if (deviceNodeId != null && !isValidNodeId(deviceNodeId)) {
      throw ArgumentError.value(
        deviceNodeId,
        'deviceNodeId',
        'must be 16 lowercase hex chars',
      );
    }
    final key = storeKeyOf(config);
    final db = (databaseFactory ?? NoteDatabase.new)(executor);
    try {
      final values = await _readOrCreateKv(db, config, deviceNodeId);
      final clock = config.clock ?? const Clock();
      final store = DriftNoteStore._(
        db: db,
        config: config,
        storageInfo: storageInfo,
        nodeId: values.nodeId,
        hlc: HlcClock(nodeId: values.nodeId, clock: clock, last: values.hlc),
        ownerId: values.ownerId,
        clock: clock,
        ids: config.idGenerator ?? UuidV7IdGenerator(clock: clock),
        storeKey: key,
        persistedHlc: values.persistedHlc,
        blobs: IdbBlobDatabase(
          blobFactory ?? newIdbFactoryMemory(),
          config.web.blobDatabaseName,
        ),
        assetChunks: assetChunks,
      );
      if (key != null) {
        _openStoreCounts.update(key, (n) => n + 1, ifAbsent: () => 1);
      }
      // 6.2.2: the default presets exist right after open (one commit, once per DB).
      if (config.seedDefaultPenPresets) await store.penPresets.ensureDefaults();
      if (autoPurge) store.trash.startAutoPurge();
      return store;
    } on Object catch (e, s) {
      try {
        await db.close();
      } on Object {
        // The original error is the one to report.
      }
      Error.throwWithStackTrace(classifyOpenError(e), s);
    }
  }

  final NoteDatabase db;
  final NoteStoreConfig config;
  final String nodeId;
  final HlcClock hlc;
  @override
  final Clock clock;
  @override
  final IdGenerator ids;
  final String? _storeKey;
  final StorageInfo _storageInfo;
  OwnerId _ownerId;
  bool _closed = false;

  final ChangeBus bus = ChangeBus();

  /// Asset chunks and thumbnails (6.13), outside SQLite.
  final IdbBlobDatabase blobs;

  /// Re-queried watch streams (C-1); refreshed by the write queue after each commit.
  final WatchHub watches = WatchHub();

  /// The single serial write queue (6.9); every write of this store goes through it.
  late final WriteQueue queue;

  @override
  OwnerId get ownerId => _ownerId;

  /// reassignOwner committed (6.10.5): library queries use [to] from now on.
  void switchOwner(OwnerId to) => _ownerId = to;

  @override
  late final DriftLibraryRepository library;
  @override
  late final DriftTrashRepository trash;
  @override
  late final DriftPenPresetRepository penPresets;
  @override
  late final DriftSettingsRepository settings;
  @override
  late final NoteContentReader content;
  @override
  late final AssetStoreImpl assets;
  @override
  late final ThumbnailCacheImpl thumbnails;
  @override
  late final DriftSyncStore sync;

  /// Open note sessions (6.14).
  late final DriftSessions sessions;

  /// Note content migration, run when an older note is opened (6.15).
  NoteMigrator get noteMigrator => _noteMigrator;
  late NoteMigrator _noteMigrator;

  /// Tests: other migration steps (the app has none yet — kNoteSchemaVersion 1).
  @visibleForTesting
  set noteMigrator(NoteMigrator migrator) => _noteMigrator = migrator;

  @override
  Stream<ChangeBatch> get changes => bus.stream;

  @override
  PersistenceStatus get persistenceStatus => queue.status;

  @override
  Stream<PersistenceStatus> get persistenceStatusStream => Stream.multi((c) {
    c.add(queue.status);
    final sub = queue.statusChanges.listen(c.add);
    c.onCancel = sub.cancel;
  }, isBroadcast: true);

  @override
  StorageInfo get storageInfo => _storageInfo;

  @override
  Future<StorageInfo> refreshStorageInfo() async => _storageInfo;

  @override
  Future<NoteSession> openSession(
    NoteId noteId, {
    NoteSessionOptions options = const NoteSessionOptions(),
  }) {
    if (_closed) return Future.error(StateError('The note store is closed'));
    return sessions.open(noteId, options);
  }

  @override
  Future<void> flush() => queue.flush();

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    trash.stopAutoPurge();
    sessions.clear();
    final key = _storeKey;
    if (key != null) {
      final n = (_openStoreCounts[key] ?? 1) - 1;
      if (n <= 0) {
        _openStoreCounts.remove(key);
      } else {
        _openStoreCounts[key] = n;
      }
    }
    // Running byte writes first: their metadata commits still go through the queue.
    await assets.close();
    await thumbnails.close();
    await queue.close();
    watches.close();
    await bus.close();
    await blobs.close();
    await db.close();
  }

  /// 6.17: after a flush, one read transaction (a snapshot; writes queue behind it),
  /// every kind in EntityKind order, rows in id order, [kBackupPageRows] per query.
  @override
  Future<Uint8List> exportBackupJson() async {
    if (_closed) throw StateError('The note store is closed');
    await queue.flush();
    final out = BackupJsonWriter(
      exportedAt: clock.now().millisecondsSinceEpoch,
      ownerId: ownerId,
      deviceNodeId: nodeId,
    );
    await db.transaction(() async {
      for (final kind in EntityKind.values) {
        String? after;
        while (true) {
          final rows = await readVersionedPage(
            db,
            kind,
            after: after,
            limit: kBackupPageRows,
          );
          for (final v in rows) {
            out.add(v.entity, v.versions);
          }
          if (rows.length < kBackupPageRows) break;
          after = rows.last.entity.id;
        }
      }
    });
    return out.finish();
  }
}

typedef _KvValues = ({
  String nodeId,
  Hlc hlc,
  String? persistedHlc,
  OwnerId ownerId,
});

/// Reads device.nodeId / hlc.last / store.ownerId, creating missing values in one
/// transaction. The first statement also opens the database (schema steps).
Future<_KvValues> _readOrCreateKv(
  NoteDatabase db,
  NoteStoreConfig config,
  String? deviceNodeId,
) => db.transaction(() async {
  final rows =
      await (db.select(db.kv)..where(
            (t) => t.key.isIn([
              KvKeys.deviceNodeId,
              KvKeys.hlcLast,
              KvKeys.ownerId,
            ]),
          ))
          .get();
  final kv = {for (final r in rows) r.key: r.value};

  final storedNode = kv[KvKeys.deviceNodeId];
  if (storedNode != null && !isValidNodeId(storedNode)) {
    throw KvCorruptionError(KvKeys.deviceNodeId, storedNode);
  }
  final nodeId = deviceNodeId ?? storedNode ?? generateNodeId();
  if (nodeId != storedNode) await _putKv(db, KvKeys.deviceNodeId, nodeId);

  final storedHlc = kv[KvKeys.hlcLast];
  final Hlc hlc;
  if (storedHlc == null) {
    hlc = Hlc(0, 0, nodeId);
  } else {
    final parsed = Hlc.tryParse(storedHlc);
    if (parsed == null) throw KvCorruptionError(KvKeys.hlcLast, storedHlc);
    hlc = parsed;
  }

  var ownerId = kv[KvKeys.ownerId];
  if (ownerId == null) {
    ownerId = config.ownerId;
    await _putKv(db, KvKeys.ownerId, ownerId);
  }
  return (nodeId: nodeId, hlc: hlc, persistedHlc: storedHlc, ownerId: ownerId);
});

Future<void> _putKv(NoteDatabase db, String key, String value) => db
    .into(db.kv)
    .insertOnConflictUpdate(KvCompanion.insert(key: key, value: value));
