// E2-21 (m5-7/04-editor 8.3, contract 7.7.1 step 6): the recording link on
// the real CORE (openTestNoteStore — DB v2) and the real INK, with CORE's
// fake audio ports (FakeAudioRecorder writes into the real store,
// FakeAudioPlayback records its calls):
//
//   the fake recorder records this note → 3 pen strokes → stop → a real
//   CORE Recording row, and each stroke carries its id and the offset read
//   at its pen down → the player opens it (ready) → the real INK getter
//   playbackFocus is null (no dimming right after the stop) → play and move
//   the fake position → the real INK focus (InkPlaybackFocus) follows →
//   a pen dot on a recorded stroke while playing → `seek` in the calls
//   (offset − the pre-roll), no dot stroke.
//
// Skipped by default (dart_test.yaml `integration` skip); runs with
// `ws test --run-skipped -t integration --package feature_editor`. The store
// is opened in tester.runAsync; work the screen started in the fake-async
// zone is drained with both clocks (_flush) and the store is closed there.
@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:async';

import 'package:feature_editor/src/state/settings/pre_roll.dart';
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing_vm.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

const _rec = 'rec-smoke';

/// Lets the real store's async work finish, pumping frames in between.
Future<void> _flush(WidgetTester tester, [int rounds = 4]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Runs [body] (started in the fake-async zone) to its end with both clocks.
Future<T> _await<T>(WidgetTester tester, Future<T> body) async {
  T? value;
  Object? error;
  var done = false;
  unawaited(
    body.then(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object e) {
        error = e;
        done = true;
      },
    ),
  );
  for (var i = 0; i < 60 && !done; i++) {
    await _flush(tester, 1);
  }
  expect(done, isTrue, reason: 'the store call did not finish');
  if (error != null) Error.throwWithStackTrace(error!, StackTrace.current);
  return value as T;
}

List<core.Stroke> _strokes(EditorTestHandles h) =>
    h.session.pageIfLoaded(h.pageId(0))!.strokes;

List<ink.InkPlaybackFocus?> _focuses(EditorTestHandles h) => [
  for (final m in h.mountedPages.all) m.controller.playbackFocus,
];

void main() {
  testWidgets('real CORE + real INK + fake audio ports: strokes while '
      'recording → Recording row → ready (no focus) → play moves the INK '
      'focus → a pen dot on a stroke seeks', (tester) async {
    final store = (await tester.runAsync(openTestNoteStore))!;
    final h = await pumpEditor(
      tester,
      store: store,
      title: '녹음 스모크',
      pages: 2,
      fakeAudio: true,
      recordSession: false, // CORE's own noteSessionProvider
    );
    await _flush(tester, 2);
    final recorder = h.audioRecorder!;
    final playback = h.audioPlayback!;

    // --- record: 3 strokes ---------------------------------------------------
    await _await(tester, recorder.start(recordingId: _rec, noteId: h.noteId));
    await tester.pump();
    expect(recorder.status.phase, core.RecorderPhase.recording);
    final offsets = <int>[];
    for (final (i, advance) in [(0, 1200), (1, 1800), (2, 2500)]) {
      recorder.advance(Duration(milliseconds: advance));
      offsets.add(recorder.offsetNowMs()!);
      await h.driver.stylusStroke(
        pathThrough(h, 0, [
          for (var x = 100.0; x <= 260; x += 20) Offset(x, 150.0 + 80 * i),
        ]),
      );
      await _flush(tester, 1);
    }
    expect(offsets, [1200, 3000, 5500]);
    expect(_strokes(h), hasLength(3));
    expect([for (final s in _strokes(h)) s.recordingId], everyElement(_rec));
    expect([for (final s in _strokes(h)) s.recordingOffsetMs], offsets);

    // --- stop → a real CORE Recording row ------------------------------------
    recorder.advance(const Duration(seconds: 2));
    final stopped = await _await(tester, recorder.stop());
    expect(stopped, isNotNull);
    expect(recorder.status.phase, core.RecorderPhase.idle);
    final row = await _await(tester, store.recordings.getRecording(_rec));
    expect(row, isNotNull);
    expect(row!.noteId, h.noteId);
    expect(row.durationMs, greaterThanOrEqualTo(7500));
    final listed = await _await(
      tester,
      store.recordings.recordingsOf(h.noteId),
    );
    expect([for (final r in listed) r.id], [_rec]);
    // The strokes in the store keep their link (read back from the DB).
    final stored = await _await(tester, store.content.loadPage(h.pageId(0)));
    expect([for (final s in stored.strokes) s.recordingOffsetMs], offsets);

    // --- the player opens it: ready, no INK focus ----------------------------
    await _await(tester, playback.open(row));
    await _flush(tester, 2);
    expect(playback.status.phase, core.PlaybackPhase.ready);
    expect(_focuses(h), everyElement(isNull));

    // --- play: the INK focus follows the fake position ------------------------
    await _await(tester, playback.play());
    playback.setPositionMs(3200);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      h.controllerOf(0).playbackFocus,
      const ink.InkPlaybackFocus(recordingId: _rec, positionMs: 3200),
    );
    playback.setPositionMs(6000);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      h.controllerOf(0).playbackFocus,
      const ink.InkPlaybackFocus(recordingId: _rec, positionMs: 6000),
    );

    // --- a pen dot on the second stroke while playing → seek ------------------
    final before = _strokes(h).length;
    final dot = h.toGlobal(0, const Offset(180, 230));
    await h.driver.stylusStroke([dot, dot + const Offset(3, 0)]);
    await _flush(tester, 1);
    final seeks = [
      for (final c in playback.calls)
        if (c.startsWith('seek:')) c,
    ];
    final preRollMs = h.container.read(editorPreRollMsProvider);
    expect(seeks, ['seek:${(offsets[1] - preRollMs).clamp(0, offsets[1])}']);
    expect(_strokes(h), hasLength(before), reason: 'the dot was taken');

    await _await(tester, playback.close());
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await _await(tester, store.close());
  });
}
