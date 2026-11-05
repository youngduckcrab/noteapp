// T18 (03-ink 6.22, 4.7 numeric contract): SelectionGeometry — the one
// implementation of selection-transform math. The handle opposite the dragged
// one stays fixed, corner + keepAspect projects onto the diagonal, edge
// handles scale one axis, per-axis scale in [0.05, 20], the box's short side
// never below 4 pt, never flips; widths = clamp(width × uniformScale, 0.1,
// 30); rotation / snapAngle; and the previews match CORE's
// Stroke.transformed (the final geometry) within 0.01 pt.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:note_core/note_core.dart' as core;

import '../../support/pixels.dart';

const _box = ui.Rect.fromLTRB(100, 100, 300, 200); // 200 × 100

ui.Offset _apply(core.Affine2 m, ui.Offset p) => interop.applyAffine(m, p);

/// The point of [r] that [h] drags and the one that stays fixed.
(ui.Offset, ui.Offset) _handleAndAnchor(ui.Rect r, SelectionHandle h) =>
    switch (h) {
      SelectionHandle.topLeft => (r.topLeft, r.bottomRight),
      SelectionHandle.top => (r.topCenter, r.bottomCenter),
      SelectionHandle.topRight => (r.topRight, r.bottomLeft),
      SelectionHandle.right => (r.centerRight, r.centerLeft),
      SelectionHandle.bottomRight => (r.bottomRight, r.topLeft),
      SelectionHandle.bottom => (r.bottomCenter, r.topCenter),
      SelectionHandle.bottomLeft => (r.bottomLeft, r.topRight),
      SelectionHandle.left => (r.centerLeft, r.centerRight),
    };

Matcher _near(ui.Offset p, [double eps = 1e-9]) => isA<ui.Offset>()
    .having((o) => o.dx, 'dx', closeTo(p.dx, eps))
    .having((o) => o.dy, 'dy', closeTo(p.dy, eps));

Matcher _rectNear(ui.Rect r, [double eps = 1e-9]) => isA<ui.Rect>()
    .having((o) => o.left, 'left', closeTo(r.left, eps))
    .having((o) => o.top, 'top', closeTo(r.top, eps))
    .having((o) => o.right, 'right', closeTo(r.right, eps))
    .having((o) => o.bottom, 'bottom', closeTo(r.bottom, eps));

void main() {
  group('resize', () {
    test('the opposite handle stays fixed (all 8 handles)', () {
      for (final h in SelectionHandle.values) {
        for (final keep in [true, false]) {
          final m = SelectionGeometry.resize(
            bounds: _box,
            handle: h,
            delta: const ui.Offset(37, -23),
            keepAspect: keep,
          );
          final (_, anchor) = _handleAndAnchor(_box, h);
          expect(_apply(m, anchor), _near(anchor), reason: '$h keep $keep');
          // axis-aligned scaling only
          expect((m.b, m.c), (0, 0));
          expect(m.a > 0 && m.d > 0, isTrue);
        }
      }
    });

    test('corner + keepAspect: projection onto the diagonal', () {
      // diagonal (200, 100); dragged size (250, 125) → s = 1.25
      final m = SelectionGeometry.resize(
        bounds: _box,
        handle: SelectionHandle.bottomRight,
        delta: const ui.Offset(50, 25),
      );
      expect((m.a, m.d), (1.25, 1.25));
      expect(
        SelectionGeometry.transformedBounds(_box, m),
        _rectNear(const ui.Rect.fromLTRB(100, 100, 350, 225)),
      );
      // off-diagonal drag: only the projection counts
      final off = SelectionGeometry.resize(
        bounds: _box,
        handle: SelectionHandle.bottomRight,
        delta: const ui.Offset(10, -20), // (210, 80) · (200, 100) / 50000
      );
      expect(off.a, closeTo((210 * 200 + 80 * 100) / 50000, 1e-12));
      expect(off.d, off.a);
      // top-left corner: growing means dragging up-left
      final tl = SelectionGeometry.resize(
        bounds: _box,
        handle: SelectionHandle.topLeft,
        delta: const ui.Offset(-50, -25),
      );
      expect(
        SelectionGeometry.transformedBounds(_box, tl),
        _rectNear(const ui.Rect.fromLTRB(50, 75, 300, 200)),
      );
    });

    test('corner without keepAspect, edge handles scale one axis', () {
      final free = SelectionGeometry.resize(
        bounds: _box,
        handle: SelectionHandle.bottomRight,
        delta: const ui.Offset(50, 40),
        keepAspect: false,
      );
      expect((free.a, free.d), (1.25, 1.4));
      final right = SelectionGeometry.resize(
        bounds: _box,
        handle: SelectionHandle.right,
        delta: const ui.Offset(30, 999),
      );
      expect((right.a, right.d), (1.15, 1.0));
      final top = SelectionGeometry.resize(
        bounds: _box,
        handle: SelectionHandle.top,
        delta: const ui.Offset(999, -20),
      );
      expect((top.a, top.d), (1.0, 1.2));
      expect(
        SelectionGeometry.transformedBounds(_box, top),
        _rectNear(const ui.Rect.fromLTRB(100, 80, 300, 200)),
      );
      final left = SelectionGeometry.resize(
        bounds: _box,
        handle: SelectionHandle.left,
        delta: const ui.Offset(50, 0),
      );
      expect(
        SelectionGeometry.transformedBounds(_box, left),
        _rectNear(const ui.Rect.fromLTRB(150, 100, 300, 200)),
      );
    });

    test('scale per axis in [0.05, 20]', () {
      final big = SelectionGeometry.resize(
        bounds: _box,
        handle: SelectionHandle.right,
        delta: const ui.Offset(10000, 0),
      );
      expect(big.a, InkTuning.scaleMax);
      final bigCorner = SelectionGeometry.resize(
        bounds: _box,
        handle: SelectionHandle.bottomRight,
        delta: const ui.Offset(100000, 50000),
      );
      expect((bigCorner.a, bigCorner.d), (20.0, 20.0));
      const wide = ui.Rect.fromLTWH(0, 0, 1000, 1000);
      final small = SelectionGeometry.resize(
        bounds: wide,
        handle: SelectionHandle.right,
        delta: const ui.Offset(-999, 0),
      );
      expect(small.a, InkTuning.scaleMin);
    });

    test('short side >= 4 pt; never flips', () {
      const narrow = ui.Rect.fromLTWH(0, 0, 40, 200);
      final shrink = SelectionGeometry.resize(
        bounds: narrow,
        handle: SelectionHandle.right,
        delta: const ui.Offset(-39, 0),
      );
      expect(
        SelectionGeometry.transformedBounds(narrow, shrink).width,
        closeTo(InkTuning.selectionMinSizePt, 1e-9),
      );
      // dragged past the opposite edge: fixed at the minimum, not mirrored
      final past = SelectionGeometry.resize(
        bounds: narrow,
        handle: SelectionHandle.left,
        delta: const ui.Offset(500, 0),
      );
      expect(past.a, greaterThan(0));
      final pastBox = SelectionGeometry.transformedBounds(narrow, past);
      expect(pastBox.width, closeTo(4, 1e-9));
      expect(pastBox.right, closeTo(narrow.right, 1e-9));
      // corner with aspect: the shorter side reaches 4 pt first
      final corner = SelectionGeometry.resize(
        bounds: narrow,
        handle: SelectionHandle.bottomRight,
        delta: const ui.Offset(-1000, -1000),
      );
      final cornerBox = SelectionGeometry.transformedBounds(narrow, corner);
      expect(cornerBox.width, closeTo(4, 1e-9));
      expect(cornerBox.height, closeTo(20, 1e-9));
      expect(corner.a, corner.d);
      for (final h in SelectionHandle.values) {
        for (final d in const [
          ui.Offset(-5000, -5000),
          ui.Offset(5000, 5000),
          ui.Offset(-5000, 5000),
          ui.Offset(5000, -5000),
        ]) {
          for (final keep in [true, false]) {
            final m = SelectionGeometry.resize(
              bounds: _box,
              handle: h,
              delta: d,
              keepAspect: keep,
            );
            final r = SelectionGeometry.transformedBounds(_box, m);
            expect(m.a > 0 && m.d > 0, isTrue, reason: '$h $d');
            expect(r.shortestSide, greaterThanOrEqualTo(4 - 1e-9));
            for (final s in [m.a, m.d]) {
              expect(s, inInclusiveRange(0.05, 20));
            }
          }
        }
      }
    });

    test('a side already under 4 pt does not shrink; it may grow', () {
      const line = ui.Rect.fromLTWH(10, 10, 300, 2);
      final down = SelectionGeometry.resize(
        bounds: line,
        handle: SelectionHandle.bottom,
        delta: const ui.Offset(0, -1),
      );
      expect(down.d, 1);
      final up = SelectionGeometry.resize(
        bounds: line,
        handle: SelectionHandle.bottom,
        delta: const ui.Offset(0, 10),
      );
      expect(up.d, 6);
    });

    test('NaN drag → no scale', () {
      final m = SelectionGeometry.resize(
        bounds: _box,
        handle: SelectionHandle.right,
        delta: const ui.Offset(double.nan, 0),
      );
      expect(m.isIdentity, isTrue);
    });
  });

  group('move, rotate, snap', () {
    test('move = translation', () {
      expect(
        SelectionGeometry.move(const ui.Offset(3, -4)),
        core.Affine2.translation(3, -4),
      );
    });

    test('rotate around the center; snapAngle 15° steps within 3°', () {
      final m = SelectionGeometry.rotate(bounds: _box, radians: math.pi / 2);
      expect(_apply(m, _box.center), _near(_box.center));
      expect(m.rotation, closeTo(math.pi / 2, 1e-12));
      expect(m.uniformScale, closeTo(1, 1e-12));
      // the 200 × 100 box turns into 100 × 200 around (200, 150)
      expect(
        SelectionGeometry.transformedBounds(_box, m),
        _rectNear(const ui.Rect.fromLTRB(150, 50, 250, 250), 1e-9),
      );
      double deg(double d) => d * math.pi / 180;
      expect(SelectionGeometry.snapAngle(deg(14)), closeTo(deg(15), 1e-12));
      expect(SelectionGeometry.snapAngle(deg(-29)), closeTo(deg(-30), 1e-12));
      expect(SelectionGeometry.snapAngle(deg(2.9)), 0);
      expect(SelectionGeometry.snapAngle(deg(11)), deg(11));
      expect(SelectionGeometry.snapAngle(deg(48.5)), deg(48.5));
      expect(
        SelectionGeometry.snapAngle(
          deg(48.5),
          step: deg(45),
          threshold: deg(5),
        ),
        closeTo(deg(45), 1e-12),
      );
    });

    test('transformedCorners: clockwise from top-left', () {
      expect(
        SelectionGeometry.transformedCorners(_box, core.Affine2.identity),
        [_box.topLeft, _box.topRight, _box.bottomRight, _box.bottomLeft],
      );
      final m = SelectionGeometry.rotate(bounds: _box, radians: math.pi / 2);
      final corners = SelectionGeometry.transformedCorners(_box, m);
      // y down: a quarter turn clockwise on screen moves top-left to top-right
      expect(corners[0], _near(const ui.Offset(250, 50), 1e-9));
      expect(corners[1], _near(const ui.Offset(250, 250), 1e-9));
      expect(corners[2], _near(const ui.Offset(150, 250), 1e-9));
      expect(corners[3], _near(const ui.Offset(150, 50), 1e-9));
    });

    test('boundsOf: union of CORE bounds; empty → Rect.zero', () {
      expect(SelectionGeometry.boundsOf(const []), ui.Rect.zero);
      final pen = core.StrokeStyle.defaultsFor(core.PenTool.ballpoint);
      final a = InkStroke.of(
        strokeThrough(
          segment(const ui.Offset(10, 10), const ui.Offset(50, 20)),
          pen,
        ),
      );
      final b = InkStroke.of(
        strokeThrough(
          segment(const ui.Offset(100, 5), const ui.Offset(90, 80)),
          pen,
        ),
      );
      expect(
        SelectionGeometry.boundsOf([a, b]),
        a.bounds.expandToInclude(b.bounds),
      );
      expect(SelectionGeometry.boundsOf([a]), interop.rectOf(a.source.bounds));
    });
  });

  group('width', () {
    test('transformedWidth = clamp(width × uniformScale, 0.1, 30)', () {
      final s2 = core.Affine2.scaling(2, 2);
      expect(SelectionGeometry.transformedWidth(1.5, s2), 3);
      expect(
        SelectionGeometry.transformedWidth(3, core.Affine2.scaling(20, 20)),
        30,
      );
      expect(
        SelectionGeometry.transformedWidth(1, core.Affine2.scaling(0.05, 0.05)),
        core.StrokeStyle.minWidth,
      );
      // anisotropic: sqrt(|det|)
      expect(
        SelectionGeometry.transformedWidth(2, core.Affine2.scaling(4, 1)),
        closeTo(4, 1e-12),
      );
      expect(
        SelectionGeometry.transformedWidth(2, core.Affine2.rotation(1.1)),
        closeTo(2, 1e-12),
      );
    });
  });

  group('CORE Stroke.transformed agreement (final geometry)', () {
    final rnd = math.Random(18);
    final strokes = [
      for (final tool in [
        core.PenTool.ballpoint,
        core.PenTool.fountain,
        core.PenTool.highlighter,
        core.PenTool.pencil,
        core.PenTool.marker,
      ])
        strokeThrough(
          [
            for (var i = 0; i < 40; i++)
              ui.Offset(
                120 + i * 4.0 + rnd.nextDouble(),
                140 + 30 * math.sin(i / 5) + rnd.nextDouble(),
              ),
          ],
          core.StrokeStyle.defaultsFor(tool)
              .copyWith(width: 0.3 + rnd.nextDouble() * 6),
          tilt: tool == core.PenTool.pencil ? 0.6 : 0,
        ),
    ];
    final inks = strokes.map(InkStroke.of).toList();
    final bounds = SelectionGeometry.boundsOf(inks);
    final transforms = <String, core.Affine2>{
      'move': SelectionGeometry.move(const ui.Offset(12.345, -7.891)),
      'corner': SelectionGeometry.resize(
        bounds: bounds,
        handle: SelectionHandle.topLeft,
        delta: const ui.Offset(-31.7, -9.2),
      ),
      'corner free': SelectionGeometry.resize(
        bounds: bounds,
        handle: SelectionHandle.bottomLeft,
        delta: const ui.Offset(13.3, 41.9),
        keepAspect: false,
      ),
      'edge': SelectionGeometry.resize(
        bounds: bounds,
        handle: SelectionHandle.right,
        delta: const ui.Offset(77.7, 0),
      ),
      'shrink': SelectionGeometry.resize(
        bounds: bounds,
        handle: SelectionHandle.bottomRight,
        delta: const ui.Offset(-150, -40),
      ),
      'grow': SelectionGeometry.resize(
        bounds: bounds,
        handle: SelectionHandle.bottomRight,
        delta: const ui.Offset(3000, 900),
      ),
      'rotate': SelectionGeometry.rotate(
        bounds: bounds,
        radians: SelectionGeometry.snapAngle(0.27),
      ),
      'rotate+move': SelectionGeometry.rotate(
        bounds: bounds,
        radians: -2.2,
      ).then(SelectionGeometry.move(const ui.Offset(5, 9))),
    };

    for (final MapEntry(key: name, value: m) in transforms.entries) {
      test('$name: preview points ≤ 0.01 pt, width = CORE', () {
        for (final s in strokes) {
          final coreResult = s.transformed(m);
          final corePoints = InkPoints.of(coreResult.points);
          final ink = InkStroke.of(s);
          for (var i = 0; i < ink.points.length; i++) {
            final preview = _apply(m, ink.points.offsetAt(i));
            expect(
              (preview - corePoints.offsetAt(i)).distance,
              lessThanOrEqualTo(0.01),
              reason: '${s.style.tool} point $i',
            );
          }
          expect(
            SelectionGeometry.transformedWidth(s.style.width, m),
            coreResult.style.width,
          );
          // the in-memory preview stroke is exactly CORE's result
          final previewStroke = interop.previewTransformedOf(s, m);
          expect(previewStroke.points.contentEquals(coreResult.points), isTrue);
          expect(previewStroke.style, coreResult.style);
          expect(previewStroke.id, s.id);
          // the selection frame preview contains the transformed strokes'
          // centerlines
          final frame = SelectionGeometry.transformedBounds(
            bounds,
            m,
          ).inflate(0.01);
          final r = coreResult.points.pointBounds;
          expect(frame.contains(ui.Offset(r.left, r.top)), isTrue);
          expect(frame.contains(ui.Offset(r.right, r.bottom)), isTrue);
        }
      });
    }
  });
}
