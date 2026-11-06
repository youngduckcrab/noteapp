// CORE T24 — the canonical dump of lib/ (m5-7/02-core 6.12.3, 6.12.4): quote() format, rows in
// line order, paging by key, chunks, and byte equality with the T25a tool
// (tool/src/v1_dump.dart) on the V7 fixture and on edge-case tables. The Chrome side of 'VM =
// Chrome bytes' is test/web/canonical_dump_browser_test.dart (same edge tables).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:note_core/src/storage/db/canonical_dump.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../tool/src/v1_dump.dart' as tool;
import '../shared/canonical_dump_cases.dart';

CanonicalDumpQuery _libQuery(Database db) =>
    (sql, args) async => [
      for (final r in db.select(sql, args)) r.values.first! as String,
    ];

tool.DumpQuery _toolQuery(Database db) =>
    (sql) async => [for (final r in db.select(sql)) r.values.first! as String];

void main() {
  group('edge tables', () {
    late Database db;
    setUp(() {
      db = sqlite3.openInMemory();
      for (final s in kDumpEdgeStatements) {
        db.execute(s);
      }
    });
    tearDown(() => db.close());

    test('the tool and lib/ write the expected bytes', () async {
      final expected = utf8.encode(kDumpEdgeExpected);
      expect(
        await tool.canonicalDump(_toolQuery(db), tables: kDumpEdgeTables),
        expected,
      );
      expect(
        await canonicalDump(_libQuery(db), tables: kDumpEdgeTables),
        expected,
      );
    });

    test('every page size gives the same bytes', () async {
      final expected = utf8.encode(kDumpEdgeExpected);
      for (final pageRows in [1, 2, 3, 5, 13, 14, 15]) {
        expect(
          await canonicalDump(
            _libQuery(db),
            tables: kDumpEdgeTables,
            pageRows: pageRows,
          ),
          expected,
          reason: 'pageRows $pageRows',
        );
      }
    });

    test('all tables by default, column subsets on request', () async {
      expect(
        await canonicalDump(_libQuery(db)),
        await tool.canonicalDump(_toolQuery(db)),
      );
      final subset = {
        'edge_int': ['seq', 't'],
        'edge_text': ['v'],
      };
      expect(
        await canonicalDump(_libQuery(db), columns: subset, pageRows: 2),
        await tool.canonicalDump(_toolQuery(db), columns: subset),
      );
    });

    test('chunks: fixed size, the last shorter, joined = the dump', () async {
      for (final size in [1, 7, 64, 1 << 20]) {
        final chunks = await canonicalDumpChunks(
          _libQuery(db),
          tables: kDumpEdgeTables,
          pageRows: 3,
          chunkBytes: size,
        ).toList();
        final joined = BytesBuilder();
        for (final (i, c) in chunks.indexed) {
          expect(c, isNotEmpty);
          if (i < chunks.length - 1) {
            expect(c.length, size);
          } else {
            expect(c.length, lessThanOrEqualTo(size));
          }
          joined.add(c);
        }
        expect(joined.takeBytes(), utf8.encode(kDumpEdgeExpected));
      }
    });

    test('firstLiteralOf reads one SQL literal', () {
      expect(firstLiteralOf("'a''b',1"), "'a''b'");
      expect(firstLiteralOf("'',9"), "''");
      expect(firstLiteralOf("'x\ny',2"), "'x\ny'");
      expect(firstLiteralOf("X'0102',3"), "X'0102'");
      expect(firstLiteralOf('-5,3.0'), '-5');
      expect(firstLiteralOf('17'), '17');
      expect(firstLiteralOf('NULL,1'), 'NULL');
    });
  });

  group('V7 fixture (T25a, test/fixtures/db_v1)', () {
    late Directory dir;
    late Database db;
    late Map<String, Object?> manifest;

    setUpAll(() {
      dir = Directory.systemTemp.createTempSync('note_core_dump_');
      // A copy: opening the WAL-mode file would write its -shm next to the fixture.
      final copy = File('test/fixtures/db_v1/noteapp_v1.sqlite')
          .copySync('${dir.path}/v1.sqlite');
      db = sqlite3.open(copy.path);
      manifest = jsonDecode(
        File('test/fixtures/db_v1/manifest.json').readAsStringSync(),
      ) as Map<String, Object?>;
    });
    tearDownAll(() {
      db.close();
      dir.deleteSync(recursive: true);
    });

    test('lib/ dump = tool dump = manifest fullDumpSha256', () async {
      final lib = await canonicalDump(_libQuery(db));
      expect(lib, await tool.canonicalDump(_toolQuery(db)));
      expect(lib.length, manifest['fullDumpBytes']);
      expect(sha256.convert(lib).toString(), manifest['fullDumpSha256']);
      // Small pages: many keyset pages over the outbox (integer keys) and strokes.
      final paged = await canonicalDump(_libQuery(db), pageRows: 97);
      expect(sha256.convert(paged).toString(), manifest['fullDumpSha256']);
    });

    test(
      'entity dump (no derived columns) = manifest entityDumpSha256',
      () async {
        final derived = (manifest['derivedColumns']! as Map<String, Object?>)
            .map(
              (t, cols) => MapEntry(t, (cols! as List<Object?>).cast<String>()),
            );
        final tables = (manifest['entityTables']! as List<Object?>)
            .cast<String>();
        final columns = <String, List<String>>{
          for (final t in derived.keys)
            t: [
              for (final r in db.select(
                'SELECT name FROM pragma_table_info(?) ORDER BY cid',
                [t],
              ))
                if (!derived[t]!.contains(r['name'])) r['name']! as String,
            ],
        };
        final dump = await canonicalDump(
          _libQuery(db),
          tables: tables,
          columns: columns,
          pageRows: 500,
        );
        expect(sha256.convert(dump).toString(), manifest['entityDumpSha256']);
      },
    );
  });
}
