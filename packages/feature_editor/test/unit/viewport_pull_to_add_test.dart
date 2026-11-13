// Pull to add a page (04-editor 6.11.7): the rubber band past the document
// end (CameraMath.pullExtent) and ViewportController's pull state —
// overscroll only for a gesture that allows it, only past the end on the
// main axis, never for a pinch or a fling; the release past the threshold
// is reported once and springs back. Fake time through testWidgets.
import 'dart:async';
import 'dart:ui' show Offset, Size;

import 'package:feature_editor/src/viewport/page_layout.dart';
import 'package:feature_editor/src/viewport/viewport_camera.dart';
import 'package:feature_editor/src/viewport/viewport_constants.dart';
import 'package:feature_editor/src/viewport/viewport_controller.dart';
import 'package:flutter/gestures.dart' show Velocity;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/test_data.dart';

const Size _portrait = Size(1032, 1376);
const Offset _centre = Offset(516, 688);
const double _k = ViewportConstants.pullToAddResistance;
const double _threshold = ViewportConstants.pullToAddThreshold;

List<core.Page> _pages(int n) => [
  for (var i = 0; i < n; i++)
    core.Page(
      id: 'p$i',
      noteId: 'note',
      sortKey: 'p$i',
      size: kA4,
      background: const core.BlankBackground(),
      createdAt: 0,
      updatedAt: 0,
      contentRevision: 0,
    ),
];

final List<ViewportController> _live = [];

ViewportController _controller({
  int pages = 3,
  LayoutAxis axis = LayoutAxis.vertical,
}) {
  final c = ViewportController()
    ..setAxis(axis)
    ..updatePages(_pages(pages))
    ..updateViewportSize(_portrait)
    ..restore(null);
  _live.add(c);
  return c;
}

void _test(String description, Future<void> Function(WidgetTester) body) {
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

Future<void> _settle(WidgetTester tester, ViewportController c) async {
  var guard = 0;
  while (c.isAnimating && guard++ < 1000) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(ViewportConstants.settleDelay);
}

/// Moves the camera to the very end (clamped).
Future<void> _toEnd(WidgetTester tester, ViewportController c) async {
  await c.jumpToPage(c.layout.length - 1, animate: false);
  c.panBy(const Offset(100000, 100000));
  await _settle(tester, c);
}

/// A one-finger pan: [delta] is the finger travel (screen px).
void _pan(
  ViewportController c,
  Offset delta, {
  bool allow = true,
  double scaleRatio = 1,
}) {
  c
    ..beginGesture(allowPullToAdd: allow)
    ..updateGesture(
      baselineFocal: _centre,
      focal: _centre + delta,
      scaleRatio: scaleRatio,
      rebased: false,
    );
}

double _mainOrigin(ViewportController c) =>
    c.axis == LayoutAxis.vertical ? c.camera.origin.dy : c.camera.origin.dx;

void main() {
  group('CameraMath.pullExtent', () {
    test('damped by the resistance, capped, 0 without travel', () {
      expect(CameraMath.pullExtent(0), 0);
      expect(CameraMath.pullExtent(-50), 0);
      expect(CameraMath.pullExtent(double.nan), 0);
      expect(CameraMath.pullExtent(100), closeTo(100 * _k, 1e-12));
      expect(
        CameraMath.pullExtent(_threshold / _k),
        closeTo(_threshold, 1e-12),
      );
      expect(CameraMath.pullExtent(1e6), ViewportConstants.pullToAddMaxExtent);
      expect(_threshold, lessThan(ViewportConstants.pullToAddMaxExtent));
    });
  });

  group('ViewportController pull', () {
    _test('vertical: past the end the camera follows with resistance; '
        'the phase arms at the threshold', (tester) async {
      final c = _controller();
      await _toEnd(tester, c);
      final end = _mainOrigin(c);
      final scale = c.camera.scale;
      expect(c.pullPhase.value, PullToAddPhase.idle);
      expect(c.pullExtent, 0);

      _pan(c, const Offset(0, -100)); // finger up = past the bottom
      expect(c.pullPhase.value, PullToAddPhase.pulling);
      expect(c.pullExtent, closeTo(100 * _k, 1e-6));
      expect(_mainOrigin(c), closeTo(end + 100 * _k / scale, 1e-9));

      c.updateGesture(
        baselineFocal: _centre,
        focal: _centre - Offset(0, _threshold / _k + 1),
        scaleRatio: 1,
        rebased: false,
      );
      expect(c.pullPhase.value, PullToAddPhase.armed);
      expect(c.pullExtent, greaterThanOrEqualTo(_threshold));

      // Back below the threshold, then back inside: idle and clamped.
      c.updateGesture(
        baselineFocal: _centre,
        focal: _centre - const Offset(0, 50),
        scaleRatio: 1,
        rebased: false,
      );
      expect(c.pullPhase.value, PullToAddPhase.pulling);
      c.updateGesture(
        baselineFocal: _centre,
        focal: _centre + const Offset(0, 40),
        scaleRatio: 1,
        rebased: false,
      );
      expect(c.pullPhase.value, PullToAddPhase.idle);
      expect(_mainOrigin(c), closeTo(end - 40 / scale, 1e-9));
      expect(c.endGesture(Velocity.zero), isFalse);
      await _settle(tester, c);
    });

    _test('capped at the max extent', (tester) async {
      final c = _controller();
      await _toEnd(tester, c);
      _pan(c, const Offset(0, -5000));
      expect(c.pullExtent, closeTo(ViewportConstants.pullToAddMaxExtent, 1e-6));
      c.cancelGesture();
      await _settle(tester, c);
    });

    _test('release past the threshold: true once, springs back to the end', (
      tester,
    ) async {
      final c = _controller();
      await _toEnd(tester, c);
      final end = c.camera;
      _pan(c, Offset(0, -(_threshold / _k + 20)));
      expect(c.endGesture(Velocity.zero), isTrue);
      expect(c.pullPhase.value, PullToAddPhase.released);
      expect(c.isAnimating, isTrue);
      await _settle(tester, c);
      expect(c.camera.origin.dy, closeTo(end.origin.dy, 1e-9));
      expect(c.pullPhase.value, PullToAddPhase.idle);
      expect(c.pullExtent, 0);
    });

    _test('release below the threshold: false, springs back', (tester) async {
      final c = _controller();
      await _toEnd(tester, c);
      final end = c.camera;
      _pan(c, Offset(0, -(_threshold / _k - 20)));
      expect(c.pullPhase.value, PullToAddPhase.pulling);
      // Even with a release speed: no fling past the end, no add.
      expect(
        c.endGesture(const Velocity(pixelsPerSecond: Offset(0, -3000))),
        isFalse,
      );
      expect(c.pullPhase.value, PullToAddPhase.pulling);
      await _settle(tester, c);
      expect(c.camera, end);
      expect(c.pullPhase.value, PullToAddPhase.idle);
    });

    _test('cancel past the threshold adds nothing', (tester) async {
      final c = _controller();
      await _toEnd(tester, c);
      _pan(c, Offset(0, -(_threshold / _k + 20)));
      c.cancelGesture();
      expect(c.pullPhase.value, PullToAddPhase.pulling);
      await _settle(tester, c);
      expect(c.pullPhase.value, PullToAddPhase.idle);
    });

    _test('without allowPullToAdd the end clamps as before', (tester) async {
      final c = _controller();
      await _toEnd(tester, c);
      final end = c.camera;
      _pan(c, const Offset(0, -400), allow: false);
      expect(c.camera, end);
      expect(c.pullPhase.value, PullToAddPhase.idle);
      expect(c.endGesture(Velocity.zero), isFalse);
      await _settle(tester, c);
    });

    _test('away from the end a pan never pulls; the start never pulls', (
      tester,
    ) async {
      final c = _controller();
      // At the document start, dragging down past the top.
      _pan(c, const Offset(0, 400));
      expect(c.pullPhase.value, PullToAddPhase.idle);
      expect(c.camera.origin.dy, 0);
      expect(c.endGesture(Velocity.zero), isFalse);
      await _settle(tester, c);
      // Mid document, a pan that stays inside.
      _pan(c, const Offset(0, -300));
      expect(c.pullPhase.value, PullToAddPhase.idle);
      expect(c.endGesture(Velocity.zero), isFalse);
      await _settle(tester, c);
    });

    _test('a fling into the end stops at the bound: no pull, no add', (
      tester,
    ) async {
      final c = _controller();
      await c.jumpToPage(2, animate: false);
      await _settle(tester, c);
      _pan(c, const Offset(0, -10));
      expect(
        c.endGesture(const Velocity(pixelsPerSecond: Offset(0, -8000))),
        isFalse,
      );
      await _settle(tester, c);
      final maxY =
          c.layout.contentSize.height - _portrait.height / c.camera.scale;
      expect(c.camera.origin.dy, closeTo(maxY, 1e-9));
      expect(c.pullPhase.value, PullToAddPhase.idle);
    });

    _test('a pinch never pulls', (tester) async {
      final c = _controller();
      await _toEnd(tester, c);
      c
        ..beginGesture(allowPullToAdd: true)
        ..updateGesture(
          baselineFocal: _centre,
          focal: _centre - const Offset(0, 400),
          scaleRatio: 1.2,
          rebased: false,
        );
      expect(c.pullPhase.value, PullToAddPhase.idle);
      expect(c.endGesture(Velocity.zero), isFalse);
      await _settle(tester, c);
    });

    _test('zoomed in at the end: pulls only past the true end', (tester) async {
      final c = _controller();
      await _toEnd(tester, c);
      unawaited(c.zoomStep(zoomIn: true));
      await _settle(tester, c);
      expect(c.zoom, greaterThan(1));
      c.panBy(const Offset(0, 100000));
      await _settle(tester, c);
      final end = c.camera.origin.dy;
      // Sideways drag at the end: cross axis only, no pull.
      _pan(c, const Offset(-200, 0));
      expect(c.pullPhase.value, PullToAddPhase.idle);
      expect(c.camera.origin.dy, closeTo(end, 1e-9));
      c.updateGesture(
        baselineFocal: _centre,
        focal: _centre + const Offset(-200, -100),
        scaleRatio: 1,
        rebased: false,
      );
      expect(c.pullPhase.value, PullToAddPhase.pulling);
      expect(c.pullExtent, closeTo(100 * _k, 1e-6));
      expect(c.endGesture(Velocity.zero), isFalse);
      await _settle(tester, c);
    });

    _test('a rebase (second finger) keeps the pull continuous', (tester) async {
      final c = _controller();
      await _toEnd(tester, c);
      _pan(c, const Offset(0, -100));
      final shown = c.pullExtent;
      final at = _centre - const Offset(0, 100);
      c.updateGesture(
        baselineFocal: at,
        focal: at,
        scaleRatio: 1,
        rebased: true,
      );
      expect(c.pullExtent, closeTo(shown, 1e-6));
      c.updateGesture(
        baselineFocal: at,
        focal: at - const Offset(0, 100),
        scaleRatio: 1,
        rebased: false,
      );
      expect(c.pullExtent, closeTo(200 * _k, 1e-6));
      c.cancelGesture();
      await _settle(tester, c);
    });

    _test('caught during the spring-back: continues from the shown pull', (
      tester,
    ) async {
      final c = _controller();
      await _toEnd(tester, c);
      _pan(c, const Offset(0, -150));
      expect(c.endGesture(Velocity.zero), isFalse);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 32));
      final shown = c.pullExtent;
      expect(shown, inExclusiveRange(0, 150 * _k));
      _pan(c, Offset.zero); // touch down again, no move yet
      expect(c.pullExtent, closeTo(shown, 1e-6));
      c.updateGesture(
        baselineFocal: _centre,
        focal: _centre - const Offset(0, 10),
        scaleRatio: 1,
        rebased: false,
      );
      expect(c.pullExtent, closeTo(shown + 10 * _k, 1e-6));
      c.cancelGesture();
      await _settle(tester, c);
      expect(c.pullPhase.value, PullToAddPhase.idle);
    });

    _test('settleNow during a spring-back puts the camera back in bounds', (
      tester,
    ) async {
      final c = _controller();
      await _toEnd(tester, c);
      final end = c.camera;
      _pan(c, const Offset(0, -150));
      c.endGesture(Velocity.zero);
      await tester.pump(const Duration(milliseconds: 16));
      c.settleNow();
      expect(c.camera, end);
      expect(c.pullPhase.value, PullToAddPhase.idle);
      await _settle(tester, c);
    });

    _test('horizontal (paged): past the last page centred, to the left', (
      tester,
    ) async {
      final c = _controller(axis: LayoutAxis.horizontal);
      await c.jumpToPage(2, animate: false);
      await _settle(tester, c);
      final end = c.camera;
      // The trailing room after the last page (the '+ 페이지' button) comes
      // first: past the centred page up to the content end, no pull.
      final bound = CameraMath.clamp(
        end.pannedBy(const Offset(-1e6, 0)),
        c.layout,
        _portrait,
        c.fitScale,
      );
      final slack = (bound.origin.dx - end.origin.dx) * end.scale;
      expect(slack, greaterThanOrEqualTo(0));
      // Finger up / down: the cross axis, no pull.
      _pan(c, const Offset(0, -300));
      expect(c.pullPhase.value, PullToAddPhase.idle);
      c.updateGesture(
        baselineFocal: _centre,
        focal: _centre - Offset(slack, 0),
        scaleRatio: 1,
        rebased: false,
      );
      expect(c.pullPhase.value, PullToAddPhase.idle);
      c.updateGesture(
        baselineFocal: _centre,
        focal: _centre - Offset(slack + _threshold / _k + 10, 0),
        scaleRatio: 1,
        rebased: false,
      );
      expect(c.pullPhase.value, PullToAddPhase.armed);
      expect(
        c.camera.origin.dx,
        closeTo(bound.origin.dx + c.pullExtent / end.scale, 1e-9),
      );
      expect(c.endGesture(Velocity.zero), isTrue);
      await _settle(tester, c);
      expect(c.camera, end, reason: 'back to the last page centred');
      expect(c.pullPhase.value, PullToAddPhase.idle);

      // The first page: dragging right never pulls.
      await c.jumpToPage(0, animate: false);
      await _settle(tester, c);
      _pan(c, const Offset(400, 0));
      expect(c.pullPhase.value, PullToAddPhase.idle);
      expect(c.endGesture(Velocity.zero), isFalse);
      await _settle(tester, c);
    });
  });
}
