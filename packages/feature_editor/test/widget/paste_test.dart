// m5-7/04-editor 8.2 E2-07a, 6.8: paste v2 through the whole editor (fake
// CORE, R2-B3 INK). Copy reads strokes and objects from CORE; a paste on
// another page is one step — AddStrokes for strokes only, AddObjects for
// objects only, CompositeCommand([AddStrokes, AddObjects]) for both — the
// pasted elements are selected with origin paste and the tool stays (6.6.3 —
// Q8); over the page's object limit (5.1.1) → the notice, no command. The
// context menu offers 붙여넣기 for objects too.
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/tools/element_clipboard.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/overlays/context_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

final core.ShapeObject _shape = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'shape-1',
  rect: const core.PageRect(300, 120, 420, 200),
  createdAt: 5,
);

final core.ImageObject _image = PageObjectFixtures.image(
  pageId: 'x',
  id: 'image-1',
  assetId: 'asset-7',
  rect: const core.PageRect(300, 450, 450, 560),
  createdAt: 6,
);

/// [count] small rectangles (page 1 filler for the object limit).
List<core.PageObject> _filler(int count) => [
  for (var i = 0; i < count; i++)
    PageObjectFixtures.shape(
      pageId: 'x',
      id: 'fill-$i',
      rect: core.PageRect(
        20 + (i % 40) * 13.0,
        20 + (i ~/ 40) * 15.0,
        28 + (i % 40) * 13.0,
        28 + (i ~/ 40) * 15.0,
      ),
      createdAt: 100 + i,
    ),
];

Future<EditorTestHandles> _pump(
  WidgetTester tester, {
  int pageOneObjects = 0,
}) => pumpEditor(
  tester,
  strokesByPageIndex: {
    0: [strokeA, strokeB],
  },
  objectsByPageIndex: {
    0: [_shape, _image],
    if (pageOneObjects > 0) 1: _filler(pageOneObjects),
  },
);

List<String> _edits(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

EditorSelection? _selection(EditorTestHandles h) =>
    h.container.read(editorSelectionProvider);

/// Selects [ids] on page 0 and copies them (no command).
Future<void> _copy(
  WidgetTester tester,
  EditorTestHandles h,
  Set<String> ids,
) async {
  h.container
      .read(editorSelectionProvider.notifier)
      .select(h.pageId(0), ids, origin: SelectionOrigin.lasso);
  await tester.pump();
  h.container.read(editorCommandsProvider).copySelection();
  await tester.pump();
  expect(_edits(h), isEmpty);
}

/// Page 1 on screen, then a secondary click at [at] (page 1 pt) → the
/// context menu → 붙여넣기.
Future<void> _pasteOnPageOne(
  WidgetTester tester,
  EditorTestHandles h, {
  Offset at = const Offset(300, 300),
}) async {
  await h.viewport.jumpToPage(1, animate: false);
  await tester.pump(const Duration(milliseconds: 200));
  await h.settlePages();
  final point = h.toGlobal(1, at);
  await h.driver.down(
    7,
    point,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await h.driver.up(7);
  await tester.pump();
  expect(find.byKey(EditorContextMenu.pasteKey), findsOneWidget);
  await tester.tap(find.byKey(EditorContextMenu.pasteKey));
  await tester.pump();
  await tester.pump();
}

core.PageContent _page(EditorTestHandles h, int index) =>
    h.session.pageIfLoaded(h.pageId(index))!;

void main() {
  testWidgets('strokes only → one add-strokes on the other page; selected '
      'with origin paste; the tool stays', (tester) async {
    final h = await _pump(tester);
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.pen);
    await _copy(tester, h, {strokeA.id, strokeB.id});
    await _pasteOnPageOne(tester, h);

    expect(_edits(h), ['executeAsync:add-strokes']);
    expect(h.session.history.undoDepth, 1);
    final pasted = _page(h, 1).strokes;
    expect(pasted, hasLength(2));
    expect(_page(h, 1).objects, isEmpty);
    expect(_selection(h)!.pageId, h.pageId(1));
    expect(_selection(h)!.elementIds, {for (final s in pasted) s.id});
    expect(_selection(h)!.origin, SelectionOrigin.paste);
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.pen);
  });

  testWidgets('strokes + objects → ONE composite step; every pasted element '
      'selected (origin paste); the image keeps its asset', (tester) async {
    final h = await _pump(tester);
    h.container.read(editorCommandsProvider).selectTool(EditorTool.lasso);
    await tester.pump();
    await _copy(tester, h, {strokeA.id, _shape.id, _image.id});
    final clip = h.container.read(editorClipboardProvider)!;
    expect(clip.elements.map((e) => e.id), [strokeA.id, _shape.id, _image.id]);
    expect(clip.objectCount, 2);

    await _pasteOnPageOne(tester, h);

    expect(_edits(h), ['executeAsync:composite']);
    expect(h.session.history.undoDepth, 1);
    expect(h.session.history.undoLabel, 'composite');
    final page = _page(h, 1);
    expect(page.strokes, hasLength(1));
    expect(page.objects, hasLength(2));
    final image = page.objects.whereType<core.ImageObject>().single;
    expect(image.assetId, 'asset-7');
    expect(image.id, isNot(_image.id));
    expect(_selection(h)!.elementIds, {
      page.strokes.single.id,
      for (final o in page.objects) o.id,
    });
    expect(_selection(h)!.origin, SelectionOrigin.paste);
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.lasso);

    // One undo removes all three.
    await h.container.read(editorCommandsProvider).undo();
    await tester.pump();
    expect(_page(h, 1).strokes, isEmpty);
    expect(_page(h, 1).objects, isEmpty);
  });

  testWidgets('objects only → one add-objects; 붙여넣기 is offered for them', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _copy(tester, h, {_shape.id});
    await _pasteOnPageOne(tester, h);
    expect(_edits(h), ['executeAsync:add-objects']);
    expect(h.session.history.undoDepth, 1);
    expect(_page(h, 1).objects, hasLength(1));
    expect(_page(h, 1).strokes, isEmpty);
    expect(_selection(h)!.origin, SelectionOrigin.paste);
  });

  testWidgets('over the page object limit → the notice, no command; up to '
      'the limit is fine', (tester) async {
    const max = core.PageObjectLimits.maxObjectsPerPage;
    final h = await _pump(tester, pageOneObjects: max - 1);
    await _copy(tester, h, {strokeA.id, _shape.id, _image.id});
    await _pasteOnPageOne(tester, h);
    expect(_edits(h), isEmpty);
    expect(find.text(EditorStrings.objectLimitReached(max)), findsOneWidget);
    expect(_page(h, 1).objectCount, max - 1);
    expect(h.session.history.undoDepth, 0);
    await tester.pump(const Duration(seconds: 5)); // snackbar timer

    // One object more fits exactly (max - 1 + 1 = max).
    await _copy(tester, h, {strokeA.id, _shape.id});
    await _pasteOnPageOne(tester, h);
    expect(_edits(h), ['executeAsync:composite']);
    expect(_page(h, 1).objectCount, max);
  });
}
