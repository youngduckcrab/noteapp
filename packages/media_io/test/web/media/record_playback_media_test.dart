// V8 (contract 7.7.2, m5-7/06-pdf 8.2 T39 — 6.8.7, 6.11, 6.17; PDF-F1) with Chrome's fake
// microphone: the REAL mediaIoOverrides() services (the browser recorder engine on MediaRecorder,
// navigator.locks, just_audio_web over a Blob URL) record 2 s with a 1 s pause in the middle →
// stop → the asset and the Recording row (M-1) → open → play at 2× (slope 1.9–2.1) → pause →
// seekMs(700) (±50 ms). The file's own timeline against the recording clock is asserted with the
// approved V8 rule (contract v2.2 C22-04 — CP-PDF-12, widened above by v2.6 C26-01):
// lastBlockStartMs − 50 ≤ clock ≤ endMs + 50 + 60 × pauses (each pause makes Chrome's file about
// one packet ≈ 60 ms shorter than the clock — T39: +35 · +46 · +52 · +65 ms with one pause),
// asserted on the real web store only (MediaStores.judged — on a loaded machine the
// MediaRecorder's start / stop events come late and the file and the clock drift apart); the two
// gaps and the old rule '|endMs − clock| ≤ 50 ms' are printed for the progress log (PDF-F1), not
// asserted. durationMs is the timeline value, and the stored WebM carries Info > Duration (the
// head patch — 6.8.7).
//
// Runs only with `ws test --package media_io --platform chrome --run-skipped -t media` (the media
// tag skips it elsewhere; ws starts Chrome through tool/chrome-fakemedia). Store: mediaStoreTest
// (media_world.dart) — the judged real web store variant and the CORE fake store variant. The
// waits are for the recording itself; the assertions compare the file with the clock and with
// the time measured here, never with fixed wall-clock numbers.
//
// Fixture refresh (06-pdf 6.1 E9): with --dart-define=MEDIA_IO_DUMP_WEBM=true the saved WebM is
// printed as one base64 line 'media-io-webm <base64>' (a browser test cannot write files).
@TestOn('browser')
@Tags(['media'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/media_io.dart';
import 'package:media_io/src/record/recorder_engine_browser.dart';
import 'package:media_io/src/record/recorder_service.dart';
import 'package:media_io/src/record/recording_output.dart';
import 'package:media_io/src/record/webm_timeline.dart';
import 'package:media_io/testing.dart';
import 'package:note_core/note_core.dart' as core;

import 'media_world.dart';

const bool _dumpWebm = bool.fromEnvironment('MEDIA_IO_DUMP_WEBM');

/// Waits for [phase]; on a time-out the failure lists the phases seen (and the error).
Future<void> _untilPhase(
  core.AudioPlaybackService playback,
  core.PlaybackPhase phase,
) async {
  if (playback.status.phase == phase) return;
  final seen = <String>[];
  try {
    await playback.statusStream
        .map((s) {
          seen.add(s.phase.name);
          return s;
        })
        .firstWhere((s) => s.phase == phase)
        .timeout(const Duration(seconds: 10));
  } on TimeoutException {
    fail(
      'no ${phase.name} within 10 s — seen $seen, now ${playback.status.phase.name} '
      'error=${playback.status.error} position=${playback.positionMs()}',
    );
  }
}

void main() {
  // just_audio's AudioPlayer sets up audio_session's method channel.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(registerMediaWebPlugins);

  mediaStoreTest(
    'V8: 2 s with a 1 s pause → stop → asset + row → 2× play, seek; the file timeline vs '
    'the clock',
    prefix: 'v8',
    (stores) async {
      final store = await stores.open();
      final container = ProviderContainer(
        overrides: [
          core.noteStoreProvider.overrideWithValue(store),
          ...mediaIoOverrides(),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await stores.close(store);
      });
      final recorder = container.read(
        core.audioRecorderServiceProvider,
      ) as MediaRecorderService;
      final playback = container.read(core.audioPlaybackServiceProvider);
      expect(recorder.engine, isA<BrowserRecorderEngine>());

      // ① record 1 s → pause 1 s → record 1 s more → stop
      expect(
        await recorder.checkSupport(requestPermission: true),
        core.AudioSupport.supported,
      );
      final note = await store.library.createNote(title: 'Lecture');
      final id = store.ids.newId();
      final wall = Stopwatch()..start();
      var pauses = 0; // user pauses in this recording (C26-01's upper margin)
      await recorder.start(recordingId: id, noteId: note.id);
      expect(recorder.status.phase, core.RecorderPhase.recording);
      expect(recorder.status.mimeType, contains('webm'));
      await until(
        () => (recorder.offsetNowMs() ?? 0) >= 1000,
        'recording for 1 s',
      );
      await recorder.pause();
      pauses++;
      expect(recorder.status.phase, core.RecorderPhase.paused);
      expect(recorder.offsetNowMs(), isNull);
      final pausedAt = recorder.status.activeMs;
      final paused = Stopwatch()..start();
      await Future<void>.delayed(const Duration(seconds: 1));
      paused.stop();
      expect(recorder.status.activeMs, pausedAt); // the clock stood still
      await recorder.resume();
      expect(recorder.status.phase, core.RecorderPhase.recording);
      await until(
        () => (recorder.offsetNowMs() ?? 0) >= 2000,
        'recording 2 s in all',
      );
      final atStopCall = recorder.offsetNowMs()!;
      final recording = await recorder.stop();
      wall.stop();
      expect(recorder.status.phase, core.RecorderPhase.idle);

      // ② the asset, then the row (M-1); the draft is gone
      expect(recording, isNotNull);
      expect(recording!.id, id);
      expect(recording.noteId, note.id);
      expect(await store.recordings.recordingsOf(note.id), [recording]);
      final asset = (await store.assets.getAsset(recording.assetId))!;
      expect(asset.type, core.AssetType.audio);
      expect(asset.mimeType, contains('webm'));
      expect(await store.recordingDrafts.listDrafts(), isEmpty);

      // ③ the length is the file's timeline; the clock lies in the last packet − 50 ms … the file
      // end + 50 ms + 60 ms per pause (C22-04, C26-01)
      final bytes = (await store.assets.readBytes(recording.assetId))!;
      expect(bytes, isNotEmpty);
      final timeline = WebmTimeline.measure(bytes)!;
      final last = recorder.diagnostics.lastRecording!;
      expect(last.source, DurationSource.webm);
      expect(last.patched, isTrue);
      expect(recording.durationMs, timeline.endMs);
      expect(last.durationMs, timeline.endMs);
      final clock = last.clockMs;
      // PDF-F1: the two gaps and the old rule, for the progress log (printed before the asserts)
      final oldRule = (timeline.endMs - clock).abs() <= 50;
      // ignore: avoid_print
      print(
        'V8 (${stores.label}): file=${timeline.endMs} ms '
        'lastBlockStart=${timeline.lastBlockStartMs} ms clock=$clock ms '
        'end−clock=${timeline.endMs - clock} ms '
        'clock−lastBlockStart=${clock - timeline.lastBlockStartMs} ms '
        'old |end−clock|≤50: $oldRule pauses=$pauses '
        'upper=endMs+${50 + 60 * pauses} '
        'clock at the stop call=$atStopCall ms '
        'wall=${wall.elapsedMilliseconds} ms paused=${paused.elapsedMilliseconds} ms '
        'bytes=${bytes.length}',
      );
      if (_dumpWebm) {
        // ignore: avoid_print
        print('media-io-webm ${base64Encode(bytes)}');
      }
      if (stores.judged) {
        expect(pauses, 1);
        expect(
          clock,
          inInclusiveRange(
            timeline.lastBlockStartMs - 50,
            timeline.endMs + 50 + 60 * pauses,
          ),
          reason: 'C22-04 / C26-01: lastBlockStart − 50 ≤ clock ≤ end + 50 + 60 × pauses',
        );
      }
      expect(clock, greaterThanOrEqualTo(2000));
      // the paused second is not in the file
      expect(
        recording.durationMs,
        lessThan(wall.elapsedMilliseconds - paused.elapsedMilliseconds + 150),
      );
      // the stored WebM has Info > Duration = durationMs (the head patch — 6.8.7)
      expect(webmInfoDurationMs(bytes), recording.durationMs);

      // ④ play at 2×: the position moves at twice the wall clock
      await playback.open(recording);
      expect(playback.status.phase, core.PlaybackPhase.ready);
      expect(playback.status.recordingId, id);
      expect(playback.status.durationMs, recording.durationMs);
      await playback.setSpeed(2);
      expect(playback.status.speed, 2.0);
      await playback.play();
      await _untilPhase(playback, core.PlaybackPhase.playing);
      final slopeWatch = Stopwatch()..start();
      final p0 = playback.positionMs();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final p1 = playback.positionMs();
      slopeWatch.stop();
      final slope = (p1 - p0) / slopeWatch.elapsedMilliseconds;
      expect(slope, inInclusiveRange(1.9, 2.1));

      // ⑤ pause → seekMs(700) → the position is there (± 50 ms)
      await playback.pause();
      await _untilPhase(playback, core.PlaybackPhase.paused);
      await playback.seekMs(700);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final seeked = playback.positionMs();
      expect(seeked, inInclusiveRange(650, 750));
      await playback.close();
      expect(playback.status.phase, core.PlaybackPhase.idle);

      // ignore: avoid_print
      print(
        'V8 (${stores.label}): slope=${slope.toStringAsFixed(3)} seek700=$seeked ms',
      );
    },
  );
}
