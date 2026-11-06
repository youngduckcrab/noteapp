// m5-7/04-editor 8.2 E2-17 (6.3.5 ③, 6.15.3 — contract R-5 (v2.1); review
// M-3 → EDITOR-M3): tap-to-seek through the whole editor with CORE's
// FakeAudioPlayback (calls) / FakeAudioRecorder: finger taps and pen dots on
// recorded strokes, decided before the stroke's end; a pen input that is not
// taken always becomes a stroke.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/state/panel.dart';
import 'package:feature_editor/src/state/settings/pre_roll.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/fake_extensions.dart';
import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

const _rec = 'rec-1';

/// strokeA (y 150, x 100…220) linked to [_rec] at 5000 ms.
final core.Stroke _recorded = strokeA.copyWith(
  recordingId: _rec,
  recordingOffsetMs: 5000,
);

/// A stroke linked to [_rec] at 800 ms (y 250, x 100…220).
final core.Stroke _early = lineStroke(
  id: 'stroke-early',
  x0: 100,
  y0: 250,
  x1: 220,
  y1: 250,
  createdAt: 4,
).copyWith(recordingId: _rec, recordingOffsetMs: 800);

const _onRecorded = Offset(160, 150);
const _onEarly = Offset(160, 250);
const _onUnrecorded = Offset(180, 400); // strokeB

const _penOnly = EditorSettings(inputMode: InputMode.penOnly);

Future<EditorTestHandles> _pump(
  WidgetTester tester, {
  EditorSettings settings = _penOnly,
  String? title,
}) async {
  final panel = TestRecordingPanelBuilder();
  final h = await pumpEditor(
    tester,
    strokesByPageIndex: {
      0: [_recorded, _early, strokeB],
    },
    fakeAudio: true,
    recordings: [RecordingSeed(id: _rec, title: title)],
    extensions: EditorExtensions(recordingPanel: panel.builder),
    settings: settings,
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(); // the note's recordings load
  }
  return h;
}

Future<void> _open(WidgetTester tester, EditorTestHandles h) async {
  core.Recording? recording;
  await h.store.recordings.getRecording(_rec).then((r) => recording = r);
  await h.audioPlayback!.open(recording!);
  await tester.pump();
  expect(h.audioPlayback!.status.phase, core.PlaybackPhase.ready);
}

Future<void> _openPanel(WidgetTester tester, EditorTestHandles h) async {
  h.container.read(editorPanelProvider.notifier).open();
  await tester.pump();
}

Future<void> _playing(WidgetTester tester, EditorTestHandles h) async {
  await _open(tester, h);
  await h.audioPlayback!.play();
  await tester.pump();
  expect(h.audioPlayback!.status.phase, core.PlaybackPhase.playing);
}

int _strokeCount(EditorTestHandles h) =>
    h.session.pageIfLoaded(h.pageId(0))!.strokes.length;

List<String> _seeks(EditorTestHandles h) => [
  for (final c in h.audioPlayback!.calls)
    if (c.startsWith('seek:')) c,
];

/// A pen dot: 3 px in 8 ms at page point [at].
Future<void> _penDot(EditorTestHandles h, Offset at) {
  final p = h.toGlobal(0, at);
  return h.driver.stylusStroke([p, p + const Offset(3, 0)]);
}

/// A one-finger tap at page point [at] — after the palm rejection window of
/// the last pen event (penCooldown), so the finger is not rejected.
Future<void> _fingerTap(
  WidgetTester tester,
  EditorTestHandles h,
  Offset at,
) async {
  await h.driver.wait(const Duration(seconds: 1));
  await h.driver.multiTap([h.toGlobal(0, at)]);
  await tester.pump();
}

/// Stops the playback before the tree goes (the Ticker).
Future<void> _close(WidgetTester tester, EditorTestHandles h) async {
  await h.audioPlayback!.close();
  await tester.pump();
}

void main() {
  testWidgets('① right after a recording stops (player ready), panel closed: '
      'a 15 px pen stroke over a recorded stroke is committed, no seek', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _open(tester, h); // media's automatic open after stop
    final before = _strokeCount(h);
    final from = h.toGlobal(0, const Offset(150, 146));
    await h.driver.stylusStroke([
      for (var i = 0; i <= 3; i++) from + Offset(5.0 * i, 0),
    ]);
    await tester.pump();
    expect(_strokeCount(h), before + 1);
    // A pen dot in the same state is a dot too, and a finger tap does not
    // seek (panel closed, not playing).
    await _penDot(h, _onRecorded);
    await tester.pump();
    expect(_strokeCount(h), before + 2);
    await _fingerTap(tester, h, _onRecorded);
    expect(_seeks(h), isEmpty);
    expect(h.audioPlayback!.calls, ['open:$_rec']);
    await _close(tester, h);
  });

  testWidgets('② panel open + ready: a pen dot (3 px) is a committed dot, no '
      'seek; a finger tap → [open, seek:<offset − 1500>, play]', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _openPanel(tester, h);
    await _open(tester, h);
    final before = _strokeCount(h);
    await _penDot(h, _onRecorded);
    await tester.pump();
    expect(_strokeCount(h), before + 1);
    expect(_seeks(h), isEmpty);

    await _fingerTap(tester, h, _onRecorded);
    expect(h.audioPlayback!.calls, ['open:$_rec', 'seek:3500', 'play']);
    expect(h.audioPlayback!.status.phase, core.PlaybackPhase.playing);
    expect(_strokeCount(h), before + 1);
    await _close(tester, h);
  });

  testWidgets(
    '③ while recording (recorder recording): neither a finger tap nor '
    'a pen dot is taken, even while playing with the panel open',
    (tester) async {
      final h = await _pump(tester);
      await _openPanel(tester, h);
      await _playing(tester, h);
      await h.audioRecorder!.start(recordingId: 'rec-live', noteId: h.noteId);
      await tester.pump();
      final before = _strokeCount(h);
      await _penDot(h, _onRecorded);
      await tester.pump();
      expect(_strokeCount(h), before + 1); // a dot stroke
      await _fingerTap(tester, h, _onRecorded);
      expect(_seeks(h), isEmpty);
      await h.audioRecorder!.cancel();
      await _close(tester, h);
    },
  );

  testWidgets('playing: a pen dot on a recorded stroke → seek and no dot '
      'stroke (cancelled before its end); paused too', (tester) async {
    final h = await _pump(tester);
    await _playing(tester, h);
    final before = _strokeCount(h);
    final commandsBefore = h.recorder!.calls.length;
    await _penDot(h, _onRecorded);
    await tester.pump();
    expect(_seeks(h), ['seek:3500']);
    expect(h.audioPlayback!.calls.last, 'play');
    expect(_strokeCount(h), before);
    expect(
      h.recorder!.calls
          .skip(commandsBefore)
          .where((c) => c.startsWith('execute')),
      isEmpty,
    );

    await h.audioPlayback!.pause();
    await tester.pump();
    await _penDot(h, _onEarly);
    await tester.pump();
    expect(_seeks(h), ['seek:3500', 'seek:0']); // 800 − 1500 < 0 → 0
    expect(_strokeCount(h), before);
    await _close(tester, h);
  });

  testWidgets('offset < preRoll → seek:0 (finger, panel open)', (tester) async {
    final h = await _pump(tester);
    await _openPanel(tester, h);
    await _open(tester, h);
    await _fingerTap(tester, h, _onEarly);
    expect(h.audioPlayback!.calls, ['open:$_rec', 'seek:0', 'play']);
    await _close(tester, h);
  });

  testWidgets('the tapToSeek setting off → ordinary input', (tester) async {
    final h = await _pump(
      tester,
      settings: const EditorSettings(
        inputMode: InputMode.penOnly,
        tapToSeek: false,
      ),
    );
    await _openPanel(tester, h);
    await _playing(tester, h);
    final before = _strokeCount(h);
    await _penDot(h, _onRecorded);
    await tester.pump();
    await _fingerTap(tester, h, _onRecorded);
    expect(_seeks(h), isEmpty);
    expect(_strokeCount(h), before + 1);
    await _close(tester, h);
  });

  testWidgets('a stroke without a recording → ordinary input', (tester) async {
    final h = await _pump(tester);
    await _openPanel(tester, h);
    await _playing(tester, h);
    final before = _strokeCount(h);
    await _penDot(h, _onUnrecorded);
    await tester.pump();
    await _fingerTap(tester, h, _onUnrecorded);
    expect(_seeks(h), isEmpty);
    expect(_strokeCount(h), before + 1);
    await _close(tester, h);
  });

  testWidgets('preRoll 3000 is used', (tester) async {
    final h = await _pump(tester);
    h.container.read(editorPreRollMsProvider.notifier).set(3000);
    await tester.pump();
    await _openPanel(tester, h);
    await _open(tester, h);
    await _fingerTap(tester, h, _onRecorded);
    expect(_seeks(h), ['seek:2000']);
    await _close(tester, h);
    await tester.pump(const Duration(milliseconds: 500)); // the debounce
  });

  testWidgets('a recovered recording (title 복구된 녹음) works the same', (
    tester,
  ) async {
    final h = await _pump(tester, title: '복구된 녹음');
    core.Recording? recording;
    await h.store.recordings.getRecording(_rec).then((r) => recording = r);
    expect(recording?.title, '복구된 녹음');
    await _playing(tester, h);
    await _penDot(h, _onRecorded);
    await tester.pump();
    expect(_seeks(h), ['seek:3500']);
    await _close(tester, h);
  });

  testWidgets('finger drawing: a finger dot takes the finger condition — '
      'panel open + ready → seek; panel closed → a dot stroke', (tester) async {
    final h = await _pump(
      tester,
      settings: const EditorSettings(inputMode: InputMode.fingerDrawing),
    );
    await _open(tester, h);
    final before = _strokeCount(h);
    final p = h.toGlobal(0, _onRecorded);
    await h.driver.fingerDrag(p, p + const Offset(2, 0), steps: 2);
    await tester.pump();
    expect(_seeks(h), isEmpty);
    expect(_strokeCount(h), before + 1);

    await _openPanel(tester, h);
    await h.driver.fingerDrag(p, p + const Offset(2, 0), steps: 2);
    await tester.pump();
    expect(_seeks(h), ['seek:3500']);
    expect(_strokeCount(h), before + 1);
    await _close(tester, h);
  });
}
