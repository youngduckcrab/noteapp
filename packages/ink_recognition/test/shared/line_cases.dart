// Shared body (VM + Chrome) of the line grouping cases — m5-7/05-library 6.5
// (V9), 6.6, 8.2 L2-05. unit/group_into_lines_test.dart runs it on the VM,
// web/recognition_browser_test.dart on dart2js (L2-20): the same generator
// and the same grouping must give the same numbers there.
//
// lineAccuracy (6.5 '정확도 계산법'):
//  1. per stroke, the true line (from the id 'syn_<seed>_l<line>_<n>') and
//     the output line (its position in the output) → count matrix C;
//  2. one-to-one match: cells from the largest (ties: lower true line, then
//     lower output line) pair a true line and an output line when both are
//     still free (greedy, deterministic);
//  3. a stroke is right when its output line is its true line's match. Two
//     lines merged → one line's share is right; a line split → the smaller
//     part is wrong.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/lines/glyph_boxes.dart'
    show estimateGlyphHeight;
import 'package:ink_recognition/src/lines/group_into_lines.dart'
    show groupTraceIndices;
import 'package:ink_recognition/testing.dart';
import 'package:note_core/note_core.dart' as core;

final RegExp _synId = RegExp(r'^syn_\d+_l(\d\d)_\d{4}$');

/// The true line of a SyntheticHandwriting stroke id.
int trueLineOf(String strokeId) {
  final match = _synId.firstMatch(strokeId);
  if (match == null) throw ArgumentError.value(strokeId, 'strokeId');
  return int.parse(match.group(1)!);
}

/// Right strokes / all strokes of [page] for the grouping [output] (6.5).
/// [trueLine] defaults to [trueLineOf] the stroke id.
({int correct, int total}) lineAccuracy(
  List<core.Stroke> page,
  List<List<HandwritingTrace>> output, {
  int Function(String strokeId) trueLine = trueLineOf,
}) {
  final counts = <(int, int), int>{};
  for (final (o, line) in output.indexed) {
    for (final trace in line) {
      final key = (trueLine(trace.strokeId!), o);
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }
  final cells = counts.entries.toList()
    ..sort((a, b) {
      var c = b.value.compareTo(a.value);
      if (c != 0) return c;
      c = a.key.$1.compareTo(b.key.$1);
      return c != 0 ? c : a.key.$2.compareTo(b.key.$2);
    });
  final match = <int, int>{};
  final used = <int>{};
  for (final cell in cells) {
    final (truth, out) = cell.key;
    if (match.containsKey(truth) || used.contains(out)) continue;
    match[truth] = out;
    used.add(out);
  }
  var correct = 0;
  for (final cell in counts.entries) {
    if (match[cell.key.$1] == cell.key.$2) correct += cell.value;
  }
  return (correct: correct, total: page.length);
}

/// The V9 sweep (6.5 '완료 판정'): SyntheticHandwriting pages for [seeds] ×
/// [lineCounts], grouped with the default gapFactor.
final class V9Result {
  int correct = 0, total = 0, pages = 0, strokes = 0;
  int pagesBelow95 = 0, maxLineDiff = 0;
  double worstPage = 1;
  final Map<int, int> lineDiffs = {};

  double get accuracy => total == 0 ? 1 : correct / total;

  @override
  String toString() {
    final keys = lineDiffs.keys.toList()..sort();
    return 'V9: ${(100 * accuracy).toStringAsFixed(2)} % of $total strokes '
        'on $pages pages, worst page ${(100 * worstPage).toStringAsFixed(1)} '
        '%, pages < 95 %: $pagesBelow95, line count diff '
        '{${keys.map((k) => '$k: ${lineDiffs[k]}').join(', ')}}';
  }
}

V9Result runV9({
  Iterable<int> seeds = const [
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, //
    11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
  ],
  Iterable<int> lineCounts = const [3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
}) {
  final result = V9Result();
  for (final seed in seeds) {
    for (final lineCount in lineCounts) {
      final page = SyntheticHandwriting.lines(
        pageId: 'p1',
        lineCount: lineCount,
        seed: seed,
      );
      final output = groupIntoLines([
        for (final s in page) HandwritingTrace.fromStroke(s),
      ]);
      final (:correct, :total) = lineAccuracy(page, output);
      result
        ..correct += correct
        ..total += total
        ..pages += 1
        ..strokes += page.length;
      final share = correct / total;
      result.worstPage = math.min(result.worstPage, share);
      if (share < 0.95) result.pagesBelow95++;
      final diff = (output.length - lineCount).abs();
      result.maxLineDiff = math.max(result.maxLineDiff, diff);
      result.lineDiffs[diff] = (result.lineDiffs[diff] ?? 0) + 1;
    }
  }
  return result;
}

/// A straight stroke from (x0, y0) to (x1, y1), [n] points, first sample at
/// [t0] ms.
HandwritingTrace segment(
  String id,
  double x0,
  double y0,
  double x1,
  double y1, {
  double t0 = 0,
  int n = 6,
}) => HandwritingTrace(
  xs: Float32List.fromList([
    for (var i = 0; i < n; i++) x0 + (x1 - x0) * i / (n - 1),
  ]),
  ys: Float32List.fromList([
    for (var i = 0; i < n; i++) y0 + (y1 - y0) * i / (n - 1),
  ]),
  ts: Float64List.fromList([for (var i = 0; i < n; i++) t0 + 8.0 * i]),
  strokeId: id,
);

/// A glyph of two touching strokes (a bar and a cross bar) in the box
/// (left, top, size × size): ids `'<id>a'`, `'<id>b'`.
List<HandwritingTrace> glyph(
  String id,
  double left,
  double top,
  double size, {
  double t0 = 0,
}) => [
  segment('${id}a', left + size / 2, top, left + size / 2, top + size, t0: t0),
  segment(
    '${id}b',
    left,
    top + size / 2,
    left + size,
    top + size / 2,
    t0: t0 + 100,
  ),
];

List<List<String?>> idsOf(List<List<HandwritingTrace>> lines) => [
  for (final line in lines) [for (final t in line) t.strokeId],
];

void defineLineCaseTests() {
  group('lineAccuracy', () {
    core.Stroke stroke(String id) => core.Stroke(
      id: id,
      pageId: 'p1',
      style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
      points: core.StrokePoints.fromList(const [core.StrokePoint(0, 0)]),
      createdAt: 0,
    );
    final page = [
      for (final id in [
        'syn_1_l00_0000',
        'syn_1_l00_0001',
        'syn_1_l00_0002',
        'syn_1_l01_0003',
        'syn_1_l01_0004',
      ])
        stroke(id),
    ];
    List<HandwritingTrace> traces(List<int> picks) => [
      for (final i in picks) HandwritingTrace.fromStroke(page[i]),
    ];

    test('true lines → all right', () {
      expect(
        lineAccuracy(page, [
          traces([0, 1, 2]),
          traces([3, 4]),
        ]),
        (correct: 5, total: 5),
      );
    });

    test('two lines merged → only the larger line counts', () {
      expect(
        lineAccuracy(page, [
          traces([0, 1, 2, 3, 4]),
        ]),
        (correct: 3, total: 5),
      );
    });

    test('a line split → the smaller part is wrong', () {
      expect(
        lineAccuracy(page, [
          traces([0, 1]),
          traces([2]),
          traces([3, 4]),
        ]),
        (correct: 4, total: 5),
      );
    });

    test('ties: the lower true line, then the lower output line', () {
      // C = {(0,0): 1, (0,1): 1, (1,0): 1}, all equal: (0,0) is taken
      // first, (0,1) and (1,0) find a side already matched → true line 1
      // has no match and only the (0,0) stroke is right.
      final page3 = [page[0], page[1], page[3]];
      expect(
        lineAccuracy(page3, [
          [
            HandwritingTrace.fromStroke(page[0]),
            HandwritingTrace.fromStroke(page[3]),
          ],
          [HandwritingTrace.fromStroke(page[1])],
        ]),
        (correct: 1, total: 3),
      );
    });

    test('trueLineOf reads the 2-digit line of the id', () {
      expect(trueLineOf('syn_12_l07_0123'), 7);
      expect(() => trueLineOf('st1'), throwsArgumentError);
    });
  });

  group('groupIntoLines (6.5)', () {
    test('V9: seeds 1–20 × 3–12 lines → ≥ 95 % strokes, line count ± 1 '
        'on every page (E-L5: 100 %, all 0)', () {
      final result = runV9();
      // ignore: avoid_print — the 6.5 record (compared with E-L5 in the log)
      print(result);
      expect(result.pages, 200);
      expect(result.accuracy, greaterThanOrEqualTo(0.95));
      expect(result.maxLineDiff, lessThanOrEqualTo(1));
    });

    test('three words on one line, a second line below', () {
      final traces = [
        ...glyph('a', 40, 40, 20, t0: 0),
        ...glyph('b', 64, 40, 20, t0: 200),
        ...glyph('c', 100, 41, 20, t0: 400), // after a word gap (~0.8·H)
        ...glyph('d', 40, 90, 20, t0: 600),
        ...glyph('e', 64, 90, 20, t0: 800),
      ];
      expect(idsOf(groupIntoLines(traces)), [
        ['aa', 'ab', 'ba', 'bb', 'ca', 'cb'],
        ['da', 'db', 'ea', 'eb'],
      ]);
    });

    test('a gap wider than gapFactor·H splits the line; a larger factor '
        'joins it', () {
      final traces = [
        ...glyph('a', 40, 40, 20),
        ...glyph('b', 64, 40, 20, t0: 200),
        ...glyph('c', 114, 40, 20, t0: 400), // gap 30 pt = 1.5·H
      ];
      expect(groupIntoLines(traces), hasLength(2));
      expect(groupIntoLines(traces, gapFactor: 1.6), hasLength(1));
    });

    test('strokes in a line come by first-sample time (a late dot last)', () {
      final traces = [
        segment('dot', 50, 30, 51, 31, t0: 5000, n: 2),
        ...glyph('a', 40, 40, 20, t0: 0),
        ...glyph('b', 64, 40, 20, t0: 200),
      ];
      expect(idsOf(groupIntoLines(traces)), [
        ['aa', 'ab', 'ba', 'bb', 'dot'],
      ]);
    });

    test('the input order does not change synthetic pages', () {
      for (final seed in [1, 2, 3]) {
        final traces = [
          for (final s in SyntheticHandwriting.lines(
            pageId: 'p1',
            lineCount: 6,
            seed: seed,
          ))
            HandwritingTrace.fromStroke(s),
        ];
        final expected = idsOf(groupIntoLines(traces));
        final shuffled = [...traces]..shuffle(math.Random(seed));
        expect(idsOf(groupIntoLines(shuffled)), expected, reason: '$seed');
        expect(
          idsOf(groupIntoLines(traces.reversed.toList())),
          expected,
          reason: '$seed',
        );
      }
    });

    test('estimateGlyphHeight: the glyph height without dots; 4 pt floor', () {
      final traces = [
        ...glyph('a', 40, 40, 20),
        ...glyph('b', 100, 40, 20, t0: 200),
        segment('dot', 70, 30, 71, 31, n: 2),
      ];
      expect(estimateGlyphHeight(traces), 20);
      expect(estimateGlyphHeight(const []), 4);
      expect(estimateGlyphHeight([segment('tiny', 0, 0, 1, 1)]), 4);
    });

    test('groupTraceIndices gives the same lines as indices', () {
      final traces = [
        ...glyph('a', 40, 40, 20),
        ...glyph('d', 40, 90, 20, t0: 600),
      ];
      expect(groupTraceIndices(traces), [
        [0, 1],
        [2, 3],
      ]);
    });
  });
}
