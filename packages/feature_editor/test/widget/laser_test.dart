// m5-7/04-editor 8.2 E2-14, 6.14.3 — with the REAL R2-B3 INK (no fake
// session — StrokeSession is a final class; R2-B3's laser end() is null,
// review S-4): a laser stroke runs no command (undoDepth 0, no stroke, the
// recent colours unchanged); on a read-only note an already active laser
// still starts its interaction (it stores nothing) while a ballpoint does
// not, and the pen buttons stay disabled.
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/color_palette.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/tool_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';

List<String> _edits(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

List<Offset> _line(EditorTestHandles h, Offset from, Offset to) => [
  for (var i = 0; i <= 8; i++) h.toGlobal(0, Offset.lerp(from, to, i / 8)!),
];

bool _active(EditorTestHandles h) =>
    h.container.read(editorInputRouterProvider).hasActiveInteraction;

void main() {
  testWidgets('a laser stroke: no command, undoDepth 0, no stroke, the recent '
      'colours unchanged', (tester) async {
    final h = await pumpEditor(tester);
    h.container
        .read(editorToolProvider.notifier)
        .selectPenType(core.PenTool.laser);
    await tester.pump();
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.pen);
    final recent = h.container.read(editorColorPaletteProvider).recent;

    final points = _line(h, const Offset(100, 200), const Offset(400, 260));
    await h.driver.down(1, points.first, kind: PointerDeviceKind.stylus);
    for (final p in points.skip(1)) {
      await h.driver.wait(const Duration(milliseconds: 8));
      await h.driver.move(1, p);
    }
    expect(_active(h), isTrue); // the laser interaction runs
    await h.driver.up(1);
    await tester.pump();
    expect(_active(h), isFalse);
    expect(_edits(h), isEmpty);
    expect(h.session.history.undoDepth, 0);
    expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, isEmpty);
    expect(h.container.read(editorColorPaletteProvider).recent, recent);
    // A ballpoint stroke afterwards is committed (one step).
    h.container
        .read(editorToolProvider.notifier)
        .selectPenType(core.PenTool.ballpoint);
    await tester.pump();
    await h.driver.stylusStroke(
      _line(h, const Offset(100, 300), const Offset(300, 320)),
    );
    await tester.pump();
    expect(_edits(h), ['execute:add-strokes']);
    expect(h.session.history.undoDepth, 1);
    await tester.pump(const Duration(seconds: 3)); // the laser trail fades
  });

  testWidgets('a read-only note: the active laser still starts (nothing '
      'stored); a ballpoint does not; the tool buttons stay disabled', (
    tester,
  ) async {
    final h = await pumpEditor(tester);
    h.container
        .read(editorToolProvider.notifier)
        .selectPenType(core.PenTool.laser);
    await tester.pump();
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    expect(h.container.read(editorReadOnlyProvider), isTrue);
    expect(
      tester.widget<ToolButton>(find.byKey(EditorToolbar.penKey)).onTap,
      isNull,
    );

    final points = _line(h, const Offset(100, 200), const Offset(400, 260));
    await h.driver.down(1, points.first, kind: PointerDeviceKind.stylus);
    for (final p in points.skip(1)) {
      await h.driver.wait(const Duration(milliseconds: 8));
      await h.driver.move(1, p);
    }
    expect(_active(h), isTrue);
    await h.driver.up(1);
    await tester.pump();
    expect(_edits(h), isEmpty);
    expect(h.session.history.undoDepth, 0);

    // The pen buttons are disabled; through the controller the ballpoint →
    // no interaction on the read-only note.
    h.container
        .read(editorToolProvider.notifier)
        .selectPenType(core.PenTool.ballpoint);
    await tester.pump();
    await h.driver.down(1, points.first, kind: PointerDeviceKind.stylus);
    await h.driver.wait(const Duration(milliseconds: 8));
    await h.driver.move(1, points[3]);
    expect(_active(h), isFalse);
    await h.driver.up(1);
    await tester.pump();
    expect(_edits(h), isEmpty);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a read-only note: a temporary tool (eraser tip) with the laser '
      'active → no input', (tester) async {
    final h = await pumpEditor(tester);
    h.container
        .read(editorToolProvider.notifier)
        .selectPenType(core.PenTool.laser);
    await tester.pump();
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    final points = _line(h, const Offset(100, 200), const Offset(400, 260));
    await h.driver.down(
      1,
      points.first,
      kind: PointerDeviceKind.invertedStylus,
    );
    await h.driver.wait(const Duration(milliseconds: 8));
    await h.driver.move(1, points[3]);
    expect(_active(h), isFalse);
    await h.driver.up(1);
    await tester.pump();
    expect(_edits(h), isEmpty);
  });
}
