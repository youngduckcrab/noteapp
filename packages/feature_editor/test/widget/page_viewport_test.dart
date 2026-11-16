// E-04: PageViewport · EditorPageView · PageMount in the editor screen
// (04-editor 6.4). Fake store + B3 INK, iPad Pro 13" portrait.
//   - mounted pages = visible ±1, at most 8, while scrolling and zooming;
//     a page leaving the range is closed (openPage − closePage = 0, counted
//     by RecordingNoteSession — pageIfLoaded cannot show the pin because of
//     CORE's LRU) and its INK controller is disposed;
//   - a mounted page's controller.content.revision equals the session's;
//   - during a pinch InkPageView.isScaling is true and ancestorScale =
//     camera.scale / settledScale; EDITOR passes only InkPageView's three
//     arguments (no setViewport call: 6.16 ⑤ source check in
//     no_platform_imports_test);
//   - the loading cover shows until the page content is loaded.
import 'package:feature_editor/src/viewport/editor_page_view.dart';
import 'package:feature_editor/src/viewport/page_viewport.dart';
import 'package:feature_editor/src/viewport/viewport_constants.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

/// Page ids of the EditorPageViews in the tree, in page order.
List<String> _viewIds(WidgetTester tester) {
  final views = tester
      .widgetList<EditorPageView>(find.byType(EditorPageView))
      .toList();
  views.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
  return [for (final v in views) v.page.id];
}

/// visible ±1, clamped to the note (6.4.1 ①②), before the cap of 8.
List<String> _visiblePlusOne(EditorTestHandles h) {
  final visible = h.viewport.visibleRange!;
  final pages = h.session.pages;
  final first = visible.first == 0 ? 0 : visible.first - 1;
  final last = visible.last == pages.length - 1
      ? visible.last
      : visible.last + 1;
  return [for (var i = first; i <= last; i++) pages[i].id];
}

ink.InkPageView _inkViewOf(WidgetTester tester, String pageId) =>
    tester.widget<ink.InkPageView>(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is EditorPageView && w.page.id == pageId,
        ),
        matching: find.byType(ink.InkPageView),
      ),
    );

ProviderContainer _root(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

/// Every page is open exactly while it is mounted (after loads finished).
void _expectPinsMatchMounts(EditorTestHandles h, WidgetTester tester) {
  final recorder = h.recorder!;
  final mounted = _viewIds(tester).toSet();
  for (final page in h.session.pages) {
    final open =
        recorder.countOf('openPage:${page.id}') -
        recorder.countOf('closePage:${page.id}');
    expect(
      open,
      mounted.contains(page.id) ? 1 : 0,
      reason: 'pins of ${page.id}',
    );
  }
}

void main() {
  testWidgets('A4 × 50: mounted = visible ±1 (≤ 8) while scrolling', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 50);
    final viewport = h.viewport;
    expect(viewport.viewportSize.isEmpty, isFalse);
    expect(_viewIds(tester), [h.pageId(0), h.pageId(1)]);
    expect(h.mountedPages.pageIds.toSet(), _viewIds(tester).toSet());
    _expectPinsMatchMounts(h, tester);

    final firstController = h.controllerOf(0);
    final root = _root(tester);
    expect(root.exists(ink.inkPageControllerProvider(h.pageId(0))), isTrue);

    // Scroll down page by page (wheel direction: positive dy shows below).
    for (var step = 0; step < 12; step++) {
      viewport.panBy(Offset(0, viewport.viewportSize.height * 0.7));
      await h.settlePages();
      final ids = _viewIds(tester);
      expect(ids, _visiblePlusOne(h), reason: 'step $step');
      expect(ids.length, lessThanOrEqualTo(ViewportConstants.maxMountedPages));
      expect(h.mountedPages.pageIds.toSet(), ids.toSet());
      _expectPinsMatchMounts(h, tester);
    }
    expect(_viewIds(tester), isNot(contains(h.pageId(0))));

    // Page 0 left the range: closed once, its INK controller disposed.
    expect(h.recorder!.countOf('closePage:${h.pageId(0)}'), 1);
    expect(root.exists(ink.inkPageControllerProvider(h.pageId(0))), isFalse);
    expect(
      () => ChangeNotifier.debugAssertNotDisposed(firstController),
      throwsFlutterError,
    );

    // Jump far ahead, then zoom out as far as allowed.
    await viewport.jumpToPage(40, animate: false);
    await h.settlePages();
    expect(_viewIds(tester), _visiblePlusOne(h));
    viewport.zoomBy(0.01, viewport.viewportSize.center(Offset.zero));
    await tester.pump(ViewportConstants.settleDelay * 2);
    await h.settlePages();
    expect(viewport.zoom, closeTo(ViewportConstants.minZoom, 1e-9));
    final ids = _viewIds(tester);
    expect(ids, _visiblePlusOne(h));
    expect(ids.length, lessThanOrEqualTo(ViewportConstants.maxMountedPages));
    _expectPinsMatchMounts(h, tester);
  });

  testWidgets('short pages: at most 8 mounted, nearest the centre', (
    tester,
  ) async {
    final h = await pumpEditor(
      tester,
      pages: 50,
      pageSize: const core.PageSize(595.2756, 100),
    );
    final viewport = h.viewport;
    viewport.zoomBy(0.01, viewport.viewportSize.center(Offset.zero));
    await tester.pump(ViewportConstants.settleDelay * 2);
    await h.settlePages();

    expect(_visiblePlusOne(h).length, greaterThan(8));
    final range = viewport.mountedRange!;
    expect(_viewIds(tester), [
      for (var i = range.first; i <= range.last; i++) h.pageId(i),
    ]);
    expect(_viewIds(tester), hasLength(ViewportConstants.maxMountedPages));
    _expectPinsMatchMounts(h, tester);
  });

  testWidgets('pages sit at their screen rect; scrolling keeps the views', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 5);
    final viewport = h.viewport;

    void expectPlaced() {
      for (final id in _viewIds(tester)) {
        final index = h.session.pages.indexWhere((p) => p.id == id);
        final view = find.byWidgetPredicate(
          (w) => w is EditorPageView && w.page.id == id,
        );
        final topLeft = tester.getTopLeft(view);
        final bottomRight = tester.getBottomRight(view);
        // The page viewport starts below the app bar.
        final origin = tester.getTopLeft(find.byType(PageViewport));
        final expected = viewport.pageRectOnScreen(index).shift(origin);
        expect(topLeft.dx, closeTo(expected.left, 1e-6));
        expect(topLeft.dy, closeTo(expected.top, 1e-6));
        expect(bottomRight.dx, closeTo(expected.right, 1e-6));
        expect(bottomRight.dy, closeTo(expected.bottom, 1e-6));
      }
    }

    expectPlaced();
    final before = tester.widget<EditorPageView>(
      find.byWidgetPredicate(
        (w) => w is EditorPageView && w.page.id == h.pageId(1),
      ),
    );
    viewport.panBy(const Offset(0, 300));
    await tester.pump();
    expectPlaced();
    // Same (id, size, settledScale, index) → the same widget instance (6.4.3).
    final after = tester.widget<EditorPageView>(
      find.byWidgetPredicate(
        (w) => w is EditorPageView && w.page.id == h.pageId(1),
      ),
    );
    expect(identical(before, after), isTrue);
    await tester.pump(ViewportConstants.settleDelay * 2);
  });

  testWidgets('mounted content revision follows the session', (tester) async {
    final h = await pumpEditor(
      tester,
      strokesByPageIndex: {
        0: [strokeA, strokeB],
      },
    );
    void expectRevisions() {
      for (final id in _viewIds(tester)) {
        final index = h.session.pages.indexWhere((p) => p.id == id);
        final content = h.controllerOf(index).content!;
        expect(content.revision, h.session.pageIfLoaded(id)!.revision);
        expect(
          content.strokes.map((s) => s.id),
          h.session.pageIfLoaded(id)!.strokes.map((s) => s.id),
        );
        expect(_inkViewOf(tester, id).controller, same(h.controllerOf(index)));
      }
    }

    expectRevisions();
    expect(h.controllerOf(0).content!.strokes, hasLength(2));

    h.session.execute(
      core.AddStrokes(
        pageId: h.pageId(0),
        strokes: [
          lineStroke(
            id: 'added',
            pageId: h.pageId(0),
            x0: 50,
            y0: 600,
            x1: 400,
            y1: 600,
          ),
        ],
      ),
    );
    await tester.pump();
    expectRevisions();
    expect(h.controllerOf(0).content!.strokes, hasLength(3));
    expect(h.recorder!.executeDuringDelivery, isFalse);
  });

  testWidgets('pinch: isScaling and ancestorScale, then settled', (
    tester,
  ) async {
    final h = await pumpEditor(tester);
    final viewport = h.viewport;
    final id = h.pageId(0);
    final fit = viewport.camera.scale;

    var view = _inkViewOf(tester, id);
    expect(view.isScaling, isFalse);
    expect(view.ancestorScale, 1);

    final centre = viewport.viewportSize.center(Offset.zero);
    viewport
      ..beginGesture()
      ..updateGesture(
        baselineFocal: centre,
        focal: centre,
        scaleRatio: 1.5,
        rebased: false,
      );
    await tester.pump();
    view = _inkViewOf(tester, id);
    expect(viewport.settledScale.value, fit);
    expect(view.isScaling, isTrue);
    expect(view.ancestorScale, closeTo(1.5, 1e-9));
    expect(
      view.ancestorScale,
      closeTo(viewport.camera.scale / viewport.settledScale.value, 1e-12),
    );
    // The pinch preview scales the laid-out page: its screen size follows
    // the live camera.
    final pageView = find.byWidgetPredicate(
      (w) => w is EditorPageView && w.page.id == id,
    );
    expect(
      tester.getSize(pageView).width,
      closeTo(kA4.width * fit, 1e-6),
    ); // layout size
    expect(
      tester.getBottomRight(pageView).dx - tester.getTopLeft(pageView).dx,
      closeTo(kA4.width * fit * 1.5, 1e-6),
    );

    viewport.endGesture(Velocity.zero);
    await tester.pump(ViewportConstants.settleDelay * 2);
    await tester.pump();
    view = _inkViewOf(tester, id);
    expect(viewport.isInteracting.value, isFalse);
    expect(viewport.settledScale.value, viewport.camera.scale);
    expect(view.isScaling, isFalse);
    expect(view.ancestorScale, 1);
    expect(
      tester.getSize(pageView).width,
      closeTo(kA4.width * fit * 1.5, 1e-6),
    );
  });

  testWidgets('(v2.13-perf) pan and fling at the same scale: interacting, '
      'but InkPageView.isScaling stays false', (tester) async {
    final h = await pumpEditor(tester);
    final viewport = h.viewport;
    String id() => h.pageId(viewport.currentPageIndex.value);
    final centre = viewport.viewportSize.center(Offset.zero);

    viewport.beginGesture();
    for (var k = 1; k <= 10; k++) {
      viewport.updateGesture(
        baselineFocal: centre,
        focal: centre - Offset(0, 8.0 * k),
        scaleRatio: 1,
        rebased: false,
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(viewport.isInteracting.value, isTrue);
      expect(
        _inkViewOf(tester, id()).isScaling,
        isFalse,
        reason: 'pan frame $k: tiles keep being made',
      );
      expect(_inkViewOf(tester, id()).ancestorScale, 1);
    }
    viewport.endGesture(const Velocity(pixelsPerSecond: Offset(0, -1500)));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(viewport.isInteracting.value, isTrue, reason: 'flinging');
    expect(_inkViewOf(tester, id()).isScaling, isFalse, reason: 'fling');
    await tester.pumpAndSettle();
    expect(_inkViewOf(tester, id()).isScaling, isFalse);

    // a pinch still is scaling, from its first scaled frame
    viewport
      ..beginGesture()
      ..updateGesture(
        baselineFocal: centre,
        focal: centre,
        scaleRatio: 1.2,
        rebased: false,
      );
    await tester.pump();
    expect(_inkViewOf(tester, id()).isScaling, isTrue);
    viewport.endGesture(Velocity.zero);
    await tester.pumpAndSettle();
    await tester.pump(ViewportConstants.settleDelay * 2);
    await tester.pump();
    expect(_inkViewOf(tester, id()).isScaling, isFalse);
  });

  testWidgets('visiblePageRect: the on-screen part in page pt', (tester) async {
    final h = await pumpEditor(tester);
    final viewport = h.viewport;
    final size = viewport.viewportSize;

    Rect expectedFor(int index) {
      final a = viewport.screenToPage(index, Offset.zero);
      final b = viewport.screenToPage(index, Offset(size.width, size.height));
      final page = Rect.fromLTWH(0, 0, kA4.width, kA4.height);
      final r = Rect.fromPoints(a, b).intersect(page);
      return r.width > 0 && r.height > 0 ? r : Rect.zero;
    }

    void expectRect(int index) {
      final actual = _inkViewOf(tester, h.pageId(index)).visiblePageRect!;
      final expected = expectedFor(index);
      expect(actual.left, closeTo(expected.left, 1e-6));
      expect(actual.top, closeTo(expected.top, 1e-6));
      expect(actual.right, closeTo(expected.right, 1e-6));
      expect(actual.bottom, closeTo(expected.bottom, 1e-6));
    }

    expectRect(0);
    expect(_inkViewOf(tester, h.pageId(1)).visiblePageRect, Rect.zero);

    // Half of page 0 and the top of page 1 on screen.
    viewport.panBy(Offset(0, size.height * 0.6));
    await tester.pump();
    expectRect(0);
    expectRect(1);
    expect(expectedFor(1), isNot(Rect.zero));
    await tester.pump(ViewportConstants.settleDelay * 2);
  });

  testWidgets('loading cover until the page content is loaded', (tester) async {
    final h = await pumpEditor(tester, settle: false);
    h.recorder!.holdPageLoads();
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    final cover = find.byKey(EditorPageView.loadingCoverKey);
    expect(_viewIds(tester), [h.pageId(0), h.pageId(1)]);
    expect(cover, findsNWidgets(2));
    expect(h.mountedPages.all.every((m) => !m.isLoaded.value), isTrue);
    expect(h.controllerOf(0).content, isNull);

    h.recorder!.releasePageLoads();
    await tester.pump();
    await tester.pump();
    expect(cover, findsNothing);
    expect(h.mountedPages.all.every((m) => m.isLoaded.value), isTrue);
    expect(h.controllerOf(0).content, isNotNull);
  });

  testWidgets('the viewport follows its size (rotation)', (tester) async {
    final h = await pumpEditor(tester);
    final portrait = h.viewport.viewportSize;
    final zoom = h.viewport.zoom;
    tester.view.physicalSize = const Size(1376, 1032) * 2;
    await tester.pump();
    await h.settlePages();
    final landscape = h.viewport.viewportSize;
    expect(landscape.width, greaterThan(portrait.width));
    expect(landscape.height, lessThan(portrait.height));
    expect(h.viewport.zoom, closeTo(zoom, 1e-9));
    expect(h.viewport.currentPageIndex.value, 0);
    expect(_viewIds(tester), _visiblePlusOne(h));
  });

  testWidgets('closing the screen closes every mounted page', (tester) async {
    final h = await pumpEditor(tester, pages: 5);
    final recorder = h.recorder!;
    final mounted = _viewIds(tester);
    expect(mounted, isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    for (final id in mounted) {
      expect(recorder.countOf('closePage:$id'), 1, reason: id);
    }
  });
}
