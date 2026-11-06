// B12 calligraphy outline, B13 dashed outline, B20 hold detection
// (m5-7/03-ink 6.25, 9.5, T43). Run: flutter test benchmark/ (bench tag).
@Tags(['bench'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:note_core/note_core.dart' as core;

import 'support/bench.dart';
import 'support/workloads.dart';

void main() {
  group('B12 calligraphy outline (nib)', () {
    for (final (points, limit) in [(200, 0.2), (1000, 0.6)]) {
      test('$points points', () {
        final stroke = cursiveStroke(points, tool: core.PenTool.calligraphy);
        expect(stroke.profile.renderMethod, InkRenderMethod.nibOutline);
        var vertices = 0;
        final stats = measure(
          () => vertices = OutlineGenerator.outline(stroke).vertexCount,
          warmup: 5,
          runs: 30,
          inner: 40,
        );
        expect(vertices, greaterThan(points ~/ 4));
        report(
          'B12',
          'calligraphy outline $points pt (angle 45°, aspect '
              '${stroke.style.nibAspect})',
          stats,
          criteria: {'median_ms': limit},
          extra: {'outline_vertices': vertices},
        );
      });
    }
  });

  test('B13 dashed outline: 1000 points, default pattern', () {
    final stroke = cursiveStroke(1000, tool: core.PenTool.dashed);
    expect(stroke.profile.renderMethod, InkRenderMethod.dashedPolyline);
    var pieces = 0, vertices = 0;
    final stats = measure(
      () {
        final o = OutlineGenerator.outline(stroke);
        pieces = o.polygons.length + o.dots.length;
        vertices = o.vertexCount;
      },
      warmup: 5,
      runs: 30,
      inner: 20,
    );
    expect(pieces, greaterThan(10));
    report(
      'B13',
      'dashed outline 1000 pt (pattern ${stroke.style.dashPattern})',
      stats,
      criteria: {'median_ms': 0.8},
      extra: {'pieces': pieces, 'outline_vertices': vertices},
    );
  });

  test(
    'B20 hold detection per sample',
    () {},
    skip:
        'T39 (P-B, 6.18) is not implemented: there is no hold detector to '
        'measure yet (03-ink 8.2 cut order T44 → T39)',
  );
}
