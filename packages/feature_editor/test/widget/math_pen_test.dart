// (math pen, phase 1 — docs/plans/m5-7/research/math-pen-phase1.md 2–9) The
// 수식 펜 through the whole editor (PointerDriver → InputRouter → PenInteraction
// → MathPenController → fake CORE), with a recording recognition session
// (helpers/fake_math_pen.dart — it converts like recog: one composite).
// - The tool is offered only with EditorExtensions.mathPen; without it a
//   stored math tool draws like the pen and no group forms.
// - A math pen stroke is an ordinary ballpoint stroke (one step); grouping:
//   a near stroke joins, a far one starts a new group and converts the old
//   one (newGroup).
// - Conversions: the bubble tap (a tap there is never a stroke), a tool
//   switch (not the eraser; eraser → pen converts), never on leaving.
// - Convert / undo / redo round trips give the exact strokes back; the
//   undone group is open again (a tool switch leaves it handwriting).
// - Continue writing: a stroke near a converted formula reopens it in ONE
//   step (one undo brings the formula back); x^2 → x^2+1.
// - The eraser in an open group: the group stays open, pieces stay in it.
// - The formula menu: a finger tap / a mouse click on a formula (a pen dot
//   is written: it reopens the formula); 고치기 → fix; 손글씨로 열기 → one
//   reopen step.
// - Review fixes: undo order after a far stroke (the stroke first), a late
//   background answer after other work is dropped (redo kept), the undone
//   group comes back once and only under the math pen / eraser, an erased
//   restored group stays handwriting, a tap that waited keeps strokes that
//   joined meanwhile, no reopen over the ink limits, eraser pieces of a copy
//   stay out, a palm on the bubble does not convert, the bubble hides off
//   screen, the iPad pose hover dot, a reopened group that does not convert
//   says so.
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/tools/interaction_host.dart';
import 'package:feature_editor/src/tools/math_pen/math_pen_controller.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/overlays/math_pen_layer.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/insert_menu.dart';
import 'package:feature_editor/src/ui/toolbar/overflow_tools_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/fake_math_pen.dart';
import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

Future<(EditorTestHandles, FakeMathPen)> _pump(
  WidgetTester tester, {
  bool withMathPen = true,
  Map<int, List<core.PageObject>> objects = const {},
}) async {
  final pen = FakeMathPen();
  final h = await pumpEditor(
    tester,
    objectsByPageIndex: objects,
    extensions: withMathPen ? EditorExtensions(mathPen: pen.slot) : null,
  );
  h.container.read(editorCommandsProvider).selectTool(EditorTool.math);
  await tester.pump();
  return (h, pen);
}

MathPenController _controller(EditorTestHandles h) =>
    h.container.read(editorMathPenProvider);

/// A short "x"-like pair of strokes at [at] (page pt), [size] pt high.
Future<void> _writeX(EditorTestHandles h, Offset at, {double size = 16}) async {
  await h.driver.stylusStroke(
    pathThrough(h, 0, [
      for (var i = 0; i <= 6; i++) at + Offset(i * size / 6, i * size / 6),
    ]),
  );
  await h.driver.stylusStroke(
    pathThrough(h, 0, [
      for (var i = 0; i <= 6; i++)
        at + Offset(size - i * size / 6, i * size / 6),
    ]),
  );
}

/// One stroke from [a] to [b] (page pt).
Future<void> _line(EditorTestHandles h, Offset a, Offset b) =>
    h.driver.stylusStroke(
      pathThrough(h, 0, [
        for (var i = 0; i <= 6; i++) Offset.lerp(a, b, i / 6)!,
      ]),
    );

List<core.Stroke> _strokes(EditorTestHandles h) =>
    h.session.pageIfLoaded(h.pageId(0))!.strokes;

List<core.MathObject> _maths(EditorTestHandles h) => [
  ...h.session.pageIfLoaded(h.pageId(0))!.objects.whereType<core.MathObject>(),
];

Future<void> _undo(WidgetTester tester, EditorTestHandles h) async {
  await h.container.read(editorCommandsProvider).undo();
  await tester.pump();
}

Future<void> _redo(WidgetTester tester, EditorTestHandles h) async {
  await h.container.read(editorCommandsProvider).redo();
  await tester.pump();
}

Future<void> _selectTool(
  WidgetTester tester,
  EditorTestHandles h,
  EditorTool tool,
) async {
  h.container.read(editorCommandsProvider).selectTool(tool);
  await tester.pump();
  await tester.pump();
}

/// The conversion steps the session ran so far.
List<EditorMathConvertTrigger> _triggers(FakeMathPen pen) => [
  for (final s in pen.sessions)
    for (final (_, t) in s.converts) t,
];

void main() {
  testWidgets('the tool button only with EditorExtensions.mathPen; without '
      'it a stored math tool draws like the pen (no group)', (tester) async {
    final (h, _) = await _pump(tester, withMathPen: false);
    // (v2.15-ui) 수식 펜 is '수식 쓰기' in [+]; without the slot (and nothing
    // else to insert here) there is no [+] at all.
    expect(find.byKey(InsertMenu.buttonKey), findsNothing);
    expect(find.byKey(InsertMenu.mathKey), findsNothing);
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.math);
    await _writeX(h, const Offset(100, 100));
    expect(_strokes(h), hasLength(2));
    expect(_controller(h).enabled, isFalse);
    expect(_controller(h).group, isNull);
    expect(find.byKey(MathPenLayer.bubbleKey), findsNothing);
  });

  testWidgets('with the slot: the button selects the math pen; strokes are '
      'ballpoint strokes (one step each) in one group; the bubble shows the '
      'session content above the group', (tester) async {
    final (h, pen) = await _pump(tester);
    await _selectTool(tester, h, EditorTool.pen);
    // (v2.15-ui) [+] › 수식 쓰기.
    await tester.tap(find.byKey(InsertMenu.buttonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(InsertMenu.mathKey));
    await tester.pumpAndSettle();
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.math);

    await _writeX(h, const Offset(100, 100));
    final strokes = _strokes(h);
    expect(strokes, hasLength(2));
    expect(strokes.map((s) => s.style.tool).toSet(), {core.PenTool.ballpoint});
    expect(h.session.history.undoDepth, 2);
    final c = _controller(h);
    expect(c.groupIds, [for (final s in strokes) s.id]);
    expect(c.phase, MathPenPhase.open);
    final session = pen.session;
    // The session opens with the first stroke; the second contact interrupts.
    expect(session.calls.where((x) => x == 'interrupt'), hasLength(1));
    expect(session.updates.last.strokes.map((s) => s.id), c.groupIds);

    await tester.pump();
    final bubble = find.byKey(MathPenLayer.bubbleKey);
    expect(bubble, findsOneWidget);
    expect(find.text('bubble 2'), findsOneWidget);
    // Above the group's bounds (screen).
    final groupTop = h.toGlobal(0, const Offset(100, 100)).dy;
    expect(tester.getBottomLeft(bubble).dy, lessThan(groupTop));
  });

  testWidgets('grouping: an exponent joins; a stroke far away starts a new '
      'group and converts the old one (newGroup)', (tester) async {
    final (h, pen) = await _pump(tester);
    await _writeX(h, const Offset(100, 100));
    await _line(h, const Offset(120, 92), const Offset(126, 84)); // exponent
    expect(_controller(h).groupIds, hasLength(3));
    expect(_triggers(pen), isEmpty);

    await _writeX(h, const Offset(300, 400));
    await tester.pump();
    expect(_triggers(pen), [EditorMathConvertTrigger.newGroup]);
    expect(_maths(h), hasLength(1));
    expect(_maths(h).single.latex, 'x^{3}');
    expect(_maths(h).single.ink, hasLength(3));
    expect(_controller(h).groupIds, hasLength(2));
  });

  testWidgets('the bubble tap converts (ONE step) and is not a stroke; undo '
      'gives the exact strokes back as the open group; redo converts again', (
    tester,
  ) async {
    final (h, pen) = await _pump(tester);
    await _writeX(h, const Offset(100, 100));
    await tester.pump();
    final before = _strokes(h);
    final depth = h.session.history.undoDepth;

    await tester.tap(find.byKey(MathPenLayer.bubbleKey));
    await tester.pump();
    await tester.pump();
    expect(_triggers(pen), [EditorMathConvertTrigger.bubbleTap]);
    expect(_strokes(h), isEmpty); // the tap drew nothing
    expect(_maths(h), hasLength(1));
    expect(h.session.history.undoDepth, depth + 1);
    expect(_controller(h).group, isNull);
    expect(find.byKey(MathPenLayer.bubbleKey), findsNothing);
    final math = _maths(h).single;
    expect(math.ink.map((s) => s.id), before.map((s) => s.id));

    await _undo(tester, h);
    expect(_maths(h), isEmpty);
    final back = _strokes(h);
    expect(back.map((s) => s.id), before.map((s) => s.id));
    for (var i = 0; i < back.length; i++) {
      expect(back[i].points.contentEquals(before[i].points), isTrue);
      expect(back[i].style, before[i].style);
      expect(back[i].createdAt, before[i].createdAt);
    }
    // The undone group is open again …
    expect(_controller(h).groupIds, before.map((s) => s.id));
    // … but a tool switch leaves it handwriting (the user chose it).
    await _selectTool(tester, h, EditorTool.lasso);
    expect(_triggers(pen), [EditorMathConvertTrigger.bubbleTap]);
    expect(_strokes(h), hasLength(2));

    await _redo(tester, h);
    expect(_maths(h), hasLength(1));
    expect(_strokes(h), isEmpty);
  });

  testWidgets('a tool switch converts (toolSwitch); the eraser keeps the '
      'group; leaving the eraser for the pen converts', (tester) async {
    final (h, pen) = await _pump(tester);
    await _writeX(h, const Offset(100, 100));
    await _selectTool(tester, h, EditorTool.eraser);
    expect(_triggers(pen), isEmpty);
    expect(_controller(h).groupIds, hasLength(2));
    await _selectTool(tester, h, EditorTool.math);
    expect(_triggers(pen), isEmpty);
    await _selectTool(tester, h, EditorTool.eraser);
    await _selectTool(tester, h, EditorTool.pen);
    expect(_triggers(pen), [EditorMathConvertTrigger.toolSwitch]);
    expect(_maths(h), hasLength(1));
  });

  testWidgets('no usable result: a tool switch leaves the handwriting', (
    tester,
  ) async {
    final (h, pen) = await _pump(tester);
    pen.latexFor = (_) => null;
    await _writeX(h, const Offset(100, 100));
    await _selectTool(tester, h, EditorTool.lasso);
    expect(_triggers(pen), [EditorMathConvertTrigger.toolSwitch]);
    expect(_strokes(h), hasLength(2));
    expect(_maths(h), isEmpty);
    expect(_controller(h).group, isNull);
  });

  testWidgets('continue writing: x^2 converted, "+1" next to it reopens it '
      'in ONE step (formula → its strokes + the new one), recognition runs on '
      'all; one undo brings the formula back', (tester) async {
    final (h, pen) = await _pump(tester);
    pen.latexFor = (g) => switch (g.strokes.length) {
      3 => 'x^{2}',
      _ => 'x^{2}+1',
    };
    await _writeX(h, const Offset(100, 100));
    await _line(h, const Offset(120, 92), const Offset(126, 84));
    await tester.pump();
    await tester.tap(find.byKey(MathPenLayer.bubbleKey));
    await tester.pump();
    await tester.pump();
    final x2 = _maths(h).single;
    expect(x2.latex, 'x^{2}');
    final depth = h.session.history.undoDepth;

    // "+": its first stroke starts just right of the formula's frame.
    final right = x2.frame.bounds.right;
    await _line(h, Offset(right + 4, 108), Offset(right + 14, 108));
    expect(_maths(h), isEmpty);
    expect(h.session.history.undoDepth, depth + 1);
    final c = _controller(h);
    expect(c.groupIds, hasLength(4));
    expect(c.group!.reopenedFrom, x2);
    expect(c.group!.reopenedStrokeIds, hasLength(3));
    // New ids for the reopened handwriting, same points.
    final reopened = c.group!.strokes.take(3).toList();
    for (var i = 0; i < 3; i++) {
      expect(reopened[i].id, isNot(x2.ink[i].id));
      expect(reopened[i].points.contentEquals(x2.ink[i].points), isTrue);
    }
    await _line(h, Offset(right + 9, 103), Offset(right + 9, 113));
    await _line(h, Offset(right + 20, 100), Offset(right + 20, 116));
    expect(c.groupIds, hasLength(6));
    expect(pen.session.updates.last.strokes, hasLength(6));

    await _selectTool(tester, h, EditorTool.pen);
    expect(_maths(h).single.latex, 'x^{2}+1');
    expect(_maths(h).single.ink, hasLength(6));

    // Undo: the second conversion, the two strokes, then the reopen step.
    for (var i = 0; i < 4; i++) {
      await _undo(tester, h);
    }
    final back = _maths(h).single;
    expect(back.id, x2.id);
    expect(back.latex, x2.latex);
    expect(back.frame, x2.frame);
    expect(back.ink, x2.ink); // the handwriting it keeps, exactly
    expect(_strokes(h), isEmpty);
  });

  testWidgets('the eraser in an open group: the group stays open and is '
      'recognized again; partial-eraser pieces stay in it', (tester) async {
    final (h, pen) = await _pump(tester);
    await _line(h, const Offset(100, 110), const Offset(160, 110));
    await _line(h, const Offset(130, 100), const Offset(130, 120));
    final c = _controller(h);
    expect(c.groupIds, hasLength(2));
    final updates = pen.session.updates.length;
    await _selectTool(tester, h, EditorTool.eraser);
    // Erase the middle of the horizontal stroke (partial eraser).
    await h.driver.stylusStroke(
      pathThrough(h, 0, [const Offset(115, 102), const Offset(115, 118)]),
    );
    await tester.pump();
    expect(_triggers(pen), isEmpty);
    expect(c.groupIds.length, greaterThanOrEqualTo(3)); // two pieces + "|"
    expect(pen.session.updates.length, greaterThan(updates));
    expect(c.groupIds.toSet(), {for (final s in _strokes(h)) s.id});
    // Back to the math pen: still the same group.
    await _selectTool(tester, h, EditorTool.math);
    await _line(h, const Offset(165, 100), const Offset(170, 95));
    expect(c.groupIds.length, greaterThanOrEqualTo(4));
  });

  testWidgets('the formula menu: a finger tap with the math pen; 고치기 → '
      'session.fix; 손글씨로 열기 → one reopen step', (tester) async {
    final ink = lineStroke(id: 'ink-1', x0: 200, y0: 300, x1: 240, y1: 320);
    final math = core.MathObject(
      id: 'math-1',
      pageId: 'x',
      frame: const core.ElementFrame(core.PageRect(200, 300, 260, 322)),
      latex: 'y',
      style: const core.MathStyle(),
      ink: [ink],
      createdAt: 5,
    );
    final (h, pen) = await _pump(
      tester,
      objects: {
        0: [math],
      },
    );
    await tester.tapAt(h.toGlobal(0, const Offset(230, 311)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(MathPenLayer.formulaMenuKey), findsOneWidget);
    expect(_strokes(h), isEmpty);
    await tester.tap(find.byKey(MathPenLayer.fixKey));
    await tester.pump();
    expect(pen.session.fixes.single.id, 'math-1');
    expect(find.byKey(MathPenLayer.formulaMenuKey), findsNothing);

    // A mouse click inside the frame opens it too (no dot stroke).
    await h.driver.stylusStroke([
      h.toGlobal(0, const Offset(230, 311)),
    ], kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(find.byKey(MathPenLayer.formulaMenuKey), findsOneWidget);
    expect(_strokes(h), isEmpty);
    final depth = h.session.history.undoDepth;
    await tester.tap(find.byKey(MathPenLayer.reopenKey));
    await tester.pump();
    expect(_maths(h), isEmpty);
    expect(_strokes(h), hasLength(1));
    expect(_strokes(h).single.points.contentEquals(ink.points), isTrue);
    expect(h.session.history.undoDepth, depth + 1);
    expect(_controller(h).groupIds, [_strokes(h).single.id]);
    await _undo(tester, h);
    expect(_maths(h).single.id, 'math-1');
    expect(_strokes(h), isEmpty);
    expect(_controller(h).group, isNull);
  });

  testWidgets('leaving the note never converts: the group stays handwriting', (
    tester,
  ) async {
    final (h, pen) = await _pump(tester);
    await _writeX(h, const Offset(100, 100));
    final session = pen.session;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(session.converts, isEmpty);
    expect(session.calls, containsAllInOrder(['clear', 'dispose']));
    final reopened = await h.store.openSession(h.noteId);
    addTearDown(reopened.close);
    final content = await reopened.openPage(h.pageId(0));
    expect(content.strokes, hasLength(2));
    expect(content.objects, isEmpty);
  });

  testWidgets('the note turns read-only: the group closes without a '
      'conversion (the strokes stay)', (tester) async {
    final (h, pen) = await _pump(tester);
    await _writeX(h, const Offset(100, 100));
    expect(_controller(h).groupIds, hasLength(2));
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    expect(_controller(h).group, isNull);
    expect(_triggers(pen), isEmpty);
    expect(_strokes(h), hasLength(2));
    expect(find.byKey(MathPenLayer.bubbleKey), findsNothing);
  });

  testWidgets('the folded toolbar: the 수식 펜 row in 도구 더보기', (tester) async {
    final pen = FakeMathPen();
    await pumpEditor(
      tester,
      logicalSize: const Size(700, 1000),
      extensions: EditorExtensions(mathPen: pen.slot),
    );
    await tester.tap(find.byKey(EditorToolbar.overflowToolsKey));
    await tester.pumpAndSettle();
    expect(find.byKey(OverflowToolsMenu.mathKey), findsOneWidget);
    await tester.tap(find.byKey(OverflowToolsMenu.mathKey));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(EditorToolbar)),
    );
    expect(container.read(editorToolProvider).activeTool, EditorTool.math);
  });

  // ---- review fixes ----

  testWidgets('review: one undo after a far stroke takes back that stroke, '
      'not the conversion of the old group (it converts first)', (
    tester,
  ) async {
    final (h, _) = await _pump(tester);
    await _writeX(h, const Offset(100, 100));
    final depth = h.session.history.undoDepth;
    await _line(h, const Offset(300, 500), const Offset(340, 500));
    await tester.pump();
    expect(_maths(h), hasLength(1));
    expect(h.session.history.undoDepth, depth + 2);
    expect(h.session.history.undoLabel, isNot('recog-math-pen'));
    await _undo(tester, h);
    expect(_maths(h), hasLength(1), reason: 'the formula stays');
    expect(_strokes(h), isEmpty, reason: 'the far stroke is undone');
    expect(_controller(h).group, isNull);
  });

  testWidgets('review: a late background answer after other work is dropped '
      '(the handwriting stays, redo is kept)', (tester) async {
    final (h, pen) = await _pump(tester);
    await _writeX(h, const Offset(100, 100));
    pen.holdConvert = Completer<void>();
    await _selectTool(tester, h, EditorTool.pen);
    await _line(h, const Offset(300, 500), const Offset(340, 500));
    await _undo(tester, h);
    expect(h.session.history.redoDepth, 1);
    pen.holdConvert!.complete();
    await tester.pump();
    await tester.pump();
    expect(pen.session.calls, contains('not wanted'));
    expect(_maths(h), isEmpty);
    expect(_strokes(h), hasLength(2));
    expect(h.session.history.redoDepth, 1, reason: 'redo kept');
    await _redo(tester, h);
    expect(_strokes(h), hasLength(3));
  });

  testWidgets('review: a late background answer with nothing done meanwhile '
      'still converts', (tester) async {
    final (h, pen) = await _pump(tester);
    await _writeX(h, const Offset(100, 100));
    pen.holdConvert = Completer<void>();
    await _selectTool(tester, h, EditorTool.lasso);
    expect(_maths(h), isEmpty);
    pen.holdConvert!.complete();
    await tester.pump();
    await tester.pump();
    expect(_maths(h), hasLength(1));
    expect(_strokes(h), isEmpty);
  });

  testWidgets('review: the undone group comes back once — closed by a tool '
      'switch, a later pen stroke never reopens it (no bubble under the '
      'pen)', (tester) async {
    final (h, pen) = await _pump(tester);
    await _writeX(h, const Offset(100, 100));
    await tester.pump();
    await tester.tap(find.byKey(MathPenLayer.bubbleKey));
    await tester.pump();
    await tester.pump();
    await _undo(tester, h);
    expect(_controller(h).groupIds, hasLength(2));
    await _selectTool(tester, h, EditorTool.pen);
    expect(_controller(h).group, isNull);
    await _line(h, const Offset(300, 500), const Offset(340, 500));
    await tester.pump();
    expect(_controller(h).group, isNull);
    expect(find.byKey(MathPenLayer.bubbleKey), findsNothing);
    // Back to the math pen: still nothing reopens by itself.
    await _selectTool(tester, h, EditorTool.math);
    await _line(h, const Offset(500, 700), const Offset(540, 700));
    expect(_controller(h).groupIds, hasLength(1));
    expect(_triggers(pen), [EditorMathConvertTrigger.bubbleTap]);
  });

  testWidgets('review: an undo of a conversion under another tool does not '
      'open the group', (tester) async {
    final (h, _) = await _pump(tester);
    await _writeX(h, const Offset(100, 100));
    await _selectTool(tester, h, EditorTool.lasso); // converts
    expect(_maths(h), hasLength(1));
    await _undo(tester, h);
    expect(_strokes(h), hasLength(2));
    expect(_controller(h).group, isNull);
    expect(find.byKey(MathPenLayer.bubbleKey), findsNothing);
  });

  testWidgets('review: erasing a part of a restored group keeps the user\'s '
      'choice — leaving the eraser does not convert it', (tester) async {
    final (h, pen) = await _pump(tester);
    await _line(h, const Offset(100, 110), const Offset(160, 110));
    await _line(h, const Offset(130, 100), const Offset(130, 120));
    await tester.pump();
    await tester.tap(find.byKey(MathPenLayer.bubbleKey));
    await tester.pump();
    await tester.pump();
    await _undo(tester, h);
    expect(_controller(h).groupIds, hasLength(2));
    await _selectTool(tester, h, EditorTool.eraser);
    await h.driver.stylusStroke(
      pathThrough(h, 0, [const Offset(115, 102), const Offset(115, 118)]),
    );
    await tester.pump();
    expect(_controller(h).groupIds.length, greaterThanOrEqualTo(3));
    await _selectTool(tester, h, EditorTool.pen);
    expect(_triggers(pen), [EditorMathConvertTrigger.bubbleTap]);
    expect(_maths(h), isEmpty);
  });

  testWidgets('review: strokes that joined while a bubble tap waited stay '
      'the open group', (tester) async {
    final (h, pen) = await _pump(tester);
    await _writeX(h, const Offset(100, 100));
    await tester.pump();
    pen.holdConvert = Completer<void>();
    await tester.tap(find.byKey(MathPenLayer.bubbleKey));
    await tester.pump();
    await _line(h, const Offset(120, 92), const Offset(126, 84)); // joins
    expect(_controller(h).groupIds, hasLength(3));
    pen.holdConvert!.complete();
    await tester.pump();
    await tester.pump();
    expect(_maths(h).single.ink, hasLength(2));
    final left = _strokes(h).single;
    expect(_controller(h).groupIds, [left.id]);
    expect(_controller(h).phase, MathPenPhase.open);
  });

  testWidgets('review: a stroke on a formula whose ink plus the stroke would '
      'go over the limits does not reopen it (a new group)', (tester) async {
    final ink = [
      for (var i = 0; i < core.PageObjectLimits.maxMathInkStrokes; i++)
        lineStroke(
          id: 'ink-$i',
          x0: 200,
          y0: 300,
          x1: 240,
          y1: 320,
          pointCount: 2,
          createdAt: i,
        ),
    ];
    final math = core.MathObject(
      id: 'big',
      pageId: 'x',
      frame: const core.ElementFrame(core.PageRect(200, 300, 260, 322)),
      latex: 'y',
      style: const core.MathStyle(),
      ink: ink,
      createdAt: 5,
    );
    final (h, _) = await _pump(
      tester,
      objects: {
        0: [math],
      },
    );
    await _line(h, const Offset(264, 310), const Offset(274, 310));
    expect(_maths(h).single.id, 'big', reason: 'not reopened');
    expect(_strokes(h), hasLength(1));
    expect(_controller(h).groupIds, [_strokes(h).single.id]);
    expect(_controller(h).group!.reopenedFrom, isNull);
  });

  testWidgets('review: eraser pieces of a pasted copy (same createdAt and '
      'style, elsewhere) do not join the open group', (tester) async {
    final (h, _) = await _pump(tester);
    await _line(h, const Offset(100, 110), const Offset(160, 110));
    final member = _strokes(h).single;
    // A copy of the same ink 20 pt lower (paste keeps createdAt).
    final copy = member
        .transformed(core.Affine2.translation(0, 20))
        .copyWith(id: 'copy');
    h.session.execute(core.AddStrokes(pageId: h.pageId(0), strokes: [copy]));
    await tester.pump();
    expect(_controller(h).groupIds, [member.id]);
    await _selectTool(tester, h, EditorTool.eraser);
    await h.driver.stylusStroke(
      pathThrough(h, 0, [const Offset(130, 100), const Offset(130, 140)]),
    );
    await tester.pump();
    final ids = _controller(h).groupIds;
    final strokes = {for (final s in _strokes(h)) s.id: s};
    expect(ids, hasLength(2), reason: 'the two pieces of the member');
    for (final id in ids) {
      expect(strokes[id]!.points.pointBounds.top, closeTo(110, 1));
    }
  });

  testWidgets('review: a pen dot inside a formula is written (it reopens '
      'the formula with the dot, one step); no menu', (tester) async {
    final ink = lineStroke(id: 'ink-1', x0: 200, y0: 300, x1: 240, y1: 320);
    final math = core.MathObject(
      id: 'math-1',
      pageId: 'x',
      frame: const core.ElementFrame(core.PageRect(200, 300, 260, 322)),
      latex: 'y',
      style: const core.MathStyle(),
      ink: [ink],
      createdAt: 5,
    );
    final (h, _) = await _pump(
      tester,
      objects: {
        0: [math],
      },
    );
    final depth = h.session.history.undoDepth;
    await h.driver.stylusStroke([h.toGlobal(0, const Offset(250, 311))]);
    await tester.pump();
    expect(find.byKey(MathPenLayer.formulaMenuKey), findsNothing);
    expect(_maths(h), isEmpty);
    expect(_strokes(h), hasLength(2)); // the handwriting + the dot
    expect(h.session.history.undoDepth, depth + 1);
    expect(_controller(h).group!.reopenedFrom!.id, 'math-1');
  });

  testWidgets('review: a finger the router takes for a palm (right after a '
      'stroke) does not convert on the bubble; a later finger tap does', (
    tester,
  ) async {
    final (h, pen) = await _pump(tester);
    await _writeX(h, const Offset(100, 100));
    await tester.pump();
    final at = tester.getCenter(find.byKey(MathPenLayer.bubbleKey));
    await h.driver.down(7, at);
    await h.driver.wait(const Duration(milliseconds: 40));
    await h.driver.up(7);
    await tester.pump();
    expect(_triggers(pen), isEmpty, reason: 'the writing hand');
    await h.driver.wait(const Duration(seconds: 3));
    await h.driver.down(7, at);
    await h.driver.wait(const Duration(milliseconds: 40));
    await h.driver.up(7);
    await tester.pump();
    await tester.pump();
    expect(_triggers(pen), [EditorMathConvertTrigger.bubbleTap]);
  });

  testWidgets('review: the bubble hides while the group is scrolled off '
      'screen', (tester) async {
    final (h, _) = await _pump(tester);
    await _writeX(h, const Offset(100, 100));
    await tester.pump();
    expect(find.byKey(MathPenLayer.bubbleKey), findsOneWidget);
    await h.viewport.jumpToPage(2, animate: false);
    await tester.pump();
    expect(_controller(h).group, isNotNull);
    expect(find.byKey(MathPenLayer.bubbleKey), findsNothing);
    await h.viewport.jumpToPage(0, animate: false);
    await tester.pump();
    expect(find.byKey(MathPenLayer.bubbleKey), findsOneWidget);
  });

  testWidgets('review: the iPad pose hover shows the math pen\'s ballpoint '
      'dot', (tester) async {
    final (h, _) = await _pump(tester);
    final host = h.container.read(editorInteractionHostProvider);
    host.poseHover(const Offset(200, 200));
    final cursor = host.cursor.value;
    expect(cursor, isA<PenDotCursor>());
    final ballpoint = h.container
        .read(editorToolProvider)
        .penStyles[core.PenTool.ballpoint]!;
    expect(
      (cursor! as PenDotCursor).color,
      Color(ballpoint.colorArgb).withValues(alpha: 0.5),
    );
    await tester.pump(const Duration(seconds: 1)); // the hide timer
  });

  testWidgets('review: a reopened formula that cannot convert again says it '
      'stayed handwriting', (tester) async {
    final ink = lineStroke(id: 'ink-1', x0: 200, y0: 300, x1: 240, y1: 320);
    final math = core.MathObject(
      id: 'math-1',
      pageId: 'x',
      frame: const core.ElementFrame(core.PageRect(200, 300, 260, 322)),
      latex: 'y',
      style: const core.MathStyle(),
      ink: [ink],
      createdAt: 5,
    );
    final (h, pen) = await _pump(
      tester,
      objects: {
        0: [math],
      },
    );
    pen.latexFor = (_) => null; // no engine answer
    await _line(h, const Offset(264, 310), const Offset(274, 310));
    expect(_controller(h).group!.reopenedFrom, isNotNull);
    await _selectTool(tester, h, EditorTool.lasso);
    await tester.pump();
    expect(_maths(h), isEmpty);
    expect(find.text(EditorStrings.mathKeptHandwriting), findsOneWidget);
  });
}
