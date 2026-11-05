// tool/v1_fixture_manifest.dart — CORE T25a (docs/plans/m5-7/02-core.md 6.12.3,
// contract 00-overview 7.7.2 V7, 00-review '최종 승인' CORE-F2): computes
// test/fixtures/db_v1/manifest.json from the fixture files — the values the V7
// migration tests (CORE T25b) compare with.
//
//   dart run tool/v1_fixture_manifest.dart            write manifest.json
//   dart run tool/v1_fixture_manifest.dart --check    exit 1 unless it is current
//   (an optional last argument names another fixture directory)
//
// Only package:sqlite3 and the canonical dump of tool/src/v1_dump.dart are used
// (no CORE code), and the databases are read from copies in a temporary
// directory, so the committed files are never opened in place. Everything in
// the manifest is computed from the files: the same files give the same bytes.
//
// Hashes (SHA-256 of a canonical dump, format 'noteapp-v1-dump 1'):
//   fullDumpSha256    every v1 table, every column — the v1 copy check (V7: the
//                     copy made before the upgrade dumps to this; 6.12.4)
//   entityDumpSha256  the 8 entity tables with their v1 columns minus the
//                     derived ones (folders.name_norm, notes.title_norm — v2
//                     recomputes them): C-14 'migration keeps the v1 data'
//   outboxDumpSha256  the outbox table; kvDumpSha256 the kv table (v2 adds keys
//                     — the kv rows are listed too, to compare key by key)
//   tables.<t>.dumpSha256  one table, every v1 column
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import 'src/v1_dump.dart';

const String kVmFile = 'noteapp_v1.sqlite';
const String kWebFile = 'noteapp_v1_web.sqlite';
const String kPdfFile = 'pdf_asset.pdf';
const String kSourceFile = 'fixture_source.json';
const String kManifestFile = 'manifest.json';

/// The synced entity tables of schema v1 (6.11).
const List<String> kEntityTables = [
  'assets',
  'folders',
  'notes',
  'pages',
  'pen_presets',
  'recordings',
  'settings',
  'strokes',
];

/// Columns v2 recomputes from other columns (C-14 excludes them).
const Map<String, List<String>> kDerivedColumns = {
  'folders': ['name_norm'],
  'notes': ['title_norm'],
};

/// Asset chunk size of the blob store (CORE 6.13, kAssetChunkBytes).
const int kAssetChunkBytes = 4 * 1024 * 1024;

Future<void> main(List<String> args) async {
  final check = args.contains('--check');
  final rest = [
    for (final a in args)
      if (a != '--check') a,
  ];
  if (rest.length > 1 || rest.any((a) => a.startsWith('-'))) {
    stderr.writeln(
      'usage: dart run tool/v1_fixture_manifest.dart [--check] [<fixture dir>]',
    );
    exit(64);
  }
  final dir = rest.isEmpty
      ? Directory('${_packageDir().path}/test/fixtures/db_v1')
      : Directory(rest.single);
  final text = await computeManifestText(dir);
  final file = File('${dir.path}/$kManifestFile');
  if (check) {
    final current = file.existsSync() ? await file.readAsString() : null;
    if (current != text) {
      stderr.writeln(
        'v1_fixture_manifest: ${file.path} is not current — run '
        'dart run tool/v1_fixture_manifest.dart',
      );
      exit(1);
    }
    stdout.writeln('v1_fixture_manifest: ${file.path} is current');
    return;
  }
  await file.writeAsString(text, flush: true);
  stdout.writeln('v1_fixture_manifest: wrote ${file.path}');
}

/// The manifest of the fixture in [dir], as written to manifest.json
/// (2-space JSON, keys in insertion order, a final newline).
Future<String> computeManifestText(Directory dir) async =>
    '${const JsonEncoder.withIndent('  ').convert(await computeManifest(dir))}\n';

Future<Map<String, Object?>> computeManifest(Directory dir) async {
  final vmBytes = await _read(dir, kVmFile);
  final webBytes = await _read(dir, kWebFile);
  final pdfBytes = await _read(dir, kPdfFile);
  final sourceBytes = await _read(dir, kSourceFile);

  final work = await Directory.systemTemp.createTemp('v1_fixture_manifest_');
  final opened = <_Db>[];
  try {
    final vm = await _inspect(vmBytes, work, 'vm');
    opened.add(vm);
    final web = await _inspect(webBytes, work, 'web');
    opened.add(web);
    if (_sha256(vm.fullDump) != _sha256(web.fullDump)) {
      throw StateError('$kVmFile and $kWebFile have different canonical dumps');
    }
    final db = vm;
    final pdfAssets = db.rows(
      "SELECT id, size, chunk_count FROM assets WHERE type = 'pdf' ORDER BY id",
    );
    if (pdfAssets.length != 1) {
      throw StateError('expected 1 PDF asset, found ${pdfAssets.length}');
    }
    final pdf = pdfAssets.single;
    final pdfId = pdf['id']! as String;
    final pdfSize = pdf['size']! as int;
    final pdfChunks = pdf['chunk_count']! as int;
    if (_sha256(pdfBytes) != pdfId || pdfBytes.length != pdfSize) {
      throw StateError('$kPdfFile is not the bytes of PDF asset $pdfId');
    }
    if (pdfChunks != (pdfSize + kAssetChunkBytes - 1) ~/ kAssetChunkBytes) {
      throw StateError('unexpected chunk_count $pdfChunks of $pdfId');
    }

    final tables = <String, Object?>{
      for (final t in db.tables)
        t: {
          'columns': db.columns[t],
          'rows': db.count('SELECT count(*) FROM ${quoteIdentifier(t)}'),
          'dumpSha256': _sha256(
            await db.dump(tables: [t], columns: {t: db.columns[t]!}),
          ),
        },
    };
    final entityColumns = {
      for (final t in kEntityTables)
        t: [
          for (final c in db.columns[t]!)
            if (!(kDerivedColumns[t]?.contains(c) ?? false)) c,
        ],
    };

    return {
      'format': 'noteapp-v1-fixture-manifest 1',
      'dumpFormat': kV1DumpHeader,
      'about':
          'V7 fixture (CORE T25a): a v1 database written by the 1st-round '
          'CORE code. Computed by tool/v1_fixture_manifest.dart from the files '
          'of this directory; dump format in tool/src/v1_dump.dart.',
      'files': {
        kVmFile: {
          'bytes': vmBytes.length,
          'sha256': _sha256(vmBytes),
          'journalHeader': 'wal',
          'use':
              'VM / native: copy to a temporary directory, openNoteStore(file '
              'database) — the native form openNoteStore left',
        },
        kWebFile: {
          'bytes': webBytes.length,
          'sha256': _sha256(webBytes),
          'journalHeader': 'delete',
          'use':
              'Chrome: the initial bytes of a new web database (drift '
              'WasmDatabase.open initializeDatabase) — same rows, rollback '
              'journal header',
        },
        kPdfFile: {
          'bytes': pdfBytes.length,
          'sha256': _sha256(pdfBytes),
          'use': 'the bytes of the PDF asset (not in the database)',
        },
        kSourceFile: {'sha256': _sha256(sourceBytes)},
      },
      'sqlite': {
        'userVersion': db.count('PRAGMA user_version'),
        'pageSize': db.count('PRAGMA page_size'),
        'encoding': db.text('PRAGMA encoding'),
      },
      'fullDumpSha256': _sha256(vm.fullDump),
      'fullDumpBytes': vm.fullDump.length,
      'entityTables': kEntityTables,
      'derivedColumns': kDerivedColumns,
      'entityDumpSha256': _sha256(
        await db.dump(tables: kEntityTables, columns: entityColumns),
      ),
      'outboxDumpSha256': _sha256(await db.dump(tables: const ['outbox'])),
      'kvDumpSha256': _sha256(await db.dump(tables: const ['kv'])),
      'kv': {
        for (final r in db.rows('SELECT key, value FROM kv ORDER BY key'))
          r['key']! as String: r['value']! as String,
      },
      'tables': tables,
      'blobs': {
        'database':
            'noteapp_blobs (WebStorageConfig.blobDatabaseName default), '
            'IndexedDB version 1',
        'store': 'asset_chunks',
        'entries': [
          for (var i = 0; i < pdfChunks; i++)
            {
              'key': '$pdfId/${i.toString().padLeft(6, '0')}',
              'file': kPdfFile,
              'offset': i * kAssetChunkBytes,
              'bytes': i == pdfChunks - 1
                  ? pdfSize - i * kAssetChunkBytes
                  : kAssetChunkBytes,
            },
        ],
      },
      'counts': {
        'notes': db.count('SELECT count(*) FROM notes'),
        'notesInTrash': db.count(
          'SELECT count(*) FROM notes WHERE deleted_at IS NOT NULL',
        ),
        'folders': db.count('SELECT count(*) FROM folders'),
        'pages': db.count('SELECT count(*) FROM pages'),
        'pagesWithPdfBackground': db.count(
          'SELECT count(*) FROM pages WHERE '
          "json_extract(background_json, '\$.type') = 'pdf'",
        ),
        'strokes': db.count('SELECT count(*) FROM strokes'),
        'strokesErased': db.count(
          'SELECT count(*) FROM strokes WHERE deleted_at IS NOT NULL',
        ),
        'strokesWithRecording': db.count(
          'SELECT count(*) FROM strokes WHERE recording_id IS NOT NULL',
        ),
        'strokePoints': db.count('SELECT sum(point_count) FROM strokes'),
        'pdfAssets': pdfAssets.length,
        'assets': db.count('SELECT count(*) FROM assets'),
        'assetsWithoutLocalBytes': db.count(
          'SELECT count(*) FROM assets WHERE has_local_bytes = 0',
        ),
        'recordings': db.count('SELECT count(*) FROM recordings'),
        'penPresets': db.count('SELECT count(*) FROM pen_presets'),
        'syncedSettings': db.count('SELECT count(*) FROM settings'),
        'deviceSettings': db.count(
          "SELECT count(*) FROM kv WHERE key LIKE 'setting.%'",
        ),
        'outbox': db.count('SELECT count(*) FROM outbox'),
        'fieldVersionOverrides': db.count(
          'SELECT ${[for (final t in kEntityTables) "(SELECT count(*) FROM ${quoteIdentifier(t)} WHERE json_extract(field_versions, '\$.o') IS NOT NULL)"].join(' + ')}',
        ),
      },
    };
  } finally {
    for (final db in opened) {
      db.close();
    }
    await work.delete(recursive: true);
  }
}

/// One fixture database, opened from a copy.
final class _Db {
  _Db(this._db, this.tables, this.columns, this.fullDump);

  final sql.Database _db;
  final List<String> tables;
  final Map<String, List<String>> columns;
  final Uint8List fullDump;

  Future<List<String>> query(String q) async => [
    for (final r in _db.select(q)) r.columnAt(0) as String,
  ];

  List<Map<String, Object?>> rows(String q) => [
    for (final r in _db.select(q)) {for (final k in r.keys) k: r[k]},
  ];

  int count(String q) => (_db.select(q).single.columnAt(0) as int?) ?? 0;

  String text(String q) => _db.select(q).single.columnAt(0) as String;

  void close() => _db.close();

  Future<Uint8List> dump({
    required List<String> tables,
    Map<String, List<String>> columns = const {},
  }) => canonicalDump(query, tables: tables, columns: columns);
}

Future<_Db> _inspect(Uint8List bytes, Directory work, String name) async {
  final path = '${work.path}/$name.sqlite';
  await File(path).writeAsBytes(bytes, flush: true);
  final db = sql.sqlite3.open(path);
  try {
    Future<List<String>> query(String q) async => [
      for (final r in db.select(q)) r.columnAt(0) as String,
    ];
    final tables = await dumpTables(query);
    final columns = {for (final t in tables) t: await dumpColumns(query, t)};
    for (final t in [...kEntityTables, 'outbox', 'kv']) {
      if (!tables.contains(t)) throw StateError('$name: no table $t');
    }
    return _Db(db, tables, columns, await canonicalDump(query));
  } on Object {
    db.close();
    rethrow;
  }
}

Future<Uint8List> _read(Directory dir, String name) async {
  final file = File('${dir.path}/$name');
  if (!file.existsSync()) {
    throw StateError('${file.path} is missing (run tool/make_v1_fixture.dart)');
  }
  return file.readAsBytes();
}

String _sha256(List<int> bytes) => sha256.convert(bytes).toString();

/// packages/note_core: the parent of this script's tool/ directory, else the
/// working directory.
Directory _packageDir() {
  if (Platform.script.isScheme('file')) {
    final dir = File.fromUri(Platform.script).parent.parent;
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/test').existsSync()) {
      return dir;
    }
  }
  return Directory.current;
}
