// lib/src/geometry/rdp.dart — INTERNAL (not exported): Ramer–Douglas–Peucker.
//
// Shared by the finish simplification (6.7 F7, stroke/simplify.dart) and the
// outline simplification (6.8 O8). Iterative (explicit stack), so 100 000
// points do not recurse.
import 'dart:math' as math;

/// Error of point [i] against the chord [a] → [b], scaled so that > 1 means
/// "keep" (for example distance / tolerance).
typedef RdpError = double Function(int a, int b, int i);

/// Marks the points of [from]..[to] (inclusive) that RDP keeps: [from] and
/// [to] always, an interior point when its [error] on the current chord is the
/// largest one and > 1 (then both halves are processed the same way).
void rdpMark(List<bool> keep, int from, int to, RdpError error) {
  keep[from] = true;
  keep[to] = true;
  final stack = <int>[from, to];
  while (stack.isNotEmpty) {
    final b = stack.removeLast();
    final a = stack.removeLast();
    if (b - a < 2) continue;
    var worst = 1.0;
    var at = -1;
    for (var i = a + 1; i < b; i++) {
      final e = error(a, b, i);
      if (e > worst) {
        worst = e;
        at = i;
      }
    }
    if (at < 0) continue;
    keep[at] = true;
    stack
      ..add(a)
      ..add(at)
      ..add(at)
      ..add(b);
  }
}

/// Distance of (px, py) from the segment (ax, ay) → (bx, by); the distance to
/// a when the segment has length 0.
double segmentDistance(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  var u = 0.0;
  if (len2 > 0) {
    u = ((px - ax) * dx + (py - ay) * dy) / len2;
    if (u < 0) u = 0;
    if (u > 1) u = 1;
  }
  final ex = px - (ax + u * dx), ey = py - (ay + u * dy);
  return math.sqrt(ex * ex + ey * ey);
}
