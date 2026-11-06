// B15 playback emphasis (m5-7/03-ink 6.19, 6.25, T43): setPlaybackFocus + the
// layer 4′ paint (the inkActive layer — the recording cost; the web raster cost
// of the veil pictures is the developer value playbackPaintUs on a device, I-B9).
// Run: flutter test benchmark/ (bench tag).
@Tags(['bench'])
library;

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkPageRenderOf, playbackStatsOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import 'support/bench.dart';
import 'support/workloads.dart';

const int _frames = 600;
const int _strokes = 3000;

/// 3000 handwriting strokes (60 points at 120 Hz — 0.49 s each) linked to one
/// recording, one every 650 ms (a pen writes one stroke at a time: 0.16 s between
/// strokes) — a 32 minute lecture (B-8).
List<core.Stroke> _recorded() {
  final strokes = handwriting(count: _strokes, points: 60);
  return [
    for (var i = 0; i < strokes.length; i++)
      strokes[i].copyWith(recordingId: 'r', recordingOffsetMs: i * _spacingMs),
  ];
}

const int _spacingMs = 650;

void _paintActive(InkPageController c) {
  final recorder = ui.PictureRecorder();
  inkPageRenderOf(c).paint(ui.Canvas(recorder), InkRenderLayer.inkActive, 1);
  recorder.endRecording().dispose();
}

/// [rounds] fresh controllers; per round a warm-up paint at the first position
/// (the index and the block pictures — not measured), then [_frames] frames of
/// setPlaybackFocus(position(f)) + the layer 4′ paint. Returns every frame time and,
/// per frame, the fastest of the rounds (B2's way of leaving out a GC pause or a
/// preemption that hits one round at random).
(BenchStats all, BenchStats perFrameMin, int recorded) _run(
  List<core.Stroke> strokes,
  int Function(int frame) position, {
  InkPlaybackStyle style = InkPlaybackStyle.dimUnwritten,
  int rounds = 3,
}) {
  final all = <double>[];
  final best = List<double>.filled(_frames, double.infinity);
  var recorded = 0;
  for (var r = 0; r < rounds; r++) {
    final c = createTestPageController()..updateContent(pageOf(strokes));
    c.setPlaybackFocus(
      InkPlaybackFocus(recordingId: 'r', positionMs: position(0), style: style),
    );
    _paintActive(c);
    final stats = playbackStatsOf(c);
    final before = stats.veilStrokes + stats.emphasisStrokes;
    final times = <double>[];
    measureSteps(_frames, (f) {
      c.setPlaybackFocus(
        InkPlaybackFocus(
          recordingId: 'r',
          positionMs: position(f),
          style: style,
        ),
      );
      _paintActive(c);
    }, record: times);
    recorded = stats.veilStrokes + stats.emphasisStrokes - before;
    for (var f = 0; f < _frames; f++) {
      if (times[f] < best[f]) best[f] = times[f];
    }
    all.addAll(times);
    c.dispose();
  }
  return (BenchStats(all), BenchStats(best), recorded);
}

void main() {
  final strokes = _recorded();

  test('B15 playback: 3000 recorded strokes, 600 frames 16 ms apart '
      '(dimUnwritten, real time from the middle)', () {
    const start = _strokes * _spacingMs ~/ 2; // half of the page written
    final (all, best, recorded) = _run(strokes, (f) => start + 16 * f);
    report(
      'B15',
      'playback 3000 strokes × 600 frames (16 ms, dimUnwritten)',
      all,
      criteria: {'mean_ms': 0.5},
      extra: {
        'per_frame_min_max_ms': best.max,
        'raw_p95_ms': all.valueOf('p95_ms'),
        'strokes_recorded': recorded,
      },
    );
    report(
      'B15',
      'playback max (per frame, fastest of 3 rounds)',
      best,
      criteria: {'max_ms': 4},
    );
  });

  test('B15 (reference): highlightRecent, real time', () {
    const start = _strokes * _spacingMs ~/ 2;
    final (all, _, recorded) = _run(
      strokes,
      (f) => start + 16 * f,
      style: InkPlaybackStyle.highlightRecent,
    );
    report(
      'B15',
      'playback highlightRecent (reference)',
      all,
      criteria: const {},
      extra: {'strokes_recorded': recorded},
    );
  });

  test('B15 (reference): a sweep over the whole recording (3.25 s a frame — '
      'the boundary crosses 5 strokes every frame)', () {
    final (all, best, recorded) = _run(strokes, (f) => 3250 * f);
    report(
      'B15',
      'playback sweep 32 min in 600 frames (reference)',
      all,
      criteria: const {},
      extra: {'per_frame_min_max_ms': best.max, 'strokes_recorded': recorded},
    );
  });
}
