// CORE T6 — drift schema v1 (6.11): tables, indexes, field_versions columns.
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
};

void main() {
  late DriftNoteStore store;
  late NoteDatabase db;

  setUp(() async {
    store = await openTestNoteStore() as DriftNoteStore;
    db = store.db;
  });
  tearDown(() => store.close());

  Future<List<String>> names(String type) async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = ? AND name NOT LIKE 'sqlite_%'",
          variables: [Variable.withString(type)],
        )
        .get();
    return [for (final r in rows) r.read<String>('name')];
  }

  Future<List<String>> columnsOf(String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return [for (final r in rows) r.read<String>('name')];
  }

  test('the ten tables exist', () async {
    expect((await names('table')).toSet(), _tables);
  });

  test('every index exists with its columns', () async {
    expect((await names('index')).toSet(), _indexes.keys.toSet());
    for (final MapEntry(key: name, value: columns) in _indexes.entries) {
      final rows = await db.customSelect('PRAGMA index_info($name)').get();
      expect(
        [for (final r in rows) r.read<String>('name')],
        columns,
        reason: name,
      );
    }
    final outboxIndexes = await db
        .customSelect('PRAGMA index_list(outbox)')
        .get();
    final entity = outboxIndexes.singleWhere(
      (r) => r.read<String>('name') == 'idx_outbox_entity',
    );
    expect(entity.read<int>('unique'), 1);
  });

  test(
    'field_versions is a nullable TEXT column of the 8 entity tables',
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
      expect(count, 8);
    },
  );

  test('settings has deleted_at; local columns are present', () async {
    expect(await columnsOf('settings'), contains('deleted_at'));
    expect(
      await columnsOf('notes'),
      containsAll(['page_count', 'first_page_id', 'last_opened_at']),
    );
    expect(await columnsOf('pages'), contains('content_rev'));
    expect(
      await columnsOf('assets'),
      containsAll(['chunk_count', 'has_local_bytes', 'storage_path']),
    );
    expect(
      await columnsOf('strokes'),
      containsAll(['note_id', 'points', 'min_x', 'max_y', 'version']),
    );
  });

  test('user_version is the schema version', () async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    expect(row.read<int>('user_version'), kDatabaseSchemaVersion);
    expect(kDatabaseSchemaVersion, 1);
    expect(NoteDatabase.currentSchemaVersion, kDatabaseSchemaVersion);
  });

  test(
    'drift_schemas/ v1 matches the tables (make-migrations output is current)',
    () async {
      final file = File('drift_schemas/note_db/drift_schema_v1.json');
      expect(file.existsSync(), isTrue);
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final entities = (json['entities']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final tables = {
        for (final e in entities)
          if (e['type'] == 'table')
            ((e['data']! as Map<String, Object?>)['name']! as String),
      };
      expect(tables, _tables);
      final indexes = {
        for (final e in entities)
          if (e['type'] == 'index')
            ((e['data']! as Map<String, Object?>)['name']! as String),
      };
      expect(indexes, _indexes.keys.toSet());
    },
  );
}
