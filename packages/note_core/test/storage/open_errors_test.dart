// CORE T6 — open error classification (6.18) and the schema step runner (6.15). (v2, m5-7
// T24) The store now writes v2 databases: the 'newer app' below is a v3 one. (v2, m5-7 T35)
// openNoteStore off the web needs both native paths: the file configs carry a temporary
// blob root (6.15.3); native_file_store_test.dart has the native storage cases.
@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/connect/connect_stub.dart' as stub;
import 'package:note_core/src/storage/db/migrations.dart';
import 'package:note_core/src/storage/db/note_database.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/kv_keys.dart';
import 'package:note_core/src/storage/open_errors.dart';
import 'package:note_core/testing_vm.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

/// A newer app's database: schema v3 with the given steps.
class _NextDatabase extends NoteDatabase {
  _NextDatabase(super.executor, {required super.upgradeSteps});
  @override
  int get schemaVersion => kDatabaseSchemaVersion + 1;
}

Matcher _openFailure(NoteStoreOpenFailure reason) =>
    isA<NoteStoreOpenException>().having((e) => e.reason, 'reason', reason);

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('note_core_open_');
    path = '${dir.path}/notes.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// A database of this app (v2 — the name is from the 1st round).
  Future<void> createV1() async {
    final s = await openTestNoteStore(filePath: path);
    await s.close();
  }

  int userVersion() {
    final raw = sqlite.sqlite3.open(path);
    try {
      return raw.userVersion;
    } finally {
      raw.close();
    }
  }

  void rawExecute(String sql) {
    final raw = sqlite.sqlite3.open(path);
    try {
      raw.execute(sql);
    } finally {
      raw.close();
    }
  }

  NoteStoreConfig fileConfig() => NoteStoreConfig(
    nativeDatabasePath: path,
    nativeAssetDirectoryPath: '${dir.path}/assets',
  );

  group('newerSchema', () {
    test(
      'user_version 99 → newerSchema, the database is left as it was',
      () async {
        await createV1();
        rawExecute('PRAGMA user_version = 99');
        await expectLater(
          openNoteStore(fileConfig()),
          throwsA(_openFailure(NoteStoreOpenFailure.newerSchema)),
        );
        await expectLater(
          openTestNoteStore(filePath: path),
          throwsA(_openFailure(NoteStoreOpenFailure.newerSchema)),
        );
        expect(userVersion(), 99);
        // The failed opens released the database: it can be deleted.
        await deleteLocalNoteData(fileConfig());
        expect(File(path).existsSync(), isFalse);
      },
    );
  });

  group('corrupted', () {
    test('a file that is not a database → corrupted', () async {
      File(path).writeAsStringSync('this is not a sqlite database\n' * 200);
      await expectLater(
        openNoteStore(fileConfig()),
        throwsA(_openFailure(NoteStoreOpenFailure.corrupted)),
      );
      await expectLater(
        openTestNoteStore(filePath: path),
        throwsA(_openFailure(NoteStoreOpenFailure.corrupted)),
      );
    });

    test('a damaged hlc.last → corrupted', () async {
      await createV1();
      rawExecute(
        "UPDATE kv SET value = 'garbage' WHERE key = '${KvKeys.hlcLast}'",
      );
      rawExecute(
        "INSERT OR REPLACE INTO kv (key, value) VALUES ('${KvKeys.hlcLast}', 'garbage')",
      );
      await expectLater(
        openTestNoteStore(filePath: path),
        throwsA(_openFailure(NoteStoreOpenFailure.corrupted)),
      );
    });

    test('a damaged device.nodeId → corrupted', () async {
      await createV1();
      rawExecute(
        "UPDATE kv SET value = 'XYZ' WHERE key = '${KvKeys.deviceNodeId}'",
      );
      await expectLater(
        openNoteStore(fileConfig()),
        throwsA(_openFailure(NoteStoreOpenFailure.corrupted)),
      );
    });
  });

  group('migrationFailed', () {
    test('a throwing schema step → migrationFailed, rolled back', () async {
      await createV1();
      await expectLater(
        DriftNoteStore.open(
          executor: NativeDatabase(File(path)),
          storageInfo: const StorageInfo(backend: StorageBackend.nativeFile),
          config: fileConfig(),
          databaseFactory: (e, _) => _NextDatabase(
            e,
            upgradeSteps: {
              kDatabaseSchemaVersion: (m, db, from) async {
                await db.customStatement('CREATE TABLE extra (x INTEGER)');
                throw StateError('step failed');
              },
            },
          ),
        ),
        throwsA(
          isA<NoteStoreOpenException>()
              .having(
                (e) => e.reason,
                'reason',
                NoteStoreOpenFailure.migrationFailed,
              )
              .having(
                (e) => e.cause,
                'cause',
                isA<SchemaStepError>().having(
                  (s) => s.from,
                  'from',
                  kDatabaseSchemaVersion,
                ),
              ),
        ),
      );
      expect(userVersion(), kDatabaseSchemaVersion);
      final raw = sqlite.sqlite3.open(path);
      addTearDown(raw.close);
      expect(
        raw.select("SELECT name FROM sqlite_master WHERE name = 'extra'"),
        isEmpty,
      );
      // The v2 app (this one) still opens it.
      final store = await openTestNoteStore(filePath: path);
      await store.close();
    });

    test('a missing step → migrationFailed', () async {
      await createV1();
      await expectLater(
        DriftNoteStore.open(
          executor: NativeDatabase(File(path)),
          storageInfo: const StorageInfo(backend: StorageBackend.nativeFile),
          config: fileConfig(),
          databaseFactory: (e, _) => _NextDatabase(e, upgradeSteps: const {}),
        ),
        throwsA(_openFailure(NoteStoreOpenFailure.migrationFailed)),
      );
      expect(userVersion(), kDatabaseSchemaVersion);
    });

    test('a working step runs once and sets user_version', () async {
      await createV1();
      var runs = 0;
      final store = await DriftNoteStore.open(
        executor: NativeDatabase(File(path)),
        storageInfo: const StorageInfo(backend: StorageBackend.nativeFile),
        config: fileConfig(),
        databaseFactory: (e, _) => _NextDatabase(
          e,
          upgradeSteps: {
            kDatabaseSchemaVersion: (m, db, from) async {
              runs++;
              await db.customStatement('CREATE TABLE extra (x INTEGER)');
            },
          },
        ),
      );
      final row = await store.db
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(row.read<int>('user_version'), kDatabaseSchemaVersion + 1);
      await store.close();
      expect(runs, 1);
    });

    test(
      'schema steps of this version: v1 → v2 (m5-7 T24), v2 → v3 (v2.17-md)',
      () {
        expect(kSchemaSteps.keys, [1, 2]);
        expect(kSchemaSteps[1], same(upgradeV1ToV2));
        expect(kSchemaSteps[2], same(upgradeV2ToV3));
        expect(kDatabaseSchemaVersion, 3);
      },
    );
  });

  group('storageUnavailable', () {
    test('the stub connection (no storage on this platform)', () async {
      await expectLater(
        stub.openNoteDatabaseExecutor(const NoteStoreConfig()),
        throwsA(_openFailure(NoteStoreOpenFailure.storageUnavailable)),
      );
      await stub.deleteLocalData(const NoteStoreConfig());
    });

    test('native config without a path and not inMemory', () async {
      await expectLater(
        openNoteStore(const NoteStoreConfig()),
        throwsA(_openFailure(NoteStoreOpenFailure.storageUnavailable)),
      );
    });

    test(
      '(v2) a database path without nativeAssetDirectoryPath (6.15.3)',
      () async {
        await expectLater(
          openNoteStore(NoteStoreConfig(nativeDatabasePath: path)),
          throwsA(_openFailure(NoteStoreOpenFailure.storageUnavailable)),
        );
        expect(File(path).existsSync(), isFalse);
      },
    );
  });

  group('openNoteStore and deleteLocalNoteData (native)', () {
    test(
      'inMemory → nativeMemory; a file → nativeFile and data survives',
      () async {
        final mem = await openNoteStore(const NoteStoreConfig(inMemory: true));
        expect(mem.storageInfo.backend, StorageBackend.nativeMemory);
        await mem.close();

        final a = await openNoteStore(fileConfig());
        expect(a.storageInfo.backend, StorageBackend.nativeFile);
        final node = a.sync.deviceNodeId;
        await a.close();
        final b = await openNoteStore(fileConfig());
        expect(b.sync.deviceNodeId, node);
        await b.close();
      },
    );

    test(
      'deleteLocalNoteData: StateError while open, then an empty database',
      () async {
        final a = await openNoteStore(fileConfig());
        final node = a.sync.deviceNodeId;
        await expectLater(deleteLocalNoteData(fileConfig()), throwsStateError);
        await a.close();
        await deleteLocalNoteData(fileConfig());
        for (final p in [path, '$path-wal', '$path-shm']) {
          expect(File(p).existsSync(), isFalse, reason: p);
        }
        final b = await openNoteStore(fileConfig());
        expect(b.sync.deviceNodeId, isNot(node));
        await b.close();
      },
    );

    test('deleteLocalNoteData of an in-memory config does nothing', () async {
      final mem = await openNoteStore(const NoteStoreConfig(inMemory: true));
      await deleteLocalNoteData(const NoteStoreConfig(inMemory: true));
      await mem.close();
    });
  });

  group('classifyOpenError', () {
    test('errors that crossed an isolate / worker as text', () {
      expect(
        classifyOpenError(Exception('${NewerSchemaError.prefix} v3, v1'))
            .reason,
        NoteStoreOpenFailure.newerSchema,
      );
      expect(
        classifyOpenError(Exception('${SchemaStepError.prefix} v1')).reason,
        NoteStoreOpenFailure.migrationFailed,
      );
      expect(
        classifyOpenError(
          Exception('SqliteException(26): file is not a database'),
        ).reason,
        NoteStoreOpenFailure.corrupted,
      );
      expect(
        classifyOpenError(Exception('database disk image is malformed')).reason,
        NoteStoreOpenFailure.corrupted,
      );
    });

    test(
      'other errors → unknown with the cause; open exceptions pass through',
      () {
        final cause = StateError('x');
        final e = classifyOpenError(cause);
        expect(e.reason, NoteStoreOpenFailure.unknown);
        expect(e.cause, same(cause));
        const given = NoteStoreOpenException(
          NoteStoreOpenFailure.storageUnavailable,
          'm',
        );
        expect(classifyOpenError(given), same(given));
      },
    );
  });
}
