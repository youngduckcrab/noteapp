// lib/src/ondevice/matrix_ink_hint.dart — (internal) ink evidence for the
// on-device math engine's matrix clean-up: when the column gap is narrower
// than about one letter, the model writes a matrix as one column whose cells
// hold whole rows (`{ 1 2 } \\ { 3 4 }`). The strokes still show where the
// columns are, so this counts the clear vertical gutters between the
// brackets; normalizeMfrLatex (latex_normalizer.dart) splits the column
// when the count fits.
//
// - tall strokes (height ≥ half the ink box) are delimiter strokes; those
//   whose x-ranges touch form one delimiter (a bracket may be several
//   strokes). The pair of neighbouring delimiters with the most short
//   strokes between them is the matrix (ink before it, `A =`, is fine);
// - short strokes that touch a delimiter's x-range (the serifs of `[`)
//   belong to it;
// - the interior strokes' x-ranges are merged; every gap wider than 0.2 ×
//   their median height is a gutter.
// No two delimiters or fewer than two interior strokes → null.
import 'dart:math' as math;

import '../model/handwriting_trace.dart';

/// The number of clear vertical gutters inside the bracketed matrix in
/// [traces], or null when the ink does not look like one.
int? matrixColumnGutters(List<HandwritingTrace> traces) {
  final boxes = <_Box>[
    for (final t in traces)
      if (t.xs.isNotEmpty && t.xs.length == t.ys.length) _Box.of(t),
  ];
  if (boxes.length < 4) return null;
  final top = boxes.map((b) => b.top).reduce(math.min);
  final bottom = boxes.map((b) => b.bottom).reduce(math.max);
  final height = bottom - top;
  if (height <= 0) return null;
  final touch = 0.05 * height;

  final tall = boxes.where((b) => b.height >= 0.5 * height).toList()
    ..sort((a, b) => a.left.compareTo(b.left));
  final short = boxes.where((b) => b.height < 0.5 * height).toList();
  // delimiters: tall strokes whose x-ranges touch
  final groups = <_Box>[];
  for (final b in tall) {
    if (groups.isNotEmpty && b.left <= groups.last.right + touch) {
      groups.last = groups.last.union(b);
    } else {
      groups.add(b);
    }
  }
  if (groups.length < 2) return null;

  List<_Box> between(_Box l, _Box r) => [
    for (final b in short)
      if (b.centerX > l.right &&
          b.centerX < r.left &&
          b.left > l.right + touch &&
          b.right < r.left - touch)
        b,
  ];
  var interior = const <_Box>[];
  for (var k = 0; k + 1 < groups.length; k++) {
    final inside = between(groups[k], groups[k + 1]);
    if (inside.length > interior.length) interior = inside;
  }
  if (interior.length < 2) return null;

  final heights = interior.map((b) => b.height).toList()..sort();
  final median = heights[heights.length ~/ 2];
  final tau = math.max(0.2 * median, 1e-3 * height);
  final spans = interior.toList()..sort((a, b) => a.left.compareTo(b.left));
  var gutters = 0;
  var reach = spans.first.right;
  for (final b in spans.skip(1)) {
    if (b.left - reach > tau) gutters++;
    reach = math.max(reach, b.right);
  }
  return gutters;
}

final class _Box {
  _Box(this.left, this.top, this.right, this.bottom);

  factory _Box.of(HandwritingTrace t) {
    var l = double.infinity, tp = double.infinity;
    var r = double.negativeInfinity, b = double.negativeInfinity;
    for (var i = 0; i < t.xs.length; i++) {
      l = math.min(l, t.xs[i]);
      r = math.max(r, t.xs[i]);
      tp = math.min(tp, t.ys[i]);
      b = math.max(b, t.ys[i]);
    }
    return _Box(l, tp, r, b);
  }

  final double left, top, right, bottom;

  double get height => bottom - top;
  double get centerX => (left + right) / 2;

  _Box union(_Box o) => _Box(
    math.min(left, o.left),
    math.min(top, o.top),
    math.max(right, o.right),
    math.max(bottom, o.bottom),
  );
}
