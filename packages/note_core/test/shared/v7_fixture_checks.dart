// The V7 checks (m5-7/02-core 6.12.3, contract 7.7.2 V7, T25b) shared by the VM test
// (test/migration/v1_fixture_migration_test.dart — file database + file blobs) and the Chrome
// test (test/web/v1_fixture_migration_browser_test.dart — the drift web worker): the store
// opened on the V7 fixture (a v1 database written by the 1st-round CORE code) is checked
// against test/fixtures/db_v1/manifest.json. Web-safe (no dart:io): each test reads the
// manifest and the fixture bytes its own way, and checks the v1 copy (④ / ④′) itself.
//
// ① the v1 columns of the entity tables without the derived ones dump to entityDumpSha256
//   (C-14), the derived columns are SearchText.normalize of their source
// ② outbox (and field_versions — in ①'s columns) unchanged, the v1 kv rows unchanged, the
//   only new kv keys are the normalizer version and the v1 copy record
// ③ the new tables are empty, pages.bg_* follow background_json, recordings.title is NULL
// ⑤ the store works: an object, a recording, text box and title search — and a reopened
//   store is the same (v7StateSha)
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/db/canonical_dump.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing.dart' show PageObjectFixtures;
import 'package:test/test.dart';

import 'v1_database.dart';

/// The parsed manifest.json of the V7 fixture.
final class V7Manifest {
  V7Manifest(this.json);

  factory V7Manifest.parse(String text) =>
      V7Manifest(jsonDecode(text) as Map<String, Object?>);

  final Map<String, Object?> json;

  String get fullDumpSha256 => json['fullDumpSha256']! as String;
  int get fullDumpBytes => json['fullDumpBytes']! as int;
  String get entityDumpSha256 => json['entityDumpSha256']! as String;
  String get outboxDumpSha256 => json['outboxDumpSha256']! as String;

  List<String> get entityTables =>
      (json['entityTables']! as List<Object?>).cast<String>();

  Map<String, List<String>> get derivedColumns =>
      (json['derivedColumns']! as Map<String, Object?>).map(
        (t, c) => MapEntry(t, (c! as List<Object?>).cast<String>()),
      );

  Map<String, Object?> get _tables => json['tables']! as Map<String, Object?>;

  /// The v1 tables (the tables of the v1 copy).
  List<String> get v1Tables => [..._tables.keys]..sort();

  /// The v1 columns of [table].
  List<String> columnsOf(String table) =>
      ((_tables[table]! as Map<String, Object?>)['columns']! as List<Object?>)
          .cast<String>();

  int rowsOf(String table) =>
      (_tables[table]! as Map<String, Object?>)['rows']! as int;

  Map<String, String> get kv => (json['kv']! as Map<String, Object?>).map(
    (k, v) => MapEntry(k, v! as String),
  );

  Map<String, Object?> get _counts => json['counts']! as Map<String, Object?>;
  int count(String name) => _counts[name]! as int;

  /// The asset blob entries (the 1st-round key format) of the PDF asset.
  List<({String key, int offset, int bytes})> get blobEntries => [
    for (final e
        in ((json['blobs']! as Map<String, Object?>)['entries']!
                as List<Object?>)
            .cast<Map<String, Object?>>())
      (
        key: e['key']! as String,
        offset: e['offset']! as int,
        bytes: e['bytes']! as int,
      ),
  ];

  /// The PDF asset id (the sha256 of pdf_asset.pdf).
  String get pdfAssetId =>
      ((json['files']! as Map<String, Object?>)['pdf_asset.pdf']!
              as Map<String, Object?>)['sha256']!
          as String;
}

/// The fixture's clock (fixture_source.json): it was written up to 1792974725000; note C went
/// to the trash at 1792974665000 and a store opened 30 days later purges it. The tests run one
/// day after the fixture, the clock moving with real time from there.
Clock v7Clock() {
  final start = DateTime.fromMillisecondsSinceEpoch(
    1792974725000 + const Duration(days: 1).inMilliseconds,
    isUtc: true,
  );
  final sw = Stopwatch()..start();
  return Clock(() => start.add(sw.elapsed));
}

/// The new kv keys an upgraded fixture has (6.12.1 step 6, 6.12.4).
// search.inkTermsVersion: recorded at the first open (no ink rows to rebuild).
const Set<String> kV7NewKvKeys = {
  'search.normalizerVersion',
  'db.v1Copy',
  'search.inkTermsVersion',
};

/// The tables v2 adds (6.11).
const List<String> kV7NewTables = [
  'page_objects',
  'handwriting',
  'recording_drafts',
  'search_owners',
  'search_units',
  'search_fts',
];

String _sha(Uint8List bytes) => sha256.convert(bytes).toString();

CanonicalDumpQuery _query(DriftNoteStore store) =>
    (sql, args) => textQuery(store.db, sql, args);

Future<List<Map<String, Object?>>> _rows(
  DriftNoteStore store,
  String sql,
) async => [for (final r in await store.db.customSelect(sql).get()) r.data];

/// The kv rows of [store].
Future<Map<String, String>> v7Kv(DriftNoteStore store) async => {
  for (final r in await _rows(store, 'SELECT key, value FROM kv'))
    r['key']! as String: r['value']! as String,
};

/// The v1 copy record (kv db.v1Copy).
Future<Map<String, Object?>> v7CopyRecord(DriftNoteStore store) async =>
    jsonDecode((await v7Kv(store))['db.v1Copy']!) as Map<String, Object?>;

/// ①②③ on the store right after the upgrade (before anything is written).
Future<void> expectV7Upgraded(DriftNoteStore store, V7Manifest m) async {
  await store.flush();
  final q = _query(store);
  expect(store.db.schemaVersion, 2);
  expect((await _rows(store, 'PRAGMA user_version')).single.values.single, 2);

  // ① entity tables, v1 columns, derived ones left out (C-14).
  final derived = m.derivedColumns;
  final entity = await canonicalDump(
    q,
    tables: m.entityTables,
    columns: {
      for (final t in m.entityTables)
        t: [
          for (final c in m.columnsOf(t))
            if (!(derived[t]?.contains(c) ?? false)) c,
        ],
    },
  );
  expect(_sha(entity), m.entityDumpSha256, reason: 'entity dump (C-14)');
  for (final r in await _rows(store, 'SELECT name, name_norm FROM folders')) {
    expect(r['name_norm'], SearchText.normalize(r['name']! as String));
  }
  for (final r in await _rows(store, 'SELECT title, title_norm FROM notes')) {
    expect(r['title_norm'], SearchText.normalize(r['title']! as String));
  }
  for (final t in m.v1Tables) {
    if (t == 'kv') continue; // ② below: v2 adds keys.
    final n = await _rows(store, 'SELECT count(*) AS n FROM "$t"');
    expect(n.single['n'], m.rowsOf(t), reason: 'rows of $t');
  }

  // ② outbox and kv.
  final outbox = await canonicalDump(
    q,
    tables: const ['outbox'],
    columns: {'outbox': m.columnsOf('outbox')},
  );
  expect(_sha(outbox), m.outboxDumpSha256, reason: 'outbox dump');
  final kv = await v7Kv(store);
  expect(kv.keys.toSet(), {...m.kv.keys, ...kV7NewKvKeys});
  for (final e in m.kv.entries) {
    expect(kv[e.key], e.value, reason: 'kv ${e.key}');
  }
  expect(kv['search.normalizerVersion'], '${SearchText.normalizerVersion}');

  // ③ new tables empty, bg_* from background_json, recording titles NULL.
  for (final t in kV7NewTables) {
    final n = await _rows(store, 'SELECT count(*) AS n FROM $t');
    expect(n.single['n'], 0, reason: '$t is empty');
  }
  final pages = await _rows(
    store,
    'SELECT background_json, bg_asset_id, bg_pdf_index FROM pages',
  );
  var withPdf = 0;
  for (final p in pages) {
    final bg =
        jsonDecode(p['background_json']! as String) as Map<String, Object?>;
    if (bg['type'] == 'pdf') {
      withPdf++;
      expect(p['bg_asset_id'], bg['assetId']);
      expect(p['bg_pdf_index'], bg['pdfPageIndex']);
    } else {
      expect(p['bg_asset_id'], bg['type'] == 'image' ? bg['assetId'] : null);
      expect(p['bg_pdf_index'], isNull);
    }
  }
  expect(withPdf, m.count('pagesWithPdfBackground'));
  expect(
    (await _rows(store, 'SELECT title FROM recordings')).map((r) => r['title']),
    List<Object?>.filled(m.count('recordings'), null),
  );
}

/// What ⑤ made, to look for again after a reopen.
typedef V7Made = ({
  NoteId noteA,
  PageId page,
  ElementId objectId,
  RecordingId recordingId,
});

/// ⑤: the upgraded store reads the v1 content and takes v2 writes — a text box (found by
/// search), a recording, title search over the folder name with full-width Latin and
/// decomposed Hangul (its name_norm is SearchText.normalize of it — ①).
Future<V7Made> exerciseV7Store(
  DriftNoteStore store,
  V7Manifest m,
  Uint8List pdfBytes,
) async {
  // The v1 content reads.
  final notes = await _rows(
    store,
    'SELECT id, title FROM notes WHERE deleted_at IS NULL ORDER BY title',
  );
  expect(notes, hasLength(m.count('notes') - m.count('notesInTrash')));
  final noteA =
      notes.firstWhere((n) => (n['title']! as String).startsWith('역학'))['id']!
          as String;
  final pages = await store.content.pagesOf(noteA);
  expect(pages, isNotEmpty);
  var strokes = 0;
  for (final p in pages) {
    strokes += (await store.content.loadPage(p.id)).strokes.length;
  }
  expect(strokes, greaterThan(0));
  expect(await store.assets.hasBytes(m.pdfAssetId), isTrue);
  expect(await store.assets.readBytes(m.pdfAssetId), pdfBytes);
  final recordings = await store.recordings.recordingsOf(noteA);
  expect(recordings, hasLength(m.count('recordings')));
  expect(recordings.single.title, isNull);

  // v2 writes: a text box object, a recording.
  final page = pages.first.id;
  final session = await store.openSession(noteA);
  try {
    await session.openPage(page);
    final text = PageObjectFixtures.textBox(
      pageId: page,
      text: '마이그레이션 뒤 첫 글상자',
      id: 'v7-text-1',
      createdAt: store.clock.now().millisecondsSinceEpoch,
    );
    session.execute(AddObjects(pageId: page, objects: [text]));
    await store.flush();
  } finally {
    await session.close();
  }
  final audio = recordings.single.assetId;
  final made = await store.recordings.createRecording(
    id: 'v7-recording-2',
    noteId: noteA,
    assetId: audio,
    durationMs: 1500,
    startedAt: store.clock.now().millisecondsSinceEpoch,
    title: '이주 뒤 녹음',
  );
  await store.flush();
  final result = (
    noteA: noteA,
    page: page,
    objectId: 'v7-text-1',
    recordingId: made.id,
  );
  await expectV7Made(store, result);
  return result;
}

/// What [exerciseV7Store] made is there (also after a reopen).
Future<void> expectV7Made(DriftNoteStore store, V7Made made) async {
  final content = await store.content.loadPage(made.page);
  expect(content.objectById(made.objectId), isA<TextBoxObject>());
  final recordings = await store.recordings.recordingsOf(made.noteA);
  expect(recordings.map((r) => r.id), contains(made.recordingId));
  expect(
    recordings.firstWhere((r) => r.id == made.recordingId).title,
    '이주 뒤 녹음',
  );
  final hits = await store.search.searchPages('마이그레이션');
  expect(hits.map((h) => (h.pageId, h.source)), [
    (made.page, SearchSource.text),
  ]);
  // The fixture's 'Ｐｈｙｓｉｃｓ  물리' is decomposed Hangul: the composed query finds it.
  final physics = (await _rows(
    store,
    "SELECT id FROM folders WHERE name LIKE 'Ｐ%'",
  )).single['id'];
  final library = await store.library.searchLibrary('물리');
  expect(library.folders.map((f) => f.id), [physics]);
  final byTitle = await store.library.searchLibrary('역학');
  expect(byTitle.notes.map((n) => n.id), [made.noteA]);
  expect(byTitle.pages.map((p) => p.pageId), isEmpty);
}

/// The sha256 of every table but kv and the FTS tables (its shadow tables change with
/// merges) — the same before closing and after reopening.
Future<String> v7StateSha(DriftNoteStore store) async {
  await store.flush();
  final q = _query(store);
  final tables = [
    for (final t in await canonicalDumpTables(q))
      if (t != 'kv' && !t.startsWith('search_fts')) t,
  ];
  return _sha(await canonicalDump(q, tables: tables));
}
