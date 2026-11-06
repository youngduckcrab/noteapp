// L2-I3 (m5-7/05-library 6.17.4, 8.3; review S-7; contract 7.7.1 step 5) —
// written with L2-06, run in the integration stage
// (ws test --run-skipped -t integration): the real GeometricShapeFitter
// behind INK's real hold detection (03-ink T39 — in the concurrent stage
// INK's controller is the foundation surface whose shapePreview stays null).
// The INK package cannot import the fitter (ink_recognition depends on
// ink_engine — contract 7.1 / INFRA R8), so LIBRARY tests the flow.
//
// If a case fails, split the cause: the fitter (synthetic V9 —
// unit/shape_fitter_test.dart) ↔ INK's hold detection / preview
// (03-ink hold_detector_test).
@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/testing.dart';
import 'package:material_ui/material_ui.dart' show Offset, Rect;
import 'package:note_core/note_core.dart' as core;

import '../shared/shape_cases.dart';

/// One pen stroke through [points] (8 ms apart), then [holdMs] at the last
/// point (samples every 8 ms inside the hold radius).
final class _Pen {
  _Pen(this.async) : clock = ink_testing.FakeInkClock(), controller = null;

  final FakeAsync async;
  final ink_testing.FakeInkClock clock;
  ink.InkPageController? controller;
  int _us = 0;

  ink.InkSample _sample(Offset p) =>
      ink.InkSample(position: p, timeUs: _us, kind: ink.InkPointerKind.stylus);

  void _step(int ms) {
    _us += ms * 1000;
    clock.advanceMs(ms.toDouble());
    async.elapse(Duration(milliseconds: ms));
  }

  ink.StrokeSession draw(
    List<Offset> points, {
    double viewScale = 1,
    int holdMs = ink.InkTuning.shapeHoldMs + 1,
  }) {
    final c = controller ??= ink_testing.createTestPageController(
      clock: clock,
      shapeFitter: const GeometricShapeFitter(),
    );
    final session = c.beginStroke(
      _sample(points.first),
      style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
      viewScale: viewScale,
      shapeAssist: ink.ShapeAssist.holdToSnap,
    );
    for (final p in points.skip(1)) {
      _step(8);
      session.addSample(_sample(p));
    }
    hold(session, points.last, holdMs);
    return session;
  }

  void hold(ink.StrokeSession session, Offset at, int ms) {
    for (var t = 0; t < ms; t += 8) {
      _step(math.min(8, ms - t));
      session.addSample(_sample(at));
    }
  }
}

void main() {
  test('1. a synthetic rectangle + 501 ms → preview rectangle → end() → '
      'addShape: one ShapeObject within 2 pt of the path box', () {
    fakeAsync((async) {
      const rect = Rect.fromLTWH(100, 100, 240, 160);
      final pen = _Pen(async);
      final s = pen.draw(SyntheticShapes.rectanglePath(rect));
      expect(s.shapePreview.value?.kind, core.ShapeKind.rectangle);
      final edit = s.end()!;
      expect(edit.kind, ink.InkEditKind.addShape);
      expect(edit.added, isEmpty);
      final command = edit.toCommand() as core.AddObjects;
      final shape = command.objects.single as core.ShapeObject;
      expect(shape.shapeKind, core.ShapeKind.rectangle);
      final f = shape.geometry.frame.rect;
      expect(f.left, closeTo(100, 2));
      expect(f.top, closeTo(100, 2));
      expect(f.right, closeTo(340, 2));
      expect(f.bottom, closeTo(260, 2));
    });
  });

  test('2. a synthetic circle → an ellipse with a square frame', () {
    fakeAsync((async) {
      final gen = SyntheticShapeGenerator(20261105);
      List<Offset> circle;
      do {
        circle = gen.stroke(ShapeTruth.circle);
      } while (verdictOf(
            const GeometricShapeFitter().fit(circle, viewScale: 1),
          ) !=
          'circle');
      final s = _Pen(async).draw(circle);
      expect(s.shapePreview.value?.kind, core.ShapeKind.ellipse);
      final shape =
          (s.end()!.toCommand() as core.AddObjects).objects.single
              as core.ShapeObject;
      final r = shape.geometry.frame.rect;
      expect(r.width, closeTo(r.height, 1e-9));
    });
  });

  test('3. a 499 ms hold → no preview → end() adds the stroke', () {
    fakeAsync((async) {
      final s = _Pen(async).draw(
        SyntheticShapes.rectanglePath(const Rect.fromLTWH(100, 100, 240, 160)),
        holdMs: ink.InkTuning.shapeHoldMs - 1,
      );
      expect(s.shapePreview.value, isNull);
      final edit = s.end()!;
      expect(edit.kind, ink.InkEditKind.addStroke);
      expect(edit.added, hasLength(1));
    });
  });

  test('4. moving out of the radius after the preview clears it; another '
      '500 ms hold judges again', () {
    fakeAsync((async) {
      const rect = Rect.fromLTWH(100, 100, 240, 160);
      final pen = _Pen(async);
      final path = SyntheticShapes.rectanglePath(rect);
      final s = pen.draw(path);
      expect(s.shapePreview.value, isNotNull);
      pen._step(8);
      s.addSample(pen._sample(path.last + const Offset(60, 0)));
      expect(s.shapePreview.value, isNull);
      pen.hold(
        s,
        path.last + const Offset(60, 0),
        ink.InkTuning.shapeHoldMs + 1,
      );
      // the stroke now has a tail: whatever the verdict, it was asked again
      expect(() => s.shapePreview.value, returnsNormally);
      s.end();
    });
  });

  test('5. a scribble → fit null → the stroke stays', () {
    fakeAsync((async) {
      final gen = SyntheticShapeGenerator(20261105);
      List<Offset> scribble;
      do {
        scribble = gen.stroke(ShapeTruth.scribble);
      } while (const GeometricShapeFitter().fit(scribble, viewScale: 1) !=
          null);
      final s = _Pen(async).draw(scribble);
      expect(s.shapePreview.value, isNull);
      expect(s.end()!.kind, ink.InkEditKind.addStroke);
    });
  });

  test('6. small-rectangle guard: 64×48 pt at viewScale 0.25 (20 px '
      'diagonal) stays a stroke; at viewScale 1 a rectangle', () {
    fakeAsync((async) {
      final path = SyntheticShapes.rectanglePath(
        const Rect.fromLTWH(100, 100, 64, 48),
      );
      final small = _Pen(async).draw(path, viewScale: 0.25);
      expect(small.shapePreview.value, isNull);
      expect(small.end()!.kind, ink.InkEditKind.addStroke);
      final big = _Pen(async).draw(path);
      expect(big.shapePreview.value?.kind, core.ShapeKind.rectangle);
      big.end();
    });
  });
}
