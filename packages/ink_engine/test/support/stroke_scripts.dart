// Recorded-style sample scripts and an arithmetic checksum (03-ink 5.6, 9.1).
// Shared by the VM tests (test/unit) and the browser tests (test/web): the
// same script must give the same checksum on both.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/stroke/stroke_builder.dart';
import 'package:note_core/note_core.dart' as core;

/// A fixed stylus script: an S curve of 240 samples at 120 Hz (2 s), pressure
/// rising then falling (0.2 … 0.9), tilt growing, no azimuth (web-like),
/// with a jittered sample clock and a few duplicates.
List<InkSample> scriptedStroke({
  InkPointerKind kind = InkPointerKind.stylus,
  Offset origin = const Offset(80, 120),
}) {
  const n = 240;
  final out = <InkSample>[];
  for (var i = 0; i < n; i++) {
    final u = i / (n - 1);
    final x = origin.dx + 260 * u;
    final y = origin.dy + 40 * math.sin(u * 2 * math.pi);
    // 8333 µs ± a few µs, deterministic
    final timeUs = i * 8333 + (i % 7) * 3;
    out.add(
      InkSample(
        position: Offset(x, y),
        timeUs: timeUs,
        kind: kind,
        pressure: 0.2 + 0.7 * math.sin(u * math.pi),
        tilt: 0.2 + 0.9 * u,
      ),
    );
    if (i % 50 == 25) {
      // a duplicate 1 ms later: merged (pressure only)
      out.add(
        InkSample(
          position: Offset(x + 0.01, y),
          timeUs: timeUs + 1000,
          kind: kind,
          pressure: 0.2 + 0.7 * math.sin(u * math.pi) + 0.01,
          tilt: 0.2 + 0.9 * u,
        ),
      );
    }
  }
  return out;
}

/// The styles the determinism checksum covers.
const List<core.PenTool> scriptedTools = [
  core.PenTool.ballpoint,
  core.PenTool.fountain,
  core.PenTool.highlighter,
  core.PenTool.pencil,
  core.PenTool.marker,
];

/// Arithmetic checksum of interleaved stroke data on CORE's quantization grid
/// (x, y 0.01 pt; widthQ, tilt, azimuth 0.001; t 0.1 ms). No bit operations and
/// every intermediate below 2^53, so the VM and the browser agree.
int strokeDataChecksum(Float32List data) {
  const m = 1000000007;
  var sum = 0;
  for (var i = 0; i < data.length; i++) {
    final scale = switch (i % core.StrokePoints.stride) {
      0 || 1 => 100.0,
      5 => 10.0,
      _ => 1000.0,
    };
    final q = (data[i] * scale).round();
    sum = (sum * 31 + q + m) % m;
  }
  return sum;
}

/// The checksum of scriptedStroke() built with every scriptedTools style
/// (viewScale 1.5), recorded on the VM. test/web/determinism_test.dart expects
/// the same value in Chrome.
const int recordedScriptChecksum = 283364609;

/// strokeDataChecksum of the scripted stroke for every scriptedTools style.
int scriptChecksum() {
  final samples = scriptedStroke();
  var sum = 0;
  for (final tool in scriptedTools) {
    final f = buildStroke(
      samples,
      style: core.StrokeStyle.defaultsFor(tool),
      viewScale: 1.5,
    )!;
    sum = (sum * 7 + strokeDataChecksum(f.data)) % 1000000007;
  }
  return sum;
}
