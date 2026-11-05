// T20 (03-ink 6.17, 4.9, EDITOR 5.3 #15/#16): the page panel thumbnail —
// strokes rasterized once per revision (not again on rebuilds or another
// width), the builder of the passed list (PDF) with isThumbnail: true and
// ancestorScale 1, and the preview form: a content with no strokes and
// revision 0 shows a new background / size on the next frame with no stroke
// raster, two cells of one pageId keeping their own backgrounds.
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/thumbnail.dart'
    show inkThumbnailRasterCount;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/pixels.dart';
import '../support/thumbnails.dart';

final _key = GlobalKey(debugLabel: 'thumbs');

final class _Recording implements PageBackgroundLayerBuilder {
  _Recording(this.kind, this.colorArgb);
  final InkBackgroundKind kind;
  final int colorArgb;
  final List<PageBackgroundContext> contexts = [];

  @override
  bool handles(InkBackgroundSpec background) => background.kind == kind;

  @override
  Widget build(BuildContext context, PageBackgroundContext ctx) {
    contexts.add(ctx);
    return SizedBox(
      width: ctx.pageSize.width * ctx.viewScale,
      height: ctx.pageSize.height * ctx.viewScale,
      child: ColoredBox(color: Color(colorArgb)),
    );
  }
}

Widget _app(List<Widget> cells) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: RepaintBoundary(
      key: _key,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: cells,
      ),
    ),
  ),
);

Future<Pixels> _shot(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      return Pixels(image.width, image.height, (await image.toByteData())!);
    } finally {
      image.dispose();
    }
  }))!;
}

core.Stroke _stroke(String id) => strokeThrough(
  segment(const ui.Offset(60, 300), const ui.Offset(540, 300)),
  core.StrokeStyle.defaultsFor(core.PenTool.marker)
      .copyWith(width: 40, colorArgb: 0xFF000000),
  id: id,
);

void main() {
  testWidgets('strokes are rasterized once per revision', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 600);
    addTearDown(tester.view.reset);
    final strokes = [_stroke('a')];
    Widget thumb(int revision, {double width = 120}) => _app([
      InkPageThumbnail(
        content: SyntheticInk.pageContent(strokes: strokes, revision: revision),
        width: width,
        backgroundBuilders: const [TemplateBackgroundLayerBuilder()],
      ),
    ]);
    final start = inkThumbnailRasterCount;
    await tester.pumpWidget(thumb(1));
    await settleThumbnails(tester);
    expect(inkThumbnailRasterCount - start, 1);
    final px = await _shot(tester);
    final y = (300 * 120 / core.PageSize.a4Portrait.width).round();
    expect(px.at(60, y).take(3), everyElement(lessThan(60)), reason: 'ink');
    expect(px.at(60, 5), [255, 255, 255, 255], reason: 'paper');

    await tester.pumpWidget(thumb(1));
    await tester.pumpWidget(thumb(1, width: 140));
    await settleThumbnails(tester);
    expect(inkThumbnailRasterCount - start, 1, reason: 'same revision');

    await tester.pumpWidget(thumb(2, width: 140));
    await settleThumbnails(tester);
    expect(inkThumbnailRasterCount - start, 2, reason: 'new revision');
    // the image stays while the next one is on its way
    await tester.pumpWidget(thumb(3, width: 140));
    final during = await _shot(tester);
    final y2 = (300 * 140 / core.PageSize.a4Portrait.width).round();
    expect(during.at(70, y2).take(3), everyElement(lessThan(60)));
    await settleThumbnails(tester);
    expect(inkThumbnailRasterCount - start, 3);
  });

  testWidgets('the listed builder draws the background: isThumbnail, '
      'ancestorScale 1, small viewScale (PDF builder)', (tester) async {
    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = const Size(800, 600);
    addTearDown(tester.view.reset);
    final pdf = _Recording(InkBackgroundKind.pdf, 0xFF2266AA);
    final content = SyntheticInk.pageContent(
      background: const core.PdfBackground(assetId: 'x', pdfPageIndex: 0),
    );
    await tester.pumpWidget(
      _app([
        InkPageThumbnail(
          content: content,
          width: 100,
          backgroundBuilders: [pdf, const TemplateBackgroundLayerBuilder()],
        ),
      ]),
    );
    expect(pdf.contexts, isNotEmpty);
    final ctx = pdf.contexts.last;
    expect(ctx.isThumbnail, isTrue);
    expect(ctx.ancestorScale, 1);
    expect(ctx.viewScale, closeTo(100 / content.pageSize.width, 1e-12));
    expect(ctx.devicePixelRatio, 2);
    expect(ctx.pageId, 'p1');
    final px = await _shot(tester);
    expect(px.at(10, 10), [0x22, 0x66, 0xAA, 255]);
  });

  testWidgets('preview form: background and size change on the next frame, '
      'no stroke raster; two cells of one pageId keep their own', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 600);
    addTearDown(tester.view.reset);
    final page = SyntheticInk.page();
    InkPageContent preview(core.PageSize size, int paper) =>
        InkPageContent.fromCore(
          page: page.copyWith(
            size: size,
            background: core.BlankBackground(paperColorArgb: paper),
          ),
          strokes: const [],
          revision: 0,
        );
    Widget cells(InkPageContent a, InkPageContent b) => _app([
      InkPageThumbnail(
        content: a,
        width: 100,
        backgroundBuilders: const [TemplateBackgroundLayerBuilder()],
      ),
      InkPageThumbnail(
        content: b,
        width: 100,
        backgroundBuilders: const [TemplateBackgroundLayerBuilder()],
      ),
    ]);
    final start = inkThumbnailRasterCount;
    await tester.pumpWidget(
      cells(
        preview(core.PageSize.a4Portrait, core.PaperColors.white),
        preview(core.PageSize.a4Portrait, core.PaperColors.black),
      ),
    );
    var px = await _shot(tester);
    expect(px.at(50, 50), [255, 255, 255, 255]);
    expect(px.at(150, 50).take(3), everyElement(lessThan(40)));
    final a4Height = tester.getSize(find.byType(InkPageThumbnail).first).height;

    // the first cell turns landscape and black, revision still 0
    await tester.pumpWidget(
      cells(
        preview(core.PageSize.a4Portrait.landscape, core.PaperColors.black),
        preview(core.PageSize.a4Portrait, core.PaperColors.white),
      ),
    );
    final size = tester.getSize(find.byType(InkPageThumbnail).first);
    expect(size.width, 100);
    expect(size.height, lessThan(a4Height));
    expect(
      size.height,
      closeTo(100 * 595.2756 / 841.8898, 1e-6),
      reason: 'landscape aspect',
    );
    px = await _shot(tester);
    expect(px.at(50, 20).take(3), everyElement(lessThan(40)));
    expect(px.at(150, 20), [255, 255, 255, 255]);
    expect(inkThumbnailRasterCount - start, 0, reason: 'no strokes');
  });

  testWidgets('a pencil thumbnail made before the grain is ready is made '
      'again once it is', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 600);
    addTearDown(tester.view.reset);
    final grain = PencilGrain();
    addTearDown(grain.dispose);
    final pencil = strokeThrough(
      segment(const ui.Offset(60, 300), const ui.Offset(540, 300)),
      core.StrokeStyle.defaultsFor(core.PenTool.pencil).copyWith(width: 40),
      id: 'pc',
    );
    final start = inkThumbnailRasterCount;
    await tester.pumpWidget(
      _app([
        InkPageThumbnail(
          content: SyntheticInk.pageContent(strokes: [pencil]),
          width: 200,
          backgroundBuilders: const [TemplateBackgroundLayerBuilder()],
          pencilGrain: grain,
        ),
      ]),
    );
    expect(grain.value, isNull, reason: 'not ready in the first frame');
    for (var i = 0; i < 500 && grain.value == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump();
    }
    expect(grain.value, isNotNull);
    await settleThumbnails(tester);
    await settleThumbnails(tester);
    expect(inkThumbnailRasterCount - start, 2, reason: 'again with grain');
  });
}
