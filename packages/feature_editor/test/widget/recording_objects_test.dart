// (v2.13-rec) Page objects and the recording (m5-7/04-editor 6.15): objects
// made while this note is being recorded carry its id and the recorder's
// offset (the shape tool, a new text box, the shape snapped from a held
// stroke — the offset of its pen-down), objects made otherwise carry none,
// and tap-to-seek on a linked object seeks to its offset.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/settings/pre_roll.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart' show EditableText;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/fake_extensions.dart';
import '../helpers/ink_edit_builders.dart';
import '../helpers/pump_editor.dart';

const _rec = 'rec-1';

List<core.PageObject> _objects(EditorTestHandles h) =>
    h.session.pageIfLoaded(h.pageId(0))!.objects;

Future<FakeAudioRecorder> _record(
  WidgetTester tester,
  EditorTestHandles h,
) async {
  final recorder = h.audioRecorder!;
  await recorder.start(recordingId: _rec, noteId: h.noteId);
  await tester.pump();
  expect(recorder.status.phase, core.RecorderPhase.recording);
  return recorder;
}

/// The stylus from page point [a] to [b] (page 0) in 6 steps.
Future<void> _drag(
  WidgetTester tester,
  EditorTestHandles h,
  Offset a,
  Offset b,
) async {
  final from = h.toGlobal(0, a), to = h.toGlobal(0, b);
  await h.driver.down(1, from, kind: PointerDeviceKind.stylus);
  for (var i = 1; i <= 6; i++) {
    await h.driver.move(1, Offset.lerp(from, to, i / 6)!);
  }
  await h.driver.up(1);
  await tester.pump();
}

void main() {
  testWidgets('the shape tool while recording → the shape is linked at the '
      'recorder offset; not recording → no link', (tester) async {
    final h = await pumpEditor(tester, fakeAudio: true);
    h.container.read(editorCommandsProvider).selectTool(EditorTool.shape);
    await tester.pump();
    await _drag(tester, h, const Offset(100, 100), const Offset(200, 180));
    final plain = _objects(h).single;
    expect(plain.recordingId, isNull);

    final recorder = await _record(tester, h);
    recorder.advance(const Duration(milliseconds: 2300));
    await _drag(tester, h, const Offset(100, 300), const Offset(200, 380));
    final linked = _objects(h).firstWhere((o) => o.id != plain.id);
    expect(linked, isA<core.ShapeObject>());
    expect(linked.recordingId, _rec);
    expect(linked.recordingOffsetMs, 2300);
    await recorder.cancel();
    await tester.pump();
  });

  testWidgets('a shape snapped from a held stroke (InkEdit addShape) gets '
      'the recording meta of its pen-down; INK\'s pending shape is resolved', (
    tester,
  ) async {
    final h = await pumpEditor(tester, fakeAudio: true);
    final shape = PageObjectFixtures.shape(
      pageId: h.pageId(0),
      id: 'snap-1',
      rect: const core.PageRect(150, 300, 300, 400),
    );
    final committed = h.container
        .read(editorCommandsProvider)
        .commitInkEdit(
          h.controllerOf(0),
          addShapeEdit(h.pageId(0), shape),
          recording: const ink.InkStrokeMeta(
            recordingId: _rec,
            recordingOffsetMs: 4100,
          ),
        );
    await tester.pump();
    expect(committed, isTrue);
    final stored = _objects(h).single;
    expect(stored.id, 'snap-1');
    expect(stored.recordingId, _rec);
    expect(stored.recordingOffsetMs, 4100);
    expect(h.controllerOf(0).pendingIds, isEmpty);
  });

  testWidgets('a new text box while recording is linked at the time it is '
      'placed', (tester) async {
    final h = await pumpEditor(tester, fakeAudio: true);
    final recorder = await _record(tester, h);
    recorder.advance(const Duration(milliseconds: 700));
    h.container.read(editorCommandsProvider).selectTool(EditorTool.text);
    await tester.pump();
    final at = h.toGlobal(0, const Offset(120, 200));
    await h.driver.stylusStroke([at, at + const Offset(1, 0)]);
    await tester.pump();
    await tester.enterText(find.byType(EditableText), '녹음 중');
    await tester.pump();
    // ends the session (a tap elsewhere commits the box)
    h.container.read(editorCommandsProvider).selectTool(EditorTool.pen);
    await tester.pump();
    await tester.pump();
    final box = _objects(h).whereType<core.TextBoxObject>().single;
    expect(box.text, '녹음 중');
    expect(box.recordingId, _rec);
    expect(box.recordingOffsetMs, 700);
    await recorder.cancel();
    await tester.pump();
  });

  testWidgets('tap-to-seek: a pen dot on a linked shape while playing seeks '
      'to its offset − pre-roll; on an unlinked shape it stays a dot', (
    tester,
  ) async {
    final linked = PageObjectFixtures.shape(
      pageId: 'x',
      id: 'linked',
      rect: const core.PageRect(100, 100, 220, 200),
      createdAt: 3,
    ).withRecording(recordingId: _rec, recordingOffsetMs: 6000);
    final plain = PageObjectFixtures.shape(
      pageId: 'x',
      id: 'plain',
      rect: const core.PageRect(100, 300, 220, 400),
      createdAt: 4,
    );
    final panel = TestRecordingPanelBuilder();
    final h = await pumpEditor(
      tester,
      objectsByPageIndex: {
        0: [linked, plain],
      },
      fakeAudio: true,
      recordings: [const RecordingSeed(id: _rec)],
      extensions: EditorExtensions(recordingPanel: panel.builder),
      settings: const EditorSettings(inputMode: InputMode.penOnly),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(); // the note's recordings load
    }
    core.Recording? recording;
    await h.store.recordings.getRecording(_rec).then((r) => recording = r);
    final playback = h.audioPlayback!;
    await playback.open(recording!);
    await playback.play();
    await tester.pump();
    expect(playback.status.phase, core.PlaybackPhase.playing);

    Future<void> dot(Offset at) async {
      final p = h.toGlobal(0, at);
      await h.driver.stylusStroke([p, p + const Offset(3, 0)]);
      await tester.pump();
    }

    final strokes = h.session.pageIfLoaded(h.pageId(0))!.strokes.length;
    await dot(const Offset(100, 150)); // the linked shape's left edge
    final preRoll = h.container.read(editorPreRollMsProvider);
    expect(
      [
        for (final c in playback.calls)
          if (c.startsWith('seek:')) c,
      ],
      ['seek:${6000 - preRoll}'],
    );
    expect(
      h.session.pageIfLoaded(h.pageId(0))!.strokes,
      hasLength(strokes),
      reason: 'the dot was taken',
    );

    await dot(const Offset(100, 350)); // the plain shape's edge
    expect([
      for (final c in playback.calls)
        if (c.startsWith('seek:')) c,
    ], hasLength(1));
    expect(
      h.session.pageIfLoaded(h.pageId(0))!.strokes,
      hasLength(strokes + 1),
    );
    await playback.close();
    await tester.pump();
  });

  testWidgets('the shape tool takes the recorder offset of its pen-down, not '
      'of the end of the drag', (tester) async {
    final h = await pumpEditor(tester, fakeAudio: true);
    h.container.read(editorCommandsProvider).selectTool(EditorTool.shape);
    await tester.pump();
    final recorder = await _record(tester, h);
    recorder.advance(const Duration(milliseconds: 1200));
    final from = h.toGlobal(0, const Offset(100, 100));
    final to = h.toGlobal(0, const Offset(200, 180));
    await h.driver.down(1, from, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 6; i++) {
      // a slow drag: 3 s pass while it is drawn
      recorder.advance(const Duration(milliseconds: 500));
      await h.driver.move(1, Offset.lerp(from, to, i / 6)!);
    }
    await h.driver.up(1);
    await tester.pump();
    final shape = _objects(h).single;
    expect(shape, isA<core.ShapeObject>());
    expect(shape.recordingId, _rec);
    expect(shape.recordingOffsetMs, 1200);
    await recorder.cancel();
    await tester.pump();
  });

  testWidgets('an insert menu item (the 수식 패드) while recording: its new '
      'formula is linked at the time it is inserted; not recording → none', (
    tester,
  ) async {
    final h = await pumpEditor(tester, fakeAudio: true);
    final commands = h.container.read(editorCommandsProvider);
    core.MathObject formula(String id) =>
        PageObjectFixtures.math(pageId: h.pageId(0), id: id, createdAt: 7);

    commands.insertContext()!.execute(
      core.AddObjects(pageId: h.pageId(0), objects: [formula('a')]),
    );
    await tester.pump();
    expect(_objects(h).single.recordingId, isNull);

    final recorder = await _record(tester, h);
    recorder.advance(const Duration(milliseconds: 8000));
    // the context is made at the press; the pad inserts later
    final insert = commands.insertContext()!;
    recorder.advance(const Duration(milliseconds: 400));
    insert.execute(
      core.AddObjects(pageId: h.pageId(0), objects: [formula('b')]),
    );
    await tester.pump();
    final linked = _objects(h).firstWhere((o) => o.id == 'b');
    expect(linked.recordingId, _rec);
    expect(linked.recordingOffsetMs, 8400);
    await recorder.cancel();
    await tester.pump();
  });

  testWidgets('tap-to-seek on linked images, formulas and text boxes: a pen '
      'dot inside the frame is written (no seek); a finger tap no other step '
      'takes seeks; with the lasso a finger tap selects instead', (
    tester,
  ) async {
    core.PageObject linked(core.PageObject o) =>
        o.withRecording(recordingId: _rec, recordingOffsetMs: 6000);
    final image = linked(
      PageObjectFixtures.image(
        pageId: 'x',
        assetId: 'a1',
        id: 'im',
        rect: const core.PageRect(100, 100, 260, 200),
        createdAt: 3,
      ),
    );
    final math = linked(
      PageObjectFixtures.math(
        pageId: 'x',
        id: 'm',
        rect: const core.PageRect(100, 300, 220, 350),
        createdAt: 4,
      ),
    );
    final box = linked(
      core.TextBoxObject(
        id: 't',
        pageId: 'x',
        frame: const core.ElementFrame(core.PageRect(100, 450, 260, 500)),
        text: '메모',
        style: const core.TextBoxStyle(),
        createdAt: 5,
      ),
    );
    final panel = TestRecordingPanelBuilder();
    final h = await pumpEditor(
      tester,
      objectsByPageIndex: {
        0: [image, math, box],
      },
      fakeAudio: true,
      recordings: [const RecordingSeed(id: _rec)],
      extensions: EditorExtensions(recordingPanel: panel.builder),
      settings: const EditorSettings(inputMode: InputMode.penOnly),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(); // the note's recordings load
    }
    core.Recording? recording;
    await h.store.recordings.getRecording(_rec).then((r) => recording = r);
    final playback = h.audioPlayback!;
    await playback.open(recording!);
    await playback.play();
    await tester.pump();
    List<String> seeks() => [
      for (final c in playback.calls)
        if (c.startsWith('seek:')) c,
    ];
    int strokes() => h.session.pageIfLoaded(h.pageId(0))!.strokes.length;

    final before = strokes();
    for (final at in const [
      Offset(180, 150), // inside the image
      Offset(160, 325), // inside the formula
      Offset(180, 475), // inside the text box
    ]) {
      final p = h.toGlobal(0, at);
      await h.driver.stylusStroke([p, p + const Offset(3, 0)]);
      await tester.pump();
    }
    expect(seeks(), isEmpty, reason: 'a pen dot never seeks on a frame');
    expect(strokes(), before + 3, reason: 'every dot was written');

    Future<void> fingerTap(Offset at) async {
      await h.driver.wait(const Duration(seconds: 1));
      await h.driver.multiTap([h.toGlobal(0, at)]);
      await tester.pump();
    }

    final preRoll = h.container.read(editorPreRollMsProvider);
    await fingerTap(const Offset(240, 190)); // the image, no stroke there
    expect(seeks(), ['seek:${6000 - preRoll}']);

    h.container.read(editorCommandsProvider).selectTool(EditorTool.lasso);
    await tester.pump();
    await fingerTap(const Offset(240, 190));
    expect(seeks(), hasLength(1), reason: 'the lasso tap selects');
    expect(h.container.read(editorSelectionProvider)?.elementIds, {'im'});
    await playback.close();
    await tester.pump();
  });
}
