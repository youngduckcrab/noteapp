// CORE T24 — the canonical dump in Chrome (m5-7/02-core 6.12.3 'VM = Chrome bytes'): the same
// edge tables as the VM test (test/shared/canonical_dump_cases.dart) dumped by lib/ through the
// drift web worker (sqlite3.wasm) give exactly the expected bytes, with any page size.
@TestOn('browser')
library;

import 'dart:convert';

import 'package:note_core/src/storage/db/canonical_dump.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:test/test.dart';

import '../shared/canonical_dump_cases.dart';
import '../shared/v1_database.dart';
import 'web_store_support.dart';

void main() {
  test('the edge tables dump to the VM bytes', () async {
    final config = freshWebConfig('dump');
    final store = await openWebStoreWithNode(
      config,
      '00000000000000d1',
    ) as DriftNoteStore;
    closeAndDropAfterTest(store, config);
    for (final s in kDumpEdgeStatements) {
      await store.db.customStatement(s);
    }
    final expected = utf8.encode(kDumpEdgeExpected);
    for (final pageRows in [1, 3, kCanonicalDumpPageRows]) {
      expect(
        await canonicalDump(
          (sql, args) => textQuery(store.db, sql, args),
          tables: kDumpEdgeTables,
          pageRows: pageRows,
        ),
        expected,
        reason: 'pageRows $pageRows',
      );
    }
  });
}
