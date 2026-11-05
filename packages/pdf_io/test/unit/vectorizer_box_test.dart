// BoxInkVectorizer (06-pdf 4.14; 8 T12) — the INK-free vectorizer of export tests (T15):
// every live stroke → a filled rect of its bounds in its color and opacity, in z-order;
// paper fill underlay on non-white blank / template pages; nothing on PDF pages.
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

core.Page _page(core.PageBackground background) => core.Page(
  id: 'page-1',
  noteId: 'note-1',
  sortKey: 'a',
  size: const core.PageSize(300, 200),
  background: background,
  createdAt: 0,
  updatedAt: 0,
);

core.Stroke _stroke(
  String id, {
  required int createdAt,
  core.PenTool tool = core.PenTool.ballpoint,
  List<(double, double)> points = const [(10, 10), (50, 30)],
  int? deletedAt,
}) => core.Stroke(
  id: id,
  pageId: 'page-1',
  style: core.StrokeStyle.defaultsFor(tool),
  points: core.StrokePoints.fromList([
    for (final (x, y) in points) core.StrokePoint(x, y),
  ]),
  createdAt: createdAt,
  deletedAt: deletedAt,
);

void main() {
  const box = BoxInkVectorizer();
  const blank = core.BlankBackground();

  test('each live stroke → its bounds rect, color, opacity, in z-order', () {
    final pen = _stroke('b', createdAt: 2);
    final marker = _stroke(
      'a',
      createdAt: 1,
      tool: core.PenTool.highlighter,
      points: const [(100, 100), (200, 120)],
    );
    final gone = _stroke('c', createdAt: 3, deletedAt: 9);
    final v = box.vectorize(
      _page(blank),
      [pen, gone, marker],
      includeInk: true,
      includeTemplate: true,
    );
    expect(v.underlay, isEmpty); // white paper
    expect(v.ink, hasLength(2));
    final first = v.ink[0] as PdfFillItem;
    final second = v.ink[1] as PdfFillItem;
    // Highlighter first (older), then the pen.
    expect(first.colorArgb, marker.style.colorArgb);
    expect(first.opacity, marker.style.opacity);
    expect(second.colorArgb, pen.style.colorArgb);
    expect(second.opacity, 1);
    final b = pen.bounds;
    expect(second.path.verbs, [0, 1, 1, 1, 3]);
    expect(second.path.coords[0], closeTo(b.left, 1e-3));
    expect(second.path.coords[1], closeTo(b.top, 1e-3));
    expect(second.path.coords[4], closeTo(b.right, 1e-3));
    expect(second.path.coords[5], closeTo(b.bottom, 1e-3));
    expect(second.blend, PdfBlend.normal);
    expect(second.fillRule, PdfFillRule.nonZero);
  });

  test('includeInk false → no ink', () {
    final v = box.vectorize(
      _page(blank),
      [_stroke('a', createdAt: 1)],
      includeInk: false,
      includeTemplate: true,
    );
    expect(v.isEmpty, isTrue);
  });

  test(
    'paper underlay: non-white blank / template pages with includeTemplate',
    () {
      const ivory = core.BlankBackground(
        paperColorArgb: core.PaperColors.ivory,
      );
      final v = box.vectorize(
        _page(ivory),
        const [],
        includeInk: true,
        includeTemplate: true,
      );
      final paper = v.underlay.single as PdfFillItem;
      expect(paper.colorArgb, core.PaperColors.ivory);
      expect(paper.path.coords, [0, 0, 300, 0, 300, 200, 0, 200]);

      const lined = core.TemplateBackground(
        template: core.PageTemplate(kind: core.PageTemplateKind.lined),
        paperColorArgb: core.PaperColors.gray,
      );
      expect(
        box
            .vectorize(
              _page(lined),
              const [],
              includeInk: true,
              includeTemplate: true,
            )
            .underlay
            .single
            .colorArgb,
        core.PaperColors.gray,
      );
      expect(
        box
            .vectorize(
              _page(ivory),
              const [],
              includeInk: true,
              includeTemplate: false,
            )
            .underlay,
        isEmpty,
      );
    },
  );

  test('PDF pages never get an underlay', () {
    const pdf = core.PdfBackground(
      assetId: 'a',
      pdfPageIndex: 0,
      paperColorArgb: core.PaperColors.ivory,
    );
    final v = box.vectorize(
      _page(pdf),
      [_stroke('a', createdAt: 1)],
      includeInk: true,
      includeTemplate: true,
    );
    expect(v.underlay, isEmpty);
    expect(v.ink, hasLength(1));
  });

  test('the result encodes (one object per item)', () {
    final v = box.vectorize(
      _page(const core.BlankBackground(paperColorArgb: core.PaperColors.ivory)),
      [_stroke('a', createdAt: 1), _stroke('b', createdAt: 2)],
      includeInk: true,
      includeTemplate: true,
    );
    final ops = PdfComposeEncoder.encode(outputIndex: 0, vectors: v);
    expect(
      ops.verbs.where((x) => x == PdfComposeOpcodes.endObject),
      hasLength(3),
    );
  });
}
