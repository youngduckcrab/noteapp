// The default formula raster port over INK's REAL InkMathRenderer.rasterize (m5-7/06-pdf 6.2.4,
// 5.2; 8.2 T25b — PDF-M2): 300 dpi size, ink drawn, a big formula frame ≤ 4 Mpx and a root
// (\sqrt — SVG glyph pictures INK waits for). Integration stage only (`ws test --run-skipped -t
// integration --package pdf_io`, 8.3 4-a) and only after INK T36 (03-ink 4.13 — the foundation
// rasterize always answers null, so these assertions fail by design until then).
@Tags(['integration'])
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/export/object_resolver.dart';
import 'package:pdf_io/src/export/raster_ports.dart';
import 'package:pdf_io/testing.dart';

core.MathObject _formula(String latex, core.PageRect rect) => core.MathObject(
  id: 'm-${latex.hashCode}',
  pageId: 'p1',
  frame: core.ElementFrame(rect),
  latex: latex,
  style: const core.MathStyle(fontSizePt: 18, colorArgb: 0xFF000000),
  createdAt: 1,
);

int _inked(PdfRgbaData data) {
  var n = 0;
  for (var i = 3; i < data.rgba.length; i += 4) {
    if (data.rgba[i] > 0) n++;
  }
  return n;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ink.InkFonts.ensureLoaded();
  });

  group(
    'InkMathRasterizer (real INK)',
    () {
      const port = InkMathRasterizer();

      test(
        '300 dpi of the laid-out size, ink drawn, transparent around it',
        () async {
          final formula = _formula(
            r'\frac{a+b}{c}',
            const core.PageRect(0, 0, 200, 100),
          );
          final layout = port.layoutSize(formula)!;
          final k = cappedPixelsPerPt(PdfTuning.mathRasterDpi / 72, layout);
          final data = await port.rasterize(formula, pixelsPerPt: k);
          expect(data, isNotNull);
          final want = rasterPixelSize(layout, k);
          expect(data!.width, closeTo(want.width, 1));
          expect(data.height, closeTo(want.height, 1));
          expect(_inked(data), greaterThan(0));
          expect(_inked(data), lessThan(data.width * data.height));
        },
      );

      test(
        'a big formula frame (700 × 700 pt) through the resolver → ≤ 4 Mpx',
        () async {
          final formula = _formula(
            r'\sum_{k=1}^{n} k^2',
            const core.PageRect(0, 0, 700, 700),
          );
          final resolver = ObjectResolver(gateway: FakePdfNoteGateway());
          final items = await resolver.resolve(
            PdfMathRef(formula),
            ResolveContext(),
          );
          final data = (items.single as PdfImageItem).image as PdfRgbaData;
          expect(
            data.width * data.height,
            lessThanOrEqualTo(PdfTuning.maxRasterPixels),
          );
          expect(_inked(data), greaterThan(0));
          resolver.dispose();
        },
      );

      test(
        r'a root (\sqrt) waits for its glyph picture — not null, ink drawn',
        () async {
          final formula = _formula(
            r'\sqrt{x^2+1}',
            const core.PageRect(0, 0, 160, 60),
          );
          final layout = port.layoutSize(formula)!;
          final data = await port.rasterize(
            formula,
            pixelsPerPt: cappedPixelsPerPt(
              PdfTuning.mathRasterDpi / 72,
              layout,
            ),
          );
          expect(data, isNotNull);
          expect(_inked(data!), greaterThan(0));
          // the radical sign spans the left part of the raster: some ink in the left fifth
          var left = 0;
          for (var y = 0; y < data.height; y++) {
            for (var x = 0; x < data.width ~/ 5; x++) {
              if (data.rgba[(y * data.width + x) * 4 + 3] > 0) left++;
            }
          }
          expect(left, greaterThan(0));
        },
      );

      test(
        'an invalid formula → layout null → left out with a warning',
        () async {
          final resolver = ObjectResolver(gateway: FakePdfNoteGateway());
          final ctx = ResolveContext();
          final formula = _formula(
            r'\frac{a',
            const core.PageRect(0, 0, 100, 50),
          );
          expect(await resolver.resolve(PdfMathRef(formula), ctx), isEmpty);
          expect(ctx.warnings.single, isA<PdfExportSkippedFormulas>());
        },
      );
    },
    skip: 'INK T36 이정표 뒤 켬 — 실제 InkMathRenderer.rasterize (03-ink 4.13), 통합 단계 4-a',
  );
}
