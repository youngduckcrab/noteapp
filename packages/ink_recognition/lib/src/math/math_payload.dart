// lib/src/math/math_payload.dart — (internal, pure) m5-7/05-library 6.11.3;
// contract m5-7/00-overview 7.2.13 `recognizeMath` input (v2.1, CP-L8):
//
//   {"data": {"v": 1, "engine": "auto", "locale": "ko",
//     "strokes": {"x": [[…]], "y": [[…]], "t": [[…]]}, "pngBase64": "…"}}
//
// - x, y: page pt with 1 decimal; t: integer ms from the first sample of the
//   first stroke. Traces without points are left out; no points at all → no
//   `strokes` key (PNG only — the server answers invalid-argument when both
//   are missing; the client does not block that).
// - The strokes JSON is at most 512 KB (524,288 B): above it every stroke is
//   thinned with Ramer–Douglas–Peucker at ε = 0.25 → 0.5 → 1 → 2 pt (from
//   the original points each time); still above → RecognizerEngineError
//   ('too-large').
// - pngBase64 only when the input has a PNG and its base64 is at most 2 MB
//   (above it the PNG is left out — the server limit, E10).
// - Always `v: 1` (E4). Nothing else of the note goes in (G-3).
import 'dart:convert';
import 'dart:math' as math;

import '../model/failures.dart';
import '../model/handwriting_trace.dart';
import '../model/math_types.dart';

/// Limits of the request body (contract 7.2.13).
const int kMathStrokesMaxBytes = 524288;
const int kMathPngBase64MaxChars = 2 * 1024 * 1024;

/// The thinning steps tried in turn when the strokes are too large (pt).
const List<double> kMathThinningEpsilons = [0.25, 0.5, 1, 2];

/// The callable request body: `{"data": <buildMathData(...)>}` as JSON. The
/// strokes JSON measured for the 512 KB limit is reused, not encoded again.
String encodeMathRequest(
  MathInput input, {
  required String engine,
  required String locale,
}) {
  final strokes = _encodedStrokes(input.traces);
  final png = _pngBase64(input);
  final out = StringBuffer('{"data":{"v":1,"engine":')
    ..write(jsonEncode(engine))
    ..write(',"locale":')
    ..write(jsonEncode(locale));
  if (strokes != null) {
    out
      ..write(',"strokes":')
      ..write(strokes.json);
  }
  if (png != null) {
    out
      ..write(',"pngBase64":')
      ..write(jsonEncode(png));
  }
  out.write('}}');
  return out.toString();
}

/// The `data` object of the callable request (6.11.3).
Map<String, Object?> buildMathData(
  MathInput input, {
  required String engine,
  required String locale,
}) {
  final data = <String, Object?>{'v': 1, 'engine': engine, 'locale': locale};
  final strokes = mathStrokesOf(input.traces);
  if (strokes != null) data['strokes'] = strokes;
  final png = _pngBase64(input);
  if (png != null) data['pngBase64'] = png;
  return data;
}

String? _pngBase64(MathInput input) {
  final png = input.png;
  if (png == null || png.isEmpty) return null;
  final encoded = base64Encode(png);
  return encoded.length <= kMathPngBase64MaxChars ? encoded : null;
}

/// `{"x": [[…]], "y": [[…]], "t": [[…]]}` of [traces] within 512 KB (thinned
/// if needed), or null when no trace has a point.
Map<String, List<List<num>>>? mathStrokesOf(List<HandwritingTrace> traces) =>
    _encodedStrokes(traces)?.strokes;

({Map<String, List<List<num>>> strokes, String json})? _encodedStrokes(
  List<HandwritingTrace> traces,
) {
  final drawn = [
    for (final t in traces)
      if (t.xs.isNotEmpty) t,
  ];
  if (drawn.isEmpty) return null;
  final t0 = drawn.first.ts.first;
  var strokes = _strokes(drawn, t0, null);
  var json = jsonEncode(strokes);
  if (json.length <= kMathStrokesMaxBytes) {
    return (strokes: strokes, json: json); // ASCII only: length = bytes
  }
  for (final epsilon in kMathThinningEpsilons) {
    strokes = _strokes(drawn, t0, epsilon);
    json = jsonEncode(strokes);
    if (json.length <= kMathStrokesMaxBytes) {
      return (strokes: strokes, json: json);
    }
  }
  throw RecognizerEngineError(
    'too-large',
    'strokes are ${json.length} B after thinning at '
        '${kMathThinningEpsilons.last} pt (limit $kMathStrokesMaxBytes B)',
  );
}

double _round1(double v) => (v * 10).roundToDouble() / 10;

Map<String, List<List<num>>> _strokes(
  List<HandwritingTrace> traces,
  double t0,
  double? epsilon,
) {
  final xs = <List<num>>[];
  final ys = <List<num>>[];
  final ts = <List<num>>[];
  for (final trace in traces) {
    final keep = epsilon == null ? null : rdpKeep(trace.xs, trace.ys, epsilon);
    final n = trace.xs.length;
    final x = <num>[];
    final y = <num>[];
    final t = <num>[];
    for (var i = 0; i < n; i++) {
      if (keep != null && !keep[i]) continue;
      x.add(_round1(trace.xs[i]));
      y.add(_round1(trace.ys[i]));
      t.add((trace.ts[i] - t0).round());
    }
    xs.add(x);
    ys.add(y);
    ts.add(t);
  }
  return {'x': xs, 'y': ys, 't': ts};
}

/// Ramer–Douglas–Peucker: which points of the polyline ([xs], [ys]) stay at
/// tolerance [epsilon] (pt). The first and last point always stay.
List<bool> rdpKeep(List<double> xs, List<double> ys, double epsilon) {
  final n = xs.length;
  final keep = List<bool>.filled(n, false);
  if (n == 0) return keep;
  keep[0] = true;
  keep[n - 1] = true;
  final stack = <(int, int)>[(0, n - 1)];
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    if (b <= a + 1) continue;
    var worst = -1.0;
    var at = -1;
    for (var i = a + 1; i < b; i++) {
      final d = _segmentDistance(xs[i], ys[i], xs[a], ys[a], xs[b], ys[b]);
      if (d > worst) {
        worst = d;
        at = i;
      }
    }
    if (worst > epsilon) {
      keep[at] = true;
      stack
        ..add((a, at))
        ..add((at, b));
    }
  }
  return keep;
}

double _segmentDistance(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final dx = bx - ax;
  final dy = by - ay;
  final length2 = dx * dx + dy * dy;
  if (length2 == 0) {
    return math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
  }
  final u = (((px - ax) * dx + (py - ay) * dy) / length2).clamp(0.0, 1.0);
  final cx = ax + u * dx;
  final cy = ay + u * dy;
  return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
}
