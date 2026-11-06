// PdfSearchIndexer on real PDFium (m5-7/06-pdf 6.4.1–6.4.2; 8.2 T27): CORE's fake store
// (memory search index) + DefaultPdfDocumentPool over PdfrxEngine. A 1차 fixture PDF (a mapped
// Hangul page and a 90°-rotated Latin page): every page's unit body = 1차
// PdfTextService.pageText text, one rect per code unit (fractions of the displayed page),
// pdfPageAspect = displayed width / height, '#0' written last, and searchPages finds the text on
// the note's PDF page.
@Tags(['pdfium'])
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/search_index/indexer_gate.dart';
import 'package:pdf_io/src/search_index/pdf_search_indexer.dart';
import 'package:pdf_io/testing.dart';

import '../support/pdfium_env.dart';

/// Records what replaceUnits gets (then the fake store writes it).
final class _Recording implements core.SearchIndex {
  _Recording(this.inner);
  final core.SearchIndex inner;
  final Map<String, List<core.SearchUnitDraft>> written = {};
  final List<String> order = [];

  @override
  Future<void> replaceUnits(
    core.SearchSource source,
    String ownerKey,
    List<core.SearchUnitDraft> units, {
    required String sourceRev,
  }) {
    order.add(ownerKey.substring(ownerKey.indexOf('#')));
    written[ownerKey] = units;
    return inner.replaceUnits(source, ownerKey, units, sourceRev: sourceRev);
  }

  @override
  Stream<core.SearchIndexStatus> get status => inner.status;

  @override
  Future<void> removeOwner(core.SearchSource source, String ownerKey) =>
      inner.removeOwner(source, ownerKey);

  @override
  Future<String?> sourceRevOf(core.SearchSource source, String ownerKey) =>
      inner.sourceRevOf(source, ownerKey);

  @override
  Future<Map<String, String>> sourceRevs(core.SearchSource source) =>
      inner.sourceRevs(source);

  @override
  Future<List<core.PageSearchHit>> searchPages(
    String query, {
    int limit = 100,
    core.NoteId? withinNote,
  }) => inner.searchPages(query, limit: limit, withinNote: withinNote);

  @override
  Future<void> rebuild({Set<core.SearchSource>? sources}) =>
      inner.rebuild(sources: sources);
}

final class _Store implements core.NoteStore {
  _Store(this.inner) : search = _Recording(inner.search);
  final core.NoteStore inner;

  @override
  final _Recording search;

  @override
  core.AssetStore get assets => inner.assets;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await initPdfiumForTests();
    await PdfrxEngine.shared().ensureInitialized();
  });

  test('units = 1차 pageText, one fraction rect per code unit, #0 last; the '
      'note page is found', () async {
    final inner = core_testing.createFakeNoteStore();
    addTearDown(inner.close);
    final store = _Store(inner);
    final gateway = CorePdfNoteGateway(inner);
    final pool = DefaultPdfDocumentPool(
      engine: PdfrxEngine.shared(),
      gateway: gateway,
    );
    addTearDown(pool.dispose);
    final pdf =
        (PdfFixtureBuilder()
              ..addPage(
                const PdfFixturePage(
                  texts: [PdfFixtureText('강의 자료', x: 72, y: 100, mapped: true)],
                ),
              )
              ..addPage(
                const PdfFixturePage(
                  width: 400,
                  height: 300,
                  rotate: 90,
                  texts: [PdfFixtureText('Hello index', x: 40, y: 80)],
                ),
              ))
            .build();
    final asset = await gateway.putPdf(pdf, fileName: 'fixture.pdf');
    final note = await inner.library.createNote(
      title: 'fixture',
      pages: [
        for (var i = 0; i < 2; i++)
          core.PageDraft(
            size: core.PageSize.a4Portrait,
            background: core.PdfBackground(assetId: asset.id, pdfPageIndex: i),
          ),
      ],
    );

    final indexer = createPdfSearchIndexer(
      store,
      pool: pool,
      gate: const AlwaysOpenIndexerGate(),
    )..start();
    addTearDown(indexer.dispose);
    for (var i = 0; i < 400 && store.search.order.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await pumpEventQueue();
    expect(store.search.order, ['#1', '#0']);

    final texts = DefaultPdfTextService(pool: pool, gateway: gateway);
    final lease = await pool.acquire(asset.id);
    addTearDown(lease.release);
    for (var i = 0; i < 2; i++) {
      final page = await texts.pageText(asset.id, i);
      final info = lease.document.info.pages[i];
      final unit = store.search.written['${asset.id}#$i']!.single;
      expect(unit.body, page.text, reason: 'page $i body = 1차 pageText');
      expect(unit.rects, hasLength(unit.body.length));
      expect(unit.pdfPageAspect, closeTo(info.width / info.height, 1e-9));
      final known = [
        for (final r in unit.rects)
          if (r != core.PageRect.zero) r,
      ];
      expect(known, isNotEmpty);
      for (final r in known) {
        for (final f in [r.left, r.top, r.right, r.bottom]) {
          expect(f, inInclusiveRange(0, 1));
        }
      }
    }
    // the rotated page is displayed 300 × 400
    expect(
      store.search.written['${asset.id}#1']!.single.pdfPageAspect,
      closeTo(300 / 400, 1e-9),
    );

    final hits = await inner.search.searchPages('hello index');
    expect(hits.single.noteId, note.id);
    expect(hits.single.rects, isNotEmpty);
    final korean = await inner.search.searchPages('강의');
    expect(korean.single.source, core.SearchSource.pdf);
  });
}
