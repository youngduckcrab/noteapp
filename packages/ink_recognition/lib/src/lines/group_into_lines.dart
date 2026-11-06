// lib/src/lines/group_into_lines.dart — contract m5-7/00-overview 7.2.11
// (m5-7/05-library 4.4.6, 6.5).
//
// 2차 foundation step R2-B6: the simple form — every stroke with points is a
// line of its own, the lines in reading order (top edge, then left edge,
// then first-sample time, then input order). LIBRARY L2-05 replaces the body
// with the 6.5 algorithm (glyph boxes, line chains, small-box attachment);
// the signature and the output rules below stay.
import 'dart:math' as math;

import '../model/handwriting_trace.dart';

/// Pure Dart line grouping (search indexing AND lasso conversion use the same function).
/// (v2.1, CP-L7) Lines in reading order, strokes in a line by first-sample time; gapFactor = the
/// horizontal gap that still joins a line ÷ the median glyph-box height; deterministic.
List<List<HandwritingTrace>> groupIntoLines(
  List<HandwritingTrace> traces, {
  double gapFactor = 1.2,
}) {
  final keyed = <_TraceKey>[];
  for (var i = 0; i < traces.length; i++) {
    final trace = traces[i];
    if (trace.xs.isEmpty) continue; // no points → dropped (4.4.6)
    var top = double.infinity;
    var left = double.infinity;
    for (var p = 0; p < trace.xs.length; p++) {
      left = math.min(left, trace.xs[p]);
      top = math.min(top, trace.ys[p]);
    }
    final t0 = trace.ts.isEmpty ? 0.0 : trace.ts[0];
    keyed.add(_TraceKey(trace, top, left, t0, i));
  }
  keyed.sort(_TraceKey.compare);
  return [
    for (final k in keyed) [k.trace],
  ];
}

final class _TraceKey {
  const _TraceKey(this.trace, this.top, this.left, this.t0, this.index);

  final HandwritingTrace trace;
  final double top, left, t0;
  final int index;

  static int compare(_TraceKey a, _TraceKey b) {
    var c = a.top.compareTo(b.top);
    if (c != 0) return c;
    c = a.left.compareTo(b.left);
    if (c != 0) return c;
    c = a.t0.compareTo(b.t0);
    if (c != 0) return c;
    return a.index.compareTo(b.index);
  }
}
