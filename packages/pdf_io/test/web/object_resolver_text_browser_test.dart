@TestOn('browser')
library;

// PDF T25b — the text box resolver under CanvasKit (m5-7/06-pdf 6.2.4 · 6.2.5, 9.2): the default
// InkTextRasterizer (InkTextLayout.rasterize — the test font, C23-07) gives a non-empty raster of
// the asked size ≤ 4 Mpx, the resolver's text object path reads the font once, and the formula
// path (fake port — no KaTeX load) keeps the cap rule in dart2js numbers.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/testing.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/export/object_resolver.dart';
import 'package:pdf_io/src/export/raster_ports.dart';
import 'package:pdf_io/testing.dart';

import '../support/fake_rasterizers.dart';

const double dpi300 = 300 / 72;

core.TextBoxObject _box(core.PageRect rect, {String text = '안녕 hello'}) =>
    core.TextBoxObject(
      id: 'text-${rect.left}',
      pageId: 'p1',
      frame: core.ElementFrame(rect),
      text: text,
      style: const core.TextBoxStyle(fontSizePt: 18, colorArgb: 0xFF000000),
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
    await ink.useInkTestFonts();
  });

  test('default InkTextRasterizer: the asked size, ink drawn, transparent background', () async {
    final box = _box(const core.PageRect(0, 0, 120, 40));
    final data = await const InkTextRasterizer().rasterize(box, pixelsPerPt: 2);
    expect(data, isNotNull);
    expect((data!.width, data.height), (240, 80));
    expect(data.rgba.length, 240 * 80 * 4);
    final inked = _inked(data);
    expect(inked, greaterThan(0));
    expect(inked, lessThan(240 * 80 ~/ 2), reason: 'no box background');
  });

  test(
    'page-size box through the resolver: capped density, RGBA ≤ 4 Mpx',
    () async {
      final resolver = ObjectResolver(gateway: FakePdfNoteGateway());
      final ctx = ResolveContext(fontsReady: false); // → the raster path
      final box = _box(const core.PageRect(40, 60, 540, 760));
      final items = await resolver.resolve(PdfTextBoxRef(box, const []), ctx);
      final data = (items.single as PdfImageItem).image as PdfRgbaData;
      final k = cappedPixelsPerPt(dpi300, const ui.Size(500, 700));
      expect(k, closeTo(3.46, 0.005));
      final want = rasterPixelSize(const ui.Size(500, 700), k);
      expect((data.width, data.height), (want.width, want.height));
      expect(
        data.width * data.height,
        lessThanOrEqualTo(PdfTuning.maxRasterPixels),
      );
      expect(_inked(data), greaterThan(0));
      expect(ctx.warnings.single, isA<PdfExportRasterizedText>());
      expect(resolver.ledger.peakBytes, lessThanOrEqualTo(16 * 1024 * 1024));
      resolver.dispose();
    },
  );

  test(
    'text object path: the real NoteSans bytes read once, lines → text items',
    () async {
      final resolver = ObjectResolver(gateway: FakePdfNoteGateway());
      final ctx = ResolveContext();
      final box = _box(const core.PageRect(10, 10, 200, 60));
      const lines = <PdfTextLine>[
        (text: '안녕 hello', x: 0, baselineY: 18, width: 90),
      ];
      final items = await resolver.resolve(PdfTextBoxRef(box, lines), ctx);
      final item = items.single as PdfTextItem;
      expect(item.text, '안녕 hello');
      expect(item.fontId, PdfComposeOpcodes.fontRegular);
      expect(ctx.fontBytes[PdfComposeOpcodes.fontRegular], isNotEmpty);
      expect(ctx.warnings, isEmpty);
    },
  );

  test('formula (fake port): 700 × 700 pt → the cap rule, ≤ 4 Mpx', () async {
    final math = FakeMathRasterizer(defaultLayout: const ui.Size(700, 700));
    final resolver = ObjectResolver(gateway: FakePdfNoteGateway(), math: math);
    final formula = core.MathObject(
      id: 'm1',
      pageId: 'p1',
      frame: const core.ElementFrame(core.PageRect(0, 0, 700, 700)),
      latex: r'\frac{a}{b}',
      style: const core.MathStyle(),
      createdAt: 1,
    );
    final items = await resolver.resolve(PdfMathRef(formula), ResolveContext());
    final data = (items.single as PdfImageItem).image as PdfRgbaData;
    expect(math.calls.single.pixelsPerPt, closeTo(2.93, 0.01));
    expect(
      data.width * data.height,
      lessThanOrEqualTo(PdfTuning.maxRasterPixels),
    );
    resolver.dispose();
  });
}
