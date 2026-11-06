// Visibility pause with Chrome's fake microphone (m5-7/06-pdf 6.8.3, M-2 — 8.2 T32b): the real web
// recorder engine (getUserMedia → the fake device, MediaRecorder opus/webm) under the real
// recorder service on CORE's fake store — record → the tab is hidden (document.visibilityState
// redefined + visibilitychange — a headless tab cannot really be hidden) → paused, interrupted,
// the chunks so far are in the draft → visible → no automatic resume → the user resumes → stop →
// the recording's length is the file's timeline (WebM blocks), which leaves the hidden time out.
// Runs only with `ws test --package media_io --platform chrome --run-skipped -t media` (the
// media tag skips it elsewhere; ws starts Chrome through tool/chrome-fakemedia). The waits are
// for the recording itself; the assertions compare the file with the recording clock and the
// hidden time measured here, never with fixed wall-clock numbers.
@TestOn('browser')
@Tags(['media'])
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/config.dart';
import 'package:media_io/src/errors.dart';
import 'package:media_io/src/platform/page_events_browser.dart';
import 'package:media_io/src/platform/web_locks_browser.dart';
import 'package:media_io/src/record/recorder_engine_browser.dart';
import 'package:media_io/src/record/recorder_service.dart';
import 'package:media_io/src/record/recording_output.dart';
import 'package:media_io/src/record/webm_timeline.dart';
import 'package:media_io/src/tuning.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:web/web.dart' as web;

void setVisibility(String state) {
  final object = globalContext.getProperty<JSObject>('Object'.toJS);
  object.callMethod(
    'defineProperty'.toJS,
    web.document,
    'visibilityState'.toJS,
    JSObject()
      ..setProperty('value'.toJS, state.toJS)
      ..setProperty('configurable'.toJS, true.toJS),
  );
  web.document.dispatchEvent(web.Event('visibilitychange'));
}

Future<void> until(bool Function() ready, String what) async {
  for (var i = 0; i < 500 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue, reason: what);
}

void main() {
  tearDown(() => (web.document as JSObject).delete('visibilityState'.toJS));

  test('hidden → paused with the chunks saved → visible: no resume → resume → stop: the '
      'timeline leaves the hidden time out', () async {
    const config = MediaIoConfig();
    final store = core_testing.createFakeNoteStore();
    final note = await store.library.createNote(title: 'Lecture');
    final engine = BrowserRecorderEngine(
      config: config,
      page: BrowserPageEvents(),
    );
    final service = MediaRecorderService(
      stores: () => RecorderStores.of(store),
      now: DateTime.now,
      config: config,
      engine: engine,
      locks: const BrowserWebLocks(),
    );
    addTearDown(service.dispose);

    expect(
      await service.checkSupport(requestPermission: true),
      core.AudioSupport.supported,
    );
    final wall = Stopwatch()..start();
    await service.start(recordingId: store.ids.newId(), noteId: note.id);
    expect(service.status.phase, core.RecorderPhase.recording);
    expect(service.status.mimeType, contains('webm'));

    // ~1.5 s of sound, then the tab goes away
    await until(
      () => (service.offsetNowMs() ?? 0) >= 1500,
      'recording for 1.5 s',
    );
    setVisibility('hidden');
    await until(
      () => service.status.phase == core.RecorderPhase.paused,
      'the hidden pause',
    );
    final hidden = Stopwatch()..start();
    expect(service.status.interrupted, isTrue);
    expect(
      (service.status.error as MediaIoException?)?.code,
      MediaErrorCode.hiddenTab,
    );
    expect(engine.counters.hiddenPauses, 1);
    expect(service.offsetNowMs(), isNull);

    // what came before the pause reaches the draft (requestData before pause — 6.8.3)
    Future<core.RecordingDraft?> draft() async {
      final all = await store.recordingDrafts.listDrafts();
      return all.isEmpty ? null : all.single;
    }

    core.RecordingDraft? saved;
    for (var i = 0; i < 200; i++) {
      saved = await draft();
      if ((saved?.bytes ?? 0) > 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(saved, isNotNull);
    expect(saved!.bytes, greaterThan(0));
    final activeAtHide = service.status.activeMs;
    expect(activeAtHide, greaterThanOrEqualTo(1500));

    // hidden for a while (keep-alive empty chunks only), then visible: still paused (M-2)
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    setVisibility('visible');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(service.status.phase, core.RecorderPhase.paused);
    expect(engine.lastCapture!.state, 'paused');
    hidden.stop();

    // the user resumes; another ~1 s of sound; stop
    await service.resume();
    expect(service.status.phase, core.RecorderPhase.recording);
    expect(service.status.interrupted, isFalse);
    final resumedAt = service.offsetNowMs()!;
    await until(
      () => (service.offsetNowMs() ?? 0) >= resumedAt + 1000,
      'recording 1 s more',
    );
    final recording = await service.stop();
    wall.stop();

    expect(recording, isNotNull);
    final last = service.diagnostics.lastRecording!;
    expect(
      last.source,
      DurationSource.webm,
    ); // the file's timeline, not the clock
    expect(recording!.durationMs, last.durationMs);
    final bytes = await store.assets.readBytes(recording.assetId);
    final timeline = WebmTimeline.measure(bytes!)!;
    expect(timeline.endMs, recording.durationMs);
    // the file agrees with the recording clock (which pauses) …
    expect(
      (recording.durationMs - last.clockMs).abs(),
      lessThanOrEqualTo(MediaTuning.clockWarnErrorMs),
    );
    // … and leaves out the time the tab was hidden
    expect(
      recording.durationMs,
      lessThan(wall.elapsedMilliseconds - hidden.elapsedMilliseconds + 150),
    );
    expect(recording.durationMs, greaterThan(activeAtHide));
    expect(await store.recordingDrafts.listDrafts(), isEmpty);
    expect(engine.session, isNull);
    // ignore: avoid_print
    print(
      'visibility pause: file=${recording.durationMs} ms clock=${last.clockMs} ms '
      'wall=${wall.elapsedMilliseconds} ms hidden=${hidden.elapsedMilliseconds} ms '
      'watchdog=${engine.counters.watchdog}',
    );
  });
}
