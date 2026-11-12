// InkEngineVectorizer.planPage over INK's REAL vector export v2 (m5-7/06-pdf 6.2.1, 5.2; 8.2 T24
// ③ — PDF-M2): exportPage → layersFromInk → planFromLayers on a page with an image object, a
// rectangle shape, a dashed stroke, a text box, a formula and tape. Integration stage only
// (`ws test --run-skipped -t integration --package pdf_io`, 8.3 4-a); INK T42 (03-ink 8.5 — 'T42
// = PDF 객체 벡터화 시험 전환') is merged, so the static skip of the concurrent stage is gone.
@Tags(['integration'])
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';

const _asset =
    'e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5';

core.Stroke _stroke(String id, core.PenTool tool, {required int createdAt}) =>
    core.Stroke(
      id: id,
      pageId: 'page-1',
      style: core.StrokeStyle.defaultsFor(tool),
      points: core.StrokePoints.fromList([
        for (var i = 0; i <= 20; i++) core.StrokePoint(80 + 15.0 * i, 700),
      ]),
      createdAt: createdAt,
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ink.InkFonts.ensureLoaded(); // text lines are empty without NoteSans (CP-INK-9)
  });

  test('objects → image refs, shape and dash pieces, text box / formula refs, tape cover', () {
    const page = core.Page(
      id: 'page-1',
      noteId: 'note-1',
      sortKey: 'a',
      size: core.PageSize.a4Portrait,
      background: core.BlankBackground(),
      createdAt: 0,
      updatedAt: 0,
    );
    final image = core_testing.PageObjectFixtures.image(
      pageId: 'page-1',
      assetId: _asset,
      createdAt: 1,
      id: 'image-1',
    );
    final shape = core_testing.PageObjectFixtures.shape(
      pageId: 'page-1',
      createdAt: 2,
      id: 'shape-1',
    );
    final dashed = _stroke('dashed-1', core.PenTool.dashed, createdAt: 3);
    final text = core_testing.PageObjectFixtures.textBox(
      pageId: 'page-1',
      text: '한글 텍스트 상자 hello',
      createdAt: 4,
      id: 'text-1',
    );
    final formula = core_testing.PageObjectFixtures.math(
      pageId: 'page-1',
      createdAt: 5,
      id: 'math-1',
    );
    final tape = _stroke('tape-1', core.PenTool.tape, createdAt: 6);
    final unknown = core_testing.PageObjectFixtures.unknown(
      pageId: 'page-1',
      id: 'unknown-1',
    );
    final content = core.PageContent(
      page: page,
      strokes: [dashed, tape],
      objects: [image, shape, text, formula, unknown],
      revision: 0,
    );

    final plan = const InkEngineVectorizer().planPage(
      content,
      includeInk: true,
      includeTemplate: true,
    );
    final items = plan.items;

    // L-2 underlay: the image object at its frame.
    expect(
      items.first,
      PdfAssetImageRef.object(assetId: _asset, frame: image.frame),
    );
    // L-4 ink: the shape's pieces, then the dash segments (z order), as fills.
    final fills = items.whereType<PdfFillItem>().toList();
    expect(
      fills.length,
      greaterThanOrEqualTo(3),
    ); // ≥ 1 shape piece, ≥ 2 dashes
    // L-5 annotations: the text box (laid out) then the formula, after every ink fill but
    // the tape.
    final textIndex = items.indexWhere((i) => i is PdfTextBoxRef);
    final mathIndex = items.indexWhere((i) => i is PdfMathRef);
    expect(textIndex, greaterThan(0));
    expect(mathIndex, textIndex + 1);
    final textRef = items[textIndex] as PdfTextBoxRef;
    expect(textRef.object, text);
    expect(textRef.lines, isNotEmpty);
    expect(
      textRef.lines.map((l) => l.text).join().replaceAll(RegExp(r'\s'), ''),
      text.text.replaceAll(' ', ''),
    );
    expect((items[mathIndex] as PdfMathRef).object, formula);
    // L-6 cover: the tape last, one solid fill.
    final last = items.last;
    expect(last, isA<PdfFillItem>());
    expect((last as PdfFillItem).opacity, 1);
    expect(items.sublist(1, textIndex), everyElement(isA<PdfFillItem>()));
    expect(items.sublist(mathIndex + 1), [same(last)]);
    // Unknown objects are never exported (CP-INK-10): 1 image + fills + 2 refs.
    expect(items.whereType<PdfAssetImageRef>(), hasLength(1));
    expect(items, hasLength(1 + fills.length + 2));

    // includeInk false: nothing on a white blank page.
    expect(
      const InkEngineVectorizer()
          .planPage(content, includeInk: false, includeTemplate: true)
          .isEmpty,
      isTrue,
    );
  });
}
