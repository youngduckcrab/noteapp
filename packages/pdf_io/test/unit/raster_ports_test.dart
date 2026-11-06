// PDF T25b — the raster ports' pixel cap (m5-7/06-pdf 6.2.4 · 6.2.10 ④, PDF-M3): cappedPixelsPerPt
// = min(want, sqrt(4 Mpx / (w·h)), 8192 / max(w, h)), lowered a little more while the rounded-up
// raster is still above the cap; the raster size rule ⌈w·k⌉ × ⌈h·k⌉; the formula contain rect;
// and the default INK text port on the VM (test font).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/testing.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/src/export/object_resolver.dart';
import 'package:pdf_io/src/export/raster_ports.dart';
import 'package:pdf_io/src/tuning.dart';

const double dpi300 = 300 / 72;

int _pixels(ui.Size size, double k) {
  final px = rasterPixelSize(size, k);
  return px.width * px.height;
}

void main() {
  group('cappedPixelsPerPt', () {
    test(
      'page-size text box 500 × 700 pt → 3.46 px/pt (≈ 249 dpi), ≤ 4 Mpx',
      () {
        const size = ui.Size(500, 700);
        final k = cappedPixelsPerPt(dpi300, size);
        expect(k, closeTo(3.46, 0.005));
        expect(k * 72, closeTo(249, 0.5));
        expect(_pixels(size, k), lessThanOrEqualTo(PdfTuning.maxRasterPixels));
        // only the rounding step below the exact cap
        expect(
          k,
          lessThanOrEqualTo(math.sqrt(PdfTuning.maxRasterPixels / 350000)),
        );
        expect(
          k,
          greaterThan(math.sqrt(PdfTuning.maxRasterPixels / 350000) * 0.995),
        );
      },
    );

    test('700 × 700 pt formula → 2.93 px/pt (≈ 211 dpi), ≤ 4 Mpx', () {
      const size = ui.Size(700, 700);
      final k = cappedPixelsPerPt(dpi300, size);
      expect(k, closeTo(2.93, 0.01));
      expect(k * 72, closeTo(211, 0.7));
      expect(_pixels(size, k), lessThanOrEqualTo(PdfTuning.maxRasterPixels));
      expect(rasterPixelSize(size, k).width, lessThanOrEqualTo(2048));
    });

    test('a small box keeps 300 dpi exactly', () {
      for (final size in const [
        ui.Size(200, 50),
        ui.Size(10, 10),
        ui.Size(480, 480),
      ]) {
        expect(cappedPixelsPerPt(dpi300, size), dpi300, reason: '$size');
      }
    });

    test('a thin long box → the long side is the limit (8192 px)', () {
      const size = ui.Size(4000, 10);
      final k = cappedPixelsPerPt(dpi300, size);
      expect(k, closeTo(8192 / 4000, 0.005));
      final px = rasterPixelSize(size, k);
      expect(px.width, lessThanOrEqualTo(PdfTuning.maxRasterSidePx));
      expect(px.width, greaterThan(8150));
      expect(
        px.width * px.height,
        lessThanOrEqualTo(PdfTuning.maxRasterPixels),
      );
      // the tall one the same way
      final kt = cappedPixelsPerPt(dpi300, const ui.Size(10, 4000));
      expect(kt, k);
    });

    test(
      'the cap is the INK value (03-ink 4.10) and never raises the request',
      () {
        expect(PdfTuning.maxRasterPixels, 4194304);
        expect(PdfTuning.maxRasterSidePx, 8192);
        for (final want in const [0.5, 1.0, 2.0, dpi300, 10.0]) {
          for (final size in const [
            ui.Size(100, 100),
            ui.Size(500, 700),
            ui.Size(3000, 20),
          ]) {
            final k = cappedPixelsPerPt(want, size);
            expect(k, lessThanOrEqualTo(want));
            expect(
              _pixels(size, k),
              lessThanOrEqualTo(PdfTuning.maxRasterPixels),
            );
          }
        }
      },
    );

    test(
      'a non-positive or non-finite request → 0; a zero size keeps the request',
      () {
        expect(cappedPixelsPerPt(0, const ui.Size(10, 10)), 0);
        expect(cappedPixelsPerPt(-1, const ui.Size(10, 10)), 0);
        expect(cappedPixelsPerPt(double.nan, const ui.Size(10, 10)), 0);
        expect(cappedPixelsPerPt(double.infinity, const ui.Size(10, 10)), 0);
        expect(cappedPixelsPerPt(dpi300, ui.Size.zero), dpi300);
      },
    );
  });

  test('rasterPixelSize = ⌈w·k⌉ × ⌈h·k⌉', () {
    expect(rasterPixelSize(const ui.Size(10, 3), 2.5), (width: 25, height: 8));
    expect(rasterPixelSize(const ui.Size(0.1, 0.1), 1), (width: 1, height: 1));
    expect(rasterPixelSize(ui.Size.zero, 3), (width: 0, height: 0));
  });

  group('mathContainRect (6.2.3 — 03-ink 6.12.4)', () {
    test('wide frame: centred horizontally, full height', () {
      final r = mathContainRect(
        const ui.Size(40, 40),
        const ui.Size(200, 100),
      )!;
      expect(r, const ui.Rect.fromLTWH(50, 0, 100, 100));
    });

    test('tall frame: centred vertically, full width', () {
      final r = mathContainRect(const ui.Size(80, 20), const ui.Size(40, 100))!;
      expect(r, const ui.Rect.fromLTWH(0, 45, 40, 10));
    });

    test('a zero side → null', () {
      expect(mathContainRect(ui.Size.zero, const ui.Size(10, 10)), isNull);
      expect(
        mathContainRect(const ui.Size(10, 10), const ui.Size(0, 10)),
        isNull,
      );
    });
  });

  group('default INK ports on the VM (test font)', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await ink.useInkTestFonts();
    });

    test('InkTextRasterizer: a non-empty frame-size raster, transparent background', () async {
      final box = core.TextBoxObject(
        id: 't1',
        pageId: 'p1',
        frame: const core.ElementFrame(core.PageRect(0, 0, 120, 40)),
        text: '안녕 hello',
        style: const core.TextBoxStyle(fontSizePt: 18, colorArgb: 0xFF000000),
        createdAt: 1,
      );
      const k = 2.0;
      final data = await const InkTextRasterizer().rasterize(
        box,
        pixelsPerPt: k,
      );
      expect(data, isNotNull);
      expect((data!.width, data.height), (240, 80));
      expect(data.rgba.length, 240 * 80 * 4);
      expect(data.hasAlpha, isTrue);
      var inked = 0, clear = 0;
      for (var i = 3; i < data.rgba.length; i += 4) {
        if (data.rgba[i] > 0) {
          inked++;
        } else {
          clear++;
        }
      }
      expect(inked, greaterThan(0), reason: 'the text is drawn');
      expect(clear, greaterThan(inked), reason: 'no box background');
    });

    test(
      'InkTextRasterizer: a page-size box stays ≤ 4 Mpx at the capped density',
      () async {
        final box = core.TextBoxObject(
          id: 't2',
          pageId: 'p1',
          frame: const core.ElementFrame(core.PageRect(0, 0, 500, 700)),
          text: 'hello',
          style: const core.TextBoxStyle(),
          createdAt: 1,
        );
        final k = cappedPixelsPerPt(dpi300, const ui.Size(500, 700));
        final data = await const InkTextRasterizer().rasterize(
          box,
          pixelsPerPt: k,
        );
        expect(data, isNotNull);
        expect(
          data!.width * data.height,
          lessThanOrEqualTo(PdfTuning.maxRasterPixels),
        );
        expect(
          (data.width, data.height),
          (
            rasterPixelSize(const ui.Size(500, 700), k).width,
            rasterPixelSize(const ui.Size(500, 700), k).height,
          ),
        );
      },
    );

    test(
      'InkMathRasterizer.layoutSize: INK layout size; invalid LaTeX → null',
      () {
        core.MathObject formula(String latex) => core.MathObject(
          id: 'm',
          pageId: 'p1',
          frame: const core.ElementFrame(core.PageRect(0, 0, 100, 50)),
          latex: latex,
          style: const core.MathStyle(fontSizePt: 20),
          createdAt: 1,
        );
        const port = InkMathRasterizer();
        final size = port.layoutSize(formula(r'\frac{a}{b}'));
        expect(size, isNotNull);
        expect(size!.width, greaterThan(0));
        expect(size.height, greaterThan(0));
        expect(port.layoutSize(formula(r'\frac{a')), isNull);
        expect(port.layoutSize(formula('')), isNull);
      },
    );
  });
}
