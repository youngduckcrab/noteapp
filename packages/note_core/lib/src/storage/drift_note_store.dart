// lib/src/storage/drift_note_store.dart (internal) — the SQLite NoteStore (CORE 6.1, 6.18).
//
// T6 opens the database, classifies open errors and keeps the per-device kv
// values (device node, HLC, owner). The repositories, sessions and the sync
// window are filled in by CORE T7–T14; until then their members throw
// UnimplementedError naming the task.
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../assets/asset_store.dart';
import '../common/hlc.dart';
import '../common/ids.dart';
import '../repo/content_reader.dart';
import '../repo/events.dart';
import '../repo/library_repository.dart';
import '../repo/note_store.dart';
import '../repo/pen_preset_repository.dart';
import '../repo/settings_repository.dart';
import '../repo/status.dart';
import '../repo/trash_repository.dart';
import '../session/note_session.dart';
import '../sync/sync_store.dart';
import 'db/note_database.dart';
import 'kv_keys.dart';
import 'open_errors.dart';

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
  }) {
    sync = _DriftSyncStore(this);
  }

  /// Opens [executor] as a note database: runs the schema steps (6.15), reads or
  /// creates the kv values and returns the store. Every failure is a
  /// NoteStoreOpenException (6.18) and closes the executor first.
  ///
  /// [deviceNodeId] fixes the HLC node (openTestNoteStore); null = the stored
  /// node, or a new random one for a new database.
  static Future<DriftNoteStore> open({
    required QueryExecutor executor,
    required StorageInfo storageInfo,
    required NoteStoreConfig config,
    String? deviceNodeId,
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
      );
      if (key != null) {
        _openStoreCounts.update(key, (n) => n + 1, ifAbsent: () => 1);
      }
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
  final OwnerId _ownerId;
  bool _closed = false;

  final StreamController<ChangeBatch> _changes = StreamController.broadcast();
  final StreamController<PersistenceStatus> _status =
      StreamController.broadcast();
  final PersistenceStatus _persistence = const PersistenceStatus(
    pendingOps: 0,
    isWriting: false,
  );

  @override
  OwnerId get ownerId => _ownerId;

  @override
  final LibraryRepository library = const _PendingLibrary();
  @override
  final TrashRepository trash = const _PendingTrash();
  @override
  final PenPresetRepository penPresets = const _PendingPresets();
  @override
  final SettingsRepository settings = const _PendingSettings();
  @override
  final NoteContentReader content = const _PendingContent();
  @override
  final AssetStore assets = const _PendingAssets();
  @override
  final ThumbnailCache thumbnails = const _PendingThumbnails();
  @override
  late final SyncStore sync;

  @override
  Stream<ChangeBatch> get changes => _changes.stream;

  @override
  PersistenceStatus get persistenceStatus => _persistence;

  @override
  Stream<PersistenceStatus> get persistenceStatusStream => Stream.multi((c) {
    c.add(_persistence);
    final sub = _status.stream.listen(c.add);
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
  }) => throw UnimplementedError('openSession: arrives with CORE T10');

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final key = _storeKey;
    if (key != null) {
      final n = (_openStoreCounts[key] ?? 1) - 1;
      if (n <= 0) {
        _openStoreCounts.remove(key);
      } else {
        _openStoreCounts[key] = n;
      }
    }
    await _changes.close();
    await _status.close();
    await db.close();
  }

  @override
  Future<Uint8List> exportBackupJson() =>
      throw UnimplementedError('exportBackupJson: arrives with CORE T19');
}

typedef _KvValues = ({String nodeId, Hlc hlc, OwnerId ownerId});

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
  return (nodeId: nodeId, hlc: hlc, ownerId: ownerId);
});

Future<void> _putKv(NoteDatabase db, String key, String value) => db
    .into(db.kv)
    .insertOnConflictUpdate(KvCompanion.insert(key: key, value: value));

/// Placeholders for members that later CORE tasks implement.
Never _pending(String type, Invocation i, String task) =>
    throw UnimplementedError('$type.${_name(i)}: arrives with CORE $task');

String _name(Invocation i) {
  final s = i.memberName.toString(); // Symbol("name")
  final start = s.indexOf('"');
  final end = s.lastIndexOf('"');
  return start >= 0 && end > start ? s.substring(start + 1, end) : s;
}

final class _PendingLibrary implements LibraryRepository {
  const _PendingLibrary();
  @override
  Never noSuchMethod(Invocation i) => _pending('LibraryRepository', i, 'T8');
}

final class _PendingTrash implements TrashRepository {
  const _PendingTrash();
  @override
  Never noSuchMethod(Invocation i) => _pending('TrashRepository', i, 'T9');
}

final class _PendingPresets implements PenPresetRepository {
  const _PendingPresets();
  @override
  Never noSuchMethod(Invocation i) => _pending('PenPresetRepository', i, 'T12');
}

final class _PendingSettings implements SettingsRepository {
  const _PendingSettings();
  @override
  Never noSuchMethod(Invocation i) => _pending('SettingsRepository', i, 'T12');
}

final class _PendingContent implements NoteContentReader {
  const _PendingContent();
  @override
  Never noSuchMethod(Invocation i) => _pending('NoteContentReader', i, 'T10');
}

final class _PendingAssets implements AssetStore {
  const _PendingAssets();
  @override
  Never noSuchMethod(Invocation i) => _pending('AssetStore', i, 'T13');
}

final class _PendingThumbnails implements ThumbnailCache {
  const _PendingThumbnails();
  @override
  Never noSuchMethod(Invocation i) => _pending('ThumbnailCache', i, 'T13');
}

/// SyncStore of the SQLite store. T6: identity values only; CORE T14 fills the rest.
final class _DriftSyncStore implements SyncStore {
  _DriftSyncStore(this._store);
  final DriftNoteStore _store;

  @override
  String get deviceNodeId => _store.nodeId;

  @override
  OwnerId get ownerId => _store.ownerId;

  @override
  Never noSuchMethod(Invocation i) => _pending('SyncStore', i, 'T14');
}
