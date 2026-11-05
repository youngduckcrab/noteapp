// T13 (03-ink 8, 4.10, 6.17, contract 7.2.16 v1.1): background builder choice
// and the scale rule — InkPageView uses the first builder that handles the
// page background (SolidBackgroundBuilder for pdf), unsupported kinds fall
// back to the paper color, isThumbnail reaches the builder (false on the page
// view, true on InkPageThumbnail), and under InkPageView(ancestorScale: 2) the
// template widget is pageSize × viewScale (not × 2), the builder's
// ctx.deviceScale = viewScale × 2 × DPR and the minimum line width follows
// that deviceScale.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/background/template_painter.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/page_view.dart';

/// Records every context it builds with; paints [colorArgb].
final class _RecordingBuilder implements PageBackgroundLayerBuilder {
  _RecordingBuilder(this.kind);
  final InkBackgroundKind kind;
  final List<PageBackgroundContext> contexts = [];

  @override
  bool handles(InkBackgroundSpec background) => background.kind == kind;

  @override
  Widget build(BuildContext context, PageBackgroundContext ctx) {
    contexts.add(ctx);
    return SizedBox(
      width: ctx.pageSize.width * ctx.viewScale,
      height: ctx.pageSize.height * ctx.viewScale,
      child: const ColoredBox(color: Color(0xFF112233)),
    );
  }
}

const _pdf = core.PdfBackground(
  assetId: 'a',
  pdfPageIndex: 0,
  paperColorArgb: core.PaperColors.ivory,
);

List<int> _rgba(int argb) => [
  (argb ~/ 65536) % 256,
  (argb ~/ 256) % 256,
  argb % 256,
  255,
];

void main() {
  testWidgets('the first builder that handles the background draws it', (
    tester,
  ) async {
    final c = createTestPageController(
      backgroundBuilders: const [
        SolidBackgroundBuilder(colorArgb: 0xFF00AA00),
        TemplateBackgroundLayerBuilder(),
      ],
    )..updateContent(SyntheticInk.pageContent(background: _pdf));
    addTearDown(c.dispose);
    await pumpPageView(tester, c, width: 300);
    final px = await capturePixels(tester);
    expect(px.at(150, 200), [0, 0xAA, 0, 255]);
  });

  testWidgets('no builder handles it → the paper color (pdf, image)', (
    tester,
  ) async {
    for (final bg in <core.PageBackground>[
      _pdf,
      const core.ImageBackground(
        assetId: 'img',
        paperColorArgb: core.PaperColors.gray,
      ),
    ]) {
      final c = createTestPageController()
        ..updateContent(SyntheticInk.pageContent(background: bg));
      addTearDown(c.dispose);
      await pumpPageView(tester, c, width: 300);
      final px = await capturePixels(tester);
      expect(px.at(150, 200), _rgba(bg.paperColorArgb), reason: '$bg');
      expect(px.at(10, 10), _rgba(bg.paperColorArgb));
    }
  });

  testWidgets('isThumbnail: false on InkPageView, true on InkPageThumbnail', (
    tester,
  ) async {
    final builder = _RecordingBuilder(InkBackgroundKind.pdf);
    final c = createTestPageController(backgroundBuilders: [builder])
      ..updateContent(SyntheticInk.pageContent(background: _pdf));
    addTearDown(c.dispose);
    await pumpPageView(tester, c, width: 300);
    expect(builder.contexts, isNotEmpty);
    expect(builder.contexts.every((x) => !x.isThumbnail), isTrue);

    builder.contexts.clear();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: InkPageThumbnail(
            content: SyntheticInk.pageContent(background: _pdf),
            width: 120,
            backgroundBuilders: [builder],
          ),
        ),
      ),
    );
    expect(builder.contexts, isNotEmpty);
    final ctx = builder.contexts.last;
    expect(ctx.isThumbnail, isTrue);
    expect(ctx.ancestorScale, 1);
    expect(ctx.viewScale, closeTo(120 / 595.2756, 1e-9));
  });

  testWidgets('scale rule under InkPageView(ancestorScale: 2)', (tester) async {
    const width = 300.0, dpr = 2.0;
    final viewScale = width / 595.2756;
    // the recording builder sees the context values
    final builder = _RecordingBuilder(InkBackgroundKind.pdf);
    final pdfPage = createTestPageController(backgroundBuilders: [builder])
      ..updateContent(SyntheticInk.pageContent(background: _pdf));
    addTearDown(pdfPage.dispose);
    await pumpPageView(
      tester,
      pdfPage,
      width: width,
      devicePixelRatio: dpr,
      ancestorScale: 2,
    );
    final ctx = builder.contexts.last;
    expect(ctx.viewScale, closeTo(viewScale, 1e-12));
    expect(ctx.ancestorScale, 2);
    expect(ctx.devicePixelRatio, dpr);
    expect(ctx.deviceScale, closeTo(viewScale * 2 * dpr, 1e-12));

    // the template builder: widget = pageSize × viewScale, painter scale =
    // viewScale, minimum line width ≥ 1 device px of that deviceScale
    final lined = createTestPageController()
      ..updateContent(
        SyntheticInk.pageContent(
          background: core.TemplateBackground(
            template: core.PageTemplate.defaults(core.PageTemplateKind.lined),
          ),
        ),
      );
    addTearDown(lined.dispose);
    await pumpPageView(
      tester,
      lined,
      width: width,
      devicePixelRatio: dpr,
      ancestorScale: 2,
    );
    final paint = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is TemplatePainter,
    );
    expect(paint, findsOneWidget);
    expect(
      tester.getSize(paint),
      Size(width, 841.8898 * viewScale), // not × ancestorScale
    );
    final painter =
        tester.widget<CustomPaint>(paint).painter! as TemplatePainter;
    final deviceScale = viewScale * 2 * dpr;
    expect(painter.viewScale, closeTo(viewScale, 1e-12));
    expect(painter.deviceScale, closeTo(deviceScale, 1e-12));
    expect(painter.minLineWidthPt, greaterThanOrEqualTo(1 / deviceScale));
    expect(painter.minLineWidthPt, lessThan(1.1893 / deviceScale)); // 2^(1/4)
    // the lined template's 0.5 pt lines are below 1 device px at this scale
    // (0.5 · 2.016 < 1) → drawn at the minimum
    expect(0.5 * deviceScale, lessThan(1.02));
  });

  testWidgets('template lines are visible on the page view', (tester) async {
    final c = createTestPageController()
      ..updateContent(
        SyntheticInk.pageContent(
          background: core.TemplateBackground(
            template: core.PageTemplate.defaults(core.PageTemplateKind.lined),
          ),
        ),
      );
    addTearDown(c.dispose);
    await pumpPageView(tester, c, width: 595.2756); // viewScale 1
    final px = await capturePixels(tester);
    // ruled line at y = 72 + 24 = 96 (centred on the pixel row 95.75..96.25)
    final onLine = px.at(300, 96);
    expect(onLine, isNot([255, 255, 255, 255]));
    expect(px.at(300, 108), [255, 255, 255, 255]); // between lines
    expect(px.at(72, 30), isNot([255, 255, 255, 255])); // margin line
  });
}
