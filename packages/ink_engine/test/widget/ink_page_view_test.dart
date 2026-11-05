// T10 (03-ink 8, 4.9, 6.12): InkPageView paints the content strokes from the
// chunk pictures (layer order: background → highlighter → ink), maps page pt
// uniformly (viewScale = width / page width), clips to the page, and a stroke
// over a chunk border is painted exactly once.
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkChunkCacheOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/page_view.dart';
import '../support/pixels.dart';

const _white = [255, 255, 255, 255];

core.StrokeStyle _pen(int argb, {double width = 6, double opacity = 1}) =>
    core.StrokeStyle.defaultsFor(core.PenTool.marker)
        .copyWith(colorArgb: argb, width: width, opacity: opacity);

void main() {
  late InkPageController controller;
  final page = core.PageSize.a4Portrait;

  setUp(() => controller = createTestPageController());
  tearDown(() => controller.dispose());

  testWidgets('content strokes are visible, scaled by viewScale', (
    tester,
  ) async {
    controller.updateContent(
      SyntheticInk.pageContent(
        strokes: [
          strokeThrough(
            segment(const Offset(50, 100), const Offset(250, 100)),
            _pen(0xFF0000FF),
            id: 'blue',
          ),
        ],
      ),
    );
    // width = 2 × page width → viewScale 2
    await pumpPageView(
      tester,
      controller,
      width: page.width * 2,
      surface: const Size(1300, 1800),
    );
    final px = await capturePixels(tester);
    expect(px.width, (page.width * 2).ceil());
    expect(px.height, (page.height * 2).ceil());
    expect(px.at(300, 200), [0, 0, 255, 255], reason: '(150, 100) pt');
    expect(px.at(300, 220), _white, reason: '10 pt below: paper');
    expect(px.at(80, 200), _white, reason: 'left of the stroke');
    expect(inkChunkCacheOf(controller).dirtyCount, 0, reason: 'recorded');
  });

  testWidgets('ink is painted above highlighters, both above the paper', (
    tester,
  ) async {
    controller.updateContent(
      SyntheticInk.pageContent(
        strokes: [
          strokeThrough(
            segment(const Offset(100, 50), const Offset(100, 250)),
            _pen(0xFF000000, width: 4),
            id: 'ink',
          ),
          strokeThrough(
            segment(const Offset(40, 150), const Offset(200, 150)),
            core.StrokeStyle.defaultsFor(core.PenTool.highlighter),
            id: 'hl', // drawn later, still below the ink
          ),
        ],
        background: const core.TemplateBackground(
          template: core.PageTemplate(kind: core.PageTemplateKind.grid),
        ),
      ),
    );
    await pumpPageView(tester, controller, width: page.width);
    final px = await capturePixels(tester);
    expect(px.at(100, 150), [0, 0, 0, 255], reason: 'ink over highlighter');
    final hl = px.at(60, 150);
    expect(hl, isNot(_white));
    expect(hl[2], lessThan(200), reason: 'yellow-ish highlighter');
  });

  testWidgets('strokes outside the page are clipped', (tester) async {
    controller.updateContent(
      SyntheticInk.pageContent(
        strokes: [
          strokeThrough(
            segment(Offset(page.width - 50, 300), Offset(page.width + 80, 300)),
            _pen(0xFFFF0000),
            id: 'out',
          ),
        ],
      ),
    );
    const key = Key('surface');
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: const Color(0xFF00FF00),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: page.width,
                child: InkPageView(controller: controller),
              ),
            ),
          ),
        ),
      ),
    );
    final px = await capturePixels(tester, key: key);
    expect(px.at((page.width - 20).floor(), 300), [255, 0, 0, 255]);
    expect(px.at((page.width + 30).ceil(), 300), [0, 255, 0, 255]);
    expect(px.at(400, page.height.ceil() + 5), [0, 255, 0, 255]);
  });

  testWidgets('a semi-transparent stroke over a chunk border: painted once', (
    tester,
  ) async {
    // 256 pt chunks (nativeDefaults): x = 256 is a border at viewScale 1
    final style = _pen(0xFF000000, width: 8, opacity: 0.5);
    controller.updateContent(
      SyntheticInk.pageContent(
        strokes: [
          strokeThrough(
            segment(const Offset(150, 200), const Offset(400, 200)),
            style,
            id: 'across',
          ),
          strokeThrough(
            segment(const Offset(200, 250.3), const Offset(300, 250.3)),
            style,
            id: 'fractional',
          ),
        ],
      ),
    );
    // viewScale 1.37: the border falls inside a device pixel
    await pumpPageView(
      tester,
      controller,
      width: page.width * 1.37,
      surface: const Size(900, 1200),
    );
    final px = await capturePixels(tester);
    final single = px.at((180 * 1.37).round(), (200 * 1.37).round());
    expect(single, isNot(_white));
    expect(single[0], greaterThan(60), reason: 'semi-transparent');
    final border = (256 * 1.37).floor();
    for (var x = border - 2; x <= border + 2; x++) {
      expect(
        samePixel(px.at(x, (200 * 1.37).round()), single, tol: 2),
        isTrue,
        reason: 'column $x: no seam, no double paint',
      );
      expect(
        samePixel(px.at(x, (250.3 * 1.37).round()), single, tol: 2),
        isTrue,
        reason: 'column $x (second stroke)',
      );
    }
  });

  testWidgets('no content → nothing painted, no exception', (tester) async {
    await pumpPageView(tester, controller, width: page.width);
    expect(tester.takeException(), isNull);
    expect(find.byType(InkPageView), findsOneWidget);
    expect(
      tester.getSize(find.byType(InkPageView)).height,
      0,
      reason: 'empty until updateContent',
    );
    controller.updateContent(SyntheticInk.pageContent());
    await tester.pump();
    expect(
      tester.getSize(find.byType(InkPageView)).height,
      closeTo(page.height, 0.01),
    );
  });

  test('InkPageGeometry maps page pt and local px uniformly', () {
    const view = ui.Size(1190.56, 1683.78);
    final p = InkPageGeometry.pageToLocal(
      const ui.Offset(100, 200),
      view,
      ui.Size(page.width, page.height),
    );
    expect(p.dx, closeTo(200, 0.01));
    expect(p.dy, closeTo(400, 0.01));
    expect(
      InkPageGeometry.localToPage(p, view, ui.Size(page.width, page.height)),
      within(distance: 1e-9, from: const ui.Offset(100, 200)),
    );
    expect(
      InkPageGeometry.viewScaleOf(view, ui.Size(page.width, page.height)),
      closeTo(2, 1e-3),
    );
  });
}
