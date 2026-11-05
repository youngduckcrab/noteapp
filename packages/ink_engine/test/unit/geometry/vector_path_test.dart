// T07 (03-ink 8, 4.5, 6.8 O7, 6.24): StrokeOutline.toVectorPath / toPath and
// InkVectorPath — the quadratic → cubic conversion keeps the curve, and the
// bounds match the outline.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/stroke_outline.dart';

import '../../support/outline_helpers.dart';

void _expectInside(ui.Rect inner, ui.Rect outer, {double tol = 0.01}) {
  expect(inner.left, greaterThanOrEqualTo(outer.left - tol));
  expect(inner.top, greaterThanOrEqualTo(outer.top - tol));
  expect(inner.right, lessThanOrEqualTo(outer.right + tol));
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom + tol));
}

void _expectRectClose(ui.Rect a, ui.Rect b, {double tol = 0.01}) {
  expect(a.left, closeTo(b.left, tol));
  expect(a.top, closeTo(b.top, tol));
  expect(a.right, closeTo(b.right, tol));
  expect(a.bottom, closeTo(b.bottom, tol));
}

StrokeOutline _wave() => outlineFor(
  sampleCurve(
    (u) => ui.Offset(30 + 200 * u, 100 + 40 * math.sin(u * 2 * math.pi)),
    length: 260,
  ),
  width: 6,
);

ui.Offset _quad(ui.Offset p0, ui.Offset c, ui.Offset p1, double t) =>
    p0 * ((1 - t) * (1 - t)) + c * (2 * (1 - t) * t) + p1 * (t * t);

ui.Offset _cubic(List<ui.Offset> p, double t) {
  final s = 1 - t;
  return p[0] * (s * s * s) +
      p[1] * (3 * s * s * t) +
      p[2] * (3 * s * t * t) +
      p[3] * (t * t * t);
}

void main() {
  test('smooth: false → the polygon edges, bounds = outline bounds', () {
    final o = _wave();
    final vp = o.toVectorPath(smooth: false);
    final poly = o.polygons.single;
    expect(vp.verbs.first, InkPathVerb.moveTo.index);
    expect(vp.verbs.last, InkPathVerb.close.index);
    expect(
      vp.verbs.where((v) => v == InkPathVerb.lineTo.index),
      hasLength(poly.length ~/ 2 - 1),
    );
    expect(vp.coords, poly);
    _expectRectClose(vp.bounds, o.bounds);
    _expectRectClose(vp.toUiPath().getBounds(), o.bounds);
    _expectRectClose(o.toPath(smooth: false).getBounds(), o.bounds);
  });

  test('smooth: quadratic → cubic keeps the end points and the curve', () {
    final o = _wave();
    final poly = o.polygons.single;
    final m = poly.length ~/ 2;
    ui.Offset v(int i) => ui.Offset(poly[2 * (i % m)], poly[2 * (i % m) + 1]);
    ui.Offset mid(int i) => (v(i) + v(i + 1)) / 2;

    final vp = o.toVectorPath();
    expect(vp.verbs.first, InkPathVerb.moveTo.index);
    expect(vp.verbs.last, InkPathVerb.close.index);
    final cubics = vp.verbs.where((x) => x == InkPathVerb.cubicTo.index);
    expect(cubics, hasLength(m));
    expect(vp.coords.length, 2 + 6 * m);
    // moveTo(mid(v_{m−1}, v_0))
    expect(vp.coords[0], closeTo(mid(m - 1).dx, 1e-4));
    expect(vp.coords[1], closeTo(mid(m - 1).dy, 1e-4));
    var p0 = mid(m - 1);
    for (var i = 0; i < m; i++) {
      final c = 2 + 6 * i;
      final pts = [
        p0,
        ui.Offset(vp.coords[c], vp.coords[c + 1]),
        ui.Offset(vp.coords[c + 2], vp.coords[c + 3]),
        ui.Offset(vp.coords[c + 4], vp.coords[c + 5]),
      ];
      // end point = mid(v_i, v_{i+1})
      expect((pts[3] - mid(i)).distance, lessThan(1e-4));
      for (final t in [0.25, 0.5, 0.75]) {
        final q = _quad(p0, v(i), mid(i), t);
        expect((_cubic(pts, t) - q).distance, lessThan(1e-3));
      }
      p0 = pts[3];
    }
    _expectInside(vp.bounds, o.bounds);
    _expectInside(vp.toUiPath().getBounds(), o.bounds);
    _expectInside(o.toPath().getBounds(), o.bounds);
  });

  test('smooth paths fill the same area (ui.Path vs InkVectorPath)', () {
    final o = _wave();
    final a = o.toPath();
    final b = o.toVectorPath().toUiPath();
    final box = o.bounds;
    var checked = 0;
    for (var y = box.top; y <= box.bottom; y += 1.37) {
      for (var x = box.left; x <= box.right; x += 1.91) {
        final p = ui.Offset(x, y);
        // skip points right on the boundary (± rounding)
        final near =
            a.contains(p + const ui.Offset(0.05, 0)) !=
            a.contains(p - const ui.Offset(0.05, 0));
        if (near) continue;
        expect(b.contains(p), a.contains(p), reason: '$p');
        checked++;
      }
    }
    expect(checked, greaterThan(1000));
  });

  test('dot → 4 cubics on the circle, bounds = circle bounds', () {
    final o = outlineFor([const ui.Offset(40, 50)], width: 3, widthQ: 0.5);
    final vp = o.toVectorPath();
    expect(vp.verbs, [
      InkPathVerb.moveTo.index,
      InkPathVerb.cubicTo.index,
      InkPathVerb.cubicTo.index,
      InkPathVerb.cubicTo.index,
      InkPathVerb.cubicTo.index,
      InkPathVerb.close.index,
    ]);
    // every on-curve point is at r = 3 from the center
    for (final i in [0, 6, 12, 18, 24]) {
      final p = ui.Offset(vp.coords[i], vp.coords[i + 1]);
      expect((p - const ui.Offset(40, 50)).distance, closeTo(3, 1e-4));
    }
    _expectRectClose(vp.bounds, o.bounds);
    _expectRectClose(vp.toUiPath().getBounds(), o.bounds);
  });

  test('several polygons → one moveTo … close per polygon', () {
    final o = outlineFor([
      for (var i = 0; i <= 50; i++) ui.Offset(10.0 + i, 20),
      for (var i = 49; i >= 0; i--) ui.Offset(10.0 + i, 20),
    ]);
    expect(o.polygons.length, greaterThanOrEqualTo(2));
    for (final smooth in [true, false]) {
      final vp = o.toVectorPath(smooth: smooth);
      expect(
        vp.verbs.where((v) => v == InkPathVerb.moveTo.index),
        hasLength(o.polygons.length),
      );
      expect(
        vp.verbs.where((v) => v == InkPathVerb.close.index),
        hasLength(o.polygons.length),
      );
    }
  });

  test('InkVectorPath: empty → Rect.zero, nonzero fill', () {
    final empty = InkVectorPath(Uint8List(0), Float32List(0));
    expect(empty.bounds, ui.Rect.zero);
    expect(empty.toUiPath().fillType, ui.PathFillType.nonZero);
    expect(_wave().toPath().fillType, ui.PathFillType.nonZero);
  });
}
