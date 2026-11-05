// B1 outline generation, B2 live per-sample cost (03-ink 9.1, T22).
// Run: flutter test benchmark/ (bench tag; never part of `flutter test`).
@Tags(['bench'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import 'support/bench.dart';
import 'support/workloads.dart';

void main() {
  group('B1 outline generation', () {
    for (final (points, limit) in [(200, 0.15), (1000, 0.5)]) {
      test('$points points', () {
        final stroke = cursiveStroke(points);
        var vertices = 0;
        final stats = measure(
          () => vertices = OutlineGenerator.outline(stroke).vertexCount,
          warmup: 5,
          runs: 30,
          inner: 40,
        );
        expect(vertices, greaterThan(points ~/ 4));
        report(
          'B1',
          'outline $points pt (fountain)',
          stats,
          criteria: {'median_ms': limit},
          extra: {'outline_vertices': vertices},
        );
      });
    }
  });

  test('B2 live sample: add + live geometry (2000-sample stroke)', () {
    final samples = cursiveSamples(2000);
    final style = core.StrokeStyle.defaultsFor(core.PenTool.fountain);
    // 2 warm-up strokes (JIT), then 5 measured ones. mean = every measured
    // sample; max = the slowest sample index after taking, per index, the
    // fastest of the 5 strokes — a GC pause or a preemption by another
    // process hits one stroke at random, the cost of the pipeline itself
    // (a chunk freeze, a long tail) hits all five.
    final rounds = <BenchStats>[];
    final perIndex = List<double>.filled(samples.length, double.infinity);
    for (var round = 0; round < 7; round++) {
      final c = createTestPageController();
      c.updateContent(SyntheticInk.pageContent());
      late StrokeSession session;
      final times = <double>[];
      final s = measureSteps(samples.length, (i) {
        if (i == 0) {
          session = c.beginStroke(samples[0], style: style, viewScale: 2);
        } else {
          session.addSample(samples[i]);
        }
        // What the active layer paints every frame.
        session.live.frozenPath;
        session.live.tailPath;
      }, record: times);
      session.cancel();
      c.dispose();
      if (round < 2) continue;
      rounds.add(s);
      for (var i = 0; i < times.length; i++) {
        if (times[i] < perIndex[i]) perIndex[i] = times[i];
      }
    }
    final all = BenchStats([for (final r in rounds) ...r.samples]);
    final structural = BenchStats(perIndex);
    report(
      'B2',
      'live sample (fountain, 240 Hz) — mean',
      all,
      criteria: {'mean_ms': 0.3},
    );
    report(
      'B2',
      'live sample (fountain, 240 Hz) — max (per-index best of 5)',
      structural,
      criteria: {'max_ms': 1.0},
      extra: {'raw_max_ms': all.max, 'raw_p99_ms': all.percentile(0.99)},
    );
  });
}
