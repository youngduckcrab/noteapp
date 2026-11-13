// CORE T24 — the v1 → v2 upgrade (m5-7/02-core 6.12.1) on a synthetic v1 file database made
// with drift's generated schema_v1: the results of steps 0–6, the bg_* columns, only the
// changed name_norm / title_norm rows updated, entity rows / versions / outbox / kv unchanged
// (C-14), and a failing step → the database stays v1, migrationFailed, the copy stays.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/db/canonical_dump.dart';
import 'package:note_core/src/storage/db/migrations.dart';
import 'package:note_core/src/storage/db/note_database.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/v1_copy/v1_copy_file.dart';
import 'package:note_core/testing_vm.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import '../shared/v1_database.dart';

CanonicalDumpQuery _rawQuery(sqlite.Database db) =>
    (sql, args) async => [
      for (final r in db.select(sql, args)) r.values.first! as String,
    ];

void main() {
  late Directory dir;
  late String path;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('note_core_mig_');
    path = '${dir.path}/notes.db';
    await createV1Database(NativeDatabase(File(path)));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  T raw<T>(T Function(sqlite.Database db) body) {
    final db = sqlite.sqlite3.open(path);
    try {
      return body(db);
    } finally {
      db.close();
    }
  }

  Future<String> dumpSha({
    Iterable<String>? tables,
    Map<String, List<String>> columns = const {},
  }) async {
    final db = sqlite.sqlite3.open(path);
    try {
      final bytes = await canonicalDump(
        _rawQuery(db),
        tables: tables,
        columns: columns,
      );
      return sha256.convert(bytes).toString();
    } finally {
      db.close();
    }
  }

  test('steps 1–6: new tables empty, bg_* filled, kv, user_version 2', () async {
    final store = await openTestNoteStore(filePath: path) as DriftNoteStore;
    await store.close();
    raw((db) {
      expect(db.userVersion, 2);
      for (final t in [
        'page_objects',
        'handwriting',
        'recording_drafts',
        'search_owners',
        'search_units',
        'search_fts',
      ]) {
        expect(db.select('SELECT count(*) AS n FROM $t').single['n'], 0);
      }
      final bg = {
        for (final r in db.select(
          'SELECT id, bg_asset_id, bg_pdf_index, ink_rev, ink_rev_at FROM pages',
        ))
          r['id']: [
            r['bg_asset_id'],
            r['bg_pdf_index'],
            r['ink_rev'],
            r['ink_rev_at'],
          ],
      };
      expect(bg, {
        'p1': [null, null, null, null],
        'p2': [kV1PdfAsset, 2, null, null],
        'p3': [kV1ImageAsset, null, null, null],
        'p4': [null, null, null, null],
      });
      expect(db.select('SELECT title FROM recordings').map((r) => r['title']), [
        null,
      ]);
      final kv = {
        for (final r in db.select('SELECT key, value FROM kv'))
          r['key']: r['value'],
      };
      expect(kv['search.normalizerVersion'], '1');
      // Step 0 made a file copy (native file database) and step 6 recorded it.
      final copy =
          jsonDecode(kv['db.v1Copy']! as String) as Map<String, Object?>;
      expect(copy['method'], 'vacuum');
      expect(copy['bytes'], File(v1CopyPathOf(path)).lengthSync());
      expect(copy['normalOpens'], 1); // this open ended without error
    });
  });

  test(
    'step 5: SearchText.normalize, and only the rows that change are updated',
    () async {
      raw((db) {
        db
          ..execute('CREATE TABLE upd (t TEXT, id TEXT)')
          ..execute(
            "CREATE TRIGGER upd_f AFTER UPDATE ON folders BEGIN INSERT INTO upd VALUES ('folder', new.id); END",
          )
          ..execute(
            "CREATE TRIGGER upd_n AFTER UPDATE ON notes BEGIN INSERT INTO upd VALUES ('note', new.id); END",
          );
      });
      final store = await openTestNoteStore(filePath: path);
      await store.close();
      raw((db) {
        final updated = [
          for (final r in db.select('SELECT t, id FROM upd ORDER BY t, id'))
            '${r['t']}:${r['id']}',
        ];
        expect(updated, ['folder:f1', 'folder:f3', 'note:n1']);
        final names = {
          for (final r in db.select('SELECT id, name, name_norm FROM folders'))
            r['id']: r['name_norm'],
        };
        expect(names, {
          ...kV1RenormalizedFolders,
          'f2': SearchText.normalize('Plain 폴더'),
        });
        for (final r in db.select('SELECT id, title, title_norm FROM notes')) {
          expect(
            r['title_norm'],
            SearchText.normalize(r['title']! as String),
            reason: '${r['id']}',
          );
        }
        expect(
          db
              .select("SELECT title_norm FROM notes WHERE id = 'n1'")
              .single['title_norm'],
          kV1RenormalizedNotes['n1'],
        );
      });
    },
  );

  test('entity columns, versions, field_versions, outbox and kv keys are unchanged (C-14)', () async {
    final entity = await dumpSha(
      tables: kV1Tables.where((t) => t != 'kv'),
      columns: kV1EntityColumns,
    );
    final kvBefore = raw(
      (db) => {
        for (final r in db.select('SELECT key, value FROM kv'))
          r['key']: r['value'],
      },
    );
    final store = await openTestNoteStore(filePath: path);
    await store.close();
    expect(
      await dumpSha(
        tables: kV1Tables.where((t) => t != 'kv'),
        columns: kV1EntityColumns,
      ),
      entity,
    );
    final kvAfter = raw(
      (db) => {
        for (final r in db.select('SELECT key, value FROM kv'))
          r['key']: r['value'],
      },
    );
    expect(kvAfter.keys.toSet(), {
      ...kvBefore.keys,
      'search.normalizerVersion',
      'db.v1Copy',
      // Recorded at the first open: no ink rows to rebuild (ink spacing).
      'search.inkTermsVersion',
    });
    for (final k in kvBefore.keys) {
      expect(kvAfter[k], kvBefore[k], reason: '$k');
    }
  });

  test(
    'the store works after the upgrade (library reads, a new note)',
    () async {
      final store = await openTestNoteStore(filePath: path);
      addTearDown(store.close);
      final folders = await store.library.watchFolderTree().first;
      expect(folders.roots.map((f) => f.id), containsAll(['f1', 'f3']));
      final note = await store.library.createNote(title: 'Après-\nmigration');
      final found = await store.library.searchLibrary('aprèsmigration');
      expect(found.notes.map((n) => n.id), [note.id]);
    },
  );

  test(
    'a failing step: v1 as it was, migrationFailed, the copy stays',
    () async {
      final before = await dumpSha();
      await expectLater(
        DriftNoteStore.open(
          executor: NativeDatabase(File(path)),
          storageInfo: const StorageInfo(backend: StorageBackend.nativeFile),
          config: NoteStoreConfig(nativeDatabasePath: path),
          databaseFactory: (e, copy) => NoteDatabase(
            e,
            v1Copy: copy,
            upgradeSteps: {
              1: (m, db, from) async {
                await upgradeV1ToV2(m, db, from);
                throw StateError('injected');
              },
            },
          ),
        ),
        throwsA(
          isA<NoteStoreOpenException>().having(
            (e) => e.reason,
            'reason',
            NoteStoreOpenFailure.migrationFailed,
          ),
        ),
      );
      expect(raw((db) => db.userVersion), 1);
      expect(await dumpSha(), before);
      expect(
        raw((db) => db.select("SELECT * FROM kv WHERE key = 'db.v1Copy'")),
        isEmpty,
      );
      // Step 0 ran before the transaction: the copy is there (the next attempt remakes it).
      final copy = File(v1CopyPathOf(path));
      expect(copy.existsSync(), isTrue);
      final copyDb = sqlite.sqlite3.open(copy.path);
      try {
        expect(copyDb.userVersion, 1);
        final bytes = await canonicalDump(_rawQuery(copyDb));
        expect(sha256.convert(bytes).toString(), before);
      } finally {
        copyDb.close();
      }
      // The next open upgrades.
      final store = await openTestNoteStore(filePath: path);
      await store.close();
      expect(raw((db) => db.userVersion), 2);
    },
  );
}
