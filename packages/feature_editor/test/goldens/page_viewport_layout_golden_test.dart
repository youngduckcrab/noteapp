// E-22: the page area as EDITOR lays it out (04-editor 6.3, 6.4.3): page
// rectangles at their layout positions (24 pt gaps and margins, fit width,
// trailing space for '+ 페이지'), the page area background, the page
// indicator and (v2.14-ui) the end-of-document hint. INK's output is fixed to a flat white
// page (SolidBackgroundBuilder, empty pages — 9.1), so only EDITOR's
// placement is compared. The image is the PageViewport rectangle cut from its
// nearest repaint boundary (the toolbar and preset bar above it are left out).
// Text is the test font's boxes (contract 7.4.8: Ahem-like font only); the
// developer overlay and the page panel are off.
@Tags(['golden'])
@TestOn('vm')
library;

import 'dart:ui' as ui;

import 'package:feature_editor/src/viewport/page_viewport.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';

/// INK output fixed to one flat colour (9.1 golden rule).
final _flatPages = ink.pageBackgroundBuildersProvider.overrideWithValue(const [
  ink_testing.SolidBackgroundBuilder(
    kind: ink.InkBackgroundKind.blank,
    colorArgb: 0xFFFFFFFF,
  ),
]);

const _portrait = Size(1032, 1376);
const _landscape = Size(1376, 1032);

/// The PageViewport rectangle, captured from its nearest repaint boundary's
/// layer at 1 image pixel per logical pixel.
Future<ui.Image> _pageArea(WidgetTester tester) async {
  final box = tester.renderObject<RenderBox>(find.byType(PageViewport));
  RenderObject boundary = box;
  while (!boundary.isRepaintBoundary) {
    boundary = boundary.parent!;
  }
  final topLeft = MatrixUtils.transformPoint(
    box.getTransformTo(boundary),
    Offset.zero,
  );
  final layer = boundary.debugLayer! as OffsetLayer;
  final image = await tester.runAsync(() => layer.toImage(topLeft & box.size));
  return image!;
}

Future<EditorTestHandles> _open(
  WidgetTester tester, {
  Size logicalSize = _portrait,
}) => pumpEditor(tester, logicalSize: logicalSize, overrides: [_flatPages]);

/// Lets the camera change reach the pages, the indicator and the button.
Future<void> _settle(WidgetTester tester, EditorTestHandles h) async {
  h.viewport.settleNow();
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('portrait, three A4 pages at fit width, top of the note', (
    tester,
  ) async {
    await _open(tester);
    await expectLater(
      await _pageArea(tester),
      matchesGoldenFile('page_viewport_portrait.png'),
    );
  });

  testWidgets('portrait, end of the note: last page and the end hint', (
    tester,
  ) async {
    final h = await _open(tester);
    await h.viewport.jumpToPage(2, animate: false);
    h.viewport.panBy(const Offset(0, 100000)); // stops at the end
    await _settle(tester, h);
    expect(h.viewport.currentPageIndex.value, 2);
    await expectLater(
      await _pageArea(tester),
      matchesGoldenFile('page_viewport_portrait_end.png'),
    );
  });

  testWidgets('portrait at 200 %: pages wider than the screen are clipped', (
    tester,
  ) async {
    final h = await _open(tester);
    h.viewport.zoomBy(2, Offset(h.viewport.viewportSize.width / 2, 0));
    await _settle(tester, h);
    expect(h.viewport.zoom, closeTo(2, 1e-9));
    await expectLater(
      await _pageArea(tester),
      matchesGoldenFile('page_viewport_zoom_200.png'),
    );
  });

  testWidgets('landscape screen, top of the note at fit width', (tester) async {
    await _open(tester, logicalSize: _landscape);
    await expectLater(
      await _pageArea(tester),
      matchesGoldenFile('page_viewport_landscape.png'),
    );
  });

  testWidgets('mixed sizes: an A4 landscape page between portrait pages', (
    tester,
  ) async {
    final h = await _open(tester);
    h.session.execute(
      core.ResizePages(
        pageIds: [h.pageId(1)],
        size: core.PageSize.a4Portrait.landscape,
      ),
    );
    await tester.pump();
    expect(h.viewport.pages[1].size, core.PageSize.a4Portrait.landscape);
    // Page 1 in the middle: the end of page 0 above, page 2 below.
    await h.viewport.jumpToPage(1, animate: false);
    h.viewport.panBy(const Offset(0, -300));
    await _settle(tester, h);
    await expectLater(
      await _pageArea(tester),
      matchesGoldenFile('page_viewport_mixed_sizes.png'),
    );
  });
}
