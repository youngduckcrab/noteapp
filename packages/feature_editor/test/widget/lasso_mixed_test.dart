// m5-7/04-editor 8.2 E2-06 (part 1), 6.6.1–6.6.3, 6.3.5 ④: mixed selections
// through the whole editor (fake CORE, R2-B3 INK) — a lasso over strokes and
// objects selects all of them (INK allIds), a move is one TransformElements
// that moves the objects' frames too, the selection priority (a′) with a
// drawing tool (lasso / paste selections move, drawn / tap ones give way to
// the tool — review M-4), the 4 px move-start threshold (a tap = no
// command), and taps that select an object (lasso / shape / text tool).
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

final core.Stroke _strokeC = lineStroke(
  id: 'stroke-c',
  x0: 100,
  y0: 600,
  x1: 240,
  y1: 600,
  createdAt: 4,
);

final core.ShapeObject _shape = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'shape-1',
  rect: const core.PageRect(300, 120, 420, 200),
  createdAt: 5,
);
final core.TextBoxObject _text = PageObjectFixtures.textBox(
  pageId: 'x',
  id: 'text-1',
  rect: const core.PageRect(300, 300, 480, 340),
  createdAt: 6,
);
final core.ImageObject _image = PageObjectFixtures.image(
  pageId: 'x',
  id: 'image-1',
  assetId: 'missing-asset',
  rect: const core.PageRect(300, 450, 450, 560),
  createdAt: 7,
);

const _penOnly = EditorSettings(inputMode: InputMode.penOnly);

/// Longer than the palm-rejection cooldown after the pen lifts.
const _afterPen = Duration(seconds: 1);

Future<EditorTestHandles> _pump(
  WidgetTester tester, {
  EditorSettings? settings,
}) => pumpEditor(
  tester,
  settings: settings,
  strokesByPageIndex: {
    0: [strokeA, strokeB, _strokeC],
  },
  objectsByPageIndex: {
    0: [_shape, _text, _image],
  },
);

List<String> _edits(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

EditorSelection? _selection(EditorTestHandles h) =>
    h.container.read(editorSelectionProvider);

/// The selection frame in global coordinates (for the PointerDriver).
Rect _frame(EditorTestHandles h) => selectionRectOnScreen(
  h.viewport,
  h.mountedPages,
  _selection(h),
)!.shift(h.viewportOrigin);

core.PageContent _page(EditorTestHandles h) =>
    h.session.pageIfLoaded(h.pageId(0))!;

Rect _rectOf(core.PageRect r) =>
    Rect.fromLTRB(r.left, r.top, r.right, r.bottom);

void _tool(EditorTestHandles h, EditorTool tool) =>
    h.container.read(editorCommandsProvider).selectTool(tool);

void _select(
  EditorTestHandles h,
  Set<String> ids, {
  SelectionOrigin origin = SelectionOrigin.lasso,
}) => h.container
    .read(editorSelectionProvider.notifier)
    .select(h.pageId(0), ids, origin: origin);

/// A stylus drag from [from] by [by] (screen px) in a few steps.
Future<void> _drag(EditorTestHandles h, Offset from, Offset by) =>
    h.driver.stylusStroke([
      from,
      from + by * 0.25,
      from + by * 0.5,
      from + by * 0.75,
      from + by,
    ]);

/// Everything on page 0 lassoed with the lasso tool.
Future<void> _lassoAll(WidgetTester tester, EditorTestHandles h) async {
  _tool(h, EditorTool.lasso);
  await tester.pump();
  await h.driver.stylusStroke(
    lassoAround(h, 0, const Rect.fromLTRB(90, 110, 490, 610)),
  );
  await tester.pump();
}

void main() {
  testWidgets('a lasso over 3 strokes + shape, text box, image → elementIds '
      '6; a move → one TransformElements, the object frames move too', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _lassoAll(tester, h);
    final ids = {
      strokeA.id,
      strokeB.id,
      _strokeC.id,
      _shape.id,
      _text.id,
      _image.id,
    };
    expect(_selection(h)?.elementIds, ids);
    expect(_selection(h)?.origin, SelectionOrigin.lasso);
    expect(h.controllerOf(0).selection!.objectIds, {
      _shape.id,
      _text.id,
      _image.id,
    });
    expect(_edits(h), isEmpty);

    final before = {
      for (final o in _page(h).objects) o.id: _rectOf(o.frame.rect),
    };
    final depth = h.session.history.undoDepth;
    const by = Offset(60, 40);
    await _drag(h, _frame(h).center, by);
    await tester.pump();
    expect(_edits(h), ['execute:transform']);
    expect(h.session.history.undoDepth, depth + 1);
    final scale = h.viewport.camera.scale;
    final pageDelta = by / scale;
    for (final o in _page(h).objects) {
      final moved = _rectOf(o.frame.rect);
      expect(moved.left, closeTo(before[o.id]!.left + pageDelta.dx, 0.05));
      expect(moved.top, closeTo(before[o.id]!.top + pageDelta.dy, 0.05));
      expect(moved.width, closeTo(before[o.id]!.width, 0.05));
    }
    final a = _page(h).strokeById(strokeA.id)!;
    expect(a.bounds.left, closeTo(strokeA.bounds.left + pageDelta.dx, 0.05));
    // The same ids stay selected, origin kept.
    expect(_selection(h)?.elementIds, ids);
    expect(_selection(h)?.origin, SelectionOrigin.lasso);
  });

  testWidgets('a body tap within the 4 px move-start threshold → no command, '
      'the selection stays', (tester) async {
    final h = await _pump(tester);
    await _lassoAll(tester, h);
    final before = _selection(h);
    final c = _frame(h).center;
    await h.driver.stylusStroke([
      c,
      c + const Offset(2, 1),
      c + const Offset(3, 2),
    ]);
    await tester.pump();
    expect(_edits(h), isEmpty);
    expect(h.session.history.undoDepth, 0);
    expect(_selection(h), before);
    expect(h.controllerOf(0).selection!.previewTransform.isIdentity, isTrue);

    // Past the threshold it moves.
    await _drag(h, c, const Offset(6, 0));
    await tester.pump();
    expect(_edits(h), ['execute:transform']);
  });

  testWidgets('pen tool + a lasso selection: a body drag moves it (no new '
      'stroke)', (tester) async {
    final h = await _pump(tester);
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.pen);
    _select(h, {strokeA.id, _shape.id});
    await tester.pump();
    await _drag(h, _frame(h).center, const Offset(40, 30));
    await tester.pump();
    expect(_edits(h), ['execute:transform']);
    expect(_page(h).strokes, hasLength(3));
    expect(_selection(h)?.elementIds, {strokeA.id, _shape.id});
  });

  testWidgets('pen tool + a pasted selection: a body drag → one '
      'TransformElements (move), no stroke (review M-4)', (tester) async {
    final h = await _pump(tester);
    _tool(h, EditorTool.lasso);
    await tester.pump();
    await h.driver.stylusStroke(
      lassoAround(h, 0, const Rect.fromLTRB(100, 145, 220, 155)),
    );
    await tester.pump();
    expect(_selection(h)?.elementIds, {strokeA.id});
    final commands = h.container.read(editorCommandsProvider)..copySelection();
    _tool(h, EditorTool.pen);
    await tester.pump();
    expect(_selection(h), isNull); // leaving the lasso clears it (1st round)
    await commands.paste();
    await tester.pump();
    await tester.pump();
    // (v2, 6.6.3 — Q8) the tool stays, origin paste.
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.pen);
    expect(_selection(h)?.origin, SelectionOrigin.paste);
    final pasted = _selection(h)!.elementIds;
    expect(pasted, hasLength(1));

    await _drag(h, _frame(h).center, const Offset(50, 50));
    await tester.pump();
    expect(_edits(h), ['executeAsync:add-strokes', 'execute:transform']);
    expect(_page(h).strokes, hasLength(4)); // 3 seeded + 1 pasted, no new one
    expect(_selection(h)?.elementIds, pasted);
  });

  testWidgets('pen tool + a tap / drawn selection: a body drag drops the '
      'selection and draws a stroke', (tester) async {
    final h = await _pump(tester);
    for (final origin in [SelectionOrigin.tap, SelectionOrigin.drawn]) {
      _select(h, {_shape.id}, origin: origin);
      await tester.pump();
      final count = _page(h).strokes.length;
      await _drag(h, _frame(h).center, const Offset(30, 20));
      await tester.pump();
      expect(_selection(h), isNull, reason: '$origin');
      expect(_page(h).strokes, hasLength(count + 1), reason: '$origin');
      expect(_edits(h).last, 'execute:add-strokes');
    }
    expect(_edits(h), ['execute:add-strokes', 'execute:add-strokes']);
  });

  testWidgets('pen tool: a handle drag manipulates even a tap selection; a '
      'down outside drops it and draws', (tester) async {
    final h = await _pump(tester);
    _select(h, {_image.id}, origin: SelectionOrigin.tap);
    await tester.pump();
    final frame = _frame(h);
    await _drag(h, frame.bottomRight, const Offset(30, 30));
    await tester.pump();
    expect(_edits(h), ['execute:transform']);
    expect(_selection(h)?.elementIds, {_image.id});

    final empty = h.toGlobal(0, const Offset(520, 700));
    await _drag(h, empty, const Offset(30, 0));
    await tester.pump();
    expect(_selection(h), isNull);
    expect(_edits(h), ['execute:transform', 'execute:add-strokes']);
  });

  testWidgets('a finger tap (pen only) selects the object under it: lasso '
      'tool → origin lasso, shape tool → tap, text tool → a non-text object '
      'only; empty → cleared', (tester) async {
    final h = await _pump(tester, settings: _penOnly);
    final image = h.toGlobal(0, const Offset(375, 505));
    final text = h.toGlobal(0, const Offset(390, 320));
    final empty = h.toGlobal(0, const Offset(520, 700));

    _tool(h, EditorTool.lasso);
    await tester.pump();
    await h.driver.multiTap([image]);
    await tester.pump();
    expect(_selection(h)?.elementIds, {_image.id});
    expect(_selection(h)?.origin, SelectionOrigin.lasso);
    await h.driver.multiTap([empty]);
    await tester.pump();
    expect(_selection(h), isNull);

    _tool(h, EditorTool.shape);
    await tester.pump();
    await h.driver.multiTap([text]);
    await tester.pump();
    expect(_selection(h)?.elementIds, {_text.id});
    expect(_selection(h)?.origin, SelectionOrigin.tap);
    await h.driver.multiTap([empty]);
    await tester.pump();

    _tool(h, EditorTool.text);
    await tester.pump();
    await h.driver.multiTap([text]);
    await tester.pump();
    expect(_selection(h), isNull); // a text box is the text tool's own (E2-10)
    await h.driver.multiTap([image]);
    await tester.pump();
    expect(_selection(h)?.elementIds, {_image.id});
    expect(_selection(h)?.origin, SelectionOrigin.tap);

    _tool(h, EditorTool.pen);
    await tester.pump();
    await h.driver.multiTap([image]);
    await tester.pump();
    expect(_selection(h), isNull); // the pen tool clears (1st round)
    expect(_edits(h), isEmpty);
  });

  testWidgets('a stylus tap with the lasso tool selects the object under it '
      '(a degenerate lasso); a real lasso over nothing selects nothing', (
    tester,
  ) async {
    final h = await _pump(tester);
    _tool(h, EditorTool.lasso);
    await tester.pump();
    final at = h.toGlobal(0, const Offset(360, 160));
    await h.driver.stylusStroke([at, at + const Offset(1, 1)]);
    await tester.pump();
    expect(_selection(h)?.elementIds, {_shape.id});
    expect(_selection(h)?.origin, SelectionOrigin.lasso);

    // A lasso drawn away from everything (no object under its start).
    await h.driver.stylusStroke(
      lassoAround(h, 0, const Rect.fromLTRB(500, 650, 560, 700)),
    );
    await tester.pump();
    expect(_selection(h), isNull);
    expect(_edits(h), isEmpty);
  });

  testWidgets('read-only note: a tap selects nothing', (tester) async {
    final h = await _pump(tester, settings: _penOnly);
    _tool(h, EditorTool.lasso);
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    await h.driver.multiTap([h.toGlobal(0, const Offset(375, 505))]);
    await tester.pump();
    expect(_selection(h), isNull);
  });

  testWidgets('pen only: a finger on a pasted selection body moves it with '
      'the pen tool (hitsSelection follows the priority)', (tester) async {
    final h = await _pump(tester, settings: _penOnly);
    _select(h, {_image.id}, origin: SelectionOrigin.paste);
    await tester.pump();
    final host = h.container.read(editorInteractionHostProvider);
    final c = _frame(h).center;
    // hitsSelection takes viewport coordinates.
    final cv = c - h.viewportOrigin;
    expect(host.hitsSelection(cv), isTrue);
    _select(h, {_image.id}, origin: SelectionOrigin.tap);
    await tester.pump();
    expect(host.hitsSelection(cv), isFalse);
    expect(
      host.hitsSelection(_frame(h).bottomRight - h.viewportOrigin),
      isTrue,
    ); // a handle

    _select(h, {_image.id}, origin: SelectionOrigin.paste);
    await tester.pump();
    await h.driver.down(21, c, kind: PointerDeviceKind.touch);
    for (var i = 1; i <= 4; i++) {
      await h.driver.move(21, c + Offset(10.0 * i, 0));
    }
    await h.driver.up(21);
    await tester.pump();
    expect(_edits(h), ['execute:transform']);
    await h.driver.wait(_afterPen);
  });
}
