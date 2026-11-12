// E2-21 (m5-7/04-editor 8.3, contract 7.7.1 step 6): the 2nd-round browser
// smoke — the editor on the web runtime (Chrome) over CORE's
// createFakeNoteStore() and the real INK, with the web stylus contact rule
// on (6.3.2: a pen event touches only with the contact bit). The shape tool
// drags a rectangle (ONE AddObjects), the text tool's tap opens a box and
// '회의록 abc' is stored on a tap outside (ONE AddObjects), and the toolbar
// undo takes the box back, then the rectangle. Web compile and the session
// rules; IME quality is iPad Safari only (B-2, B-15).
//
// Run: `dart run tool/ws.dart test --package feature_editor --platform
// chrome`.
@TestOn('browser')
library;

import 'package:feature_editor/src/input/stylus_contact.dart';
import 'package:feature_editor/src/text/text_box_editor.dart';
import 'package:feature_editor/src/text/text_edit_session.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/undo_redo_buttons.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';

List<String> _executes(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

core.PageContent _page(EditorTestHandles h) =>
    h.session.pageIfLoaded(h.pageId(0))!;

void main() {
  setUpAll(useInkTestFonts);

  testWidgets('web rule: a rectangle, a text box, undo → each ONE step', (
    tester,
  ) async {
    expect(kIsWeb, isTrue);
    expect(StylusContact.platformRule, StylusContactRule.web);
    final h = await pumpEditor(tester);

    // --- the shape tool: drag a rectangle (contact bit on every move) ------
    await tester.tap(find.byKey(EditorToolbar.shapeKey));
    await tester.pump();
    final from = h.toGlobal(0, const Offset(120, 160));
    final to = h.toGlobal(0, const Offset(320, 260));
    await h.driver.down(1, from, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 8; i++) {
      await h.driver.wait(const Duration(milliseconds: 8));
      await h.driver.move(1, Offset.lerp(from, to, i / 8)!);
    }
    await h.driver.wait(const Duration(milliseconds: 8));
    await h.driver.up(1);
    await tester.pump();
    await tester.pump();
    expect(_executes(h), ['execute:add-objects']);
    final shape = _page(h).objects.whereType<core.ShapeObject>().single;
    expect(shape.shapeKind, core.ShapeKind.rectangle);
    expect(h.controllerOf(0).content!.objects.map((o) => o.id), [shape.id]);

    // --- the text tool: a tap → a new box → '회의록 abc' → a tap outside ---
    await tester.tap(find.byKey(EditorToolbar.textKey));
    await tester.pump();
    final at = h.toGlobal(0, const Offset(120, 400));
    await h.driver.down(2, at, kind: PointerDeviceKind.stylus);
    await h.driver.wait(const Duration(milliseconds: 20));
    await h.driver.move(2, at + const Offset(1, 0));
    await h.driver.wait(const Duration(milliseconds: 20));
    await h.driver.up(2);
    await tester.pump();
    await tester.pump();
    final s = h.container.read(editorTextEditProvider)!;
    expect(s.isNew, isTrue);
    await tester.enterText(find.byKey(textEditorKey), '회의록 abc');
    await tester.pump();
    await tester.tap(find.byKey(EditorToolbar.titleKey));
    await tester.pump();
    final notifier = h.container.read(editorTextEditProvider.notifier);
    await notifier.ending;
    await tester.pump();
    expect(notifier.lastEndReason, TextEditEndReason.tapOutside);
    expect(_executes(h), ['execute:add-objects', 'execute:add-objects']);
    final box = _page(h).objectById(s.boxId)! as core.TextBoxObject;
    expect(box.text, '회의록 abc');
    expect(h.session.history.undoDepth, 2);

    // --- undo twice: the box, then the rectangle -----------------------------
    await tester.tap(find.byKey(UndoRedoButtons.undoKey));
    await tester.pump();
    await tester.pump();
    expect(_page(h).objectById(s.boxId), isNull);
    expect(_page(h).objectById(shape.id), isNotNull);
    await tester.tap(find.byKey(UndoRedoButtons.undoKey));
    await tester.pump();
    await tester.pump();
    expect(_page(h).objects, isEmpty);
    expect(h.controllerOf(0).content!.objects, isEmpty);
    expect(h.session.history.undoDepth, 0);
    expect(h.session.history.canRedo, isTrue);
  });
}
