// planFromLayers on HAND-MADE page layers (m5-7/06-pdf 4.1.3, 6.2.1, 6.2.9; 8.2 T24 ① — PDF-M2):
// no ink_engine import. The L-1 order (paper → template → image background → image objects →
// highlighter → ink → text boxes / formulas → tape), includeInk false → background only,
// includeTemplate false → no paper / template but the image background stays, a PDF page has
// no background items, empty layers → the empty plan.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/export/page_layers.dart';

const _asset =
    'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';
const _photo =
    'b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2';
const _size = ui.Size(600, 800);

PdfFillItem _fill(int color, {double opacity = 1}) => PdfFillItem(
  path: PdfVectorPath.rect(const ui.Rect.fromLTWH(10, 10, 20, 20)),
  colorArgb: color,
  opacity: opacity,
);

PdfStrokeItem _stroke(int color) => PdfStrokeItem(
  path: PdfVectorPath.rect(const ui.Rect.fromLTWH(0, 0, 5, 5)),
  colorArgb: color,
  width: 2,
);

final _template = [_stroke(0xFFAACCEE), _fill(0xFFAACCEE)];
const _imageBackground = PdfAssetImageRef.background(
  assetId: _asset,
  fit: core.ImageFit.contain,
  pageSize: _size,
);
final _imageObject = PdfAssetImageRef.object(
  assetId: _photo,
  frame: core.ElementFrame(
    const core.PageRect(50, 60, 250, 210),
    rotation: 0.3,
  ),
);
final _highlighter = _stroke(0xFFFFEB3B);
final _pen = _fill(0xFF1A1A1A);
final _shapePiece = _fill(0xFF2255AA, opacity: 0.5);
final _text = PdfTextBoxRef(
  core_testing.PageObjectFixtures.textBox(pageId: 'p', id: 'text-1'),
  const [(text: '안녕 hello', x: 0, baselineY: 14, width: 80)],
);
final _math = PdfMathRef(
  core_testing.PageObjectFixtures.math(pageId: 'p', id: 'math-1'),
);
final _tape = _fill(0xFFE0C080);

PdfPageLayers _full({PdfPageBackgroundPart? background}) => PdfPageLayers(
  pageSize: _size,
  background:
      background ??
      PdfPageBackgroundPart(
        paperArgb: core.PaperColors.ivory,
        templateItems: _template,
        image: _imageBackground,
      ),
  underlay: [_imageObject],
  highlighter: [_highlighter],
  ink: [_pen, _shapePiece],
  annotations: [_math, _text], // z order as given (formula below the text box)
  cover: [_tape],
);

void _expectPaper(PdfPlanItem item, int color) {
  expect(item, isA<PdfFillItem>());
  final fill = item as PdfFillItem;
  expect(fill.colorArgb, color);
  expect(fill.opacity, 1);
  expect(fill.path.verbs, [0, 1, 1, 1, 3]);
  expect(fill.path.coords, [0, 0, 600, 0, 600, 800, 0, 800]);
}

void main() {
  test('L-1 order: background, image objects, highlighter, ink, annotations, cover', () {
    final plan = planFromLayers(
      _full(),
      includeInk: true,
      includeTemplate: true,
    );
    expect(plan.items, hasLength(11));
    _expectPaper(plan.items[0], core.PaperColors.ivory);
    expect(plan.items.sublist(1), [
      same(_template[0]),
      same(_template[1]),
      _imageBackground,
      _imageObject,
      same(_highlighter),
      same(_pen),
      same(_shapePiece),
      same(_math),
      same(_text),
      same(_tape),
    ]);
    expect(plan.hasReferences, isTrue);
  });

  test('includeInk false → the background only (image background kept)', () {
    final plan = planFromLayers(
      _full(),
      includeInk: false,
      includeTemplate: true,
    );
    expect(plan.items, hasLength(4));
    _expectPaper(plan.items[0], core.PaperColors.ivory);
    expect(plan.items.sublist(1), [
      same(_template[0]),
      same(_template[1]),
      _imageBackground,
    ]);
  });

  test(
    'includeTemplate false → no paper, no template; the image background stays',
    () {
      final plan = planFromLayers(
        _full(),
        includeInk: true,
        includeTemplate: false,
      );
      expect(plan.items, [
        _imageBackground,
        _imageObject,
        same(_highlighter),
        same(_pen),
        same(_shapePiece),
        same(_math),
        same(_text),
        same(_tape),
      ]);
      final backgroundOnly = planFromLayers(
        _full(),
        includeInk: false,
        includeTemplate: false,
      );
      expect(backgroundOnly.items, [_imageBackground]);
    },
  );

  test('PDF page (background none): no background items', () {
    final layers = _full(background: PdfPageBackgroundPart.none);
    final plan = planFromLayers(
      layers,
      includeInk: true,
      includeTemplate: true,
    );
    expect(plan.items.first, _imageObject);
    expect(plan.items, hasLength(7));
    expect(
      planFromLayers(layers, includeInk: false, includeTemplate: true),
      PdfPagePlan.empty,
    );
  });

  test('white paper (no paperArgb), template only', () {
    final plan = planFromLayers(
      PdfPageLayers(
        pageSize: _size,
        background: PdfPageBackgroundPart(templateItems: _template),
      ),
      includeInk: true,
      includeTemplate: true,
    );
    expect(plan.items, [same(_template[0]), same(_template[1])]);
    expect(plan.hasReferences, isFalse);
  });

  test('empty layers → the empty plan', () {
    for (final ink in [true, false]) {
      for (final template in [true, false]) {
        final plan = planFromLayers(
          const PdfPageLayers(pageSize: _size),
          includeInk: ink,
          includeTemplate: template,
        );
        expect(plan.isEmpty, isTrue, reason: 'ink $ink, template $template');
        expect(plan, PdfPagePlan.empty);
      }
    }
    // A white blank page with an empty template list is empty too.
    expect(
      planFromLayers(
        const PdfPageLayers(
          pageSize: _size,
          background: PdfPageBackgroundPart(templateItems: []),
        ),
        includeInk: true,
        includeTemplate: true,
      ).isEmpty,
      isTrue,
    );
  });

  test('the plan list cannot be changed', () {
    final plan = planFromLayers(
      _full(),
      includeInk: true,
      includeTemplate: true,
    );
    expect(() => plan.items.add(_imageBackground), throwsUnsupportedError);
  });

  group('value equality', () {
    test('PdfPageBackgroundPart', () {
      final a = PdfPageBackgroundPart(
        paperArgb: 1,
        templateItems: _template,
        image: _imageBackground,
      );
      final b = PdfPageBackgroundPart(
        paperArgb: 1,
        templateItems: List.of(_template),
        image: const PdfAssetImageRef.background(
          assetId: _asset,
          fit: core.ImageFit.contain,
          pageSize: _size,
        ),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a == PdfPageBackgroundPart(paperArgb: 1, image: _imageBackground),
        isFalse,
      );
      // Vector items keep identity (1차): another item with the same fields is different.
      expect(
        a ==
            PdfPageBackgroundPart(
              paperArgb: 1,
              templateItems: [_stroke(0xFFAACCEE), _template[1]],
              image: _imageBackground,
            ),
        isFalse,
      );
      expect(PdfPageBackgroundPart.none.isEmpty, isTrue);
      expect(const PdfPageBackgroundPart(templateItems: []).isEmpty, isTrue);
      expect(a.isEmpty, isFalse);
    });

    test('PdfPageLayers', () {
      expect(_full(), _full());
      expect(_full().hashCode, _full().hashCode);
      expect(_full() == _full(background: PdfPageBackgroundPart.none), isFalse);
      expect(
        const PdfPageLayers(pageSize: _size) ==
            const PdfPageLayers(pageSize: ui.Size(600, 801)),
        isFalse,
      );
    });
  });
}
