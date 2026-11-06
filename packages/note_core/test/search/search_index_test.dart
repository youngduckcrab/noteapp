// CORE T33b — the query side of the real search index (m5-7/02-core 6.10.4) beyond the shared
// contract: trashed notes / deleted pages excluded and found again after restore / undo, other
// owners' notes excluded, withinNote, trashed units not taking the 2,000 candidate cap, a
// missing glyph box blob read as 'no boxes' (C-13), the candidate query reading neither body
// nor rects_ref, no sort step in either candidate plan (EXPLAIN QUERY PLAN), and the same hits
// as the fake store for the same writes.
@TestOn('vm')
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/drift_search_index.dart';
import 'package:note_core/testing.dart'
    show PageObjectFixtures, createFakeNoteStore, newerVersionWinsPolicy;
import 'package:test/test.dart';

import '../storage/storage_support.dart';
import '../sync/support/sync_support.dart';

const String _asset =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

/// A note whose pages hold one text box each with [bodies].
Future<(Note, List<PageId>)> textNote(
  NoteStore store,
  String title,
  List<String> bodies,
) async {
  final note = await store.library.createNote(
    title: title,
    pages: [
      for (final b in bodies)
        PageDraft(
          size: PageSize.a4Portrait,
          background: const BlankBackground(),
          objects: [PageObjectFixtures.textBox(pageId: 'x', text: b)],
        ),
    ],
  );
  return (note, [for (final p in await store.content.pagesOf(note.id)) p.id]);
}

void main() {
  late DriftNoteStore store;
  setUp(() async => store = await openStore());
  tearDown(() => store.close());

  Future<List<PageId>> pagesFor(String q, {NoteId? within}) async => [
    for (final h in await store.search.searchPages(q, withinNote: within))
      h.pageId,
  ];

  test('trashed notes and deleted pages are skipped and come back', () async {
    final (a, ap) = await textNote(store, 'a', const ['복원 시험 하나']);
    final (_, bp) = await textNote(store, 'b', const ['복원 시험 둘', '복원 셋']);
    expect((await pagesFor('복원')).toSet(), {...ap, ...bp});

    await store.library.trashItems([NoteRef(a.id)]);
    expect((await pagesFor('복원')).toSet(), {...bp});
    await store.trash.restore([NoteRef(a.id)]);
    expect((await pagesFor('복원')).toSet(), {...ap, ...bp});

    final session = await store.openSession(
      (await store.library.searchLibrary('b')).notes.single.id,
    );
    await session.execute(DeletePages(pageIds: [bp[1]])).persisted;
    expect((await pagesFor('복원')).toSet(), {...ap, bp[0]});
    await session.undo();
    await session.flush();
    expect((await pagesFor('복원')).toSet(), {...ap, ...bp});
    await session.close();
  });

  test('withinNote and other owners', () async {
    final (a, ap) = await textNote(store, 'a', const ['소유 범위']);
    final (_, bp) = await textNote(store, 'b', const ['소유 범위']);
    expect(await pagesFor('범위', within: a.id), ap);
    expect((await pagesFor('범위')).toSet(), {...ap, ...bp});
    // A note of another owner (arrived remotely) with an indexed text box.
    await store.sync.applyRemote([
      upsert(
        Note(
          id: 'n-other',
          ownerId: 'someone-else',
          title: 'other',
          sortKey: 'a0',
          createdAt: 1,
          updatedAt: 1,
        ),
        remoteAfter(store),
      ),
      upsert(page('p-other', 'n-other'), remoteAfter(store)),
      upsert(
        PageObjectFixtures.textBox(pageId: 'p-other', id: 'o1', text: '소유 범위'),
        remoteAfter(store),
      ),
    ], policy: newerVersionWinsPolicy);
    expect(
      await store.db.select(store.db.searchUnits).get(),
      hasLength(3),
      reason: 'the other owner\'s text is indexed, only not returned',
    );
    expect((await pagesFor('범위')).toSet(), {...ap, ...bp});
  });

  test('trashed units do not take the 2,000 candidate cap', () async {
    final (_, live) = await textNote(store, 'live', const ['오래된 공통']);
    final trashed = await store.library.createNote(
      title: 'trashed',
      pages: const [PageDraft.blankA4],
    );
    final tp = (await store.content.pagesOf(trashed.id)).single.id;
    await store.library.trashItems([NoteRef(trashed.id)]);
    for (var i = 0; i < 3; i++) {
      await store.handwriting.put(
        HandwritingText(
          noteId: trashed.id,
          pageId: tp,
          engineId: 'fake/1:ko',
          sourceRev: '$i' * 16,
          lines: [
            for (var l = 0; l < 700 + i; l++)
              HandwritingLine(
                text: '공통 $l',
                rect: PageRect(0, l.toDouble(), 10, l + 1.0),
                strokeIds: const [],
              ),
          ],
          createdAt: 1,
        ),
      );
    }
    expect(
      await store.db.select(store.db.searchUnits).get(),
      hasLength(1 + 702),
    );
    final r = await store.library.searchLibrary('공통');
    expect(r.pages.map((h) => h.pageId), live);
    expect(r.pagesTruncated, isFalse);
  });

  test('a missing box blob: the hit without rects (C-13)', () async {
    final note = await store.library.createNote(
      title: 'pdf',
      pages: const [
        PageDraft(
          size: PageSize(600, 800),
          background: PdfBackground(assetId: _asset, pdfPageIndex: 0),
        ),
      ],
    );
    await store.search.replaceUnits(SearchSource.pdf, '$_asset#0', [
      SearchUnitDraft(
        body: '상자 사라짐',
        rects: [
          for (var i = 0; i < 6; i++) PageRect(i / 10, 0.1, (i + 1) / 10, 0.2),
        ],
      ),
    ], sourceRev: 'r');
    var hit = (await store.search.searchPages('상자')).single;
    expect(hit.rects, hasLength(1));
    expect(hit.noteId, note.id);
    await store.search.blobs.deletePrefix(kSearchBlobRoot);
    hit = (await store.search.searchPages('상자')).single;
    expect(hit.rects, isEmpty);
    expect(hit.snippet, '상자 사라짐');
  });

  test('candidate queries read neither body nor rects_ref; no sort step in their plans', () async {
    await textNote(store, 'plan', const ['회의록 정리']);
    store.search.debugCandidateSql.clear();
    expect(await store.search.searchPages('회의록'), hasLength(1));
    expect(await store.search.searchPages('정'), hasLength(1));
    expect(store.search.debugCandidateSql, hasLength(2));
    for (final sql in store.search.debugCandidateSql) {
      // Nowhere in the query (its liveness reads are pages / notes columns only).
      expect(sql, isNot(contains('body')));
      expect(sql, isNot(contains('rects_ref')));
      expect(sql, isNot(contains('rect_')));
      final n = '?'.allMatches(sql).length;
      final plan = [
        for (final r
            in await store.db
                .customSelect(
                  'EXPLAIN QUERY PLAN $sql',
                  variables: [
                    for (var i = 0; i < n; i++) const Variable<String>('x'),
                  ],
                )
                .get())
          r.read<String>('detail'),
      ];
      expect(plan.join('\n'), isNot(contains('TEMP B-TREE')), reason: sql);
    }
    expect(store.search.debugCandidateSql.first, contains('MATCH'));
    expect(store.search.debugCandidateSql.last, contains('LIKE'));
  });

  test('the same hits as the fake store for the same writes', () async {
    final fake = createFakeNoteStore(seedDefaultPenPresets: false);
    addTearDown(fake.close);
    Future<void> fill(NoteStore s) async {
      await textNote(s, 'one', const [
        '오늘 회의록을 정리했다 meeting notes',
        '방정식 laplace 변환',
      ]);
      await textNote(s, 'two', const ['정식 계약서', '확률과 통계 단어 암기']);
      final n = await s.library.createNote(
        title: 'ink',
        pages: const [PageDraft.blankA4],
      );
      final p = (await s.content.pagesOf(n.id)).single.id;
      await s.handwriting.put(
        HandwritingText(
          noteId: n.id,
          pageId: p,
          engineId: 'fake/1:ko',
          sourceRev: '0' * 16,
          lines: const [
            HandwritingLine(
              text: '손글씨 회의',
              rect: PageRect(1, 2, 30, 4),
              strokeIds: [],
            ),
            HandwritingLine(
              text: 'meet again',
              rect: PageRect(1, 6, 30, 8),
              strokeIds: [],
            ),
          ],
          createdAt: 1,
        ),
      );
    }

    await fill(store);
    await fill(fake);
    for (final q in [
      '회의',
      '회의록',
      '정식',
      '정',
      'meet',
      'LAPLACE',
      '확률 통계',
      '방정 정식',
      'eeting',
      '없음',
    ]) {
      final real = await store.search.searchPages(q);
      final mem = await fake.search.searchPages(q);
      expect(
        [
          for (final h in real)
            (h.source, h.snippet, h.matchRange, '${h.rects}', h.score),
        ],
        [
          for (final h in mem)
            (h.source, h.snippet, h.matchRange, '${h.rects}', h.score),
        ],
        reason: q,
      );
    }
  });
}
