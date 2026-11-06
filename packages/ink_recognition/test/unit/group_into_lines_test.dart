// groupIntoLines — 2차 foundation step R2-B6 body (m5-7/05-library 8.1 B6-b:
// one line per stroke). Checks the output rules the real algorithm keeps
// (4.4.6): strokes without points are dropped, lines in reading order, the
// result does not depend on the input order. LIBRARY L2-05 replaces the body
// and adds the 6.5 / V9 cases (shared/line_cases.dart, lineAccuracy).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';

HandwritingTrace _trace(String id, double x, double y, double t0) =>
    HandwritingTrace(
      xs: Float32List.fromList([x, x + 10]),
      ys: Float32List.fromList([y, y + 10]),
      ts: Float64List.fromList([t0, t0 + 8]),
      strokeId: id,
    );

List<String?> _ids(List<List<HandwritingTrace>> lines) => [
  for (final line in lines)
    for (final t in line) t.strokeId,
];

void main() {
  test('empty input → empty list; strokes without points are dropped', () {
    expect(groupIntoLines(const []), isEmpty);
    final empty = HandwritingTrace(
      xs: Float32List(0),
      ys: Float32List(0),
      ts: Float64List(0),
      strokeId: 'empty',
    );
    final lines = groupIntoLines([empty, _trace('a', 0, 0, 1)]);
    expect(_ids(lines), ['a']);
  });

  test('R2-B6: one line per stroke, in reading order (top, then left)', () {
    final traces = [
      _trace('second-line', 40, 100, 1),
      _trace('first-right', 200, 40, 2),
      _trace('first-left', 40, 40, 3),
    ];
    final lines = groupIntoLines(traces);
    expect(lines, hasLength(3));
    expect(lines.every((l) => l.length == 1), isTrue);
    expect(_ids(lines), ['first-left', 'first-right', 'second-line']);
  });

  test('deterministic: the input order does not change the result', () {
    final traces = [
      _trace('a', 40, 40, 1),
      _trace('b', 80, 40, 2),
      _trace('c', 40, 90, 3),
      _trace('d', 10, 90, 4),
    ];
    final expected = _ids(groupIntoLines(traces));
    expect(_ids(groupIntoLines(traces.reversed.toList())), expected);
    expect(
      _ids(groupIntoLines([traces[2], traces[0], traces[3], traces[1]])),
      expected,
    );
    expect(_ids(groupIntoLines(traces, gapFactor: 1.5)), expected);
  });
}
