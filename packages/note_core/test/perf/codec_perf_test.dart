// CORE T18 — 9.1 budget: decoding one million points (StrokePointsCodec v1, 6.2.4).
@TestOn('vm')
@Tags(['perf'])
library;

import 'dart:typed_data';

import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import 'perf_support.dart';

void main() {
  test('decode 1,000,000 points < 300 ms', () {
    final ids = SequentialIdGenerator();
    final blobs = <Uint8List>[
      for (var i = 0; i < 10000; i++)
        StrokePointsCodec.encode(
          StrokeFixtures.synthetic(pageId: 'p', ids: ids, seed: i).points,
        ),
    ];
    var points = 0;
    for (final b in blobs.take(500)) {
      points += StrokePointsCodec.decode(b).length; // warm-up
    }
    expect(points, 500 * 100);

    final runs = <Duration>[];
    for (var r = 0; r < 3; r++) {
      final sw = Stopwatch()..start();
      points = 0;
      for (final b in blobs) {
        points += StrokePointsCodec.decode(b).length;
      }
      sw.stop();
      expect(points, 1000000);
      runs.add(sw.elapsed);
    }
    record(
      'decode 1,000,000 points (median of 3)',
      median(runs),
      budget: const Duration(milliseconds: 300),
      note: 'runs ${[for (final r in runs) ms(r)]}',
    );
  });
}
