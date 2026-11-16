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

import '../shared/hand_drawn_corpus.dart';
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

/// The point a uniform drag scales about (03-ink 6.18): the frame centre
/// for an ellipse, the vertex mean for a polygon.
Offset _centre(core.ShapeGeometry g) {
  if (g is core.PolylineGeometry) {
    var x = 0.0, y = 0.0;
    for (final p in g.points) {
      x += p.x;
      y += p.y;
    }
    return Offset(x / g.points.length, y / g.points.length);
  }
  final r = g.frame.rect;
  return Offset((r.left + r.right) / 2, (r.top + r.bottom) / 2);
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

  test('4. (v2.12, C212-01) moving after the preview no longer clears it: '
      'the rectangle follows the pen and end() commits the adjusted shape', () {
    fakeAsync((async) {
      const rect = Rect.fromLTWH(100, 100, 240, 160);
      final pen = _Pen(async);
      final path = SyntheticShapes.rectanglePath(rect);
      final s = pen.draw(path);
      final snapped = s.shapePreview.value!;
      final out = path.last - rect.center;
      final dir = out / out.distance;
      for (var k = 1; k <= 12; k++) {
        pen._step(8);
        s.addSample(pen._sample(path.last + dir * (5.0 * k)));
        expect(s.shapePreview.value, isNotNull, reason: 'step $k');
      }
      final edit = s.end()!;
      expect(edit.kind, ink.InkEditKind.addShape);
      final shape =
          (edit.toCommand() as core.AddObjects).objects.single
              as core.ShapeObject;
      expect(shape.shapeKind, core.ShapeKind.rectangle);
      final r0 = snapped.geometry.frame.rect;
      final r1 = shape.geometry.frame.rect;
      expect(
        r1.width * r1.height,
        greaterThan(r0.width * r0.height * 1.1),
        reason: 'dragging away from the centre grows it',
      );
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

  // Integration of the two 2026-11-16 tracks (C212-01 adjust, C213-01
  // recognition): a HAND-DRAWN triangle / ellipse (6.17.5 corpus, its own
  // ~0.5 s hold tail included) snaps through INK's real hold with the real
  // fitter, then the pen — still down — drags straight away from the shape's
  // centre: the preview stays the same kind and grows about a fixed centre
  // (uniform scale); dragging toward the centre shrinks it. end() commits ONE
  // addShape with the adjusted geometry.
  for (final kind in ['triangle', 'ellipse']) {
    for (final grow in [true, false]) {
      test('7. hand-drawn $kind + hold snaps, then dragging '
          '${grow ? 'outward grows' : 'inward shrinks'} it', () {
        final strokes = [
          for (final c in HandDrawnCorpus(1).build(perVariant: 4))
            if (c.variant.startsWith('$kind/') &&
                !c.variant.contains('small') &&
                !c.variant.contains('thin'))
              c,
        ];
        expect(strokes.length, greaterThanOrEqualTo(20));
        var snappedCount = 0;
        for (final c in strokes) {
          fakeAsync((async) {
            final pen = _Pen(async);
            final s = pen.draw(c.points);
            final before = s.shapePreview.value;
            if (verdictOf(before) != kind) return;
            snappedCount++;
            final r0 = before!.geometry.frame.rect;
            final centre = _centre(before.geometry);
            final last = c.points.last;
            var dir = last - centre;
            dir = dir / dir.distance;
            // straight out of / into the dead zone, then 30 pt more
            for (var k = 1; k <= 10; k++) {
              pen._step(8);
              s.addSample(pen._sample(last + dir * ((grow ? 5.0 : -5.0) * k)));
            }
            final during = s.shapePreview.value;
            expect(verdictOf(during), kind, reason: c.variant);
            final edit = s.end()!;
            expect(edit.kind, ink.InkEditKind.addShape, reason: c.variant);
            final shape =
                (edit.toCommand() as core.AddObjects).objects.single
                    as core.ShapeObject;
            expect(shape.shapeKind, before.kind, reason: c.variant);
            final r1 = shape.geometry.frame.rect;
            expect(
              (_centre(shape.geometry) - centre).distance,
              lessThan(1),
              reason: '${c.variant}: the centre stays',
            );
            if (grow) {
              expect(r1.width, greaterThan(r0.width * 1.05), reason: c.variant);
              expect(
                r1.height,
                greaterThan(r0.height * 1.05),
                reason: c.variant,
              );
            } else {
              expect(r1.width, lessThan(r0.width * 0.95), reason: c.variant);
              expect(r1.height, lessThan(r0.height * 0.95), reason: c.variant);
            }
            expect(
              r1.width / r1.height,
              closeTo(r0.width / r0.height, 0.02 * r0.width / r0.height),
              reason: '${c.variant}: uniform scale keeps the proportions',
            );
          });
        }
        // the corpus recall is ≥ 99 % (unit/shape_corpus_test.dart); here
        // nearly every stroke must snap through the real session too
        expect(
          snappedCount,
          greaterThanOrEqualTo((strokes.length * 0.9).ceil()),
        );
      });
    }
  }
}
