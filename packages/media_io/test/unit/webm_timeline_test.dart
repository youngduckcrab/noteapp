// WebM timeline length and header patch (m5-7/06-pdf 6.8.7, 6.6.4; 8.2 T32a — PDF-M6, R-3).
// Hand samples from test/support/webm_builder.dart (each case of the 6.8.7 last paragraph —
// test/support/webm_timeline_cases.dart, also run in Chrome) and the six Chrome MediaRecorder
// recordings of 6.1 E9 (test/support/fixtures/chrome_opus_*.webm — fake microphone tone). The
// Chrome values were computed by the plan-stage parser (pdf57-rev/webm/ebml.py — a separate
// Python implementation) with the packet length taken from the last block's TOC (20 ms × 3).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/record/webm_timeline.dart';

import '../support/webm_builder.dart';
import '../support/webm_timeline_cases.dart';

Uint8List _fixture(String name) =>
    File('test/support/fixtures/$name').readAsBytesSync();

void main() {
  webmTimelineCases();

  group('Chrome MediaRecorder recordings (6.1 E9)', () {
    // file → (lastBlockStartMs, endMs). 64 kbps audio/webm;codecs=opus, start(1000): Segment and
    // Cluster sizes unknown, no Duration, 60 ms packets; paused spans are not in the timecodes.
    const recordings = {
      'chrome_opus_r0.webm': (1979, 2039), // 2 s active
      'chrome_opus_r1.webm': (1980, 2040), // 2 s active (E11)
      'chrome_opus_r3.webm': (1979, 2039), // 2 s active
      'chrome_opus_r2.webm': (3300, 3360), // 3.3 s
      'chrome_opus_r4.webm': (4980, 5040), // 5 s
      'chrome_opus_rec.webm': (2939, 2999), // 1.5 s + pause 1 s + 1.5 s
    };

    for (final MapEntry(key: name, value: (start, end)) in recordings.entries) {
      test('$name → endMs $end', () {
        final bytes = _fixture(name);
        expect(WebmTimeline.measure(bytes), (
          lastBlockStartMs: start,
          endMs: end,
          packetMs: 60,
        ));
        // Patched with its own length, then measured again: the same values.
        final patch = WebmTimeline.patchedHead(bytes, end)!;
        final patched = applyPatch(bytes, patch);
        expect(patched.length, bytes.length + 11);
        expect(WebmTimeline.measure(patched), WebmTimeline.measure(bytes));
      });
    }

    test(
      'the r1 patch is byte for byte the E11 file (<audio> read 2.04 s)',
      () {
        final original = _fixture('chrome_opus_r1.webm');
        final reference = _fixture('chrome_opus_r1_patched.webm');
        final patch = WebmTimeline.patchedHead(original, 2040)!;
        expect(patch.restOffset, 78);
        expect(patch.bytes.length, 89);
        expect(applyPatch(original, patch), reference);
      },
    );

    test('a recovered draft cut in its last chunk', () {
      final bytes = _fixture('chrome_opus_r4.webm');
      // One block is 483 B: cutting 100 B drops the last 60 ms packet.
      expect(WebmTimeline.measure(cutEnd(bytes, 100)), (
        lastBlockStartMs: 4920,
        endMs: 4980,
        packetMs: 60,
      ));
    });
  });
}
