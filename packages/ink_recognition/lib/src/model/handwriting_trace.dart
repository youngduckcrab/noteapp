// lib/src/model/handwriting_trace.dart — contract m5-7/00-overview 7.2.11
// (m5-7/05-library 4.2, 4.4.6, 6.4). Final since the 2차 foundation step
// R2-B6.
//
// One stroke as recognizer input: page pt and absolute wall-clock ms. The
// times are a Float64List, not an Int64List: dart2js has no Int64List, and a
// double holds every 13-digit epoch ms exactly (integers up to 2^53 — 1차
// 7.4.3 web-safe numbers).
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:note_core/note_core.dart' as core;

final class HandwritingTrace {
  // one stroke; page pt; absolute ms
  const HandwritingTrace({
    required this.xs,
    required this.ys,
    required this.ts,
    this.strokeId,
  });

  /// ts = createdAt + t(i). Point i: xs[i] = x, ys[i] = y, ts[i] =
  /// stroke.createdAt + t(i); strokeId = stroke.id. A stroke without points
  /// gives three empty lists (05-library 4.4.6).
  factory HandwritingTrace.fromStroke(core.Stroke stroke) {
    final points = stroke.points;
    final n = points.length;
    final xs = Float32List(n);
    final ys = Float32List(n);
    final ts = Float64List(n);
    final createdAt = stroke.createdAt.toDouble();
    for (var i = 0; i < n; i++) {
      xs[i] = points.x(i);
      ys[i] = points.y(i);
      ts[i] = createdAt + points.t(i);
    }
    return HandwritingTrace(xs: xs, ys: ys, ts: ts, strokeId: stroke.id);
  }

  final Float32List xs, ys;

  /// Float64List, NOT Int64List (dart2js, 1차 7.4.3 웹 안전 수치).
  final Float64List ts;
  final String? strokeId;

  @override
  String toString() =>
      'HandwritingTrace(${strokeId ?? '-'}, ${xs.length} points)';
}

final class HandwritingLineInput {
  const HandwritingLineInput(
    this.traces, {
    this.preContext = '',
    this.writingAreaPt,
  });

  final List<HandwritingTrace> traces;
  final String preContext;
  final Size? writingAreaPt;

  @override
  String toString() =>
      'HandwritingLineInput(${traces.length} traces, '
      'preContext: ${preContext.length} chars, area: $writingAreaPt)';
}
