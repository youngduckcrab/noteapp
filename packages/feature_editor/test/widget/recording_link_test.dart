// m5-7/04-editor 8.2 E2-16 (6.15.1 — contract 7.2.4 R-1, E-5): strokes drawn
// while CORE's FakeAudioRecorder records this note carry the recording id and
// the recorder's offsetNowMs() at each pen down; on the web rule the value
// is the one at the contact move, not at the airborne down.
import 'package:feature_editor/src/input/stylus_contact.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

List<core.Stroke> _coreStrokes(EditorTestHandles h) =>
    h.session.pageIfLoaded(h.pageId(0))!.strokes;

/// A short horizontal line on page 0 at y [y] pt.
List<Offset> _line(EditorTestHandles h, double y) =>
    pathThrough(h, 0, [for (var x = 100.0; x <= 220; x += 20) Offset(x, y)]);

Future<FakeAudioRecorder> _record(
  WidgetTester tester,
  EditorTestHandles h, {
  String? noteId,
}) async {
  final recorder = h.audioRecorder!;
  await recorder.start(recordingId: 'rec-1', noteId: noteId ?? h.noteId);
  await tester.pump();
  expect(recorder.status.phase, core.RecorderPhase.recording);
  return recorder;
}

void main() {
  tearDown(() => StylusContact.debugRuleOverride = null);

  testWidgets('3 strokes while recording → each CORE stroke has recordingId '
      'and the offsetNowMs() of its pen down', (tester) async {
    final h = await pumpEditor(tester, fakeAudio: true);
    final recorder = await _record(tester, h);
    final expected = <int>[];
    for (final (i, advance) in [(0, 1200), (1, 800), (2, 2500)]) {
      recorder.advance(Duration(milliseconds: advance));
      expected.add(recorder.offsetNowMs()!);
      // The recorder clock does not move while the stroke is drawn: the
      // value must be the one read at pen down.
      await h.driver.stylusStroke(_line(h, 150.0 + 60 * i));
      await tester.pump();
    }
    final strokes = _coreStrokes(h);
    expect(strokes, hasLength(3));
    expect([for (final s in strokes) s.recordingId], everyElement('rec-1'));
    expect([for (final s in strokes) s.recordingOffsetMs], expected);
    expect(expected, [1200, 2000, 4500]);
  });

  testWidgets('the offset is read at pen down, not at pen up', (tester) async {
    final h = await pumpEditor(tester, fakeAudio: true);
    final recorder = await _record(tester, h);
    recorder.advance(const Duration(milliseconds: 300));
    final points = _line(h, 200);
    await h.driver.down(1, points.first, kind: PointerDeviceKind.stylus);
    for (final p in points.skip(1)) {
      recorder.advance(const Duration(milliseconds: 100));
      await h.driver.wait(const Duration(milliseconds: 4));
      await h.driver.move(1, p);
    }
    await h.driver.up(1);
    await tester.pump();
    expect(_coreStrokes(h).single.recordingOffsetMs, 300);
  });

  testWidgets('paused, another note recording, not recording → strokes have '
      'no recording link', (tester) async {
    final h = await pumpEditor(tester, fakeAudio: true);
    await h.driver.stylusStroke(_line(h, 150)); // idle
    final recorder = await _record(tester, h);
    recorder.advance(const Duration(seconds: 1));
    await recorder.pause();
    await h.driver.stylusStroke(_line(h, 210)); // paused
    await recorder.cancel();
    await tester.pump();
    await _record(tester, h, noteId: 'another-note');
    recorder.advance(const Duration(seconds: 1));
    await h.driver.stylusStroke(_line(h, 270)); // another note
    await tester.pump();
    final strokes = _coreStrokes(h);
    expect(strokes, hasLength(3));
    for (final s in strokes) {
      expect(s.recordingId, isNull);
      expect(s.recordingOffsetMs, isNull);
    }
  });

  testWidgets('web rule: an airborne down, then the contact move → the offset '
      'at the contact', (tester) async {
    StylusContact.debugRuleOverride = StylusContactRule.web;
    final h = await pumpEditor(tester, fakeAudio: true);
    final recorder = await _record(tester, h);
    recorder.advance(const Duration(milliseconds: 500));
    final points = _line(h, 180);
    // Airborne (no contact bit) at 500 ms.
    await h.driver.down(
      1,
      points.first,
      kind: PointerDeviceKind.stylus,
      buttons: 0,
    );
    await h.driver.wait(const Duration(milliseconds: 4));
    await h.driver.move(1, points[1], buttons: 0);
    // The pen touches at 1300 ms.
    recorder.advance(const Duration(milliseconds: 800));
    for (final p in points.skip(1)) {
      await h.driver.wait(const Duration(milliseconds: 4));
      await h.driver.move(1, p, buttons: kPrimaryButton);
      recorder.advance(const Duration(milliseconds: 50));
    }
    await h.driver.wait(const Duration(milliseconds: 4));
    await h.driver.up(1);
    await tester.pump();
    final stroke = _coreStrokes(h).single;
    expect(stroke.recordingId, 'rec-1');
    expect(stroke.recordingOffsetMs, 1300);
  });
}
