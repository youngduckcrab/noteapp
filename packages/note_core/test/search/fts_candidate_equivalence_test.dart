// CORE T33b — the fake index's FTS5 model = SQLite FTS5 on the VM (m5-7/02-core 6.10.6): the
// shared body test/shared/fts_equivalence_cases.dart on the real store's search_fts table.
@TestOn('vm')
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:test/test.dart';

import '../shared/fts_equivalence_cases.dart';
import '../storage/storage_support.dart';

void main() {
  late DriftNoteStore store;
  setUp(() async => store = await openStore());
  tearDown(() => store.close());

  defineFtsEquivalenceCases(
    insert: (rows) => store.db.transaction(() async {
      for (final (id, g) in rows) {
        await store.db.customStatement(
          'INSERT INTO search_fts (rowid, g) VALUES (?, ?)',
          [id, g],
        );
      }
    }),
    match: (m) async => {
      for (final r
          in await store.db
              .customSelect(
                'SELECT rowid AS id FROM search_fts WHERE search_fts MATCH ?',
                variables: [Variable<String>(m)],
              )
              .get())
        r.read<int>('id'),
    },
  );
}
