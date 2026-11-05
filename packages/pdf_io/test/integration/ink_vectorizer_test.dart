// InkEngineVectorizer over the REAL INK vector export (06-pdf 6.11.8, 8 T12; INK T21 export,
// T13 / T13b templates) — integration stage only (`ws test --run-skipped -t integration`,
// contract 7.7 step 5). With INK's foundation bodies (empty export, no template items) these
// assertions fail by design: they check what INK's real output turns into.
//   - highlighters → stroke objects with Multiply on white paper (one per width / cap),
//     drawn before the fills; pens → non-zero fills; pencil → flat color × 0.85,
//   - all six templates give underlay items.
@Tags(['integration'])
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';

core.Page _page(core.PageBackground background) => core.Page(
  id: 'page-1',
  noteId: 'note-1',
  sortKey: 'a',
  size: core.PageSize.a4Portrait,
  background: background,
  createdAt: 0,
  updatedAt: 0,
);

core.Stroke _stroke(
  String id,
  core.PenTool tool, {
  required int createdAt,
  double? width,
  double y = 100,
}) {
  final style = core.StrokeStyle.defaultsFor(tool);
  return core.Stroke(
    id: id,
    pageId: 'page-1',
    style: width == null
        ? style
        : core.StrokeStyle(
            tool: style.tool,
            colorArgb: style.colorArgb,
            width: width,
            opacity: style.opacity,
            smoothing: style.smoothing,
            extras: style.extras,
          ),
    points: core.StrokePoints.fromList([
      for (var i = 0; i <= 10; i++)
        core.StrokePoint(100 + 20.0 * i, y + (i.isEven ? 0 : 6)),
    ]),
    createdAt: createdAt,
  );
}

void main() {
  const vectorizer = InkEngineVectorizer();

  test('highlighters → Multiply stroke objects first, then the pen fills', () {
    final strokes = [
      _stroke('pen', core.PenTool.ballpoint, createdAt: 1),
      _stroke('hl-1', core.PenTool.highlighter, createdAt: 2, y: 200),
      _stroke('hl-2', core.PenTool.highlighter, createdAt: 3, y: 220),
      _stroke(
        'hl-wide',
        core.PenTool.highlighter,
        createdAt: 4,
        width: 24,
        y: 300,
      ),
    ];
    final v = vectorizer.vectorize(
      _page(const core.BlankBackground()),
      strokes,
      includeInk: true,
      includeTemplate: true,
    );
    expect(v.underlay, isEmpty);
    final hl = v.ink.whereType<PdfStrokeItem>().toList();
    final fills = v.ink.whereType<PdfFillItem>().toList();
    // Same color / opacity, two widths → two stroke objects.
    expect(hl, hasLength(2));
    expect(hl.map((s) => s.width).toSet(), {12.0, 24.0});
    for (final s in hl) {
      expect(s.blend, PdfBlend.multiply);
      expect(s.join, PdfLineJoin.round);
      expect(s.colorArgb, 0xFFFFE600);
      expect(s.opacity, closeTo(0.35, 1e-6));
    }
    // The 12 pt object holds both thin highlighters as two subpaths.
    final thin = hl.firstWhere((s) => s.width == 12);
    expect(thin.path.verbs.where((v) => v == 0), hasLength(2));
    // Highlighters come before the pen fill.
    expect(v.ink.indexOf(hl.first), lessThan(v.ink.indexOf(fills.first)));
    expect(fills.single.fillRule, PdfFillRule.nonZero);
    expect(fills.single.path.isEmpty, isFalse);

    final ops = PdfComposeEncoder.encode(outputIndex: 0, vectors: v);
    expect(
      ops.verbs.where((x) => x == PdfComposeOpcodes.endObject),
      hasLength(3),
    );
    // Paint of the first object: stroke (1) with Multiply (index 8 = 1).
    expect(ops.paints[0], 1);
    expect(ops.paints[8], 1);
  });

  test('pencil: one flat fill at style opacity × 0.85', () {
    final pencil = _stroke('pencil', core.PenTool.pencil, createdAt: 1);
    final v = vectorizer.vectorize(
      _page(const core.BlankBackground()),
      [pencil],
      includeInk: true,
      includeTemplate: true,
    );
    final fill = v.ink.single as PdfFillItem;
    expect(fill.opacity, closeTo(pencil.style.opacity * 0.85, 1e-6));
  });

  for (final kind in core.PageTemplateKind.values) {
    test('template ${kind.name}: underlay items > 0', () {
      final v = vectorizer.vectorize(
        _page(core.TemplateBackground(template: core.PageTemplate(kind: kind))),
        const [],
        includeInk: true,
        includeTemplate: true,
      );
      expect(v.underlay, isNotEmpty);
      expect(
        PdfComposeEncoder.encode(outputIndex: 0, vectors: v).isEmpty,
        isFalse,
      );
    });
  }
}
