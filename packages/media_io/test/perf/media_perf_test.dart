// Performance on the VM (m5-7/06-pdf 6.17 · 9.5; 8.2 T41 — P-C): offsetNowMs() 100 000 times
// (the pen-down read of the recording clock — synchronous, no allocation, about 1 µs) and the
// image normalizer's slow path for a 4000 × 3000 JPEG → 2048 × 1536 in an isolate (≤ 2 s).
// The values are printed for the progress log.
//
// Wall-clock bound on purpose: perf tag, skipped by default
// (`ws test --package media_io --run-skipped -t perf`). Building the samples is not timed.
@Tags(['perf'])
@TestOn('vm')
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:media_io/src/image/image_codec_io.dart';
import 'package:media_io/src/image/image_normalizer.dart';
import 'package:media_io/src/record/recording_clock.dart';
import 'package:note_core/note_core.dart' as core;

img.Image _gradient(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (final p in image) {
    p
      ..r = p.x * 255 ~/ max(1, w - 1)
      ..g = p.y * 255 ~/ max(1, h - 1)
      ..b = 128;
  }
  return image;
}

void main() {
  test('offsetNowMs: 100 000 calls while recording ≤ 200 ms (≈ 1 µs each)', () {
    final clock = RecordingClock()..start();
    var sum = 0;
    for (var i = 0; i < 10000; i++) {
      sum += offsetNowMsOf(core.RecorderPhase.recording, clock)!; // warm-up
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < 100000; i++) {
      sum += offsetNowMsOf(core.RecorderPhase.recording, clock)!;
    }
    watch.stop();
    final perCall = watch.elapsedMicroseconds / 100000;
    debugPrint(
      'media perf: offsetNowMs ${perCall.toStringAsFixed(3)} µs/call '
      '(${watch.elapsedMicroseconds} µs for 100 000; checksum $sum)',
    );
    expect(sum, greaterThanOrEqualTo(0));
    expect(watch.elapsed, lessThanOrEqualTo(const Duration(milliseconds: 200)));
    expect(offsetNowMsOf(core.RecorderPhase.paused, clock), isNull);
  });

  test(
    'image normalizer: 4000 × 3000 JPEG → 2048 × 1536 in an isolate ≤ 2 s',
    () async {
      final jpeg = img.encodeJpg(_gradient(4000, 3000), quality: 90);
      const normalizer = ImageNormalizer(codec: IoImageCodec());
      await normalizer.normalize(
        img.encodeJpg(_gradient(400, 300)),
      ); // isolate warm-up

      final watch = Stopwatch()..start();
      final n = await normalizer.normalize(jpeg);
      watch.stop();
      debugPrint(
        'media perf: normalize 4000x3000 JPEG (${jpeg.length} B) → '
        '${n.width}x${n.height} ${n.mimeType} (${n.bytes.length} B) in '
        '${watch.elapsedMilliseconds} ms',
      );
      expect((n.width, n.height), (2048, 1536));
      expect(n.path, NormalizePath.slow);
      expect(watch.elapsed, lessThanOrEqualTo(const Duration(seconds: 2)));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
