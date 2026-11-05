// Browser smoke of the editor (04-editor 8.2 E-21, 9.1, 10 #2; contract
// 7.4.8): the editor screen on the web runtime (Chrome) over CORE's
// createFakeNoteStore() (web-safe, in memory) and the real INK. One stylus
// stroke through the whole screen (PointerDriver → InputRouter → INK →
// EditorCommands → CORE) → one add-strokes step, the stroke in CORE and on the
// INK controller; the toolbar undo → gone again, redo available.
//
// Run: `flutter test --platform chrome test/web` (or from the root
// `dart run tool/ws.dart test --platform chrome`). EDITOR needs no
// tool/prepare_web_test.dart.
@TestOn('browser')
library;

import 'package:feature_editor/src/ui/toolbar/undo_redo_buttons.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

/// Page points (pt) of a short curve in the upper part of page 0.
const List<Offset> _points = [
  Offset(100, 150),
  Offset(130, 170),
  Offset(170, 190),
  Offset(220, 205),
  Offset(280, 215),
];

List<String> _historyCalls(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute') || c.startsWith('undo')) c,
];

void main() {
  testWidgets('a stylus stroke → one add-strokes step; undo removes it', (
    tester,
  ) async {
    expect(kIsWeb, isTrue);
    final h = await pumpEditor(tester);
    final pageId = h.pageId(0);
    final controller = h.controllerOf(0);

    await h.driver.stylusStroke(pathThrough(h, 0, _points));
    await tester.pump();

    expect(_historyCalls(h), ['execute:add-strokes']);
    expect(h.session.history.undoDepth, 1);
    expect(h.session.history.undoLabel, 'add-strokes');
    final stroke = h.session.pageIfLoaded(pageId)!.strokes.single;
    expect(stroke.pageId, pageId);
    // The stroke starts and ends on its page points (F1 keeps the raw end).
    final last = stroke.points.length - 1;
    expect(stroke.points.x(0), closeTo(_points.first.dx, 0.02));
    expect(stroke.points.y(0), closeTo(_points.first.dy, 0.02));
    expect(stroke.points.x(last), closeTo(_points.last.dx, 0.02));
    expect(stroke.points.y(last), closeTo(_points.last.dy, 0.02));
    expect(controller.content!.strokes.map((s) => s.id), [stroke.id]);
    expect(controller.pendingIds, isEmpty);
    expect(h.recorder!.executeDuringDelivery, isFalse);

    await tester.tap(find.byKey(UndoRedoButtons.undoKey));
    await tester.pump();
    await tester.pump();

    expect(_historyCalls(h), ['execute:add-strokes', 'undo']);
    expect(h.session.history.undoDepth, 0);
    expect(h.session.history.canRedo, isTrue);
    expect(h.session.pageIfLoaded(pageId)!.strokes, isEmpty);
    expect(controller.content!.strokes, isEmpty);
    expect(controller.pendingIds, isEmpty);
  });
}
