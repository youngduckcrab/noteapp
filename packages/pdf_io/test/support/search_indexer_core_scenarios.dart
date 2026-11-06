// V10's PDF part (m5-7/06-pdf 8.3 4-a; 8.2 T29): the app's real wiring (support/real_wiring.dart)
// imports a PDF, pdfSearchIndexerProvider indexes it into the store's search index, and
// SearchIndex.searchPages finds the same places as the 1차 PdfTextService.searchNote — the hit
// rects (note page pt) within ±0.5 pt, on an imported page (note page = PDF page size), on a
// note page of another size showing that PDF page (pdfPageAspect → PdfPageFit contain), and for
// a word of glyphs of mixed heights: the boxes of one line share a vertical band (unit_builder
// _lineBands — T29), so it is one rect, as in the 1차 merge. A query of several words gets the
// rects of its first word (CORE's AND of words — 02-core 6.10.4). (The plan's 'a match with
// PageRect.zero boxes → one rect per line' cannot be reached end to end — no CORE match run
// holds white space, and PDFium joins a hyphenated line end with U+0002 and no line break; the
// band rule is checked in unit/unit_builder_test.dart — progress log, T29.)
//
// Two callers: integration/search_indexer_core_test.dart (CORE's REAL store — openTestNoteStore;
// until CORE T33a/T33b its search writes throw UnimplementedError, so the scenarios skip
// themselves at run time — T39/T40 rule) and pdfium/search_indexer_fake_core_test.dart (CORE's
// fake store — memory search index with the same judgement, CP-14 — every run).
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

import 'real_wiring.dart';

/// Why the real-store scenarios skip themselves.
const String v10WaitsForCore =
    'CORE T33a/T33b milestone (the real search index) — judged at integration step 4-a';

/// Page 1: 400 × 300 pt, 'HHHH' (x 100, baseline 80, size 40). Page 2: A4 with 'Second
/// lecture' (glyphs of mixed heights on one line).
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
          ))
        .build();

/// Whether [store]'s search index takes pdf units (false: CORE T33a not there yet).
Future<bool> searchIndexWritable(core.NoteStore store) async {
  try {
    await store.search.replaceUnits(
      core.SearchSource.pdf,
      'probe#0',
      const [],
      sourceRev: 'probe',
    );
    await store.search.removeOwner(core.SearchSource.pdf, 'probe#0');
    return true;
  } on UnimplementedError {
    return false;
  }
}

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

/// The v2 hit of [pageId] for [query] has the rects of the 1차 hit [v1] (±0.5 pt each).
Future<void> expectSameRects(
  core.NoteStore store,
  String query,
  PdfSearchHit v1, {
  int? lines,
}) async {
  final hits = await store.search.searchPages(query);
  final v2 = hits.where((h) => h.pageId == v1.pageId).toList();
  expect(v2, hasLength(1), reason: '"$query" on ${v1.pageId}: $hits');
  expect(v2.single.source, core.SearchSource.pdf);
  final got = [for (final r in v2.single.rects) _rect(r)];
  debugPrint('V10 "$query" 1차 ${v1.rects} · v2 $got');
  if (lines != null) expect(v1.rects, hasLength(lines), reason: '1차 "$query"');
  expect(
    got,
    hasLength(v1.rects.length),
    reason: '"$query": 1차 ${v1.rects}, v2 $got',
  );
  for (var i = 0; i < got.length; i++) {
    final a = got[i], b = v1.rects[i];
    for (final (x, y, side) in [
      (a.left, b.left, 'left'),
      (a.top, b.top, 'top'),
      (a.right, b.right, 'right'),
      (a.bottom, b.bottom, 'bottom'),
    ]) {
      expect(
        x,
        closeTo(y, 0.5),
        reason: '"$query" rect $i $side: 1차 $b, v2 $a',
      );
    }
  }
}

/// The V10 PDF scenarios on the store [open] gives; [real]: skip at run time until CORE T33a.
void searchIndexerCoreScenarios(
  Future<core.NoteStore> Function() open, {
  required bool real,
}) {
  late RealWiring app;

  setUp(() async => app = RealWiring(await open()));
  tearDown(() => app.close());

  test(
    'imported PDF → indexed by pdfSearchIndexerProvider → searchPages rects = '
    '1차 searchNote rects (±0.5 pt), also for mixed glyph heights and on a resized page',
    () async {
      if (real && !await searchIndexWritable(app.store)) {
        markTestSkipped(v10WaitsForCore);
        return;
      }
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
      // Several words: CORE's rects are those of the FIRST word's first match (02-core 6.10.4
      // — the AND of words is judged per unit, the snippet and rects follow the first run).
      await expectSameRects(app.store, 'second lecture', second, lines: 1);

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
