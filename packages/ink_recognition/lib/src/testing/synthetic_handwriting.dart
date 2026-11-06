// lib/src/testing/synthetic_handwriting.dart — body of
// package:ink_recognition/testing.dart SyntheticHandwriting (contract
// m5-7/00-overview 7.6, m5-7/05-library 4.3, 6.6).
//
// 2차 foundation step R2-B6: a simple generator that already follows the
// contract id format and the 6.6 frame (Random(seed) only, no clock, page
// width 595 pt, margin 40 pt, glyph height H ∈ [14, 28] pt, line pitch
// ∈ [1.6, 2.4]·H, 8 ms between points, increasing createdAt from
// 1,730,790,000,000, ballpoint default style, StrokePoints.fromList).
// LIBRARY L2-05 replaces the body with the 6.6 v2.1 generator (the E-L5
// prototype — slant, line gap guarantee, filled glyph boxes, late marks) and
// pins its output in unit/synthetic_handwriting_test.dart.
import 'dart:math' as math;

import 'package:note_core/note_core.dart' as core;

const double _pageWidth = 595;
const double _margin = 40;
const int _baseCreatedAt = 1730790000000;
const int _pointIntervalMs = 8;

// Stroke id 'syn_<seed>_l<line, 2 digits>_<n, 4 digits>': line from 0, n =
// stroke number on the page from 0 (both in writing order).
String _strokeId(int seed, int line, int n) =>
    'syn_${seed}_l${line.toString().padLeft(2, '0')}_'
    '${n.toString().padLeft(4, '0')}';

abstract final class SyntheticHandwriting {
  // fixed-seed lines as core.Stroke lists
  /// (v2.1) stroke ids `'syn_<seed>_l<line>_<n>'` (CP-L4)
  // Line from 0 (2 digits), n = stroke number on the page from 0 (4 digits);
  // createdAt increases in writing order. lineCount outside 0..99 →
  // ArgumentError (the id has two line digits).
  static List<core.Stroke> lines({
    required String pageId,
    int lineCount = 5,
    int seed = 1,
  }) => _lines(pageId: pageId, lineCount: lineCount, seed: seed);
}

List<core.Stroke> _lines({
  required String pageId,
  required int lineCount,
  required int seed,
}) {
  if (lineCount < 0 || lineCount > 99) {
    throw ArgumentError.value(lineCount, 'lineCount', 'must be 0..99');
  }
  final rnd = math.Random(seed);
  double u(double a, double b) => a + (b - a) * rnd.nextDouble();
  int ui(int a, int b) => a + rnd.nextInt(b - a + 1);

  final glyphHeight = u(14, 28);
  final pitch = u(1.6, 2.4) * glyphHeight;
  final style = core.StrokeStyle.defaultsFor(core.PenTool.ballpoint);
  final out = <core.Stroke>[];
  var clock = _baseCreatedAt;
  var n = 0;
  var baseline = _margin + glyphHeight;

  for (var line = 0; line < lineCount; line++) {
    var x = _margin;
    final words = ui(2, 5);
    for (var w = 0; w < words; w++) {
      final letters = ui(2, 5);
      for (var k = 0; k < letters; k++) {
        final width = u(0.8, 1.1) * glyphHeight;
        if (x + width > _pageWidth - _margin) break;
        final top = baseline - glyphHeight;
        // One zigzag stroke per glyph: 6–12 points across the glyph box.
        final count = ui(6, 12);
        final points = <core.StrokePoint>[
          for (var p = 0; p < count; p++)
            core.StrokePoint(
              x + width * p / (count - 1),
              p.isEven
                  ? top + u(0, 0.2) * glyphHeight
                  : baseline - u(0, 0.2) * glyphHeight,
              t: (p * _pointIntervalMs).toDouble(),
            ),
        ];
        out.add(
          core.Stroke(
            id: _strokeId(seed, line, n),
            pageId: pageId,
            style: style,
            points: core.StrokePoints.fromList(points),
            createdAt: clock,
          ),
        );
        n++;
        clock += count * _pointIntervalMs + ui(80, 200);
        x += width + u(0.05, 0.2) * glyphHeight;
      }
      x += u(0.4, 0.9) * glyphHeight;
    }
    clock += ui(600, 1500);
    baseline += pitch;
  }
  return out;
}
