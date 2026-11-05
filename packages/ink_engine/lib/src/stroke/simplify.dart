// lib/src/stroke/simplify.dart — INTERNAL (not exported): 03-ink 6.7 F7.
//
// RDP on x·y (tolerance finishSimplifyPt = 0.03 pt) over the interleaved
// finish data [x, y, widthQ, tilt, azimuth, t]; a point whose widthQ differs
// by more than finishSimplifyWidthQ (0.004, 1.6 % of the width) from the
// linear widthQ of its chord (by arc length) is kept too, as are both ends.
// When the result still has more than core.StrokePoints.maxLength points the
// tolerances are doubled and the data simplified again (at most
// maxSimplifyRetries times); after that the first maxLength points are kept.
//
// RDP runs in windows of _window points (the window ends are always kept):
// RDP is O(n²) on unlucky input (a zigzag of equal teeth), and finish runs
// on the UI thread at pen lift — the windows bound it at O(n · _window).
// Strokes up to _window points (almost all) are simplified in one piece.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;

import '../geometry/rdp.dart';
import '../tuning.dart';

const int _stride = core.StrokePoints.stride;
const int _window = 1024;

/// F7 with the retry rule. [maxPoints] = core.StrokePoints.maxLength
/// (smaller values only in tests). Returns [data] itself when nothing is
/// dropped.
Float32List simplifyStrokeData(
  Float32List data, {
  int maxPoints = core.StrokePoints.maxLength,
}) {
  var tol = InkTuning.finishSimplifyPt;
  var tolQ = InkTuning.finishSimplifyWidthQ;
  var out = simplifyOnce(data, tolerance: tol, widthQTolerance: tolQ);
  for (
    var retry = 0;
    retry < InkTuning.maxSimplifyRetries && out.length ~/ _stride > maxPoints;
    retry++
  ) {
    tol *= 2;
    tolQ *= 2;
    out = simplifyOnce(data, tolerance: tol, widthQTolerance: tolQ);
  }
  if (out.length ~/ _stride > maxPoints) {
    out = Float32List.fromList(
      Float32List.sublistView(out, 0, maxPoints * _stride),
    );
  }
  return out;
}

/// One RDP pass (see the file comment). Returns [data] itself when every
/// point is kept.
Float32List simplifyOnce(
  Float32List data, {
  required double tolerance,
  required double widthQTolerance,
}) {
  final n = data.length ~/ _stride;
  if (n <= 2) return data;
  final cum = Float64List(n);
  for (var i = 1; i < n; i++) {
    final dx = data[i * _stride] - data[(i - 1) * _stride];
    final dy = data[i * _stride + 1] - data[(i - 1) * _stride + 1];
    cum[i] = cum[i - 1] + math.sqrt(dx * dx + dy * dy);
  }
  double error(int a, int b, int i) {
    final oa = a * _stride, ob = b * _stride, oi = i * _stride;
    final d = segmentDistance(
      data[oi],
      data[oi + 1],
      data[oa],
      data[oa + 1],
      data[ob],
      data[ob + 1],
    );
    final span = cum[b] - cum[a];
    final u = span > 0 ? (cum[i] - cum[a]) / span : (i - a) / (b - a);
    final qa = data[oa + 2], qb = data[ob + 2];
    final dq = (data[oi + 2] - (qa + (qb - qa) * u)).abs();
    return math.max(d / tolerance, dq / widthQTolerance);
  }

  final keep = List<bool>.filled(n, false);
  for (var from = 0; from < n - 1; from += _window - 1) {
    rdpMark(keep, from, math.min(from + _window - 1, n - 1), error);
  }
  var kept = 0;
  for (final k in keep) {
    if (k) kept++;
  }
  if (kept == n) return data;
  final out = Float32List(kept * _stride);
  var o = 0;
  for (var i = 0; i < n; i++) {
    if (!keep[i]) continue;
    out.setRange(o, o + _stride, data, i * _stride);
    o += _stride;
  }
  return out;
}
