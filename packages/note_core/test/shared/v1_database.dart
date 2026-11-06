// A synthetic 1st-round (v1) database for the CORE T24 upgrade tests (m5-7/02-core 6.12):
// the schema of drift's generated schema_v1 (the 1st-round tables exactly) plus rows written
// with SQL in the v1 row formats (copied from the V7 fixture). Web-safe (VM file databases
// and the Chrome web worker both use it).
// SQL statements are written as adjacent literals with SQL quotes inside.
// ignore_for_file: no_adjacent_strings_in_list, prefer_single_quotes
import 'package:drift/drift.dart';
import 'package:note_core/src/storage/db/canonical_dump.dart';

import '../storage/generated_migrations/note_db/generated/schema_v1.dart' as v1;

/// The HLC node of the synthetic database.
const String kV1Node = '00000000000000aa';
const String kV1Hlc = '001792974725000-0000-00000000000000aa';
const String kV1PdfAsset =
    'a9d04a94683249a064d05127ae71571899d12bb520b437f697f4309eed125f06';
const String kV1ImageAsset =
    'b9d04a94683249a064d05127ae71571899d12bb520b437f697f4309eed125f07';

/// The 1st-round tables (the v1 dump of the copy covers exactly these).
const List<String> kV1Tables = [
  'assets',
  'folders',
  'kv',
  'notes',
  'outbox',
  'pages',
  'pen_presets',
  'recordings',
  'settings',
  'strokes',
];

/// The v1 columns of the tables v2 widens (an upgraded table dumped with these is the v1
/// table), and the derived columns v2 may recompute.
const Map<String, List<String>> kV1WidenedColumns = {
  'pages': [
    'id',
    'note_id',
    'sort_key',
    'width',
    'height',
    'background_json',
    'created_at',
    'updated_at',
    'deleted_at',
    'version',
    'field_versions',
    'content_rev',
  ],
  'recordings': [
    'id',
    'note_id',
    'asset_id',
    'duration_ms',
    'started_at',
    'created_at',
    'updated_at',
    'deleted_at',
    'version',
    'field_versions',
  ],
};

/// The v1 columns without the derived name_norm / title_norm (C-14 'entity dump').
const Map<String, List<String>> kV1EntityColumns = {
  ...kV1WidenedColumns,
  'folders': [
    'id',
    'owner_id',
    'parent_id',
    'name',
    'color_argb',
    'icon',
    'sort_key',
    'created_at',
    'updated_at',
    'deleted_at',
    'trash_root_id',
    'version',
    'field_versions',
  ],
  'notes': [
    'id',
    'owner_id',
    'folder_id',
    'title',
    'cover_json',
    'tags_json',
    'is_favorite',
    'sort_key',
    'schema_version',
    'created_at',
    'updated_at',
    'deleted_at',
    'trash_root_id',
    'version',
    'field_versions',
    'page_count',
    'first_page_id',
    'last_opened_at',
  ],
};

/// Rows whose normalized name changes in v2 (SearchText.normalize removes zero-width and
/// soft-hyphen characters and joins line-end hyphens; the v1 function did not).
const Map<String, String> kV1RenormalizedFolders = {
  'f1': 'abc',
  'f3': 'linebreak',
};
const Map<String, String> kV1RenormalizedNotes = {'n1': 'noteone'};

/// The synthetic rows (SQL; one statement each).
List<String> syntheticV1Rows() {
  const v = kV1Hlc;
  String q(String s) => "'${s.replaceAll("'", "''")}'";
  return [
    for (final (k, val) in [
      ('device.nodeId', kV1Node),
      ('hlc.last', kV1Hlc),
      ('store.ownerId', 'local'),
      ('seed.presets.v1', '1'),
      ('setting.library.viewMode', '"list"'),
      ('sync.cursor', '"c-1"'),
    ])
      'INSERT INTO kv (key, value) VALUES (${q(k)}, ${q(val)})',
    // f1, f3: v1 name_norm differs from SearchText.normalize; f2: the same.
    for (final (id, name, norm, parent) in [
      ('f1', 'Ab​c', 'ab​c', null),
      ('f2', 'Plain 폴더', 'plain 폴더', 'f1'),
      ('f3', 'Line-\nbreak', 'line- break', null),
    ])
      'INSERT INTO folders (id, owner_id, parent_id, name, name_norm, color_argb, icon, '
          'sort_key, created_at, updated_at, deleted_at, trash_root_id, version, '
          "field_versions) VALUES (${q(id)}, 'local', ${parent == null ? 'NULL' : q(parent)}, "
          "${q(name)}, ${q(norm)}, 4282351551, NULL, 'a0', 1792972860000, 1792972860000, "
          "NULL, NULL, ${q(v)}, NULL)",
    for (final (id, title, norm, deleted) in [
      ('n1', 'Note­One', 'note­one', 'NULL'),
      ('n2', '강의 노트', '강의 노트', '1792974000000'),
    ])
      'INSERT INTO notes (id, owner_id, folder_id, title, title_norm, cover_json, tags_json, '
          'is_favorite, sort_key, schema_version, created_at, updated_at, deleted_at, '
          'trash_root_id, version, field_versions, page_count, first_page_id, '
          "last_opened_at) VALUES (${q(id)}, 'local', 'f2', ${q(title)}, ${q(norm)}, "
          '\'{"type":"color","color":4287505578}\', \'["물리","week 1"]\', 0, \'a0\', 1, '
          "1792972980000, 1792974305000, $deleted, ${deleted == 'NULL' ? 'NULL' : q(id)}, "
          "${q(v)}, '{\"b\":\"$v\"}', 2, 'p1', 1792974240000)",
    for (final (id, note, bg) in [
      ('p1', 'n1', '{"type":"blank","paperColor":4294967295}'),
      (
        'p2',
        'n1',
        '{"type":"pdf","paperColor":4294967295,"assetId":"$kV1PdfAsset",'
            '"pdfPageIndex":2}',
      ),
      (
        'p3',
        'n2',
        '{"type":"image","paperColor":4294967295,"assetId":"$kV1ImageAsset",'
            '"fit":"contain"}',
      ),
      (
        'p4',
        'n2',
        '{"type":"template","paperColor":4294967295,"template":{"kind":"lined"}}',
      ),
    ])
      'INSERT INTO pages (id, note_id, sort_key, width, height, background_json, '
          'created_at, updated_at, deleted_at, version, field_versions, content_rev) '
          "VALUES (${q(id)}, ${q(note)}, ${q('a$id')}, 595.2756, 841.8898, ${q(bg)}, "
          "1792972980000, 1792972980000, NULL, ${q(v)}, NULL, 3)",
    for (var i = 0; i < 5; i++)
      'INSERT INTO strokes (id, page_id, note_id, tool, color_argb, width, opacity, '
          'pressure_sensitivity, pressure_curve, smoothing, style_extras_json, points, '
          'point_count, min_x, min_y, max_x, max_y, recording_id, recording_offset_ms, '
          'created_at, updated_at, deleted_at, version, field_versions) VALUES '
          "('s$i', 'p1', 'n1', 'ballpoint', 4279900698, 1.6, 1.0, 1.0, "
          "'0.25,0.25,0.75,0.75', 0.5, NULL, X'01020304FF', 2, 0.1, 0.2, 10.30000000000001, "
          "20.0, ${i == 0 ? "'r1'" : 'NULL'}, ${i == 0 ? '1200' : 'NULL'}, 1792972980000, "
          "1792972980000, NULL, ${q(v)}, NULL)",
    "INSERT INTO pen_presets (id, owner_id, name, style_json, group_name, pinned, sort_key, "
        "created_at, updated_at, deleted_at, version, field_versions) VALUES "
        "('preset-default-ballpoint', 'local', '볼펜', '{\"tool\":\"ballpoint\"}', NULL, 1, "
        "'a0', 1792972800000, 1792972800000, NULL, '000000000000001-0000-0000000000000000', "
        'NULL)',
    for (final (id, type, mime) in [
      (kV1PdfAsset, 'pdf', 'application/pdf'),
      (kV1ImageAsset, 'image', 'image/png'),
    ])
      'INSERT INTO assets (id, owner_id, type, mime_type, size, file_name, chunk_count, '
          'has_local_bytes, storage_path, created_at, deleted_at, version, field_versions) '
          "VALUES (${q(id)}, 'local', ${q(type)}, ${q(mime)}, 1990, 'it''s.pdf', 1, 0, NULL, "
          "1792973340000, NULL, ${q(v)}, NULL)",
    'INSERT INTO recordings (id, note_id, asset_id, duration_ms, started_at, created_at, '
        "updated_at, deleted_at, version, field_versions) VALUES ('r1', 'n1', "
        "${q(kV1PdfAsset)}, 900000, 1792972980000, 1792973880000, 1792973880000, NULL, "
        "${q(v)}, NULL)",
    'INSERT INTO settings (key, value_json, updated_at, deleted_at, version, '
        "field_versions) VALUES ('library.newNote.defaults', '{\"size\":\"a4\"}', "
        "1792974725000, NULL, ${q(v)}, NULL)",
    for (final (i, (kind, id)) in [
      ('stroke', 's0'),
      ('stroke', 's1'),
      ('stroke', 's2'),
      ('stroke', 's3'),
      ('stroke', 's4'),
      ('folder', 'f1'),
      ('folder', 'f2'),
      ('folder', 'f3'),
      ('note', 'n1'),
      ('note', 'n2'),
      ('page', 'p1'),
      ('page', 'p2'),
    ].indexed)
      'INSERT INTO outbox (seq, rev, entity_kind, entity_id, note_id, page_id, op, '
          "changed_fields, hlc, enqueued_at) VALUES (${i + 1}, ${i + 1}, ${q(kind)}, "
          "${q(id)}, 'n1', NULL, 'upsert', '[\"*\"]', ${q(v)}, ${1792972800000 + i})",
  ];
}

/// Creates the v1 schema (drift's generated schema_v1: user_version 1) on [executor], runs
/// [statements] (default: [syntheticV1Rows]) and closes it; returns the canonical dump of the
/// v1 database (lib/ canonical_dump.dart).
Future<Uint8List> createV1Database(
  QueryExecutor executor, {
  Iterable<String>? statements,
}) async {
  final db = v1.DatabaseAtV1(executor);
  try {
    await db.customSelect('SELECT 1').get(); // opens: onCreate + user_version 1
    for (final s in statements ?? syntheticV1Rows()) {
      await db.customStatement(s);
    }
    return await canonicalDump((sql, args) => textQuery(db, sql, args));
  } finally {
    await db.close();
  }
}

/// [sql] as a dump query of [db] (first column as text).
Future<List<String>> textQuery(
  GeneratedDatabase db,
  String sql,
  List<Object?> args,
) async {
  final rows = await db
      .customSelect(
        sql,
        variables: [
          for (final a in args)
            a is int ? Variable<int>(a) : Variable<String>(a! as String),
        ],
      )
      .get();
  return [for (final r in rows) r.data.values.first! as String];
}
