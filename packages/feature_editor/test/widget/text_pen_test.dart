// (text pen, phase 1 — m5-7/04-editor 6.21) The 텍스트 펜 through the whole
// editor (PointerDriver → InputRouter → PenInteraction → TextPenController →
// fake CORE), with a recording recognition session (helpers/fake_text_pen.dart
// — it converts like recog: one composite 'recog-text-pen').
// - The tool is offered only with EditorExtensions.textPen; without it a
//   stored textPen tool draws like the pen and no group forms.
// - A text pen stroke is an ordinary ballpoint stroke (one step); grouping:
//   word gaps and the next row join; a far stroke starts a new group and the
//   old one stays handwriting (no background conversion — the math pen's
//   difference).
// - Conversion ONLY on the bubble tap (never a stroke): one step; undo gives
//   the exact strokes back as the open group; redo converts again.
// - A tool switch closes the group as handwriting; a long press on the bubble
//   or its '고치기' opens the sheet (fix).
// - Toolbar / folded ⋯도구 rows; [+] '손글씨를 텍스트로' picks the pen, or
//   with handwriting selected opens the sheet on it.
// - The math pen beside it keeps its own group and behaviour.
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/tools/math_pen/math_pen_controller.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/text_pen/text_pen_controller.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/overlays/text_pen_layer.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/insert_menu.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/fake_math_pen.dart';
import '../helpers/fake_text_pen.dart';
import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

Future<(EditorTestHandles, FakeTextPen)> _pump(
  WidgetTester tester, {
  bool withTextPen = true,
  FakeMathPen? mathPen,
  Size logicalSize = const Size(1032, 1376),
}) async {
  final pen = FakeTextPen();
  final h = await pumpEditor(
    tester,
    logicalSize: logicalSize,
    extensions: EditorExtensions(
      textPen: withTextPen ? pen.slot : null,
      mathPen: mathPen?.slot,
    ),
  );
  h.container.read(editorCommandsProvider).selectTool(EditorTool.textPen);
  await tester.pump();
  return (h, pen);
}

TextPenController _controller(EditorTestHandles h) =>
    h.container.read(editorTextPenProvider);

/// A short letter-like pair of strokes at [at] (page pt), [size] pt high.
Future<void> _letter(EditorTestHandles h, Offset at, {double size = 16}) async {
  await h.driver.stylusStroke(
    pathThrough(h, 0, [
      for (var i = 0; i <= 6; i++) at + Offset(i * size / 12, i * size / 6),
    ]),
  );
  await h.driver.stylusStroke(
    pathThrough(h, 0, [
      for (var i = 0; i <= 6; i++)
        at + Offset(size / 2 - i * size / 12, i * size / 6),
    ]),
  );
}

List<core.Stroke> _strokes(EditorTestHandles h) =>
    h.session.pageIfLoaded(h.pageId(0))!.strokes;

List<core.TextBoxObject> _boxes(EditorTestHandles h) => [
  ...h.session
      .pageIfLoaded(h.pageId(0))!
      .objects
      .whereType<core.TextBoxObject>(),
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

List<String> _sessionCalls(FakeTextPen pen) => [
  for (final s in pen.sessions) ...s.calls,
];

void main() {
  testWidgets('without EditorExtensions.textPen: no tool button, and a '
      'stored textPen tool draws like the pen (no group)', (tester) async {
    final (h, _) = await _pump(tester, withTextPen: false);
    expect(find.byKey(EditorToolbar.textPenKey), findsNothing);
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.textPen);
    await _letter(h, const Offset(100, 100));
    expect(_strokes(h), hasLength(2));
    expect(_controller(h).enabled, isFalse);
    expect(_controller(h).group, isNull);
    expect(find.byKey(TextPenLayer.bubbleKey), findsNothing);
  });

  testWidgets('with the slot: the toolbar button selects the text pen; '
      'strokes are ballpoint strokes (one step each) in one group; the '
      'bubble shows the session content above the group', (tester) async {
    final (h, pen) = await _pump(tester);
    await _selectTool(tester, h, EditorTool.pen);
    await tester.tap(find.byKey(EditorToolbar.textPenKey));
    await tester.pump();
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.textPen);

    await _letter(h, const Offset(100, 100));
    final strokes = _strokes(h);
    expect(strokes, hasLength(2));
    expect(strokes.map((s) => s.style.tool).toSet(), {core.PenTool.ballpoint});
    expect(h.session.history.undoDepth, 2);
    final c = _controller(h);
    expect(c.groupIds, [for (final s in strokes) s.id]);
    expect(c.phase, TextPenPhase.open);
    expect(pen.session.calls.where((x) => x == 'interrupt'), hasLength(1));
    expect(pen.session.updates.last.strokes.map((s) => s.id), c.groupIds);

    await tester.pump();
    final bubble = find.byKey(TextPenLayer.bubbleKey);
    expect(bubble, findsOneWidget);
    expect(find.text('text bubble 2'), findsOneWidget);
    final groupTop = h.toGlobal(0, const Offset(100, 100)).dy;
    expect(tester.getBottomLeft(bubble).dy, lessThan(groupTop));
  });

  testWidgets('grouping: the next letter, a word gap and the next row join; '
      'a far stroke starts a new group and the old one stays handwriting '
      '(no conversion)', (tester) async {
    final (h, pen) = await _pump(tester);
    await _letter(h, const Offset(100, 100));
    await _letter(h, const Offset(112, 100)); // next letter
    await _letter(h, const Offset(150, 100)); // a word gap (≈ 2 H)
    await _letter(h, const Offset(100, 128)); // the next row
    expect(_controller(h).groupIds, hasLength(8));

    await _letter(h, const Offset(400, 600));
    await tester.pump();
    expect(_controller(h).groupIds, hasLength(2));
    expect(_sessionCalls(pen).where((c) => c.startsWith('convert')), isEmpty);
    expect(_boxes(h), isEmpty);
    expect(_strokes(h), hasLength(10));
  });

  testWidgets('the bubble tap converts (ONE step, label recog-text-pen) and '
      'is not a stroke; undo gives the exact strokes back as the open group; '
      'redo converts again', (tester) async {
    final (h, pen) = await _pump(tester);
    await _letter(h, const Offset(100, 100));
    await tester.pump();
    final before = _strokes(h);
    final depth = h.session.history.undoDepth;

    await tester.tap(find.byKey(TextPenLayer.bubbleKey));
    await tester.pump();
    await tester.pump();
    expect(pen.session.converts, hasLength(1));
    expect(_strokes(h), isEmpty); // the tap drew nothing
    expect(_boxes(h).single.text, '글 2');
    expect(h.session.history.undoDepth, depth + 1);
    expect(h.session.history.undoLabel, 'recog-text-pen');
    expect(_controller(h).group, isNull);
    expect(find.byKey(TextPenLayer.bubbleKey), findsNothing);

    await _undo(tester, h);
    expect(_boxes(h), isEmpty);
    final back = _strokes(h);
    expect(back.map((s) => s.id), before.map((s) => s.id));
    for (var i = 0; i < back.length; i++) {
      expect(back[i].points.contentEquals(before[i].points), isTrue);
      expect(back[i].style, before[i].style);
    }
    expect(_controller(h).groupIds, before.map((s) => s.id));
    await tester.pump();
    expect(find.byKey(TextPenLayer.bubbleKey), findsOneWidget);

    await _redo(tester, h);
    expect(_boxes(h), hasLength(1));
    expect(_strokes(h), isEmpty);
  });

  testWidgets('a tool switch never converts: the group closes and stays '
      'handwriting; the eraser keeps it open', (tester) async {
    final (h, pen) = await _pump(tester);
    await _letter(h, const Offset(100, 100));
    await _selectTool(tester, h, EditorTool.eraser);
    expect(_controller(h).groupIds, hasLength(2));
    await _selectTool(tester, h, EditorTool.textPen);
    expect(_controller(h).groupIds, hasLength(2));
    await _selectTool(tester, h, EditorTool.lasso);
    expect(_controller(h).group, isNull);
    expect(_sessionCalls(pen).where((c) => c.startsWith('convert')), isEmpty);
    expect(_strokes(h), hasLength(2));
    expect(_boxes(h), isEmpty);
    expect(find.byKey(TextPenLayer.bubbleKey), findsNothing);
  });

  testWidgets('a long press on the bubble and its 고치기 open the sheet '
      '(fix); a sheet that converts is one step; a cancelled sheet keeps the '
      'group', (tester) async {
    final (h, pen) = await _pump(tester);
    await _letter(h, const Offset(100, 100));
    await tester.pump();
    await tester.longPress(find.byKey(TextPenLayer.bubbleKey));
    await tester.pump();
    expect(pen.session.fixes, hasLength(1));
    expect(_strokes(h), hasLength(2)); // cancelled
    expect(_controller(h).groupIds, hasLength(2));
    expect(_controller(h).phase, TextPenPhase.open);

    pen.sheetText = '고친 글';
    await tester.tap(find.byKey(const ValueKey('fake.textBubble.fix')));
    await tester.pump();
    await tester.pump();
    expect(pen.session.fixes, hasLength(2));
    expect(_boxes(h).single.text, '고친 글');
    expect(_strokes(h), isEmpty);
    expect(_controller(h).group, isNull);
  });

  testWidgets('no usable answer: the bubble tap opens the sheet instead', (
    tester,
  ) async {
    final (h, pen) = await _pump(tester);
    pen.textFor = (_) => null;
    await _letter(h, const Offset(100, 100));
    await tester.pump();
    await tester.tap(find.byKey(TextPenLayer.bubbleKey));
    await tester.pump();
    expect(pen.session.calls, containsAllInOrder(['convert 2', 'fix 2']));
    expect(_boxes(h), isEmpty);
    expect(_strokes(h), hasLength(2));
  });

  testWidgets('strokes written while the tap waited stay the open group', (
    tester,
  ) async {
    final (h, pen) = await _pump(tester);
    await _letter(h, const Offset(100, 100));
    await tester.pump();
    pen.holdConvert = Completer<void>();
    await tester.tap(find.byKey(TextPenLayer.bubbleKey));
    await tester.pump();
    expect(_controller(h).phase, TextPenPhase.converting);
    await _letter(h, const Offset(112, 100));
    expect(_strokes(h), hasLength(4));
    pen.holdConvert!.complete();
    await tester.pump();
    await tester.pump();
    expect(_boxes(h), hasLength(1));
    expect(_strokes(h), hasLength(2));
    expect(_controller(h).groupIds, [for (final s in _strokes(h)) s.id]);
  });

  testWidgets('(review) a stroke joining while the tap waits keeps the '
      'conversion running: a second tap starts no second conversion', (
    tester,
  ) async {
    final (h, pen) = await _pump(tester);
    await _letter(h, const Offset(100, 100));
    await tester.pump();
    pen.holdConvert = Completer<void>();
    await tester.tap(find.byKey(TextPenLayer.bubbleKey));
    await tester.pump();
    await _letter(h, const Offset(112, 100));
    await tester.pump();
    expect(_controller(h).phase, TextPenPhase.converting);
    await tester.tap(find.byKey(TextPenLayer.bubbleKey));
    await tester.pump();
    expect(pen.session.converts, hasLength(1));
    pen.holdConvert!.complete();
    await tester.pump();
    await tester.pump();
    expect(_controller(h).phase, TextPenPhase.open);
    expect(_boxes(h), hasLength(1));
  });

  testWidgets('(review) a short stroke written onto the bubble (it moved) '
      'does not convert; a tap does', (tester) async {
    final (h, pen) = await _pump(tester);
    await _letter(h, const Offset(100, 100));
    await tester.pump();
    final at = tester.getCenter(find.byKey(TextPenLayer.bubbleKey));
    final gesture = await tester.startGesture(
      at,
      kind: PointerDeviceKind.stylus,
    );
    await gesture.moveBy(const Offset(6, 0));
    await gesture.moveBy(const Offset(6, 0)); // 12 px: inside the InkWell slop
    await gesture.up();
    await tester.pump();
    expect(pen.session.converts, isEmpty);
    await tester.tap(
      find.byKey(TextPenLayer.bubbleKey),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await tester.pump();
    expect(pen.session.converts, hasLength(1));
  });

  testWidgets('(review) the first switch to the text pen says how it works — '
      'once per note screen', (tester) async {
    final (h, _) = await _pump(tester);
    await tester.pump();
    expect(find.text(EditorStrings.textPenFirstHint), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); // the enter animation
    await tester.pump(const Duration(seconds: 5)); // its display time
    await tester.pumpAndSettle();
    expect(find.text(EditorStrings.textPenFirstHint), findsNothing);
    await _selectTool(tester, h, EditorTool.pen);
    await _selectTool(tester, h, EditorTool.textPen);
    expect(find.text(EditorStrings.textPenFirstHint), findsNothing);
  });

  testWidgets('the folded toolbar: the 텍스트 펜 row in 도구 더보기, next to '
      'the 수식 펜', (tester) async {
    final math = FakeMathPen();
    final (h, _) = await _pump(
      tester,
      mathPen: math,
      logicalSize: const Size(700, 1000),
    );
    await _selectTool(tester, h, EditorTool.pen);
    await tester.tap(find.byKey(EditorToolbar.overflowToolsKey));
    await tester.pumpAndSettle();
    expect(find.byKey(EditorToolbar.mathKey), findsOneWidget);
    expect(find.byKey(EditorToolbar.textPenKey), findsOneWidget);
    // (review) no second row doing the same as the 텍스트 펜 row.
    expect(find.byKey(InsertMenu.handwritingToTextKey), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(EditorToolbar.mathKey)).dy,
      lessThan(tester.getTopLeft(find.byKey(EditorToolbar.textPenKey)).dy),
    );
    await tester.tap(find.byKey(EditorToolbar.textPenKey));
    await tester.pumpAndSettle();
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.textPen);
  });

  testWidgets('the unfolded toolbar at its narrowest (foldWidth) fits both '
      'pens without an overflow', (tester) async {
    final math = FakeMathPen();
    await _pump(
      tester,
      mathPen: math,
      logicalSize: const Size(EditorToolbar.foldWidth, 1000),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(EditorToolbar.mathKey), findsOneWidget);
    expect(find.byKey(EditorToolbar.textPenKey), findsOneWidget);
  });

  testWidgets('[+] 손글씨를 텍스트로: without a selection it picks the text '
      'pen', (tester) async {
    final (h, _) = await _pump(tester);
    await _selectTool(tester, h, EditorTool.pen);
    await tester.tap(find.byKey(InsertMenu.buttonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(InsertMenu.handwritingToTextKey));
    await tester.pumpAndSettle();
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.textPen);
  });

  testWidgets('[+] 손글씨를 텍스트로 with handwriting selected: the sheet on '
      'the selected recognition ink; a conversion clears the selection', (
    tester,
  ) async {
    final pen = FakeTextPen()..sheetText = '선택한 글';
    final h = await pumpEditor(
      tester,
      strokesByPageIndex: {
        0: [strokeA, strokeB, highlighterStroke],
      },
      extensions: EditorExtensions(textPen: pen.slot),
    );
    h.container.read(editorCommandsProvider).selectTool(EditorTool.lasso);
    await tester.pump();
    h.container.read(editorSelectionProvider.notifier).select(h.pageId(0), {
      strokeA.id,
      strokeB.id,
      highlighterStroke.id,
    }, origin: SelectionOrigin.lasso);
    await tester.pump();
    await tester.tap(find.byKey(InsertMenu.buttonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(InsertMenu.handwritingToTextKey));
    await tester.pumpAndSettle();
    final fixed = pen.session.fixes.single;
    expect(fixed.strokes.map((s) => s.id), [strokeA.id, strokeB.id]);
    expect(_boxes(h).single.text, '선택한 글');
    expect(h.container.read(editorSelectionProvider), isNull);
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.lasso);
  });

  testWidgets('the math pen beside it: its own group, converted on its own '
      'tool switch (math pen behaviour unchanged); the text group is '
      'separate', (tester) async {
    final math = FakeMathPen();
    final (h, pen) = await _pump(tester, mathPen: math);
    await _letter(h, const Offset(100, 100));
    expect(_controller(h).groupIds, hasLength(2));
    await _selectTool(tester, h, EditorTool.math);
    // The text group stays handwriting.
    expect(_controller(h).group, isNull);
    await _letter(h, const Offset(300, 400));
    final mathController = h.container.read(editorMathPenProvider);
    expect(mathController.groupIds, hasLength(2));
    await _selectTool(tester, h, EditorTool.textPen);
    // The math pen converts on a switch to another tool (its rule).
    expect(
      math.session.converts.single.$2,
      EditorMathConvertTrigger.toolSwitch,
    );
    expect(_sessionCalls(pen).where((c) => c.startsWith('convert')), isEmpty);
    expect(_strokes(h), hasLength(2));
  });

  testWidgets('leaving the note never converts', (tester) async {
    final (h, pen) = await _pump(tester);
    await _letter(h, const Offset(100, 100));
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
}
