// B12 calligraphy outline, B13 dashed outline, B20 hold detection
// (m5-7/03-ink 6.25, 9.5, T43). Run: flutter test benchmark/ (bench tag).
@Tags(['bench'])
library;

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/shape/hold_detector.dart';
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

  group('B20 hold detection per sample (6.18)', () {
    // cursive writing: the anchor moves every few samples (the no-sample timer is
    // re-armed each time); a fast line: every sample moves it (the worst case).
    final cursive = cursiveSamples(2000);
    final fast = [
      for (var i = 0; i < 2000; i++)
        InkSample(
          position: ui.Offset(40 + 9.0 * i, 300),
          timeUs: i * 4167,
          kind: InkPointerKind.stylus,
          pressure: 0.5,
        ),
    ];
    for (final (name, samples) in [
      ('cursive 2000 samples, 240 Hz', cursive),
      ('fast line 2000 samples (9 pt apart)', fast),
    ]) {
      test(name, () {
        var anchorMoves = 0;
        final stats = measure(
          () {
            final first = samples.first;
            final d = HoldDetector(
              start: first.position,
              startUs: first.timeUs,
              viewScale: 1,
              onHold: () {},
              onMove: () {},
            );
            var anchor = d.anchor;
            var moves = 0;
            for (var i = 1; i < samples.length; i++) {
              final s = samples[i];
              d.add(s.position, s.timeUs);
              if (d.anchor != anchor) {
                anchor = d.anchor;
                moves++;
              }
            }
            d.stop();
            anchorMoves = moves;
          },
          warmup: 5,
          runs: 30,
        );
        // per sample
        final perSample = BenchStats([
          for (final ms in stats.samples) ms / (samples.length - 1),
        ]);
        expect(anchorMoves, greaterThan(samples.length ~/ 10));
        report(
          'B20',
          'hold detection: $name',
          perSample,
          criteria: {'median_ms': 0.02},
          extra: {'anchor_moves': anchorMoves},
        );
      });
    }
  });
}
