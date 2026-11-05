// Search on real PDFium (06-pdf 6.10; 8 T11): DefaultPdfTextService + DefaultPdfDocumentPool
// over PdfrxEngine and FakePdfNoteGateway. The '강의 자료' ToUnicode fixture gives a '강의'
// rect inside the glyph boxes; a page rotated 90° gives displayed-page coordinates; a
// 50 × 50 pt page on a 72 × 72 note page (s ≠ 1, P-1) gives NOTE pt at the glyphs.
@Tags(['pdfium'])
@TestOn('vm')
library;

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

import '../support/pdfium_env.dart';

final class _World {
  final FakePdfNoteGateway gateway = FakePdfNoteGateway();
  late final DefaultPdfDocumentPool pool = DefaultPdfDocumentPool(
    engine: PdfrxEngine.shared(),
    gateway: gateway,
  );
  late final DefaultPdfTextService service = DefaultPdfTextService(
    pool: pool,
    gateway: gateway,
  );

  /// Stores [pdf] and makes a note of its page 0 at [size].
  Future<core.Note> note(Uint8List pdf, core.PageSize size) async {
    final asset = await gateway.putPdf(pdf, fileName: 'fixture.pdf');
    return gateway.createNote(
      title: 'fixture',
      pages: [
        core.PageDraft(
          size: size,
          background: core.PdfBackground(assetId: asset.id, pdfPageIndex: 0),
        ),
      ],
    );
  }

  Future<List<PdfSearchHit>> search(core.NoteId noteId, String query) async {
    final events = await service.searchNote(noteId, query).toList();
    expect(events.last.isDone, isTrue);
    return [for (final e in events) ...e.newHits];
  }

  Future<void> dispose() => pool.dispose();
}

void main() {
  setUpAll(() async {
    await initPdfiumForTests();
    await PdfrxEngine.shared().ensureInitialized();
  });

  test("'강의' in the ToUnicode fixture: the rect lies on the glyphs", () async {
    final w = _World();
    addTearDown(w.dispose);
    final note = await w.note(
      (PdfFixtureBuilder()..addPage(
            const PdfFixturePage(
              texts: [PdfFixtureText('강의 자료', x: 72, y: 100, mapped: true)],
            ),
          ))
          .build(),
      core.PageSize.a4Portrait,
    );
    final hit = (await w.search(note.id, '강의')).single;
    expect(hit.notePageNumber, 1);
    expect(hit.snippet.substring(hit.matchStart, hit.matchStart + 2), '강의');
    final rect = hit.rects.single;
    expect(rect.left, closeTo(72, 6));
    expect(rect.bottom, closeTo(100, 4));
    expect(rect.height, inInclusiveRange(5, 20));

    // Inside the boxes of the text's characters (displayed pt = note pt here).
    final text = await w.service.pageText(hit.assetId, 0);
    final at = text.text.indexOf('강의');
    final glyphs = text.charRects[at].expandToInclude(text.charRects[at + 1]);
    expect(rect.left, closeTo(glyphs.left, 0.01));
    expect(rect.right, closeTo(glyphs.right, 0.01));
    expect(rect.top, closeTo(glyphs.top, 0.01));
    expect(rect.bottom, closeTo(glyphs.bottom, 0.01));

    // The same query typed in conjoining jamo finds it too.
    expect(await w.search(note.id, '강의'), [hit]);
  });

  for (final rotate in [0, 90]) {
    test('displayed-page coordinates on a page rotated $rotate°', () async {
      final w = _World();
      addTearDown(w.dispose);
      // 400 × 300 pt media box; rotated 90° it is displayed 300 × 400.
      final displayed = rotate == 90
          ? const core.PageSize(300, 400)
          : const core.PageSize(400, 300);
      final note = await w.note(
        (PdfFixtureBuilder()..addPage(
              PdfFixturePage(
                width: 400,
                height: 300,
                rotate: rotate,
                texts: const [PdfFixtureText('HHHH', x: 100, y: 80, size: 40)],
              ),
            ))
            .build(),
        displayed,
      );
      final rect = (await w.search(note.id, 'hhhh')).single.rects.single;
      // 'HHHH' at displayed (100, 80), size 40: x 100..~210, cap top ≈ 80 − 29.
      expect(rect.left, closeTo(100, 6));
      expect(rect.bottom, closeTo(80, 3));
      expect(rect.top, inInclusiveRange(45, 60));
      expect(rect.right, inInclusiveRange(180, 220));
    });
  }

  test('50 × 50 pt page on a 72 × 72 note page: rects in note pt', () async {
    final w = _World();
    addTearDown(w.dispose);
    const pdfSize = Size(50, 50);
    final noteSize = PdfPageSizePolicy.toNotePageSize(50, 50);
    expect(noteSize, const core.PageSize(72, 72));
    final note = await w.note(
      (PdfFixtureBuilder()..addPage(
            const PdfFixturePage(
              width: 50,
              height: 50,
              texts: [PdfFixtureText('HI', x: 10, y: 30, size: 12)],
            ),
          ))
          .build(),
      noteSize,
    );
    final hit = (await w.search(note.id, 'hi')).single;
    final rect = hit.rects.single;
    // Glyphs at displayed x 10.., baseline 30 → ×1.44 in the note: x 14.4.., baseline 43.2.
    expect(rect.left, closeTo(14.4, 3));
    expect(rect.bottom, closeTo(43.2, 3));

    final text = await w.service.pageText(hit.assetId, 0);
    final at = text.text.indexOf('HI');
    final glyphs = text.charRects[at].expandToInclude(text.charRects[at + 1]);
    final fit = PdfPageFit(
      notePageSize: const Size(72, 72),
      pdfPageSize: pdfSize,
    );
    final expected = fit.pdfToNote(glyphs);
    expect(rect.left, closeTo(expected.left, 1e-6));
    expect(rect.top, closeTo(expected.top, 1e-6));
    expect(rect.width, closeTo(expected.width, 1e-6));
    expect(rect.height, closeTo(expected.height, 1e-6));
  });
}
