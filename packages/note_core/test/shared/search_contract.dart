// Shared body (m5-7/02-core 6.10.2–6.10.6, CP-14): SearchIndex results AND order — the 6.10.2
// query table on text boxes, ink and pdf sources, trashed notes and deleted pages excluded,
// withinNote, a pdf asset shared by two notes, snippets and match ranges, rects (ink lines,
// object bounds, pdf boxes merged per line with PageRect.zero skipped, the pdfPageAspect fit),
// the empty unit list keeping its owner, the 2,000-candidate cap (most recent first,
// pagesTruncated), writer validation, searchLibrary.pages, status / rebuild. Public API only.
// The fake store runs it now (test/search/search_contract_fake_test.dart), the real store from
// CORE T33b.
// Web-safe.
import 'dart:async';

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

const String _asset =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void defineSearchContract(FutureOr<NoteStore> Function() open) {
  late NoteStore store;

  setUp(() async => store = await open());
  tearDown(() => store.close());

  /// A note whose pages hold one text box each with [bodies].
  Future<(Note, List<PageId>)> textNote(
    String title,
    List<String> bodies,
  ) async {
    final note = await store.library.createNote(
      title: title,
      pages: [for (final _ in bodies) PageDraft.blankA4],
    );
    final pages = [for (final p in await store.content.pagesOf(note.id)) p.id];
    final session = await store.openSession(note.id);
    for (final (i, body) in bodies.indexed) {
      await session.openPage(pages[i]);
      await session
          .execute(
            AddObjects(
              pageId: pages[i],
              objects: [
                TextBoxObject(
                  id: store.ids.newId(),
                  pageId: pages[i],
                  frame: ElementFrame(PageRect(10, 10.0 + i, 300, 50)),
                  text: body,
                  style: const TextBoxStyle(),
                  createdAt: 1,
                ),
              ],
            ),
          )
          .persisted;
    }
    await session.close();
    return (note, pages);
  }

  /// A note with one page showing PDF page [index] of [asset].
  Future<(Note, PageId)> pdfNote(
    String title, {
    int index = 0,
    String asset = _asset,
  }) async {
    final note = await store.library.createNote(
      title: title,
      pages: [
        PageDraft(
          size: const PageSize(600, 800),
          background: PdfBackground(assetId: asset, pdfPageIndex: index),
        ),
      ],
    );
    return (note, (await store.content.pagesOf(note.id)).single.id);
  }

  Future<Set<int>> docsFor(String query, List<PageId> pages) async => {
    for (final h in await store.search.searchPages(query))
      if (pages.contains(h.pageId)) pages.indexOf(h.pageId) + 1,
  };

  test('the 6.10.2 table on text boxes', () async {
    final (_, pages) = await textNote('docs', const [
      '오늘 회의록을 정리했다 meeting notes',
      '라플라스 방정식 Laplace equation',
      '확률과 통계',
      '정식 계약서',
      '영어 단어 암기',
    ]);
    final table = <String, Set<int>>{
      '회의': {1},
      '회의록': {1},
      '의록': {1},
      '정식': {2, 4},
      '정': {1, 2, 4},
      '록': {1},
      'meet': {1},
      'LAPLACE': {2},
      '확률 통계': {3},
      '단어 암기': {5},
      '방정 정식': {2},
      'eeting': {},
      '': {},
      '   ': {},
      '!!!': {},
    };
    for (final MapEntry(key: q, value: expected) in table.entries) {
      expect(await docsFor(q, pages), expected, reason: q);
    }
  });

  test('a hit: source, snippet, match range, object bounds, score order', () async {
    final (note, pages) = await textNote('hit', const ['오늘 Meeting 회의']);
    final hit = (await store.search.searchPages('meeting')).single;
    expect(hit.noteId, note.id);
    expect(hit.pageId, pages.single);
    expect(hit.source, SearchSource.text);
    expect(hit.snippet, '오늘 Meeting 회의');
    final (start, end) = hit.matchRange;
    expect(hit.snippet.substring(start, end), 'Meeting');
    expect(hit.rects, hasLength(1));
    expect(hit.rects.single.left, lessThanOrEqualTo(10));
    expect(hit.score, greaterThan(0));
    // A text unit outranks a pdf unit with the same match (weights 1.0 / 0.8).
    final (_, pdfPage) = await pdfNote('pdf');
    await store.search.replaceUnits(SearchSource.pdf, '$_asset#0', const [
      SearchUnitDraft(body: '오늘 Meeting 회의'),
    ], sourceRev: '$_asset:1');
    final hits = await store.search.searchPages('meeting');
    expect(hits.map((h) => h.pageId), [pages.single, pdfPage]);
    expect(hits.last.source, SearchSource.pdf);
  });

  test('ink: line units; rects are the matched lines', () async {
    final note = await store.library.createNote(title: 'ink');
    final page = (await store.content.pagesOf(note.id)).single.id;
    await store.handwriting.put(
      HandwritingText(
        noteId: note.id,
        pageId: page,
        engineId: 'fake/1:ko',
        sourceRev: '0000000000000000',
        lines: const [
          HandwritingLine(
            text: '회의록 첫 줄',
            rect: PageRect(10, 10, 200, 30),
            strokeIds: ['s1'],
          ),
          HandwritingLine(
            text: '',
            rect: PageRect(10, 40, 200, 60),
            strokeIds: ['s2'],
          ),
          HandwritingLine(
            text: '둘째 회의',
            rect: PageRect(10, 70, 200, 90),
            strokeIds: ['s3'],
          ),
          HandwritingLine(
            text: '상관없음',
            rect: PageRect(10, 100, 200, 120),
            strokeIds: ['s4'],
          ),
        ],
        createdAt: 1,
      ),
    );
    final hit = (await store.search.searchPages('회의')).single;
    expect(hit.source, SearchSource.ink);
    expect(hit.rects, const [
      PageRect(10, 10, 200, 30),
      PageRect(10, 70, 200, 90),
    ]);
    await store.handwriting.removeForPage(page);
    expect(await store.search.searchPages('회의'), isEmpty);
  });

  test(
    'pdf: boxes merged per line, PageRect.zero skipped, the aspect fit',
    () async {
      final (_, page) = await pdfNote('pdf');
      const body = 'ab cd';
      await store.search.replaceUnits(SearchSource.pdf, '$_asset#0', [
        SearchUnitDraft(
          body: body,
          rects: const [
            PageRect(0.1, 0.1, 0.2, 0.2),
            PageRect(0.2, 0.1, 0.3, 0.2),
            PageRect.zero,
            PageRect(0.4, 0.3, 0.5, 0.4),
            PageRect(0.5, 0.3, 0.6, 0.4),
          ],
          pdfPageAspect:
              2, // a landscape PDF page: 600 × 300 centered on 600 × 800
        ),
      ], sourceRev: '$_asset:1');
      final ab = (await store.search.searchPages('ab')).single;
      expect(ab.pageId, page);
      expect(ab.source, SearchSource.pdf);
      expect(ab.rects, hasLength(1));
      expect(ab.rects.single.left, closeTo(60, 0.02));
      expect(ab.rects.single.top, closeTo(250 + 30, 0.02));
      expect(ab.rects.single.right, closeTo(180, 0.02));
      expect(ab.rects.single.bottom, closeTo(250 + 60, 0.02));
      final cd = (await store.search.searchPages('cd')).single;
      expect(cd.rects, hasLength(1));
      // No rects: a hit without boxes.
      await store.search.replaceUnits(SearchSource.pdf, '$_asset#0', const [
        SearchUnitDraft(body: 'plain text'),
      ], sourceRev: '$_asset:1');
      expect((await store.search.searchPages('plain')).single.rects, isEmpty);
    },
  );

  test('a pdf asset shared by two notes: one hit per note page', () async {
    final (a, pa) = await pdfNote('A');
    final (b, pb) = await pdfNote('B');
    await store.search.replaceUnits(SearchSource.pdf, '$_asset#0', const [
      SearchUnitDraft(body: '공유 자료'),
    ], sourceRev: '$_asset:1');
    final hits = await store.search.searchPages('공유');
    expect(hits.map((h) => h.pageId).toSet(), {pa, pb});
    expect(
      (await store.search.searchPages(
        '공유',
        withinNote: a.id,
      )).map((h) => h.pageId),
      [pa],
    );
    expect(
      (await store.search.searchPages(
        '공유',
        withinNote: b.id,
      )).map((h) => h.pageId),
      [pb],
    );
  });

  test(
    'trashed notes and deleted pages are excluded (and come back on restore)',
    () async {
      final (note, pages) = await textNote('trash', const ['휴지통 시험', '삭제 시험']);
      expect(await store.search.searchPages('시험'), hasLength(2));
      final session = await store.openSession(note.id);
      await session.execute(DeletePages(pageIds: [pages[1]])).persisted;
      await session.close();
      expect((await store.search.searchPages('시험')).map((h) => h.pageId), [
        pages[0],
      ]);
      await store.library.trashItems([NoteRef(note.id)]);
      expect(await store.search.searchPages('시험'), isEmpty);
      await store.trash.restore([NoteRef(note.id)]);
      expect((await store.search.searchPages('시험')).map((h) => h.pageId), [
        pages[0],
      ]);
    },
  );

  test('the empty unit list keeps the owner with its sourceRev', () async {
    final key = '$_asset#3';
    expect(await store.search.sourceRevOf(SearchSource.pdf, key), isNull);
    await store.search.replaceUnits(
      SearchSource.pdf,
      key,
      const [],
      sourceRev: 'r1:x2',
    );
    expect(await store.search.sourceRevOf(SearchSource.pdf, key), 'r1:x2');
    expect(await store.search.sourceRevs(SearchSource.pdf), {key: 'r1:x2'});
    await store.search.removeOwner(SearchSource.pdf, key);
    expect(await store.search.sourceRevOf(SearchSource.pdf, key), isNull);
    expect(await store.search.sourceRevs(SearchSource.pdf), isEmpty);
  });

  test('2,000 candidates, most recent first; pagesTruncated', () async {
    final (_, old) = await pdfNote('old', index: 0);
    final (_, recent) = await pdfNote('recent', index: 1);
    await store.search.replaceUnits(SearchSource.pdf, '$_asset#0', const [
      SearchUnitDraft(body: '공통 낱말'),
    ], sourceRev: 'r');
    await store.search.replaceUnits(SearchSource.pdf, '$_asset#1', [
      for (var i = 0; i < 1999; i++) SearchUnitDraft(body: '공통 낱말 $i'),
    ], sourceRev: 'r');
    var result = await store.library.searchLibrary('공통');
    expect(result.pages.map((h) => h.pageId).toSet(), {old, recent});
    expect(result.pagesTruncated, isFalse);
    // One more recent unit: the oldest candidate falls past the cap.
    await store.search.replaceUnits(SearchSource.pdf, '$_asset#1', [
      for (var i = 0; i < 2000; i++) SearchUnitDraft(body: '공통 낱말 $i'),
    ], sourceRev: 'r');
    result = await store.library.searchLibrary('공통');
    expect(result.pages.map((h) => h.pageId), [recent]);
    expect(result.pagesTruncated, isTrue);
  });

  test('more pages than the limit: pagesTruncated', () async {
    await textNote('many', [for (var i = 0; i < 3; i++) '반복 $i']);
    expect(await store.search.searchPages('반복', limit: 2), hasLength(2));
    final r = await store.library.searchLibrary('반복');
    expect(r.pages, hasLength(3));
    expect(r.pagesTruncated, isFalse);
  });

  test(
    'SearchIndexWriter validation: ArgumentError, nothing changes',
    () async {
      final s = store.search;
      final ok = '$_asset#0';
      final bad = <String, Future<void> Function()>{
        'ink': () =>
            s.replaceUnits(SearchSource.ink, ok, const [], sourceRev: 'r'),
        'owner key': () =>
            s.replaceUnits(SearchSource.pdf, 'x#0', const [], sourceRev: 'r'),
        'rects length': () => s.replaceUnits(SearchSource.pdf, ok, const [
          SearchUnitDraft(body: 'abc', rects: [PageRect.zero]),
        ], sourceRev: 'r'),
        'fraction': () => s.replaceUnits(SearchSource.pdf, ok, const [
          SearchUnitDraft(body: 'a', rects: [PageRect(0, 0, 1.5, 1)]),
        ], sourceRev: 'r'),
        'aspect': () => s.replaceUnits(SearchSource.pdf, ok, const [
          SearchUnitDraft(body: 'a', pdfPageAspect: 0),
        ], sourceRev: 'r'),
        'empty rev': () =>
            s.replaceUnits(SearchSource.pdf, ok, const [], sourceRev: ''),
        'long rev': () => s.replaceUnits(
          SearchSource.pdf,
          ok,
          const [],
          sourceRev: 'r' * 201,
        ),
        'remove ink': () => s.removeOwner(SearchSource.ink, ok),
      };
      for (final MapEntry(key: name, value: call) in bad.entries) {
        await expectLater(call(), throwsArgumentError, reason: name);
      }
      expect(await s.sourceRevs(SearchSource.pdf), isEmpty);
    },
  );

  test('searchLibrary: folders and notes as before, pages added', () async {
    final (note, pages) = await textNote('강의 노트', const ['강의 내용 요약']);
    final r = await store.library.searchLibrary('강의');
    expect(r.notes.map((n) => n.id), [note.id]);
    expect(r.pages.map((h) => h.pageId), pages);
    expect((await store.library.searchLibrary('')).pages, isEmpty);
  });

  test(
    'status and rebuild: text rebuilt from the objects, pdf dropped',
    () async {
      final statuses = <SearchIndexStatus>[];
      final sub = store.search.status.listen(statuses.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);
      expect(statuses.first, const SearchIndexStatus());
      await textNote('rebuild', const ['다시 만들기']);
      await pdfNote('pdf');
      await store.search.replaceUnits(SearchSource.pdf, '$_asset#0', const [
        SearchUnitDraft(body: '다시 피디에프'),
      ], sourceRev: 'r');
      await store.search.rebuild();
      await Future<void>.delayed(Duration.zero);
      expect(statuses.any((s) => s.rebuilding), isTrue);
      expect(statuses.last.rebuilding, isFalse);
      expect(statuses.last.lastRebuildAt, isNotNull);
      final hits = await store.search.searchPages('다시');
      expect(hits.map((h) => h.source), [SearchSource.text]);
      expect(await store.search.sourceRevs(SearchSource.pdf), isEmpty);
    },
  );
}
