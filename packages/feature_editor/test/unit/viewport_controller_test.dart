// E-03: ViewportController (04-editor 6.3.4, 6.11.6). Fake time through
// testWidgets: tester.pump drives the controller's Ticker and the 150 ms
// settle Timer. iPad Pro 13" portrait viewport (1032×1376).
import 'dart:async';
import 'dart:ui' show Offset, Rect, Size;

import 'package:feature_editor/src/viewport/page_layout.dart';
import 'package:feature_editor/src/viewport/viewport_camera.dart';
import 'package:feature_editor/src/viewport/viewport_constants.dart';
import 'package:feature_editor/src/viewport/viewport_controller.dart';
import 'package:flutter/gestures.dart' show Velocity;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/test_data.dart';

const Size _portrait = Size(1032, 1376);
const Size _landscape = Size(1376, 1032);
const Offset _centre = Offset(516, 688);
const double _gap = ViewportConstants.pageGap;

core.Page _page(String id, {core.PageSize size = kA4, int revision = 0}) =>
    core.Page(
      id: id,
      noteId: 'note',
      sortKey: id,
      size: size,
      background: const core.BlankBackground(),
      createdAt: 0,
      updatedAt: 0,
      contentRevision: revision,
    );

List<core.Page> _pages(int n, {core.PageSize size = kA4}) => [
  for (var i = 0; i < n; i++) _page('p$i', size: size),
];

/// Controllers made by the running test (disposed at the end of its body,
/// before the pending-timer check of testWidgets).
final List<ViewportController> _live = [];

ViewportController _track(ViewportController c) {
  _live.add(c);
  return c;
}

/// A controller with [pages] at [size], restored (first page or [anchor]).
ViewportController _controller({
  List<core.Page>? pages,
  Size size = _portrait,
  ViewportAnchor? anchor,
}) => _track(
  ViewportController()
    ..updatePages(pages ?? _pages(10))
    ..updateViewportSize(size)
    ..restore(anchor),
);

void _viewportTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      for (final c in _live) {
        c.dispose();
      }
      _live.clear();
    }
  });
}

/// Pumps frames of 16 ms for [total].
Future<void> _frames(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 16);
  var elapsed = Duration.zero;
  while (elapsed < total) {
    await tester.pump(step);
    elapsed += step;
  }
}

/// Lets any animation finish and the settle wait pass.
Future<void> _settle(WidgetTester tester, ViewportController c) async {
  var guard = 0;
  while (c.isAnimating && guard++ < 1000) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(ViewportConstants.settleDelay);
}

/// A finger pan by [delta] (screen px) as one navigation gesture.
void _drag(ViewportController c, Offset delta, {Offset from = _centre}) {
  c
    ..beginGesture()
    ..updateGesture(
      baselineFocal: from,
      focal: from + delta,
      scaleRatio: 1,
      rebased: false,
    );
}

/// A pinch by [ratio] about [focal].
void _pinch(ViewportController c, double ratio, {Offset focal = _centre}) {
  c
    ..beginGesture()
    ..updateGesture(
      baselineFocal: focal,
      focal: focal,
      scaleRatio: ratio,
      rebased: false,
    );
}

Matcher _offsetCloseTo(Offset expected, [double tolerance = 1e-6]) =>
    isA<Offset>()
        .having((o) => o.dx, 'dx', closeTo(expected.dx, tolerance))
        .having((o) => o.dy, 'dy', closeTo(expected.dy, tolerance));

void main() {
  final fit = (_portrait.width - 2 * ViewportConstants.sideMargin) / kA4.width;
  double pageTop(int i) =>
      ViewportConstants.leadingPadding + i * (kA4.height + _gap);

  group('first display (restore)', () {
    _viewportTest('without an anchor: first page top at fit width, settled', (
      tester,
    ) async {
      final c = _controller();
      expect(c.fitScale, closeTo(fit, 1e-12));
      expect(c.zoom, 1);
      expect(c.camera.origin.dy, closeTo(pageTop(0) - _gap / 2, 1e-9));
      expect(c.currentPageIndex.value, 0);
      expect(c.isInteracting.value, isFalse);
      expect(c.settledScale.value, c.camera.scale);
    });

    _viewportTest('restore before the size and pages is applied later', (
      tester,
    ) async {
      final c = _track(ViewportController())
        ..restore(
          const ViewportAnchor(
            pageId: 'p4',
            offsetInPage: Offset(10, 300),
            zoom: 2,
          ),
        )
        ..updatePages(_pages(10));
      expect(c.captureAnchor(), isNull, reason: 'no viewport size yet');
      c.updateViewportSize(_portrait);
      final anchor = c.captureAnchor()!;
      expect(anchor.pageId, 'p4');
      expect(anchor.offsetInPage, _offsetCloseTo(const Offset(10, 300)));
      expect(anchor.zoom, closeTo(2, 1e-12));
      expect(c.isInteracting.value, isFalse);
      expect(c.settledScale.value, c.camera.scale);
    });

    _viewportTest('initialPageId wins; unknown ids and gone pages fall back', (
      tester,
    ) async {
      final c = _controller();
      const anchor = ViewportAnchor(
        pageId: 'p4',
        offsetInPage: Offset(0, 100),
        zoom: 1.5,
      );
      c.restore(anchor, initialPageId: 'p7');
      expect(c.currentPageIndex.value, 7);
      expect(c.zoom, closeTo(1, 1e-12));
      expect(c.camera.origin.dy, closeTo(pageTop(7) - _gap / 2, 1e-9));

      c.restore(anchor, initialPageId: 'nope');
      expect(c.captureAnchor()!.pageId, 'p4');
      expect(c.zoom, closeTo(1.5, 1e-12));

      c.restore(
        const ViewportAnchor(
          pageId: 'gone',
          offsetInPage: Offset.zero,
          zoom: 3,
        ),
      );
      expect(c.currentPageIndex.value, 0, reason: 'missing page → page 0');
      expect(c.zoom, closeTo(1, 1e-12));
    });
  });

  group('gesture end', () {
    _viewportTest('a fling decelerates and stops, then settles', (
      tester,
    ) async {
      final c = _controller();
      _drag(c, const Offset(0, -200));
      final afterDrag = c.camera.origin.dy;
      expect(afterDrag, closeTo(pageTop(0) - _gap / 2 + 200 / fit, 1e-9));

      c.endGesture(const Velocity(pixelsPerSecond: Offset(0, -2000)));
      expect(c.isAnimating, isTrue);
      await _frames(tester, const Duration(milliseconds: 100));
      final early = c.camera.origin.dy;
      expect(early, greaterThan(afterDrag), reason: 'content keeps moving up');

      await _frames(tester, const Duration(seconds: 4));
      expect(c.isAnimating, isFalse, reason: 'the fling ended by itself');
      final stopped = c.camera;
      expect(stopped.origin.dy, greaterThan(early));
      expect(c.camera.scale, closeTo(fit, 1e-12), reason: 'pan only');
      await tester.pump(ViewportConstants.settleDelay);
      expect(c.isInteracting.value, isFalse);
      await _frames(tester, const Duration(milliseconds: 300));
      expect(c.camera, stopped, reason: 'no movement after the stop');
    });

    _viewportTest('a fling into a bound stops at the bound', (tester) async {
      final c = _controller();
      _drag(c, const Offset(0, 5));
      c.endGesture(const Velocity(pixelsPerSecond: Offset(0, 3000)));
      await _frames(tester, const Duration(milliseconds: 64));
      expect(c.camera.origin.dy, 0, reason: 'top bound');
      expect(c.isAnimating, isFalse, reason: 'stopped at the bound');

      // The bottom bound.
      await c.jumpToPage(9, animate: false);
      await tester.pump(ViewportConstants.settleDelay);
      _drag(c, const Offset(0, -10));
      c.endGesture(const Velocity(pixelsPerSecond: Offset(0, -8000)));
      await _frames(tester, const Duration(seconds: 3));
      final maxY = c.layout.contentSize.height - _portrait.height / fit;
      expect(c.camera.origin.dy, closeTo(maxY, 1e-9));
      expect(c.isAnimating, isFalse);
    });

    _viewportTest('a slow release has no fling', (tester) async {
      final c = _controller();
      _drag(c, const Offset(0, -100));
      final before = c.camera;
      c.endGesture(const Velocity(pixelsPerSecond: Offset(0, -40)));
      expect(c.isAnimating, isFalse);
      await _frames(tester, const Duration(milliseconds: 200));
      expect(c.camera, before);
    });

    _viewportTest('zoom within 5 % of 100 % snaps to 100 % about the focal', (
      tester,
    ) async {
      final c = _controller();
      const focal = Offset(300, 500);
      _pinch(c, 1.03, focal: focal);
      expect(c.zoom, closeTo(1.03, 1e-9));
      final docUnderFocal = c.camera.screenToDoc(focal);
      c.endGesture(Velocity.zero);
      expect(c.isAnimating, isTrue);
      await _frames(tester, const Duration(milliseconds: 200));
      expect(c.isAnimating, isFalse);
      expect(c.zoom, 1);
      // The cross axis recentres at fit width; the main axis keeps the focal.
      expect(c.camera.docToScreen(docUnderFocal).dy, closeTo(focal.dy, 1e-6));

      _pinch(c, 1.2, focal: focal);
      c.endGesture(Velocity.zero);
      expect(c.isAnimating, isFalse, reason: '1.2 is outside the snap range');
      await _frames(tester, const Duration(milliseconds: 200));
      expect(c.zoom, closeTo(1.2, 1e-9));
    });

    _viewportTest('isInteracting turns false and settledScale updates 150 ms '
        'after the gesture', (tester) async {
      final c = _controller();
      final settled = <double>[];
      c.settledScale.addListener(() => settled.add(c.settledScale.value));
      _pinch(c, 2);
      expect(c.isInteracting.value, isTrue);
      expect(c.settledScale.value, closeTo(fit, 1e-12));
      c.endGesture(Velocity.zero);
      await tester.pump(const Duration(milliseconds: 149));
      expect(c.isInteracting.value, isTrue);
      expect(settled, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(c.isInteracting.value, isFalse);
      expect(c.settledScale.value, c.camera.scale);
      expect(settled, [c.camera.scale]);
    });

    _viewportTest('a scale change under 0.1 % does not change settledScale', (
      tester,
    ) async {
      final c = _controller();
      final before = c.settledScale.value;
      // 1.0005 snaps back to 1 (inside 5 %), so zoom from 2 instead.
      _pinch(c, 2);
      c.endGesture(Velocity.zero);
      await _settle(tester, c);
      final atTwo = c.settledScale.value;
      expect(atTwo, isNot(before));
      _pinch(c, 1.0005);
      c.endGesture(Velocity.zero);
      await _settle(tester, c);
      expect(c.isInteracting.value, isFalse);
      expect(c.settledScale.value, atTwo);
    });
  });

  group('size and page changes', () {
    _viewportTest('a size change keeps the anchor and the zoom', (
      tester,
    ) async {
      final c = _controller();
      await c.jumpToPage(3, animate: false);
      c
        ..panBy(const Offset(0, 300))
        ..zoomBy(2, _centre);
      await _settle(tester, c);
      final before = c.captureAnchor()!;
      expect(before.pageId, 'p3');
      expect(before.zoom, closeTo(2, 1e-9));

      c.updateViewportSize(_landscape);
      final after = c.captureAnchor()!;
      expect(after.pageId, 'p3');
      expect(after.zoom, closeTo(2, 1e-9));
      expect(after.offsetInPage, _offsetCloseTo(before.offsetInPage));
      expect(
        c.fitScale,
        closeTo(
          (_landscape.width - 2 * ViewportConstants.sideMargin) / kA4.width,
          1e-12,
        ),
      );
      expect(c.isInteracting.value, isTrue, reason: 'the scale changed');
      await tester.pump(ViewportConstants.settleDelay);
      expect(c.settledScale.value, c.camera.scale);
    });

    _viewportTest('inserting a page before keeps the viewed page', (
      tester,
    ) async {
      final pages = _pages(10);
      final c = _controller(pages: pages);
      await c.jumpToPage(3, animate: false);
      c.panBy(const Offset(0, 200));
      await _settle(tester, c);
      final before = c.captureAnchor()!;
      final originBefore = c.camera.origin;

      c.updatePages([_page('new'), ...pages]);
      expect(c.layout.length, 11);
      expect(c.captureAnchor(), before);
      expect(c.currentPageIndex.value, 4);
      expect(
        c.camera.origin,
        _offsetCloseTo(originBefore + Offset(0, kA4.height + _gap)),
      );

      // The viewed page removed → the same index.
      final without = [_page('new'), ...pages]
        ..removeWhere((p) => p.id == 'p3');
      c.updatePages(without);
      expect(c.currentPageIndex.value, 4);
      expect(c.captureAnchor()!.pageId, 'p4');
    });

    _viewportTest('updatePages: only contentRevision changed → no relayout, '
        'no notification, new values kept', (tester) async {
      final pages = _pages(5);
      final c = _controller(pages: pages);
      final layout = c.layout;
      final camera = c.camera;
      var notified = 0;
      c.addListener(() => notified++);

      final revised = [
        for (final p in pages)
          p.copyWith(contentRevision: p.contentRevision + 3),
      ];
      c.updatePages(revised);
      expect(notified, 0);
      expect(identical(c.layout, layout), isTrue, reason: 'no relayout');
      expect(c.camera, camera);
      expect(c.isInteracting.value, isFalse);
      expect(c.pages.map((p) => p.contentRevision), everyElement(3));
      await tester.pump(ViewportConstants.settleDelay);
    });

    _viewportTest('updatePages: a resized page (ResizePages) relayouts', (
      tester,
    ) async {
      final pages = _pages(5);
      final c = _controller(pages: pages);
      final layout = c.layout;
      var notified = 0;
      c.addListener(() => notified++);

      final resized = [
        for (final p in pages)
          p.id == 'p2' ? p.copyWith(size: kA4.landscape) : p,
      ];
      c.updatePages(resized);
      expect(c.layout, isNot(layout));
      expect(c.layout.rectOf(2).width, closeTo(kA4.height, 1e-9));
      expect(c.layout.rectOf(2).height, closeTo(kA4.width, 1e-9));
      expect(notified, greaterThan(0));
      await _settle(tester, c);
    });
  });

  group('navigation', () {
    _viewportTest('jumpToPage animates to the page top at the current zoom', (
      tester,
    ) async {
      final c = _controller();
      final done = c.jumpToPage(5);
      var completed = false;
      unawaited(done.then((_) => completed = true));
      expect(c.isAnimating, isTrue);
      await _frames(tester, ViewportConstants.jumpDuration);
      await tester.pump(const Duration(milliseconds: 16));
      expect(completed, isTrue);
      expect(c.currentPageIndex.value, 5);
      expect(c.camera.origin.dy, closeTo(pageTop(5) - _gap / 2, 1e-9));
      expect(c.zoom, closeTo(1, 1e-12));
      await tester.pump(ViewportConstants.settleDelay);
      expect(c.isInteracting.value, isFalse);

      await c.jumpToPage(1, animate: false);
      expect(c.currentPageIndex.value, 1);
      expect(c.pageRectOnScreen(1).top, closeTo(_gap / 2 * fit, 1e-6));
      await tester.pump(ViewportConstants.settleDelay);
    });

    _viewportTest('currentPageIndex notifies only when the page changes', (
      tester,
    ) async {
      final c = _controller();
      final seen = <int>[];
      c.currentPageIndex.addListener(() => seen.add(c.currentPageIndex.value));
      var cameraChanges = 0;
      c.addListener(() => cameraChanges++);

      c
        ..panBy(const Offset(0, 100))
        ..panBy(const Offset(0, 100))
        ..panBy(const Offset(0, 100));
      expect(cameraChanges, 3);
      expect(seen, isEmpty, reason: 'still page 0');
      c.panBy(const Offset(0, 600));
      expect(seen, [1]);
      c.panBy(const Offset(0, 10));
      expect(seen, [1]);
      await tester.pump(ViewportConstants.settleDelay);
    });

    _viewportTest('ensurePageVisible is a no-op for a visible page', (
      tester,
    ) async {
      final c = _controller();
      final camera = c.camera;
      await c.ensurePageVisible(0);
      expect(c.camera, camera);
      final moved = c.ensurePageVisible(6);
      await _frames(tester, ViewportConstants.jumpDuration * 2);
      await moved;
      expect(c.currentPageIndex.value, 6);
      await tester.pump(ViewportConstants.settleDelay);
    });

    _viewportTest('zoomStep and zoomToFit', (tester) async {
      final c = _controller();
      unawaited(c.zoomStep(zoomIn: true));
      await _settle(tester, c);
      expect(c.zoom, closeTo(1.25, 1e-9));
      unawaited(c.zoomStep(zoomIn: false));
      await _settle(tester, c);
      expect(c.zoom, 1);
      c.zoomBy(3, _centre);
      unawaited(c.zoomToFit());
      await _settle(tester, c);
      expect(c.zoom, closeTo(1, 1e-12));
    });

    _viewportTest('scrollByViewport moves 0.9 viewport', (tester) async {
      final c = _controller();
      final y = c.camera.origin.dy;
      unawaited(c.scrollByViewport(1));
      await _settle(tester, c);
      expect(
        c.camera.origin.dy,
        closeTo(y + 0.9 * _portrait.height / fit, 1e-9),
      );
      unawaited(c.scrollByViewport(-1));
      await _settle(tester, c);
      expect(c.camera.origin.dy, closeTo(y, 1e-9));
    });

    _viewportTest('wheel panBy scrolls down for a positive dy; zoomBy keeps '
        'the focal point', (tester) async {
      final c = _controller();
      final y = c.camera.origin.dy;
      c.panBy(const Offset(0, 120));
      expect(c.camera.origin.dy, closeTo(y + 120 / fit, 1e-9));
      const focal = Offset(400, 300);
      final doc = c.camera.screenToDoc(focal);
      c.zoomBy(2, focal);
      expect(c.zoom, closeTo(2, 1e-9));
      expect(c.camera.docToScreen(doc), _offsetCloseTo(focal));
      c.zoomBy(1000, focal);
      expect(c.zoom, closeTo(ViewportConstants.maxZoom, 1e-9));
      await tester.pump(ViewportConstants.settleDelay);
    });
  });

  group('revealPageRect', () {
    _viewportTest('a fully visible rect does not move the camera', (
      tester,
    ) async {
      final c = _controller();
      var notified = 0;
      c.addListener(() => notified++);
      await c.revealPageRect(
        0,
        focusRectPt: const Rect.fromLTWH(100, 100, 200, 200),
      );
      expect(notified, 0);
      expect(c.isAnimating, isFalse);
    });

    _viewportTest('a rect off screen is centred at the current zoom', (
      tester,
    ) async {
      final c = _controller();
      const rect = Rect.fromLTWH(200, 300, 100, 100);
      final done = c.revealPageRect(6, focusRectPt: rect);
      await _settle(tester, c);
      await done;
      expect(c.zoom, closeTo(1, 1e-12));
      final centre = c.pageToScreen(6, rect.center);
      expect(centre.dy, closeTo(_centre.dy, 1e-6));
      final onScreen = Offset.zero & _portrait;
      expect(onScreen.contains(c.pageToScreen(6, rect.topLeft)), isTrue);
      expect(onScreen.contains(c.pageToScreen(6, rect.bottomRight)), isTrue);
      expect(c.currentPageIndex.value, 6);
    });

    _viewportTest('a rect that does not fit zooms out (24 px margin, not below '
        'fit × minZoom)', (tester) async {
      final c = _controller();
      c.zoomBy(4, _centre);
      await _settle(tester, c);
      const rect = Rect.fromLTWH(50, 50, 500, 700);
      unawaited(c.revealPageRect(2, focusRectPt: rect));
      await _settle(tester, c);
      final expected = (_portrait.height - 48) / 700; // height-bound
      expect(c.camera.scale, closeTo(expected, 1e-9));
      final shown = Rect.fromPoints(
        c.pageToScreen(2, rect.topLeft),
        c.pageToScreen(2, rect.bottomRight),
      );
      expect(shown.top, greaterThanOrEqualTo(24 - 1e-6));
      expect(shown.bottom, lessThanOrEqualTo(_portrait.height - 24 + 1e-6));

      unawaited(
        c.revealPageRect(
          4,
          focusRectPt: const Rect.fromLTWH(0, 0, 20000, 20000),
        ),
      );
      await _settle(tester, c);
      expect(c.camera.scale, closeTo(fit * ViewportConstants.minZoom, 1e-9));
    });

    _viewportTest('without a rect it is jumpToPage', (tester) async {
      final c = _controller();
      unawaited(c.revealPageRect(8));
      await _settle(tester, c);
      expect(c.currentPageIndex.value, 8);
      expect(c.camera.origin.dy, closeTo(pageTop(8) - _gap / 2, 1e-9));
    });
  });

  group('settleNow', () {
    _viewportTest('right after a pinch: settled at once, fling stopped', (
      tester,
    ) async {
      final c = _controller();
      _pinch(c, 2);
      c.endGesture(const Velocity(pixelsPerSecond: Offset(0, -2500)));
      expect(c.isAnimating, isTrue);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      c.settleNow();
      expect(c.isAnimating, isFalse);
      expect(c.isInteracting.value, isFalse);
      expect(c.settledScale.value, c.camera.scale);
      final camera = c.camera;
      await _frames(tester, const Duration(milliseconds: 400));
      expect(c.camera, camera, reason: 'the fling does not continue');
      expect(c.isInteracting.value, isFalse);
    });

    _viewportTest('already settled → no notification', (tester) async {
      final c = _controller();
      _pinch(c, 1.5);
      c.endGesture(Velocity.zero);
      await _settle(tester, c);
      var notified = 0;
      void count() => notified++;
      c
        ..addListener(count)
        ..settledScale.addListener(count)
        ..isInteracting.addListener(count)
        ..currentPageIndex.addListener(count)
        ..settleNow();
      expect(notified, 0);
    });
  });

  group('mapping and ranges', () {
    _viewportTest('hitPage / pageToScreen / screenToPage round trip', (
      tester,
    ) async {
      final c = _controller();
      c.zoomBy(1.7, const Offset(200, 900));
      await c.jumpToPage(2, animate: false);
      const p = Offset(100, 200);
      final screen = c.pageToScreen(2, p);
      final hit = c.hitPage(screen)!;
      expect(hit.index, 2);
      expect(hit.pageId, 'p2');
      expect(hit.pagePoint, _offsetCloseTo(p, 1e-9));
      expect(c.screenToPage(2, screen), _offsetCloseTo(p, 1e-9));
      // Outside the page: still mapped, no hit.
      final below = c.pageToScreen(2, Offset(p.dx, kA4.height + _gap / 2));
      expect(c.hitPage(below), isNull, reason: 'gap');
      expect(
        c.screenToPage(2, below),
        _offsetCloseTo(Offset(p.dx, kA4.height + _gap / 2), 1e-9),
      );
      final rect = c.pageRectOnScreen(2);
      expect(rect.topLeft, _offsetCloseTo(c.pageToScreen(2, Offset.zero)));
      expect(rect.width, closeTo(kA4.width * c.camera.scale, 1e-9));
      await tester.pump(ViewportConstants.settleDelay);
    });

    _viewportTest('mountedRange = visible ±1, at most 8 nearest the centre', (
      tester,
    ) async {
      final c = _controller(pages: _pages(50));
      await c.jumpToPage(20, animate: false);
      final visible = c.visibleRange!;
      final mounted = c.mountedRange!;
      expect(mounted.first, visible.first - 1);
      expect(mounted.last, visible.last + 1);
      expect(mounted.last - mounted.first + 1, lessThanOrEqualTo(8));

      // Short pages zoomed out: many visible, 8 mounted around the centre.
      final short = _track(ViewportController())
        ..updatePages(_pages(50, size: const core.PageSize(595, 100)))
        ..updateViewportSize(_portrait)
        ..restore(null);
      await short.jumpToPage(25, animate: false);
      short.zoomBy(0.01, _centre);
      final many = short.visibleRange!;
      expect(many.last - many.first + 1, greaterThan(8));
      final capped = short.mountedRange!;
      expect(capped.last - capped.first + 1, 8);
      final current = short.currentPageIndex.value;
      expect(current, inInclusiveRange(capped.first, capped.last));
      expect(
        (current - capped.first) - (capped.last - current),
        inInclusiveRange(-1, 1),
      );
      await tester.pump(ViewportConstants.settleDelay);
    });

    _viewportTest('ViewportAnchor JSON round trip and invalid values', (
      tester,
    ) async {
      const anchor = ViewportAnchor(
        pageId: 'p1',
        offsetInPage: Offset(-3.5, 120.25),
        zoom: 1.75,
      );
      expect(ViewportAnchor.fromJson(anchor.toJson()), anchor);
      expect(
        ViewportAnchor.fromJson({'pageId': 'x', 'dx': 1, 'dy': 2, 'zoom': 1}),
        const ViewportAnchor(pageId: 'x', offsetInPage: Offset(1, 2), zoom: 1),
      );
      for (final bad in <Map<String, Object?>>[
        {'dx': 0, 'dy': 0, 'zoom': 1},
        {'pageId': '', 'dx': 0, 'dy': 0, 'zoom': 1},
        {'pageId': 'x', 'dx': 'a', 'dy': 0, 'zoom': 1},
        {'pageId': 'x', 'dx': 0, 'dy': 0, 'zoom': 0},
        {'pageId': 'x', 'dx': 0, 'dy': double.nan, 'zoom': 1},
      ]) {
        expect(() => ViewportAnchor.fromJson(bad), throwsFormatException);
      }
    });
  });

  _viewportTest('setAxis keeps the current page at zoom 1', (tester) async {
    final c = _controller();
    await c.jumpToPage(4, animate: false);
    c.zoomBy(2, _centre);
    c.setAxis(LayoutAxis.horizontal);
    expect(c.axis, LayoutAxis.horizontal);
    expect(c.layout.axis, LayoutAxis.horizontal);
    expect(c.currentPageIndex.value, 4);
    expect(c.zoom, closeTo(1, 1e-12));
    c.setAxis(LayoutAxis.vertical);
    expect(c.currentPageIndex.value, 4);
    expect(c.zoom, closeTo(1, 1e-12));
    await tester.pump(ViewportConstants.settleDelay);
  });

  _viewportTest('dispose completes a running animation', (tester) async {
    final c = _controller();
    var completed = false;
    unawaited(c.jumpToPage(7).then((_) => completed = true));
    await tester.pump(const Duration(milliseconds: 16));
    c.dispose();
    await tester.pump();
    expect(completed, isTrue);
  });

  test('a camera is a value', () {
    expect(
      const ViewportCamera(scale: 2, origin: Offset(1, 2)),
      const ViewportCamera(scale: 2, origin: Offset(1, 2)),
    );
  });
}
