// V10's PDF part (m5-7/06-pdf 8.3 4-a; 8.2 T29): the app's real wiring (support/real_wiring.dart)
// imports a PDF, pdfSearchIndexerProvider indexes it into the store's search index, and
// SearchIndex.searchPages finds the same places as the 1차 PdfTextService.searchNote — the hit
// rects (note page pt) within ±0.5 pt, on an imported page (note page = PDF page size), on a
// note page of another size showing that PDF page (pdfPageAspect → PdfPageFit contain), and for
// a word of glyphs of mixed heights: the boxes of one line share a vertical band (unit_builder
// _lineBands — T29), so it is one rect, as in the 1차 merge. A query of several words (contract
// v2.6 C26-03) gets, for each query word, the rects of that word's first match, in query order:
// 'second lecture' = the 1차 'Second' rect then the 1차 'lecture' rect, and together they cover
// the 1차 phrase rect. A word hyphenated at a line end ('IN-' / 'DEXING' — C26-04) is found
// by both searches with one rect on each line. (The plan's 'a match with PageRect.zero boxes → one rect per line' cannot
// be reached end to end — no CORE match run holds white space; the band rule is checked in
// unit/unit_builder_test.dart — progress log, T29.)
//
// Two callers: integration/search_indexer_core_test.dart (CORE's REAL store — openTestNoteStore)
// and pdfium/search_indexer_fake_core_test.dart (CORE's fake store — memory search index with the
// same judgement, CP-14 — every run).
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

import 'pdfium_text_cases.dart' show hyphenatedWordPage;
import 'real_wiring.dart';

/// Page 1: 400 × 300 pt, 'HHHH' (x 100, baseline 80, size 40). Page 2: A4 with 'Second
/// lecture' (glyphs of mixed heights on one line). Page 3: 'IN-' at a line end, 'DEXING' on the
/// next line (PDFium joins them with U+0002 — the adapter hands on U+00AD, C26-04).
Uint8List v10Lecture() =>
    (PdfFixtureBuilder()
          ..addPage(
            const PdfFixturePage(
              width: 400,
              height: 300,
              texts: [PdfFixtureText('HHHH', x: 100, y: 80, size: 40)],
            ),
          )
          ..addPage(
            const PdfFixturePage(
              texts: [PdfFixtureText('Second lecture', x: 72, y: 120)],
            ),
          )
          ..addPage(hyphenatedWordPage))
        .build();

/// Waits (real time, bounded — nothing is asserted about the time) until [asset]'s '#0' owner
/// has the indexer's sourceRev: the '#0 last' completion mark (6.4.2).
Future<void> waitIndexed(core.NoteStore store, core.AssetId asset) async {
  for (var i = 0; i < 600; i++) {
    final rev = await store.search.sourceRevOf(
      core.SearchSource.pdf,
      '$asset#0',
    );
    if (rev != null && rev.startsWith('$asset:')) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('the PDF search indexer did not finish $asset within 30 s');
}

ui.Rect _rect(core.PageRect r) =>
    ui.Rect.fromLTRB(r.left, r.top, r.right, r.bottom);

/// The v2 hit of [v1]'s page for [query] has the rects of the 1차 hit [v1] (±0.5 pt each).
Future<void> expectSameRects(
  core.NoteStore store,
  String query,
  PdfSearchHit v1, {
  int? lines,
}) async {
  if (lines != null) expect(v1.rects, hasLength(lines), reason: '1차 "$query"');
  await expectV2Rects(store, query, v1.pageId, v1.rects);
}

/// The v2 hit of [pageId] for [query] has the rects [expected] (note page pt, ±0.5 pt each, in
/// order); returns them.
Future<List<ui.Rect>> expectV2Rects(
  core.NoteStore store,
  String query,
  String pageId,
  List<ui.Rect> expected,
) async {
  final hits = await store.search.searchPages(query);
  final v2 = hits.where((h) => h.pageId == pageId).toList();
  expect(v2, hasLength(1), reason: '"$query" on $pageId: $hits');
  expect(v2.single.source, core.SearchSource.pdf);
  final got = [for (final r in v2.single.rects) _rect(r)];
  debugPrint('V10 "$query" expected $expected · v2 $got');
  expect(
    got,
    hasLength(expected.length),
    reason: '"$query": expected $expected, v2 $got',
  );
  for (var i = 0; i < got.length; i++) {
    _expectRectClose(got[i], expected[i], '"$query" rect $i');
  }
  return got;
}

void _expectRectClose(ui.Rect a, ui.Rect b, String what) {
  for (final (x, y, side) in [
    (a.left, b.left, 'left'),
    (a.top, b.top, 'top'),
    (a.right, b.right, 'right'),
    (a.bottom, b.bottom, 'bottom'),
  ]) {
    expect(x, closeTo(y, 0.5), reason: '$what $side: expected $b, got $a');
  }
}

/// The V10 PDF scenarios on the store [open] gives ([real]: CORE's real store — only the
/// description says so; both variants assert the same).
void searchIndexerCoreScenarios(
  Future<core.NoteStore> Function() open, {
  required bool real,
}) {
  late RealWiring app;

  setUp(() async => app = RealWiring(await open()));
  tearDown(() => app.close());

  test(
    'imported PDF → indexed by pdfSearchIndexerProvider → searchPages rects = '
    '1차 searchNote rects (±0.5 pt), also for mixed glyph heights, several words (C26-03) '
    'and on a resized page${real ? ' — real store' : ''}',
    () async {
      final imported = await app.import(
        v10Lecture(),
        const PdfImportAsNewNote(),
      );
      final pages = await app.store.content.pagesOf(imported.noteId);
      // A note page of another size showing PDF page 1 (400 × 300 on A4 — contain, centred).
      final resized = await app
          .read(pdfNoteGatewayProvider)
          .createNote(
            title: 'resized',
            pages: [
              core.PageDraft(
                size: core.PageSize.a4Portrait,
                background: core.PdfBackground(
                  assetId: imported.assetId,
                  pdfPageIndex: 0,
                ),
              ),
            ],
          );
      final resizedPage = (await app.store.content.pagesOf(resized.id)).single;

      app.read(pdfSearchIndexerProvider).start();
      await waitIndexed(app.store, imported.assetId);

      final hhhh = (await app.search(imported.noteId, 'HHHH')).single;
      expect(hhhh.pageId, pages[0].id);
      await expectSameRects(app.store, 'HHHH', hhhh, lines: 1);
      // One word of a line with glyphs of mixed heights ('S', 'd' above 'e', 'c', 'o', 'n').
      final second = (await app.search(imported.noteId, 'Second')).single;
      expect(second.pageId, pages[1].id);
      await expectSameRects(app.store, 'Second', second, lines: 1);
      // Several words (contract v2.6 C26-03): for each query word the rects of its first match,
      // in query order — the 1차 'Second' rect, then the 1차 'lecture' rect; together they cover
      // the 1차 phrase hit (one rect from 'S' to the last 'e').
      final lecture = (await app.search(imported.noteId, 'lecture')).single;
      expect(lecture.pageId, pages[1].id);
      expect(lecture.rects, hasLength(1));
      final words = await expectV2Rects(
        app.store,
        'second lecture',
        pages[1].id,
        [...second.rects, ...lecture.rects],
      );
      final phrase = (await app.search(
        imported.noteId,
        'second lecture',
      )).single;
      expect(phrase.rects, hasLength(1), reason: '1차 phrase hit');
      _expectRectClose(
        words.reduce((a, b) => a.expandToInclude(b)),
        phrase.rects.single,
        '"second lecture" v2 rects together vs the 1차 phrase rect',
      );
      // The word order of the query decides the order of the rects (C26-03 — query order).
      await expectV2Rects(app.store, 'lecture second', pages[1].id, [
        ...lecture.rects,
        ...second.rects,
      ]);

      // A word hyphenated at a line end (C26-04): found whole by both searches, one rect on
      // each line, the same rects.
      final indexing = (await app.search(imported.noteId, 'indexing')).single;
      expect(indexing.pageId, pages[2].id);
      await expectSameRects(app.store, 'indexing', indexing, lines: 2);

      final onResized = (await app.search(resized.id, 'HHHH')).single;
      expect(onResized.pageId, resizedPage.id);
      expect(
        onResized.rects.single.left,
        isNot(closeTo(hhhh.rects.single.left, 0.5)),
        reason: 'the resized page places the PDF page differently',
      );
      await expectSameRects(app.store, 'HHHH', onResized, lines: 1);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
