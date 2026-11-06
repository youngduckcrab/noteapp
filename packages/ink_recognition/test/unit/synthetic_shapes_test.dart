// SyntheticShapes.rectanglePath (contract m5-7/00-overview 7.6; m5-7/05-library
// 4.3, 8.1 B6-b). R2-B6 part: the path shape — clockwise centreline from the
// middle of the top edge, pointsPerSide samples per side, exactly closed —
// and the ArgumentError rules. The 'GeometricShapeFitter judges it a
// rectangle' assertions (aspect 1:1–4:1, 48–2400 pt, pointsPerSide 4–48,
// viewScale 0.25–4) are switched on with L2-06 (LIBRARY-F2: a commit that
// changes the ShapeFitTuning defaults runs this file).
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/testing.dart';
import 'package:material_ui/material_ui.dart' show Offset, Rect;

/// Whether [p] lies on the outline of [r].
bool _onBoundary(Offset p, Rect r) {
  const eps = 1e-9;
  final onX = (p.dx - r.left).abs() < eps || (p.dx - r.right).abs() < eps;
  final onY = (p.dy - r.top).abs() < eps || (p.dy - r.bottom).abs() < eps;
  final insideX = p.dx >= r.left - eps && p.dx <= r.right + eps;
  final insideY = p.dy >= r.top - eps && p.dy <= r.bottom + eps;
  return insideX && insideY && (onX || onY);
}

/// Signed area (shoelace) — positive = clockwise in y-down page coordinates.
double _signedArea(List<Offset> path) {
  var sum = 0.0;
  for (var i = 0; i + 1 < path.length; i++) {
    sum += path[i].dx * path[i + 1].dy - path[i + 1].dx * path[i].dy;
  }
  return sum / 2;
}

void main() {
  const rect = Rect.fromLTWH(100, 200, 240, 120);

  test('default: 24 points per side, 4 × 24 + 1 points, exactly closed', () {
    final path = SyntheticShapes.rectanglePath(rect);
    expect(path, hasLength(4 * 24 + 1));
    expect(path.first, const Offset(220, 200)); // middle of the top edge
    expect(path.last, path.first); // exactly closed (==, no tolerance)
    expect(path.last.dx, path.first.dx);
    expect(path.last.dy, path.first.dy);
  });

  test('every point is on the rectangle, the four corners are visited', () {
    final path = SyntheticShapes.rectanglePath(rect);
    for (final p in path) {
      expect(_onBoundary(p, rect), isTrue, reason: '$p');
    }
    for (final corner in [
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
      rect.topLeft,
    ]) {
      expect(path.where((p) => p == corner), hasLength(1), reason: '$corner');
    }
    // Clockwise order of the corners (y down): top-right, bottom-right,
    // bottom-left, top-left.
    final order = [
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
      rect.topLeft,
    ].map(path.indexOf).toList();
    expect(order, orderedEquals([...order]..sort()));
    expect(_signedArea(path), closeTo(rect.width * rect.height, 1e-6));
  });

  test('pointsPerSide samples per side, evenly spaced', () {
    for (final n in [4, 5, 7, 24, 48]) {
      final path = SyntheticShapes.rectanglePath(rect, pointsPerSide: n);
      expect(path, hasLength(4 * n + 1), reason: 'n=$n');
      final right = path
          .where((p) => p.dx == rect.right && p.dy < rect.bottom)
          .toList();
      expect(right, hasLength(n), reason: 'right side, n=$n');
      for (var i = 1; i < right.length; i++) {
        expect(right[i].dy - right[i - 1].dy, closeTo(rect.height / n, 1e-9));
      }
      // The top side: both halves, without the top-right corner (the first
      // sample of the right side) and without the closing point.
      final top = path
          .sublist(0, path.length - 1)
          .where((p) => p.dy == rect.top && p.dx < rect.right);
      expect(top, hasLength(n), reason: 'top side, n=$n');
      // No two consecutive points are equal (no zero-length steps).
      for (var i = 1; i < path.length; i++) {
        expect(path[i], isNot(path[i - 1]), reason: 'n=$n, i=$i');
      }
    }
  });

  test('the 48 pt rule uses the default ShapeFitTuning', () {
    expect(2 * const ShapeFitTuning().minDiagonalLogicalPx, 48);
    expect(
      SyntheticShapes.rectanglePath(const Rect.fromLTWH(0, 0, 48, 48)),
      hasLength(97),
    );
    expect(
      SyntheticShapes.rectanglePath(const Rect.fromLTWH(0, 0, 2400, 600)),
      hasLength(97),
    );
  });

  test('out of range → ArgumentError', () {
    for (final bad in [
      const Rect.fromLTWH(0, 0, 47.9, 100),
      const Rect.fromLTWH(0, 0, 100, 47.9),
      const Rect.fromLTRB(100, 100, 0, 0), // negative size
      Rect.zero,
      const Rect.fromLTWH(0, 0, double.infinity, 100),
      const Rect.fromLTWH(double.nan, 0, 100, 100),
    ]) {
      expect(
        () => SyntheticShapes.rectanglePath(bad),
        throwsArgumentError,
        reason: '$bad',
      );
    }
    for (final n in [3, 0, -1]) {
      expect(
        () => SyntheticShapes.rectanglePath(rect, pointsPerSide: n),
        throwsArgumentError,
        reason: 'pointsPerSide $n',
      );
    }
  });
}
