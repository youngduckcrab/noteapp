// The matrix ink hint (ondevice/matrix_ink_hint.dart): clear vertical
// gutters between a matrix's brackets, from synthetic strokes (page pt).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/src/model/handwriting_trace.dart';
import 'package:ink_recognition/src/ondevice/matrix_ink_hint.dart';

/// A stroke through the points (x0, y0, x1, y1, …).
HandwritingTrace _stroke(List<double> xy) {
  final n = xy.length ~/ 2;
  return HandwritingTrace(
    xs: Float32List.fromList([for (var i = 0; i < n; i++) xy[2 * i]]),
    ys: Float32List.fromList([for (var i = 0; i < n; i++) xy[2 * i + 1]]),
    ts: Float64List.fromList([for (var i = 0; i < n; i++) i * 10.0]),
  );
}

/// A small letter-like loop in the box [x, x + w] × [y, y + h].
HandwritingTrace _glyph(double x, double y, {double w = 8, double h = 10}) =>
    _stroke([x, y, x + w, y, x + w, y + h, x, y + h, x, y + 2]);

/// `[` at [x] (a bar and two serifs) over [0, 40].
List<HandwritingTrace> _open(double x) => [
  _stroke([x, 0, x, 40]),
  _stroke([x, 0, x + 5, 0]),
  _stroke([x, 40, x + 5, 40]),
];

/// `]` at [x].
List<HandwritingTrace> _close(double x) => [
  _stroke([x, 0, x, 40]),
  _stroke([x - 5, 0, x, 0]),
  _stroke([x - 5, 40, x, 40]),
];

/// Two rows of glyphs starting at the x positions [columns].
List<HandwritingTrace> _grid(List<double> columns) => [
  for (final y in [5.0, 25.0])
    for (final x in columns) _glyph(x, y),
];

void main() {
  test('a tight 2×2 matrix (gap 0.5 × the height): one gutter', () {
    final traces = [
      ..._open(0),
      ..._grid([10, 23]),
      ..._close(41),
    ];
    expect(matrixColumnGutters(traces), 1);
  });

  test('three columns: two gutters', () {
    final traces = [
      ..._open(0),
      ..._grid([10, 23, 36]),
      ..._close(54),
    ];
    expect(matrixColumnGutters(traces), 2);
  });

  test('digits written close (12 / 34): no gutter', () {
    // gap 1 pt, far below 0.35 × 10 pt
    final traces = [
      ..._open(0),
      ..._grid([10, 19]),
      ..._close(37),
    ];
    expect(matrixColumnGutters(traces), 0);
  });

  test('three two-digit numbers (10 / 20 / 30, gaps 0.2 to 0.3 × the '
      'height): no gutter', () {
    final traces = [
      ..._open(0),
      for (final (y, gap) in [(2.0, 2.0), (15.0, 2.5), (28.0, 3.0)]) ...[
        _glyph(10, y),
        _glyph(18 + gap, y),
      ],
      ..._close(39),
    ];
    expect(matrixColumnGutters(traces), 0);
  });

  test('the space inside a number (12 / 34, 0.3 × the height): no gutter', () {
    final traces = [
      ..._open(0),
      ..._grid([10, 21]),
      ..._close(39),
    ];
    expect(matrixColumnGutters(traces), 0);
  });

  test('dots and minus signs do not shrink the threshold', () {
    // more flat strokes than glyphs, over the glyphs (no gaps of their own)
    final traces = [
      ..._open(0),
      ..._grid([10, 21]),
      for (final x in [11.0, 13.0, 22.0, 24.0, 26.0]) _stroke([x, 3, x + 1, 3]),
      ..._close(39),
    ];
    expect(matrixColumnGutters(traces), 0);
  });

  test('a matrix after A = counts only the ink between its brackets', () {
    final traces = [
      // a tall A (more than half the box) and =
      _stroke([-40, 32, -34, 10, -28, 32]),
      _stroke([-38, 24, -30, 24]),
      _stroke([-22, 18, -14, 18]),
      _stroke([-22, 22, -14, 22]),
      ..._open(0),
      ..._grid([10, 23]),
      ..._close(41),
    ];
    expect(matrixColumnGutters(traces), 1);
  });

  test('a bracket drawn in several strokes is one delimiter', () {
    final traces = [
      _stroke([0, 0, 0, 21]),
      _stroke([0, 20, 0, 40]),
      _stroke([0, 0, 5, 0]),
      _stroke([0, 40, 5, 40]),
      ..._grid([10, 23]),
      ..._close(41),
    ];
    expect(matrixColumnGutters(traces), 1);
  });

  test('no brackets, or too little inside: null', () {
    expect(matrixColumnGutters(_grid([10, 22])), isNull);
    expect(matrixColumnGutters([..._open(0), ..._close(40)]), isNull);
    expect(
      matrixColumnGutters([..._open(0), _glyph(10, 15), ..._close(40)]),
      isNull,
    );
    expect(matrixColumnGutters(const []), isNull);
  });
}
