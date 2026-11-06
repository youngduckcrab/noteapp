// CORE T24 — drift schema v2 (m5-7/02-core 6.11; replaces the 1st-round T6 schema_test): the 15
// tables, the FTS5 table and its shadow tables, every index, field_versions on the 10 entity
// tables, no rects BLOB column, user_version 2, drift_schemas/ current — and a new v2 database
// has exactly the schema of a v1 database upgraded to v2 (sqlite_master).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:note_core/note_core.dart' show kDatabaseSchemaVersion;
import 'package:note_core/src/storage/db/note_database.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

import '../shared/v1_database.dart';

const _tables = {
  'kv',
  'folders',
  'notes',
  'pages',
  'strokes',
  'pen_presets',
  'assets',
  'recordings',
  'settings',
  'outbox',
  // (v2)
  'page_objects',
  'handwriting',
  'recording_drafts',
  'search_owners',
  'search_units',
};

const _entityTables = {
  'folders',
  'notes',
  'pages',
  'strokes',
  'pen_presets',
  'assets',
  'recordings',
  'settings',
  // (v2)
  'page_objects',
  'handwriting',
};

/// The FTS5 table and the shadow tables of a contentless (content='') table.
const _ftsTables = {
  'search_fts',
  'search_fts_data',
  'search_fts_idx',
  'search_fts_docsize',
  'search_fts_config',
};

const _indexes = {
  'idx_folders_parent': ['owner_id', 'parent_id', 'deleted_at'],
  'idx_folders_trash': ['trash_root_id'],
  'idx_notes_folder': ['owner_id', 'folder_id', 'deleted_at'],
  'idx_notes_opened': ['owner_id', 'last_opened_at'],
  'idx_notes_favorite': ['owner_id', 'is_favorite', 'deleted_at'],
  'idx_notes_trash': ['trash_root_id'],
  'idx_pages_note': ['note_id', 'deleted_at', 'sort_key'],
  'idx_strokes_page': ['page_id', 'deleted_at'],
  'idx_strokes_note': ['note_id'],
  'idx_strokes_recording': ['recording_id'],
  'idx_outbox_entity': ['entity_kind', 'entity_id'],
  // (v2)
  'idx_pages_bg': ['bg_asset_id', 'bg_pdf_index'],
  'idx_recordings_note': ['note_id', 'deleted_at'],
  'idx_objects_page': ['page_id', 'deleted_at'],
  'idx_objects_note': ['note_id'],
  'idx_objects_asset': ['asset_id'],
  'idx_handwriting_note': ['note_id', 'deleted_at'],
  'idx_drafts_note': ['note_id'],
  'idx_search_owners_note': ['note_id'],
  'idx_search_owners_pending': ['pending'],
  'idx_search_units_note': ['note_id'],
  'idx_search_units_pdf': ['asset_id', 'pdf_index'],
};

Future<List<String>> _names(NoteDatabase db, String type) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = ? AND name NOT LIKE 'sqlite_%'",
        variables: [Variable.withString(type)],
      )
      .get();
  return [for (final r in rows) r.read<String>('name')];
}

Future<List<String>> _columnsOf(NoteDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return [for (final r in rows) r.read<String>('name')];
}

/// sqlite_master, sorted, with whitespace and identifier quotes normalized: the upgrade creates
/// the new tables from drift's versioned schema (note_database.steps.dart), which writes
/// `PRIMARY KEY(id)` where the live table writes `PRIMARY KEY ("id")` — same columns, types,
/// constraints and order.
Future<List<String>> _master(NoteDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT type || ' ' || name || ' ' || tbl_name || ' ' || "
        "coalesce(sql, '-') AS e FROM sqlite_master",
      )
      .get();
  return [
    for (final r in rows)
      r
          .read<String>('e')
          .replaceAll('"', '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r' ?\( ?'), '(')
          .replaceAll(' )', ')'),
  ]..sort();
}

void main() {
  late DriftNoteStore store;
  late NoteDatabase db;

  setUp(() async {
    store = await openTestNoteStore() as DriftNoteStore;
    db = store.db;
  });
  tearDown(() => store.close());

  test(
    'the fifteen tables exist, and the FTS5 table with its shadow tables',
    () async {
      final tables = (await _names(db, 'table')).toSet();
      expect(tables, {..._tables, ..._ftsTables});
      final fts = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE name = 'search_fts'",
          )
          .getSingle();
      expect(fts.read<String>('sql'), kSearchFtsCreateSql);
    },
  );

  test('every index exists with its columns', () async {
    expect((await _names(db, 'index')).toSet(), _indexes.keys.toSet());
    for (final MapEntry(key: name, value: columns) in _indexes.entries) {
      final rows = await db.customSelect('PRAGMA index_info($name)').get();
      expect(
        [for (final r in rows) r.read<String>('name')],
        columns,
        reason: name,
      );
    }
    Future<bool> unique(String table, List<String> columns) async {
      for (final r
          in await db.customSelect('PRAGMA index_list($table)').get()) {
        if (r.read<int>('unique') != 1) continue;
        final name = r.read<String>('name');
        final cols = await db.customSelect('PRAGMA index_info("$name")').get();
        if ([for (final c in cols) c.read<String>('name')].join(',') ==
            columns.join(',')) {
          return true;
        }
      }
      return false;
    }

    expect(await unique('outbox', ['entity_kind', 'entity_id']), isTrue);
    expect(await unique('recording_drafts', ['recording_id']), isTrue);
    expect(
      await unique('search_units', ['source', 'owner_key', 'seq']),
      isTrue,
    );
    expect(await unique('search_owners', ['source', 'owner_key']), isTrue);
  });

  test(
    'field_versions is a nullable TEXT column of the 10 entity tables',
    () async {
      var count = 0;
      for (final table in _tables) {
        final rows = await db.customSelect('PRAGMA table_info($table)').get();
        final fv = rows.where(
          (r) => r.read<String>('name') == 'field_versions',
        );
        if (_entityTables.contains(table)) {
          expect(fv, hasLength(1), reason: table);
          expect(fv.single.read<String>('type'), 'TEXT');
          expect(fv.single.read<int>('notnull'), 0);
          count++;
        } else {
          expect(fv, isEmpty, reason: table);
        }
      }
      expect(count, 10);
    },
  );

  test('local and derived columns are present; no rects BLOB column', () async {
    expect(await _columnsOf(db, 'settings'), contains('deleted_at'));
    expect(
      await _columnsOf(db, 'notes'),
      containsAll(['page_count', 'first_page_id', 'last_opened_at']),
    );
    final pages = await _columnsOf(db, 'pages');
    expect(pages, contains('content_rev'));
    // (v2) appended last, as ALTER TABLE ADD COLUMN does.
    expect(pages.sublist(pages.length - 4), [
      'ink_rev',
      'ink_rev_at',
      'bg_asset_id',
      'bg_pdf_index',
    ]);
    expect((await _columnsOf(db, 'recordings')).last, 'title');
    expect(
      await _columnsOf(db, 'assets'),
      containsAll(['chunk_count', 'has_local_bytes', 'storage_path']),
    );
    expect(
      await _columnsOf(db, 'strokes'),
      containsAll(['note_id', 'points', 'min_x', 'max_y', 'version']),
    );
    final units = await _columnsOf(db, 'search_units');
    expect(
      units,
      containsAll(['rect_l', 'rect_t', 'rect_r', 'rect_b', 'rects_ref']),
    );
    expect(units, isNot(contains('rects')));
    final types = await db
        .customSelect('PRAGMA table_info(search_units)')
        .get();
    expect(types.where((r) => r.read<String>('type') == 'BLOB'), isEmpty);
    // id is the rowid (INTEGER PRIMARY KEY, no AUTOINCREMENT — 'max + 1').
    final id = types.firstWhere((r) => r.read<String>('name') == 'id');
    expect((id.read<String>('type'), id.read<int>('pk')), ('INTEGER', 1));
  });

  test('user_version is the schema version (2); a new database records the normalizer', () async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    expect(row.read<int>('user_version'), kDatabaseSchemaVersion);
    expect(kDatabaseSchemaVersion, 2);
    expect(NoteDatabase.currentSchemaVersion, kDatabaseSchemaVersion);
    final kv = await db
        .customSelect(
          "SELECT value FROM kv WHERE key = 'search.normalizerVersion'",
        )
        .getSingle();
    expect(kv.read<String>('value'), '1');
  });

  test(
    'a new v2 database = a v1 database upgraded to v2 (sqlite_master)',
    () async {
      final dir = Directory.systemTemp.createTempSync('note_core_schema_');
      addTearDown(() => dir.deleteSync(recursive: true));
      // The v1 database as the 1st-round code wrote it (the V7 fixture, T25a): drift's
      // generated schema_v1 writes the same tables with slightly different SQL text.
      final path = '${dir.path}/v1.db';
      File('test/fixtures/db_v1/noteapp_v1.sqlite').copySync(path);
      final upgraded =
          await openTestNoteStore(filePath: path) as DriftNoteStore;
      addTearDown(upgraded.close);
      final row = await upgraded.db
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(row.read<int>('user_version'), 2);
      expect(await _master(upgraded.db), await _master(db));
    },
  );

  test('drift_schemas/ v1 and v2 match the tables (make-migrations output is current)', () {
    Set<String> namesOf(String file, String type) {
      final json =
          jsonDecode(File(file).readAsStringSync()) as Map<String, Object?>;
      return {
        for (final e
            in (json['entities']! as List<Object?>)
                .cast<Map<String, Object?>>())
          if (e['type'] == type)
            ((e['data']! as Map<String, Object?>)['name']! as String),
      };
    }

    const v1 = 'drift_schemas/note_db/drift_schema_v1.json';
    const v2 = 'drift_schemas/note_db/drift_schema_v2.json';
    expect(namesOf(v1, 'table'), kV1Tables.toSet());
    expect(namesOf(v2, 'table'), _tables);
    expect(namesOf(v2, 'index'), _indexes.keys.toSet());
    expect(
      File('lib/src/storage/db/note_database.steps.dart').existsSync(),
      isTrue,
    );
  });
}
