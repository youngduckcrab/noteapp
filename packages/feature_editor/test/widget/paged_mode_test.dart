// E-18: the horizontal page flip mode (04-editor 6.3.4 gesture end ③,
// EDITOR-S8, contract 7.8): pages side by side, one page centred at its fit
// scale; a fast finger swipe flips to the next / previous page, a slow one
// snaps to the page nearest the centre; zoomed in there is no snap (pan and
// fling as usual); switching the mode keeps the current page; navigateToPage
// and PageDown flip too. Finger input goes PointerDriver → InputRouter →
// InteractionHost → ViewportController (pen-only mode, so fingers navigate).
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/viewport/page_layout.dart';
import 'package:feature_editor/src/viewport/viewport_constants.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_editor.dart';

const _paged = EditorSettings(
  inputMode: InputMode.penOnly,
  pageFlipMode: PageFlipMode.horizontalPaged,
);

/// Lets snaps (280 ms), animations (250 ms) and the 150 ms settle finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Page [index] is centred in the page area (paged mode at fit).
void _expectCentred(EditorTestHandles h, int index) {
  final rect = h.viewport.pageRectOnScreen(index);
  final centre = h.viewport.viewportSize.center(Offset.zero);
  expect(rect.center.dx, closeTo(centre.dx, 0.5), reason: 'x of page $index');
  expect(rect.center.dy, closeTo(centre.dy, 0.5), reason: 'y of page $index');
}

/// Global centre of the page area.
Offset _areaCentre(EditorTestHandles h) =>
    h.viewportOrigin + h.viewport.viewportSize.center(Offset.zero);

/// A finger drag of [dx] px (negative = to the left) through the area centre.
Future<void> _swipe(
  EditorTestHandles h,
  double dx, {
  required bool fast,
}) async {
  final from = _areaCentre(h) - Offset(dx / 2, 0);
  await h.driver.fingerDrag(
    from,
    from + Offset(dx, 0),
    // fast: 10 moves 8 ms apart (thousands of px/s); slow: 40 moves 60 ms
    // apart (well under the 300 px/s flip speed).
    steps: fast ? 10 : 40,
    interval: Duration(milliseconds: fast ? 8 : 60),
  );
}

void main() {
  testWidgets('pages side by side, the first one centred at its fit scale', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 4, settings: _paged);
    final v = h.viewport;
    expect(v.axis, LayoutAxis.horizontal);
    expect(v.layout.axis, LayoutAxis.horizontal);
    for (var i = 1; i < 4; i++) {
      final prev = v.layout.rectOf(i - 1);
      final rect = v.layout.rectOf(i);
      expect(rect.left, closeTo(prev.right + ViewportConstants.pageGap, 1e-9));
      expect(rect.top, prev.top);
    }
    // Fit = the whole page inside the area (24 px margins), zoom 1.
    final page = v.layout.rectOf(0);
    final size = v.viewportSize;
    const m = ViewportConstants.sideMargin;
    final fit = [
      (size.width - 2 * m) / page.width,
      (size.height - 2 * m) / page.height,
    ].reduce((a, b) => a < b ? a : b);
    expect(v.camera.scale, closeTo(fit, 1e-9));
    expect(v.zoom, closeTo(1, 1e-9));
    expect(v.currentPageIndex.value, 0);
    _expectCentred(h, 0);
    // Mounted: the visible pages ±1 (page 1's edge shows beside page 0).
    final range = v.mountedRange!;
    expect(range.first, 0);
    expect(range.last, lessThan(3));
    expect(h.mountedPages.all.map((m) => m.pageId).toSet(), {
      for (var i = range.first; i <= range.last; i++) h.pageId(i),
    });
  });

  testWidgets('a fast swipe flips to the next page, then back', (tester) async {
    final h = await pumpEditor(tester, pages: 4, settings: _paged);
    await _swipe(h, -200, fast: true);
    await _settle(tester);
    expect(h.viewport.currentPageIndex.value, 1);
    expect(h.viewport.zoom, closeTo(1, 1e-9));
    _expectCentred(h, 1);

    await _swipe(h, -200, fast: true);
    await _settle(tester);
    expect(h.viewport.currentPageIndex.value, 2);
    _expectCentred(h, 2);

    await _swipe(h, 200, fast: true); // to the right → previous page
    await _settle(tester);
    expect(h.viewport.currentPageIndex.value, 1);
    _expectCentred(h, 1);
    expect(h.viewport.isInteracting.value, isFalse);
  });

  testWidgets('a fast swipe flips one page only, and not past the ends', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 3, settings: _paged);
    await _swipe(h, 200, fast: true); // previous of the first page
    await _settle(tester);
    expect(h.viewport.currentPageIndex.value, 0);
    _expectCentred(h, 0);

    await _swipe(h, -700, fast: true); // a long fast swipe: still one page
    await _settle(tester);
    expect(h.viewport.currentPageIndex.value, 1);
    _expectCentred(h, 1);

    await _swipe(h, -200, fast: true);
    await _settle(tester);
    await _swipe(h, -200, fast: true); // next of the last page
    await _settle(tester);
    expect(h.viewport.currentPageIndex.value, 2);
    _expectCentred(h, 2);
  });

  testWidgets('a slow drag snaps to the page nearest the centre', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 4, settings: _paged);
    final pageWidth = h.viewport.pageRectOnScreen(0).width;

    // Less than half a page: back to the same page.
    await _swipe(h, -pageWidth * 0.3, fast: false);
    await _settle(tester);
    expect(h.viewport.currentPageIndex.value, 0);
    _expectCentred(h, 0);

    // More than half a page (plus the gap): the next page is nearer.
    await _swipe(h, -pageWidth * 0.7, fast: false);
    await _settle(tester);
    expect(h.viewport.currentPageIndex.value, 1);
    _expectCentred(h, 1);
  });

  testWidgets('zoomed in: no page snap, the swipe pans (and flings)', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 4, settings: _paged);
    final v = h.viewport
      ..zoomBy(2, h.viewport.viewportSize.center(Offset.zero))
      ..settleNow();
    await tester.pump();
    expect(v.zoom, closeTo(2, 1e-9));
    final before = v.camera.origin;

    await _swipe(h, -200, fast: true);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100)); // fling ends
    }
    expect(v.zoom, closeTo(2, 1e-9)); // a snap would go back to zoom 1
    expect(v.camera.origin.dx, greaterThan(before.dx + 200 / v.camera.scale));
    expect(v.isAnimating, isFalse);
    expect(v.isInteracting.value, isFalse);

    // A slow drag at 200 %: moves exactly with the finger (no snap either).
    final settled = v.camera.origin;
    await _swipe(h, -100, fast: false);
    await _settle(tester);
    expect(v.zoom, closeTo(2, 1e-9));
    expect(v.camera.origin.dx, greaterThan(settled.dx));
  });

  testWidgets('switching the mode keeps the current page', (tester) async {
    final h = await pumpEditor(
      tester,
      pages: 5,
      settings: const EditorSettings(inputMode: InputMode.penOnly),
    );
    final v = h.viewport;
    final commands = h.container.read(editorCommandsProvider);
    await v.jumpToPage(3, animate: false);
    await tester.pump();
    expect(v.axis, LayoutAxis.vertical);
    expect(v.currentPageIndex.value, 3);

    commands.setPageFlipMode(PageFlipMode.horizontalPaged);
    await tester.pump();
    expect(v.axis, LayoutAxis.horizontal);
    expect(v.currentPageIndex.value, 3);
    expect(v.zoom, closeTo(1, 1e-9));
    _expectCentred(h, 3);
    expect(
      h.container.read(editorSettingsProvider).pageFlipMode,
      PageFlipMode.horizontalPaged,
    );

    await _swipe(h, -200, fast: true);
    await _settle(tester);
    expect(v.currentPageIndex.value, 4);

    commands.setPageFlipMode(PageFlipMode.verticalScroll);
    await tester.pump();
    expect(v.axis, LayoutAxis.vertical);
    expect(v.currentPageIndex.value, 4);
    expect(v.zoom, closeTo(1, 1e-9));
    // Vertical: the page top just under the area top (half a gap above).
    expect(
      v.pageRectOnScreen(4).top,
      closeTo(ViewportConstants.pageGap / 2 * v.camera.scale, 0.5),
    );
    await _settle(tester);
  });

  testWidgets('a new viewport size keeps the current page centred', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 4, settings: _paged);
    await _swipe(h, -200, fast: true);
    await _settle(tester);
    expect(h.viewport.currentPageIndex.value, 1);

    // Rotate to landscape (1376×1032).
    tester.view.physicalSize = const Size(1376, 1032) * 2;
    await tester.pump();
    await tester.pump();
    await _settle(tester);
    expect(h.viewport.viewportSize.width, 1376);
    expect(h.viewport.currentPageIndex.value, 1);
    expect(h.viewport.zoom, closeTo(1, 1e-9));
    _expectCentred(h, 1);
  });

  testWidgets('navigateToPage and PageDown / PageUp flip pages', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 5, settings: _paged);
    final commands = h.container.read(editorCommandsProvider);

    commands.navigateToPage(h.pageId(3), null);
    await _settle(tester);
    expect(h.viewport.currentPageIndex.value, 3);
    _expectCentred(h, 3);

    // Canvas focus (a pointer down on the page area focuses it — E-12).
    await h.driver.multiTap([_areaCentre(h)]);
    await _settle(tester);
    expect(h.viewport.currentPageIndex.value, 3);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await _settle(tester);
    expect(h.viewport.currentPageIndex.value, 4);
    _expectCentred(h, 4);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await _settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await _settle(tester);
    expect(h.viewport.currentPageIndex.value, 2);
    _expectCentred(h, 2);
  });
}
