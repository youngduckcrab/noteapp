// Page plan items v2 (m5-7/06-pdf 4.1.3, 6.2.1, 6.2.3; 8.1 T20 — what works from R2-B4):
// PdfAffine (frame matrix = core.ElementFrame.corners, composition, apply), the value equality
// of the plan items, PdfPagePlan.isEmpty / hasReferences, and planPage of the two vectorizers
// — InkEngineVectorizer's R2-B4 body (1차 vectorize in L-1 order + the image background
// reference) and BoxInkVectorizer v2 (4.3.1, objects as references in L-1 order).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

const String _assetId =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

core.Page _page(core.PageBackground background) => core.Page(
  id: 'page-1',
  noteId: 'note-1',
  sortKey: 'a',
  size: const core.PageSize(300, 200),
  background: background,
  createdAt: 0,
  updatedAt: 0,
);

core.Stroke _stroke(String id, {required int createdAt}) => core.Stroke(
  id: id,
  pageId: 'page-1',
  style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
  points: core.StrokePoints.fromList(const [
    core.StrokePoint(10, 10),
    core.StrokePoint(50, 30),
  ]),
  createdAt: createdAt,
);

core.PageContent _content(
  core.PageBackground background, {
  List<core.Stroke> strokes = const [],
  List<core.PageObject> objects = const [],
}) => core.PageContent(
  page: _page(background),
  strokes: strokes,
  objects: objects,
  revision: 0,
);

void _same(Object a, Object b) {
  expect(identical(a, b), isFalse, reason: 'build the two values separately');
  expect(a, b);
  expect(a.hashCode, b.hashCode);
}

void _closeTo(ui.Offset actual, core.PagePoint expected) {
  expect(actual.dx, closeTo(expected.x, 1e-6));
  expect(actual.dy, closeTo(expected.y, 1e-6));
}

void main() {
  group('PdfAffine (6.2.3)', () {
    test('frame: local rect corners land on ElementFrame.corners', () {
      for (final degrees in [0.0, 90.0, -30.0, 180.0, 45.0]) {
        final frame = core.ElementFrame(
          const core.PageRect(40, 60, 240, 160),
          rotation: degrees * math.pi / 180,
        );
        final m = PdfAffine.frame(frame);
        final corners = frame.corners;
        const w = 200.0, h = 100.0;
        final local = [
          ui.Offset.zero,
          const ui.Offset(w, 0),
          const ui.Offset(w, h),
          const ui.Offset(0, h),
        ];
        for (var i = 0; i < 4; i++) {
          _closeTo(m.apply(local[i]), corners[i]);
        }
      }
    });

    test('rotation 0 is the exact translation to the top-left corner', () {
      final m = PdfAffine.frame(
        const core.ElementFrame(core.PageRect(0.1, 0.7, 100.3, 50.9)),
      );
      expect(m, const PdfAffine(1, 0, 0, 1, 0.1, 0.7));
    });

    test('then = outer ∘ this; identity is neutral', () {
      const scale = PdfAffine(2, 0, 0, 3, 0, 0);
      const move = PdfAffine(1, 0, 0, 1, 10, 20);
      const p = ui.Offset(1, 1);
      // scale first, then move: (2, 3) + (10, 20)
      expect(scale.then(move).apply(p), const ui.Offset(12, 23));
      // move first, then scale: (11, 21) scaled
      expect(move.then(scale).apply(p), const ui.Offset(22, 63));
      expect(scale.then(PdfAffine.identity), scale);
      expect(PdfAffine.identity.then(move), move);
      // unit square → y-down rect (x0, y0, rw, rh) = [rw, 0, 0, −rh, x0, y0 + rh] (6.2.3)
      const unit = PdfAffine(50, 0, 0, -20, 5, 7 + 20);
      expect(unit.apply(const ui.Offset(0, 1)), const ui.Offset(5, 7));
      expect(unit.apply(const ui.Offset(1, 0)), const ui.Offset(55, 27));
    });

    test('value equality', () {
      _same(
        PdfAffine(1, 2, 3, 4, 5, double.parse('6')),
        const PdfAffine(1, 2, 3, 4, 5, 6),
      );
      expect(PdfAffine.identity == const PdfAffine(1, 0, 0, 1, 0, 1), isFalse);
    });
  });

  group('plan items: value equality, PdfPagePlan', () {
    final textBox = core_testing.PageObjectFixtures.textBox(
      pageId: 'page-1',
      id: 't1',
    );
    final math1 = core_testing.PageObjectFixtures.math(
      pageId: 'page-1',
      id: 'm1',
    );
    const frame = core.ElementFrame(core.PageRect(10, 20, 110, 70));

    test('references and text items compare by value', () {
      _same(
        PdfAssetImageRef.object(
          assetId: _assetId,
          frame: core.ElementFrame(
            core.PageRect(10, 20, 110, double.parse('70')),
          ),
        ),
        const PdfAssetImageRef.object(assetId: _assetId, frame: frame),
      );
      _same(
        PdfAssetImageRef.background(
          assetId: _assetId,
          fit: core.ImageFit.cover,
          pageSize: ui.Size(double.parse('300'), 200),
        ),
        const PdfAssetImageRef.background(
          assetId: _assetId,
          fit: core.ImageFit.cover,
          pageSize: ui.Size(300, 200),
        ),
      );
      expect(
        const PdfAssetImageRef.object(assetId: _assetId, frame: frame) ==
            const PdfAssetImageRef.background(
              assetId: _assetId,
              fit: core.ImageFit.contain,
              pageSize: ui.Size(300, 200),
            ),
        isFalse,
      );
      _same(
        PdfTextBoxRef(textBox, [
          (text: 'a', x: 0, baselineY: 16, width: double.parse('10')),
        ]),
        PdfTextBoxRef(textBox, const [
          (text: 'a', x: 0, baselineY: 16, width: 10),
        ]),
      );
      expect(
        PdfTextBoxRef(textBox, const []) ==
            PdfTextBoxRef(textBox, const [
              (text: 'a', x: 0, baselineY: 16, width: 10),
            ]),
        isFalse,
      );
      _same(PdfMathRef(math1), PdfMathRef(math1));
      _same(
        PdfTextItem(
          text: 'ab',
          fontId: 1,
          fontSize: 12,
          colorArgb: 0xFF000000,
          matrix: PdfAffine(1, 0, 0, -1, 3, double.parse('4')),
        ),
        const PdfTextItem(
          text: 'ab',
          fontId: 1,
          fontSize: 12,
          colorArgb: 0xFF000000,
          matrix: PdfAffine(1, 0, 0, -1, 3, 4),
        ),
      );
    });

    test('byte payloads keep identity; an image item compares its image by identity', () {
      final bytes = Uint8List(4);
      final a = PdfJpegData(bytes, width: 2, height: 1);
      final b = PdfJpegData(bytes, width: 2, height: 1);
      expect(a == b, isFalse);
      expect(a.byteLength, 4);
      expect(
        PdfRgbaData(
          Uint8List(8),
          width: 2,
          height: 1,
          hasAlpha: false,
        ).byteLength,
        8,
      );
      _same(
        PdfImageItem(
          image: a,
          matrix: PdfAffine(1, 0, 0, 1, 0, double.parse('0')),
        ),
        PdfImageItem(image: a, matrix: PdfAffine.identity),
      );
      expect(
        PdfImageItem(image: a, matrix: PdfAffine.identity) ==
            PdfImageItem(image: b, matrix: PdfAffine.identity),
        isFalse,
      );
    });

    test('PdfPagePlan: isEmpty, hasReferences, equality over items', () {
      expect(PdfPagePlan.empty.isEmpty, isTrue);
      expect(PdfPagePlan(const []).isEmpty, isTrue);
      expect(PdfPagePlan.empty.hasReferences, isFalse);
      final fill = PdfFillItem(
        path: PdfVectorPath.rect(ui.Rect.zero),
        colorArgb: 0,
      );
      final drawOnly = PdfPagePlan([fill]);
      expect([drawOnly.isEmpty, drawOnly.hasReferences], [false, false]);
      final withRef = PdfPagePlan([fill, PdfMathRef(math1)]);
      expect(withRef.hasReferences, isTrue);
      _same(PdfPagePlan([fill, PdfMathRef(math1)]), withRef);
      expect(
        PdfPagePlan([PdfMathRef(math1), fill]) == withRef,
        isFalse,
        reason: 'order',
      );
      // Vector items keep identity equality (their paths hold bytes).
      expect(
        PdfPagePlan([
              PdfFillItem(path: PdfVectorPath.rect(ui.Rect.zero), colorArgb: 0),
            ]) ==
            drawOnly,
        isFalse,
      );
    });
  });

  group(
    'InkEngineVectorizer.planPage (R2-B4: 1차 vectorize + image background)',
    () {
      const v = InkEngineVectorizer();

      test('white blank page: empty plan; tinted paper: one paper fill', () {
        expect(
          v
              .planPage(
                _content(const core.BlankBackground()),
                includeInk: true,
                includeTemplate: true,
              )
              .isEmpty,
          isTrue,
        );
        final tinted = v.planPage(
          _content(
            const core.BlankBackground(paperColorArgb: core.PaperColors.ivory),
          ),
          includeInk: true,
          includeTemplate: true,
        );
        expect(tinted.items, [isA<PdfFillItem>()]);
        expect(
          (tinted.items.single as PdfFillItem).colorArgb,
          core.PaperColors.ivory,
        );
      });

      test(
        'image background: paper, then its reference (kept without templates)',
        () {
          const background = core.ImageBackground(
            assetId: _assetId,
            fit: core.ImageFit.cover,
            paperColorArgb: core.PaperColors.ivory,
          );
          final plan = v.planPage(
            _content(background),
            includeInk: true,
            includeTemplate: true,
          );
          expect(plan.items, hasLength(2));
          expect(plan.items[0], isA<PdfFillItem>());
          expect(
            plan.items[1],
            const PdfAssetImageRef.background(
              assetId: _assetId,
              fit: core.ImageFit.cover,
              pageSize: ui.Size(300, 200),
            ),
          );
          expect(plan.hasReferences, isTrue);
          final noTemplate = v.planPage(
            _content(background),
            includeInk: false,
            includeTemplate: false,
          );
          expect(noTemplate.items, [
            const PdfAssetImageRef.background(
              assetId: _assetId,
              fit: core.ImageFit.cover,
              pageSize: ui.Size(300, 200),
            ),
          ]);
        },
      );

      test('PDF page: no background items; objects are left out until T24', () {
        final plan = v.planPage(
          _content(
            const core.PdfBackground(assetId: _assetId, pdfPageIndex: 0),
            objects: [core_testing.PageObjectFixtures.math(pageId: 'page-1')],
          ),
          includeInk: true,
          includeTemplate: true,
        );
        expect(plan.isEmpty, isTrue);
      });

      test('template page: the 1차 underlay items, in order', () {
        final page = _page(
          const core.TemplateBackground(
            template: core.PageTemplate(kind: core.PageTemplateKind.lined),
          ),
        );
        final plan = v.planPage(
          core.PageContent(page: page, strokes: const [], revision: 0),
          includeInk: true,
          includeTemplate: true,
        );
        final vectors = v.vectorize(
          page,
          const [],
          includeInk: true,
          includeTemplate: true,
        );
        expect(plan.items, hasLength(vectors.underlay.length));
        expect(plan.items, everyElement(isA<PdfVectorItem>()));
        expect(
          v
              .planPage(
                core.PageContent(page: page, strokes: const [], revision: 0),
                includeInk: true,
                includeTemplate: false,
              )
              .isEmpty,
          isTrue,
        );
      });
    },
  );

  group('BoxInkVectorizer.planPage (4.3.1)', () {
    const box = BoxInkVectorizer();
    final image = core_testing.PageObjectFixtures.image(
      pageId: 'page-1',
      assetId: _assetId,
      id: 'i1',
      createdAt: 1,
    );
    final shape = core_testing.PageObjectFixtures.shape(
      pageId: 'page-1',
      id: 's1',
      createdAt: 2,
    );
    final text = core_testing.PageObjectFixtures.textBox(
      pageId: 'page-1',
      id: 't1',
      createdAt: 3,
    );
    final formula = core_testing.PageObjectFixtures.math(
      pageId: 'page-1',
      id: 'm1',
      createdAt: 4,
    );
    final unknown = core_testing.PageObjectFixtures.unknown(
      pageId: 'page-1',
      id: 'u1',
    );

    test('L-1 order: background, image objects, strokes, shapes, text / math; unknown skipped', () {
      const background = core.ImageBackground(
        assetId: _assetId,
        paperColorArgb: core.PaperColors.ivory,
      );
      final plan = box.planPage(
        _content(
          background,
          strokes: [_stroke('k1', createdAt: 5)],
          objects: [image, shape, text, formula, unknown],
        ),
        includeInk: true,
        includeTemplate: true,
      );
      expect(plan.items, [
        isA<PdfFillItem>(), // paper
        const PdfAssetImageRef.background(
          assetId: _assetId,
          fit: core.ImageFit.contain,
          pageSize: ui.Size(300, 200),
        ),
        PdfAssetImageRef.object(assetId: _assetId, frame: image.frame),
        isA<PdfFillItem>(), // stroke box
        isA<PdfFillItem>(), // shape box
        PdfTextBoxRef(text, [
          (
            text: text.text,
            x: 0,
            baselineY: text.style.fontSizePt,
            width: text.frame.rect.right - text.frame.rect.left,
          ),
        ]),
        PdfMathRef(formula),
      ]);
      final shapeBox = plan.items[4] as PdfFillItem;
      expect(shapeBox.colorArgb, shape.style.strokeColorArgb);
      expect(shapeBox.path.coords[0], closeTo(shape.bounds.left, 1e-3));
    });

    test('includeInk false → the background only', () {
      const background = core.ImageBackground(assetId: _assetId);
      final plan = box.planPage(
        _content(
          background,
          strokes: [_stroke('k1', createdAt: 5)],
          objects: [image, text],
        ),
        includeInk: false,
        includeTemplate: false,
      );
      expect(plan.items, [
        const PdfAssetImageRef.background(
          assetId: _assetId,
          fit: core.ImageFit.contain,
          pageSize: ui.Size(300, 200),
        ),
      ]);
    });
  });
}
