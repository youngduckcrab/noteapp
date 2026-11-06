// CORE T24 — the v1 database copy made right before the v1 → v2 upgrade (m5-7/02-core 6.12.4,
// contract 7.2.7 C22-01·C22-02) on the VM: the file form (VACUUM INTO → rename, an older copy
// replaced, a left-over temporary file removed), a failed copy (the upgrade goes on, kv failure
// record), the lifetime (5 normal opens AND 7 days — fake clock), deleteLocalNoteData, the
// dev_tools.dart API (chunk sizes, idempotent delete), no copy for in-memory databases, and the
// web form (canonical dump in the blob store, meta last) run on the VM's in-memory blob store.
// The browser side is test/web/v1_copy_browser_test.dart.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:note_core/dev_tools.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/assets/blob_store.dart';
import 'package:note_core/src/storage/db/canonical_dump.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/v1_copy/v1_copy.dart';
import 'package:note_core/src/storage/v1_copy/v1_copy_file.dart';
import 'package:note_core/testing_vm.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import '../shared/v1_database.dart';

const int _day = 24 * 60 * 60 * 1000;
final int _t0 = DateTime.utc(2026, 11, 6).millisecondsSinceEpoch;

CanonicalDumpQuery _rawQuery(sqlite.Database db) =>
    (sql, args) async => [
      for (final r in db.select(sql, args)) r.values.first! as String,
    ];

Future<Uint8List> _dumpOf(String path) async {
  final db = sqlite.sqlite3.open(path);
  try {
    return await canonicalDump(_rawQuery(db));
  } finally {
    db.close();
  }
}

/// Records the order of the blob writes (meta must be last).
final class _RecordingBlobs implements BlobStore {
  _RecordingBlobs(this._inner);
  final BlobStore _inner;
  final List<String> puts = [];
  Object? failOnPut;

  @override
  Future<void> put(String key, Uint8List bytes) {
    final fail = failOnPut;
    if (fail != null && key.startsWith(kV1CopyBlobPrefix)) {
      return Future.error(fail);
    }
    puts.add(key);
    return _inner.put(key, bytes);
  }

  @override
  Future<Uint8List?> get(String key) => _inner.get(key);
  @override
  Future<List<Uint8List?>> getMany(List<String> keys) => _inner.getMany(keys);
  @override
  Future<void> delete(String key) => _inner.delete(key);
  @override
  Future<void> deletePrefix(String prefix) => _inner.deletePrefix(prefix);
  @override
  Future<List<String>> keys(String prefix) => _inner.keys(prefix);
}

void main() {
  late Directory dir;
  late String path;
  late int now;
  late Clock clock;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('note_core_v1copy_');
    path = '${dir.path}/notes.db';
    now = _t0;
    clock = Clock(() => DateTime.fromMillisecondsSinceEpoch(now, isUtc: true));
    await createV1Database(NativeDatabase(File(path)));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<NoteStore> open() => openTestNoteStore(filePath: path, clock: clock);

  group('native file copy (VACUUM INTO)', () {
    test('a v1 SQLite file next to the database with the v1 dump', () async {
      final v1Dump = await _dumpOf(path);
      final store = await open();
      addTearDown(store.close);
      final copy = File(v1CopyPathOf(path));
      expect(copy.existsSync(), isTrue);
      expect(File(v1CopyTempPathOf(path)).existsSync(), isFalse);
      final raw = sqlite.sqlite3.open(copy.path);
      try {
        expect(raw.userVersion, 1);
        expect(
          raw.select('PRAGMA journal_mode').single.values.single,
          'delete',
        );
      } finally {
        raw.close();
      }
      expect(await _dumpOf(copy.path), v1Dump);
      expect(
        await v1DatabaseCopyInfo(store),
        V1DatabaseCopyInfo(
          createdAt: _t0,
          bytes: copy.lengthSync(),
          normalOpens: 1,
          fileName: 'noteapp-v1-backup.sqlite',
        ),
      );
      final chunks = await readV1DatabaseCopy(store).toList();
      expect(chunks.expand((c) => c).toList(), copy.readAsBytesSync());
    });

    test(
      'an older copy is replaced, a left-over temporary file removed',
      () async {
        File(v1CopyPathOf(path)).writeAsStringSync('old copy');
        File(v1CopyTempPathOf(path)).writeAsStringSync('cut');
        final store = await open();
        addTearDown(store.close);
        expect(File(v1CopyTempPathOf(path)).existsSync(), isFalse);
        final raw = sqlite.sqlite3.open(v1CopyPathOf(path));
        try {
          expect(raw.userVersion, 1);
        } finally {
          raw.close();
        }
      },
    );

    test('readV1DatabaseCopy hands out chunks of at most 4 MiB', () async {
      // A v1 database over 4 MiB: one stroke row with 5 MiB of points.
      final big = sqlite.sqlite3.open(path);
      try {
        big.execute(
          "UPDATE strokes SET points = randomblob(${5 * 1024 * 1024}) WHERE id = 's1'",
        );
      } finally {
        big.close();
      }
      final store = await open();
      addTearDown(store.close);
      final chunks = await readV1DatabaseCopy(store).toList();
      expect(chunks.length, greaterThanOrEqualTo(2));
      for (final c in chunks.take(chunks.length - 1)) {
        expect(c.length, kV1CopyChunkBytes);
      }
      expect(chunks.last.length, lessThanOrEqualTo(kV1CopyChunkBytes));
      final copy = File(v1CopyPathOf(path)).readAsBytesSync();
      expect(
        sha256.convert(chunks.expand((c) => c).toList()),
        sha256.convert(copy),
      );
    });

    test(
      'a failed copy: the upgrade goes on, a failure record, nothing to read',
      () async {
        // The temporary path is a non-empty directory: deleting it before VACUUM INTO fails.
        Directory(v1CopyTempPathOf(path)).createSync();
        File('${v1CopyTempPathOf(path)}/x').writeAsStringSync('x');
        final store = await open();
        addTearDown(store.close);
        expect((store as DriftNoteStore).db.schemaVersion, 2);
        final info = await v1DatabaseCopyInfo(store);
        expect(info, isNotNull);
        expect(info!.failure, 'io');
        expect(info.bytes, 0);
        expect(info.createdAt, _t0);
        expect(info.normalOpens, 1);
        expect(info.fileName, 'noteapp-v1-backup.sqlite');
        await expectLater(readV1DatabaseCopy(store).toList(), throwsStateError);
        await deleteV1DatabaseCopy(store);
        expect(await v1DatabaseCopyInfo(store), isNull);
      },
    );

    test(
      'lifetime: deleted at the first open with ≥ 5 normal opens AND 7 days',
      () async {
        Future<int?> opensAfterOpen() async {
          final store = await open();
          final info = await v1DatabaseCopyInfo(store);
          await store.close();
          return info?.normalOpens;
        }

        // Opens 1..5 within the first day: kept.
        for (var n = 1; n <= 5; n++) {
          now = _t0 + (n - 1) * 1000; // the copy is made at _t0 (first open)
          expect(await opensAfterOpen(), n);
        }
        // 7 days less 1 ms after the copy: still kept (the 6th open).
        now = _t0 + 7 * _day - 1;
        expect(await opensAfterOpen(), 6);
        expect(File(v1CopyPathOf(path)).existsSync(), isTrue);
        // 7 days after the copy: the 7th open deletes it and the record.
        now = _t0 + 7 * _day;
        expect(await opensAfterOpen(), isNull);
        expect(File(v1CopyPathOf(path)).existsSync(), isFalse);
      },
    );

    test('30 days are not enough without 5 normal opens', () async {
      now = _t0;
      await (await open()).close();
      now = _t0 + 30 * _day;
      for (var n = 2; n <= 4; n++) {
        final store = await open();
        expect((await v1DatabaseCopyInfo(store))!.normalOpens, n);
        await store.close();
      }
      final fifth = await open();
      expect(await v1DatabaseCopyInfo(fifth), isNull);
      await fifth.close();
      expect(File(v1CopyPathOf(path)).existsSync(), isFalse);
    });

    test('deleteV1DatabaseCopy: the file and the record, idempotent', () async {
      final store = await open();
      addTearDown(store.close);
      await deleteV1DatabaseCopy(store);
      expect(File(v1CopyPathOf(path)).existsSync(), isFalse);
      expect(await v1DatabaseCopyInfo(store), isNull);
      await expectLater(readV1DatabaseCopy(store).toList(), throwsStateError);
      await deleteV1DatabaseCopy(store);
    });

    test('deleteLocalNoteData deletes the copy too', () async {
      final config = NoteStoreConfig(
        nativeDatabasePath: path,
        nativeAssetDirectoryPath: '${dir.path}/assets',
      );
      final store = await openNoteStore(config);
      expect(File(v1CopyPathOf(path)).existsSync(), isTrue);
      await store.close();
      await deleteLocalNoteData(config);
      expect(File(path).existsSync(), isFalse);
      expect(File(v1CopyPathOf(path)).existsSync(), isFalse);
    });

    test('a new file database and an in-memory one get no copy', () async {
      final fresh = await openTestNoteStore(filePath: '${dir.path}/new.db');
      expect(await v1DatabaseCopyInfo(fresh), isNull);
      expect(File(v1CopyPathOf('${dir.path}/new.db')).existsSync(), isFalse);
      await fresh.close();
      final mem = await openTestNoteStore();
      expect(await v1DatabaseCopyInfo(mem), isNull);
      await expectLater(readV1DatabaseCopy(mem).toList(), throwsStateError);
      await deleteV1DatabaseCopy(mem);
      await mem.close();
    });
  });

  group('web form (canonical dump in the blob store) on the VM', () {
    late _RecordingBlobs blobs;

    Future<DriftNoteStore> openDump() async {
      final config = NoteStoreConfig(nativeDatabasePath: path, clock: clock);
      return DriftNoteStore.open(
        executor: NativeDatabase(File(path)),
        storageInfo: const StorageInfo(backend: StorageBackend.nativeFile),
        config: config,
        blobFactory: newIdbFactoryMemory(),
        assetChunks: blobs,
        v1CopyMethod: V1CopyMethod.dump,
      );
    }

    setUp(() {
      blobs = _RecordingBlobs(_MemoryBlobs());
    });

    test(
      'chunks then meta (last); the joined chunks are the v1 dump',
      () async {
        final v1Dump = await _dumpOf(path);
        final store = await openDump();
        addTearDown(store.close);
        final copyKeys = blobs.puts
            .where((k) => k.startsWith(kV1CopyBlobPrefix))
            .toList();
        expect(copyKeys.last, kV1CopyMetaKey);
        expect(copyKeys.sublist(0, copyKeys.length - 1), [v1CopyChunkKey(0)]);
        final meta = jsonDecode(
          utf8.decode((await blobs.get(kV1CopyMetaKey))!),
        ) as Map<String, Object?>;
        expect(meta, {
          'createdAt': _t0,
          'bytes': v1Dump.length,
          'chunkCount': 1,
          'sha256': sha256.convert(v1Dump).toString(),
          'format': 'noteapp-v1-dump 1',
        });
        final chunks = await readV1DatabaseCopy(store).toList();
        expect(chunks.expand((c) => c).toList(), v1Dump);
        expect(
          await v1DatabaseCopyInfo(store),
          V1DatabaseCopyInfo(
            createdAt: _t0,
            bytes: v1Dump.length,
            normalOpens: 1,
            fileName: 'noteapp-v1-backup.sql.txt',
          ),
        );
        await deleteV1DatabaseCopy(store);
        expect(await blobs.keys(kV1CopyBlobPrefix), isEmpty);
        expect(await v1DatabaseCopyInfo(store), isNull);
      },
    );

    test(
      'a copy cut before its meta is replaced by the next attempt',
      () async {
        await blobs.put(v1CopyChunkKey(0), Uint8List.fromList([1, 2, 3]));
        await blobs.put(v1CopyChunkKey(7), Uint8List.fromList([4]));
        final v1Dump = await _dumpOf(path);
        final store = await openDump();
        addTearDown(store.close);
        expect(await blobs.keys(kV1CopyBlobPrefix), [
          v1CopyChunkKey(0),
          kV1CopyMetaKey,
        ]);
        final chunks = await readV1DatabaseCopy(store).toList();
        expect(chunks.expand((c) => c).toList(), v1Dump);
      },
    );

    test(
      'a failed blob write: failure record, nothing left, the upgrade goes on',
      () async {
        blobs.failOnPut = StateError(
          'QuotaExceededError: the quota has been exceeded',
        );
        final store = await openDump();
        addTearDown(store.close);
        expect(store.db.schemaVersion, 2);
        final info = await v1DatabaseCopyInfo(store);
        expect(info!.failure, 'quota');
        expect(info.fileName, 'noteapp-v1-backup.sql.txt');
        expect(await blobs.keys(kV1CopyBlobPrefix), isEmpty);
      },
    );
  });

  test('classifyV1CopyFailure', () {
    expect(
      classifyV1CopyFailure(
        Exception('SqliteException(13): database or disk is full'),
      ),
      'quota',
    );
    expect(classifyV1CopyFailure(Exception('QuotaExceededError')), 'quota');
    expect(classifyV1CopyFailure(const FileSystemException('x')), 'io');
    expect(
      classifyV1CopyFailure(Exception('SqliteException(10): disk I/O error')),
      'io',
    );
    expect(classifyV1CopyFailure(StateError('?')), 'other');
  });
}

/// In-memory BlobStore.
final class _MemoryBlobs implements BlobStore {
  final Map<String, Uint8List> _m = {};
  @override
  Future<void> put(String key, Uint8List bytes) async => _m[key] = bytes;
  @override
  Future<Uint8List?> get(String key) async => _m[key];
  @override
  Future<List<Uint8List?>> getMany(List<String> keys) async => [
    for (final k in keys) _m[k],
  ];
  @override
  Future<void> delete(String key) async => _m.remove(key);
  @override
  Future<void> deletePrefix(String prefix) async =>
      _m.removeWhere((k, _) => k.startsWith(prefix));
  @override
  Future<List<String>> keys(String prefix) async => [
    for (final k in _m.keys)
      if (k.startsWith(prefix)) k,
  ]..sort();
}
