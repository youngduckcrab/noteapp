// Template underlay (06-pdf 6.11.8 'underlay'; 8 T12): INK TemplateVectors items → one stroke
// object per (color, width) of the lines and one fill object per color of the dots; the CORE
// PageTemplate goes to INK as it is; paper fill only when the paper is not white; no
// underlay on PDF pages; InkEngineVectorizer's include flags. The ink part of
// InkEngineVectorizer needs INK's real export (integration/ink_vectorizer_test).
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/ink_adapter/template_underlay.dart';

core.Page _page(
  core.PageBackground background, {
  double w = 200,
  double h = 100,
}) => core.Page(
  id: 'page-1',
  noteId: 'note-1',
  sortKey: 'a',
  size: core.PageSize(w, h),
  background: background,
  createdAt: 0,
  updatedAt: 0,
);

final class _RecordingBuild {
  final List<
    ({
      core.PageTemplate template,
      Size pageSize,
      int paperColorArgb,
      Rect? clip,
    })
  >
  calls = [];
  List<ink.TemplateVectorItem> result = const [];

  List<ink.TemplateVectorItem> call(
    core.PageTemplate template, {
    required Size pageSize,
    required int paperColorArgb,
    Rect? clip,
  }) {
    calls.add((
      template: template,
      pageSize: pageSize,
      paperColorArgb: paperColorArgb,
      clip: clip,
    ));
    return result;
  }
}

void main() {
  group('pdfTemplateItems', () {
    test(
      'lines grouped by (color, width): butt caps, one segment per subpath',
      () {
        final items = pdfTemplateItems(const [
          ink.TemplateLine(
            Offset(0, 10),
            Offset(100, 10),
            width: 0.5,
            colorArgb: 0xFFAAAAAA,
          ),
          ink.TemplateLine(
            Offset(10, 0),
            Offset(10, 100),
            width: 1,
            colorArgb: 0xFFAAAAAA,
          ),
          ink.TemplateLine(
            Offset(0, 20),
            Offset(100, 20),
            width: 0.5,
            colorArgb: 0xFFAAAAAA,
          ),
          ink.TemplateLine(
            Offset(0, 30),
            Offset(100, 30),
            width: 0.5,
            colorArgb: 0xFFFF0000,
          ),
        ]);
        expect(items, hasLength(3));
        final strokes = items.cast<PdfStrokeItem>();
        expect(
          [
            for (final s in strokes)
              (s.colorArgb, s.width, s.path.verbs.length),
          ],
          [(0xFFAAAAAA, 0.5, 4), (0xFFAAAAAA, 1.0, 2), (0xFFFF0000, 0.5, 2)],
        );
        expect(strokes.first.path.verbs, [0, 1, 0, 1]);
        expect(strokes.first.path.coords, [0, 10, 100, 10, 0, 20, 100, 20]);
        for (final s in strokes) {
          expect(s.cap, PdfLineCap.butt);
          expect(s.opacity, 1);
          expect(s.blend, PdfBlend.normal);
        }
      },
    );

    test('dots grouped by color into circle fills', () {
      final items = pdfTemplateItems(const [
        ink.TemplateDot(Offset(5, 5), radius: 1, colorArgb: 0xFFBBBBBB),
        ink.TemplateDot(Offset(15, 5), radius: 1, colorArgb: 0xFFBBBBBB),
        ink.TemplateDot(Offset(25, 5), radius: 1, colorArgb: 0xFF00FF00),
      ]);
      expect(items, hasLength(2));
      final fills = items.cast<PdfFillItem>();
      expect(fills.first.colorArgb, 0xFFBBBBBB);
      expect(fills.first.fillRule, PdfFillRule.nonZero);
      expect(fills.first.path.verbs, [0, 2, 2, 2, 2, 3, 0, 2, 2, 2, 2, 3]);
      expect(fills.first.path.coords.sublist(0, 2), [6, 5]); // (cx + r, cy)
      expect(fills.last.path.verbs, hasLength(6));
    });

    test('lines and dots together keep the first-appearance order', () {
      final items = pdfTemplateItems(const [
        ink.TemplateDot(Offset(5, 5), radius: 1, colorArgb: 0xFFBBBBBB),
        ink.TemplateLine(
          Offset(0, 10),
          Offset(100, 10),
          width: 0.5,
          colorArgb: 0xFFBBBBBB,
        ),
        ink.TemplateDot(Offset(9, 5), radius: 1, colorArgb: 0xFFBBBBBB),
      ]);
      expect(items.map((i) => i.runtimeType), [PdfFillItem, PdfStrokeItem]);
    });

    test('nothing → nothing', () {
      expect(pdfTemplateItems(const []), isEmpty);
    });
  });

  group('pdfPageUnderlay', () {
    const template = core.PageTemplate(kind: core.PageTemplateKind.grid);

    test('the CORE PageTemplate goes to INK as it is', () {
      final build = _RecordingBuild()
        ..result = const [
          ink.TemplateLine(
            Offset(0, 5),
            Offset(200, 5),
            width: 0.5,
            colorArgb: 0xFFAAAAAA,
          ),
        ];
      final items = pdfPageUnderlay(
        _page(const core.TemplateBackground(template: template)),
        build: build.call,
      );
      expect(build.calls, hasLength(1));
      final call = build.calls.single;
      expect(identical(call.template, template), isTrue);
      expect(call.pageSize, const Size(200, 100));
      expect(call.paperColorArgb, core.PaperColors.white);
      expect(call.clip, isNull);
      // White paper: no paper fill, only the template line object.
      expect(items, hasLength(1));
      expect(items.single, isA<PdfStrokeItem>());
    });

    test('non-white paper → full-page fill first, then the template', () {
      final build = _RecordingBuild()
        ..result = const [
          ink.TemplateDot(Offset(5, 5), radius: 1, colorArgb: 0xFFAAAAAA),
        ];
      final items = pdfPageUnderlay(
        _page(
          const core.TemplateBackground(
            template: template,
            paperColorArgb: core.PaperColors.ivory,
          ),
        ),
        build: build.call,
      );
      expect(build.calls.single.paperColorArgb, core.PaperColors.ivory);
      expect(items, hasLength(2));
      final paper = items.first as PdfFillItem;
      expect(paper.colorArgb, core.PaperColors.ivory);
      expect(paper.path.coords, [0, 0, 200, 0, 200, 100, 0, 100]);
      expect(items.last, isA<PdfFillItem>());
    });

    test('blank pages: paper fill only when not white', () {
      final build = _RecordingBuild();
      expect(
        pdfPageUnderlay(_page(const core.BlankBackground()), build: build.call),
        isEmpty,
      );
      final gray = pdfPageUnderlay(
        _page(
          const core.BlankBackground(paperColorArgb: core.PaperColors.gray),
        ),
        build: build.call,
      );
      expect(gray.single.colorArgb, core.PaperColors.gray);
      expect(build.calls, isEmpty);
    });

    test('PDF pages: no underlay, INK not asked', () {
      final build = _RecordingBuild();
      expect(
        pdfPageUnderlay(
          _page(
            const core.PdfBackground(
              assetId: 'a',
              pdfPageIndex: 0,
              paperColorArgb: core.PaperColors.ivory,
            ),
          ),
          build: build.call,
        ),
        isEmpty,
      );
      expect(build.calls, isEmpty);
    });

    // Integration stage (real INK merged): every template gives lines or dots on an A4 page,
    // and the default builder's underlay is exactly those items grouped (the foundation
    // INK body returned none, so this used to compare lengths only).
    test('default builder = ink.TemplateVectors.build, item for item', () {
      const a4 = Size(595.276, 841.89);
      for (final kind in core.PageTemplateKind.values) {
        final t = core.PageTemplate(kind: kind);
        final page = _page(
          core.TemplateBackground(template: t),
          w: a4.width,
          h: a4.height,
        );
        final fromInk = ink.TemplateVectors.build(
          t,
          pageSize: a4,
          paperColorArgb: core.PaperColors.white,
        );
        expect(fromInk, isNotEmpty, reason: '$kind');
        final expected = pdfTemplateItems(fromInk);
        final actual = pdfPageUnderlay(page);
        expect(actual, hasLength(expected.length), reason: '$kind');
        for (var i = 0; i < expected.length; i++) {
          final (a, e) = (actual[i], expected[i]);
          expect(a.runtimeType, e.runtimeType, reason: '$kind #$i');
          expect(
            (a.colorArgb, a.opacity, a.blend),
            (e.colorArgb, e.opacity, e.blend),
            reason: '$kind #$i',
          );
          if (a is PdfStrokeItem && e is PdfStrokeItem) {
            expect((a.width, a.cap), (e.width, e.cap), reason: '$kind #$i');
          }
          expect(a.path.verbs, e.path.verbs, reason: '$kind #$i');
          expect(a.path.coords, e.path.coords, reason: '$kind #$i');
        }
      }
    });
  });

  group('InkEngineVectorizer flags', () {
    const vectorizer = InkEngineVectorizer();
    final ivory = _page(
      const core.BlankBackground(paperColorArgb: core.PaperColors.ivory),
    );

    test('includeTemplate → paper underlay; false → white page', () {
      final withTemplate = vectorizer.vectorize(
        ivory,
        const [],
        includeInk: true,
        includeTemplate: true,
      );
      expect(withTemplate.underlay.single.colorArgb, core.PaperColors.ivory);
      expect(withTemplate.ink, isEmpty);
      expect(
        vectorizer
            .vectorize(
              ivory,
              const [],
              includeInk: true,
              includeTemplate: false,
            )
            .isEmpty,
        isTrue,
      );
    });

    test('PDF page: no underlay', () {
      final pdf = _page(
        const core.PdfBackground(
          assetId: 'a',
          pdfPageIndex: 0,
          paperColorArgb: core.PaperColors.ivory,
        ),
      );
      expect(
        vectorizer
            .vectorize(pdf, const [], includeInk: true, includeTemplate: true)
            .underlay,
        isEmpty,
      );
    });

    test('includeInk false → no ink even with strokes', () {
      final stroke = core.Stroke(
        id: 's1',
        pageId: 'page-1',
        style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
        points: core.StrokePoints.fromList(const [
          core.StrokePoint(10, 10),
          core.StrokePoint(20, 10),
        ]),
        createdAt: 1,
      );
      final v = vectorizer.vectorize(
        ivory,
        [stroke],
        includeInk: false,
        includeTemplate: true,
      );
      expect(v.ink, isEmpty);
      expect(v.underlay, hasLength(1));
    });
  });
}
