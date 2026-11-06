// CORE T19 — NoteStore.exportBackupJson on the SQLite store (6.17): the shared cases, the
// golden bytes (same as the fake), field versions, recordings, paging and the snapshot.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:note_core/dev_tools.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

import '../shared/backup_cases.dart';
import '../shared/v1_database.dart';
import '../storage/storage_support.dart';
import '../sync/support/sync_support.dart';
import 'backup_golden.dart';

Future<NoteStore> _open() => openTestNoteStore(
  clock: kBackupClock,
  ids: SequentialIdGenerator(),
  deviceNodeId: kBackupNode,
  seedDefaultPenPresets: false,
);

Future<void> _seed(NoteStore store, List<VersionedEntity> state) =>
    store.sync.applyRemote([
      for (final v in state) RemoteUpsert(v.entity, v.versions),
    ], policy: (_, _, _) => const TakeRemote());

List<Map<String, Object?>> _entities(Uint8List bytes) => [
  for (final e
      in (jsonDecode(utf8.decode(bytes)) as Map<String, Object?>)['entities']!
          as List<Object?>)
    e! as Map<String, Object?>,
];

void main() {
  defineBackupTests(open: _open, seed: _seed);

  test('the golden state exports the golden bytes', tags: ['golden'], () async {
    final store = await _open();
    addTearDown(store.close);
    await _seed(store, backupGoldenState());
    expectBackupGolden(await store.exportBackupJson());
  });

  group('SQLite store only', () {
    late NoteStore store;
    setUp(() async => store = await _open());
    tearDown(() => store.close());

    test(
      'per-field versions and recordings are exported; sync meta is not',
      () async {
        final n = await store.library.createNote(title: 'n');
        await store.library.renameNote(n.id, 'renamed');
        await store.sync.applyRemote([
          upsert(
            recording('rec-1', n.id),
            remoteAfter(store as DriftNoteStore),
          ),
        ], policy: (_, _, _) => const TakeRemote());
        await store.sync.writeMeta({'sync.cursor': 'secret-cursor'});
        final bytes = await store.exportBackupJson();
        expect(utf8.decode(bytes), isNot(contains('secret-cursor')));
        final entities = _entities(bytes);
        final note = entities.singleWhere((e) => e['kind'] == 'note');
        final versions = EntityFieldVersions.fromJson(
          note['versions']! as Map<String, Object?>,
        );
        expect(versions.overrides.keys, ['title']);
        expect(
          (note['data']! as Map<String, Object?>)['version'],
          versions.max.toString(),
        );
        expect(entities.where((e) => e['kind'] == 'recording'), hasLength(1));
      },
    );

    test(
      'more rows than one page (2,000) are all exported in id order',
      () async {
        final v = Hlc(kBackupT, 0, kRemoteNode);
        await store.sync.applyRemote([
          for (var i = 0; i < 2101; i++)
            upsert(folder('f${i.toString().padLeft(5, '0')}'), v),
        ], policy: (_, _, _) => const TakeRemote());
        final ids = [
          for (final e in _entities(await store.exportBackupJson()))
            if (e['kind'] == 'folder')
              (e['data']! as Map<String, Object?>)['id'],
        ];
        expect(ids, hasLength(2101));
        expect(ids.first, 'f00000');
        expect(ids.last, 'f02100');
      },
    );

    test('writes queued before the call are in the export (flush)', () async {
      final queued = store.library.createFolder(name: 'queued');
      final bytes = await store.exportBackupJson();
      await queued;
      expect(
        _entities(bytes).where((e) => e['kind'] == 'folder'),
        hasLength(1),
      );
    });

    test('(v2.1) the v1 database copy is not in the backup (6.14.4)', () async {
      final dir = Directory.systemTemp.createTempSync('note_core_backup_v1_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/notes.db';
      // An empty v1 database (the synthetic v1 rows carry placeholder stroke bytes).
      await createV1Database(NativeDatabase(File(path)), statements: const []);
      final upgraded = await openTestNoteStore(
        filePath: path,
        clock: kBackupClock,
        deviceNodeId: kBackupNode,
      );
      addTearDown(upgraded.close);
      final copy = (await v1DatabaseCopyInfo(upgraded))!;
      expect(copy.bytes, greaterThan(0));
      await upgraded.library.createNote(title: '이주 뒤');
      final bytes = await upgraded.exportBackupJson();
      final doc = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      expect((doc['schema']! as Map<String, Object?>)['database'], 2);
      final text = utf8.decode(bytes);
      for (final local in ['v1Copy', copy.fileName, 'SQLite format']) {
        expect(text, isNot(contains(local)), reason: local);
      }
      expect(
        bytes.length,
        lessThan(copy.bytes),
        reason: 'the entities only, not the copy',
      );
      expect(
        {for (final e in _entities(bytes)) e['kind']},
        {'note', 'page', 'penPreset'},
        reason: 'the data written after the upgrade (and the seeded presets)',
      );
    });

    test('a closed store → StateError', () async {
      final other = await _open();
      await other.close();
      await expectLater(other.exportBackupJson(), throwsStateError);
    });
  });
}
