// CORE T33a — the write side of the search index on the real web store (sqlite3.wasm in a
// worker, blobs in the browser IndexedDB): the FTS5 table with content='' and
// contentless_delete=1 is created, a text box write puts its terms in, an edit DELETEs the old
// row by rowid and re-inserts, a delete removes it, the pdf writer stores its glyph boxes in
// IndexedDB outside SQLite and deletes the old ones after the commit, and rebuild gives the same
// rows (m5-7/02-core 6.10.3, 6.10.5). The query part (MATCH / V10 table = VM) is CORE T33b.
@TestOn('browser')
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:note_core/note_core.dart';
import 'package:note_core/src/search/search_rects.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/drift_search_index.dart';
import 'package:note_core/testing.dart' show PageObjectFixtures;
import 'package:test/test.dart';

import 'web_store_support.dart';

const String _asset =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Future<List<int>> _match(DriftNoteStore s, String normalizedQuery) async => [
  for (final r
      in await s.db
          .customSelect(
            'SELECT rowid AS id FROM search_fts WHERE search_fts MATCH ? '
            'ORDER BY rowid',
            variables: [
              Variable<String>(SearchText.matchQuery(normalizedQuery)!),
            ],
          )
          .get())
    r.read<int>('id'),
];

Future<List<String>> _rows(DriftNoteStore s) async => [
  for (final u in await s.db.select(s.db.searchUnits).get())
    [u.source, u.ownerKey, u.seq, u.body, u.norm, u.rectL, u.rectB].join('|'),
  for (final o in await s.db.select(s.db.searchOwners).get())
    [o.source, o.ownerKey, o.sourceRev, o.pending].join('|'),
]..sort();

void main() {
  late DriftNoteStore store;

  setUp(() async {
    final config = freshWebConfig('t33a', seedDefaultPenPresets: false);
    store = await openWebStoreWithNode(
      config,
      '00000000000000aa',
    ) as DriftNoteStore;
    closeAndDropAfterTest(store, config);
  });

  test('the FTS5 table is contentless with contentless_delete', () async {
    final sql =
        (await store.db
                .customSelect(
                  "SELECT sql FROM sqlite_master WHERE name = 'search_fts'",
                )
                .getSingle())
            .read<String>('sql');
    expect(sql, contains("content=''"));
    expect(sql, contains('contentless_delete=1'));
  });

  test(
    'text box: insert, edit (DELETE by rowid + re-insert), delete, undo',
    () async {
      final note = await store.library.createNote(
        title: 'web',
        pages: const [PageDraft.blankA4],
      );
      final pageId = (await store.content.pagesOf(note.id)).single.id;
      final session = await store.openSession(note.id);
      addTearDown(session.close);
      await session.openPage(pageId);
      await session
          .execute(
            AddObjects(
              pageId: pageId,
              objects: [
                PageObjectFixtures.textBox(
                  pageId: pageId,
                  id: 'w1',
                  text: '오늘 회의록을 정리했다 meeting',
                ),
              ],
            ),
          )
          .persisted;
      final first = await _match(store, '회의록');
      expect(first, hasLength(1));
      expect(await _match(store, 'meet'), first);

      final o = session.pageIfLoaded(pageId)!.objects.single as TextBoxObject;
      await session
          .execute(
            UpdateObjects(
              pageId: pageId,
              objects: [o.copyWith(text: '방정식 풀이')],
            ),
          )
          .persisted;
      expect(await _match(store, '회의록'), isEmpty);
      expect(await _match(store, '방정'), hasLength(1));

      await session
          .execute(RemoveElements(pageId: pageId, elementIds: const ['w1']))
          .persisted;
      expect(await _match(store, '방정'), isEmpty);
      await session.undo();
      await session.flush();
      expect(await _match(store, '방정'), hasLength(1));
      final v = session.pageIfLoaded(pageId)!.objects.single.version;
      expect(
        await store.search.sourceRevOf(SearchSource.text, 'w1'),
        '$v:${SearchText.normalizerVersion}',
      );
    },
  );

  test('pdf writer: boxes in IndexedDB, old boxes deleted after the commit, empty list keeps the owner', () async {
    final s = store.search;
    const key = '$_asset#0';
    final rects = [
      for (var i = 0; i < 4; i++) PageRect(i / 10, 0.2, (i + 1) / 10, 0.25),
    ];
    await s.replaceUnits(SearchSource.pdf, key, [
      SearchUnitDraft(body: '피디에프', rects: rects, pdfPageAspect: 0.75),
    ], sourceRev: '$_asset:1:x2');
    final firstKeys = await s.blobs.keys(kSearchBlobRoot);
    expect(firstKeys, hasLength(1));
    expect(
      SearchRectsCodec.decode((await s.blobs.get(firstKeys.single))!),
      SearchRectsCodec.decode(SearchRectsCodec.encode(rects)),
    );
    expect(await _match(store, '피디'), hasLength(1));
    expect(await s.sourceRevs(SearchSource.pdf), {key: '$_asset:1:x2'});

    await s.replaceUnits(SearchSource.pdf, key, [
      SearchUnitDraft(body: '바뀐 쪽', rects: rects.sublist(0, 4)),
    ], sourceRev: 'r2');
    final secondKeys = await s.blobs.keys(kSearchBlobRoot);
    expect(secondKeys, hasLength(1));
    expect(secondKeys, isNot(firstKeys));
    expect(await _match(store, '피디'), isEmpty);

    await s.replaceUnits(SearchSource.pdf, key, const [], sourceRev: 'r3');
    expect(await s.sourceRevOf(SearchSource.pdf, key), 'r3');
    expect(await s.blobs.keys(kSearchBlobRoot), isEmpty);
    expect(await _match(store, '바뀐'), isEmpty);
    await s.removeOwner(SearchSource.pdf, key);
    expect(await s.sourceRevOf(SearchSource.pdf, key), isNull);
  });

  test('rebuild gives the same ink / text rows; pdf is dropped', () async {
    final note = await store.library.createNote(
      title: 'rebuild',
      pages: [
        PageDraft(
          size: PageSize.a4Portrait,
          background: const BlankBackground(),
          objects: [PageObjectFixtures.textBox(pageId: 'x', text: '다시 만들기')],
        ),
      ],
    );
    final pageId = (await store.content.pagesOf(note.id)).single.id;
    await store.handwriting.put(
      HandwritingText(
        noteId: note.id,
        pageId: pageId,
        engineId: 'fake/1:ko',
        sourceRev: '0000000000000000',
        lines: const [
          HandwritingLine(
            text: '손글씨',
            rect: PageRect(1, 2, 3, 4),
            strokeIds: ['s'],
          ),
        ],
        createdAt: 1,
      ),
    );
    await store.search.replaceUnits(SearchSource.pdf, '$_asset#1', const [
      SearchUnitDraft(body: '피디에프'),
    ], sourceRev: 'r');
    final before = [
      for (final r in await _rows(store))
        if (!r.startsWith('pdf|')) r,
    ];
    await store.search.rebuild();
    expect(await _rows(store), before);
    expect(await _match(store, '만들기'), hasLength(1));
    expect(await _match(store, '손글'), hasLength(1));
    expect(await _match(store, '피디'), isEmpty);
  });
}
