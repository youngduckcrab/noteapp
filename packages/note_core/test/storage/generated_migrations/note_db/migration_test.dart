// CORE T24 (m5-7/02-core 6.12.1) — drift's generated migration test, adopted: the template of
// `dart run drift_dev make-migrations` with package:test (note_core is a pure Dart member) and
// real rows in the data-integrity case. Schema files: generated/ (do not edit; rerun
// make-migrations after a schema change).
@TestOn('vm')
library;

import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:note_core/src/storage/db/migrations.dart';
import 'package:note_core/src/storage/db/note_database.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // Every schema step without data. The FTS5 table search_fts (not a drift table) is
    // outside the expected schema; SchemaVerifier does not check extra tables
    // (validateDropped defaults to false — 6.11 option 1).
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = NoteDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  test('migration from v1 to v2 keeps the rows (derived columns aside)', () async {
    const fv = '{"name":"001792974725000-0000-ab463465a52e80fa"}';
    const v = '001792974725000-0000-ab463465a52e80fa';
    // name_norm as the v1 code wrote it (no zero-width removal): v2 recomputes it.
    final oldFolders = [
      const v1.FoldersData(
        id: 'f1',
        ownerId: 'local',
        name: 'Ab​c',
        nameNorm: 'ab​c',
        sortKey: 'a0',
        createdAt: 1,
        updatedAt: 2,
        version: v,
        fieldVersions: fv,
      ),
    ];
    final newFolders = [
      const v2.FoldersData(
        id: 'f1',
        ownerId: 'local',
        name: 'Ab​c',
        nameNorm: 'abc',
        sortKey: 'a0',
        createdAt: 1,
        updatedAt: 2,
        version: v,
        fieldVersions: fv,
      ),
    ];
    final asset = 'a' * 64;
    final pdfJson =
        '{"type":"pdf","assetId":"$asset","pdfPageIndex":3,"paperColor":4294967295}';
    final oldPages = [
      v1.PagesData(
        id: 'p1',
        noteId: 'n1',
        sortKey: 'a0',
        width: 595.0,
        height: 842.0,
        backgroundJson: pdfJson,
        createdAt: 1,
        updatedAt: 2,
        version: v,
        contentRev: 7,
      ),
    ];
    final newPages = [
      v2.PagesData(
        id: 'p1',
        noteId: 'n1',
        sortKey: 'a0',
        width: 595.0,
        height: 842.0,
        backgroundJson: pdfJson,
        createdAt: 1,
        updatedAt: 2,
        version: v,
        contentRev: 7,
        bgAssetId: asset,
        bgPdfIndex: 3,
      ),
    ];
    final oldRecordings = [
      const v1.RecordingsData(
        id: 'r1',
        noteId: 'n1',
        assetId: 'b',
        durationMs: 1000,
        startedAt: 0,
        createdAt: 1,
        updatedAt: 2,
        version: v,
      ),
    ];
    final newRecordings = [
      const v2.RecordingsData(
        id: 'r1',
        noteId: 'n1',
        assetId: 'b',
        durationMs: 1000,
        startedAt: 0,
        createdAt: 1,
        updatedAt: 2,
        version: v,
      ),
    ];
    final oldOutbox = [
      const v1.OutboxData(
        seq: 1,
        rev: 1,
        entityKind: 'folder',
        entityId: 'f1',
        op: 'put',
        changedFields: '["name"]',
        hlc: v,
        enqueuedAt: 2,
      ),
    ];
    final newOutbox = [
      const v2.OutboxData(
        seq: 1,
        rev: 1,
        entityKind: 'folder',
        entityId: 'f1',
        op: 'put',
        changedFields: '["name"]',
        hlc: v,
        enqueuedAt: 2,
      ),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: NoteDatabase.new,
      createItems: (batch, oldDb) {
        batch
          ..insertAll(oldDb.folders, oldFolders)
          ..insertAll(oldDb.pages, oldPages)
          ..insertAll(oldDb.recordings, oldRecordings)
          ..insertAll(oldDb.outbox, oldOutbox);
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.folders).get(), newFolders);
        expect(await newDb.select(newDb.pages).get(), newPages);
        expect(await newDb.select(newDb.recordings).get(), newRecordings);
        expect(await newDb.select(newDb.outbox).get(), newOutbox);
        expect(await newDb.select(newDb.pageObjects).get(), isEmpty);
        expect(
          (await newDb.select(newDb.kv).get()).map((r) => (r.key, r.value)),
          [('search.normalizerVersion', '1')],
        );
      },
    );
  });

  // (v2.17-md, MD-T04) v2 → v3 adds md_docs only: every v2 row stays as it was.
  test(
    'migration from v2 to v3 keeps every row; md_docs starts empty',
    () async {
      const v = '001792974725000-0000-ab463465a52e80fa';
      const note = v2.NotesData(
        id: 'n1',
        ownerId: 'local',
        title: '노트',
        titleNorm: '노트',
        coverJson: '{"type":"firstPage"}',
        tagsJson: '[]',
        isFavorite: 0,
        sortKey: 'a0',
        schemaVersion: 1,
        createdAt: 1,
        updatedAt: 2,
        version: v,
        pageCount: 0,
      );
      const newNote = v3.NotesData(
        id: 'n1',
        ownerId: 'local',
        title: '노트',
        titleNorm: '노트',
        coverJson: '{"type":"firstPage"}',
        tagsJson: '[]',
        isFavorite: 0,
        sortKey: 'a0',
        schemaVersion: 1,
        createdAt: 1,
        updatedAt: 2,
        version: v,
        pageCount: 0,
      );
      await verifier.testWithDataIntegrity(
        oldVersion: 2,
        newVersion: 3,
        createOld: v2.DatabaseAtV2.new,
        createNew: v3.DatabaseAtV3.new,
        openTestedDatabase: NoteDatabase.new,
        createItems: (batch, oldDb) {
          batch
            ..insert(oldDb.notes, note)
            ..insert(
              oldDb.kv,
              const v2.KvData(key: 'search.normalizerVersion', value: '1'),
            );
        },
        validateItems: (newDb) async {
          expect(await newDb.select(newDb.notes).get(), [newNote]);
          expect(await newDb.select(newDb.mdDocs).get(), isEmpty);
          expect(
            (await newDb.select(newDb.kv).get()).map((r) => (r.key, r.value)),
            [('search.normalizerVersion', '1')],
          );
        },
      );
    },
  );

  test('a failing v2 → v3 step leaves the v2 database as it was', () async {
    final schema = await verifier.schemaAt(2);
    final db = NoteDatabase(
      schema.newConnection(),
      upgradeSteps: {
        1: upgradeV1ToV2,
        2: (m, db, from) async {
          await upgradeV2ToV3(m, db, from);
          throw StateError('injected');
        },
      },
    );
    await expectLater(
      db.customSelect('SELECT 1').get(),
      throwsA(isA<SchemaStepError>()),
    );
    await db.close();
    expect(schema.rawDatabase.userVersion, 2);
    expect(
      schema.rawDatabase.select(
        "SELECT name FROM sqlite_master WHERE name = 'md_docs'",
      ),
      isEmpty,
    );
  });
}
