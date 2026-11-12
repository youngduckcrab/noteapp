// m5-7/04-editor 8.2 E2-09, 6.9.2: the shape tool through the whole editor
// (fake CORE, R2-B3 INK). A drag previews the shape (getter previewObjects)
// → ONE AddObjects, the new shape selected (origin drawn), the tool kept; a
// circle drawn inside the rectangle drawn a moment ago (review M-4); the
// drawn rectangle's corner handle resizes it (the handle first); under 8 px
// = a tap (an object selected, origin tap); a tap-selected shape's body
// starts a new shape; cancel → nothing; a read-only note → nothing; over
// the object limit → the notice, no command; (revision 3) the auto-shape
// commit path: InkEdit(addShape) through commitInkEdit → ONE AddObjects
// (5.1.2 '자동 도형 보정 확정' — mapping_table points here).
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/shape_interaction.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_options.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/ink_edit_builders.dart';
import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

final core.ImageObject _image = PageObjectFixtures.image(
  pageId: 'x',
  id: 'image-1',
  assetId: 'missing-asset',
  rect: const core.PageRect(320, 450, 470, 560),
  createdAt: 5,
);

final core.ShapeObject _triangle = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'triangle-1',
  kind: core.ShapeKind.triangle,
  rect: const core.PageRect(320, 120, 470, 260),
  createdAt: 6,
);

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
  List<core.PageObject>? objects,
  core.ShapeKind kind = core.ShapeKind.rectangle,
}) async {
  final h = await pumpEditor(
    tester,
    strokesByPageIndex: {
      0: [strokeA],
    },
    objectsByPageIndex: {
      0: objects ?? [_image, _triangle],
    },
  );
  h.container.read(editorCommandsProvider).selectTool(EditorTool.shape);
  h.container.read(editorToolOptionsProvider.notifier).setShapeKind(kind);
  await tester.pump();
  return h;
}

EditorSelection? _selection(EditorTestHandles h) =>
    h.container.read(editorSelectionProvider);

List<String> _edits(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

core.PageContent _page(EditorTestHandles h) =>
    h.session.pageIfLoaded(h.pageId(0))!;

/// The stylus from page point [a] to [b] (page 0) in 6 steps; up unless
/// [lift] is false.
Future<void> _drag(
  WidgetTester tester,
  EditorTestHandles h,
  Offset a,
  Offset b, {
  bool lift = true,
}) async {
  final from = h.toGlobal(0, a), to = h.toGlobal(0, b);
  await h.driver.down(1, from, kind: PointerDeviceKind.stylus);
  for (var i = 1; i <= 6; i++) {
    await h.driver.move(1, Offset.lerp(from, to, i / 6)!);
  }
  if (lift) await h.driver.up(1);
  await tester.pump();
}

/// A stylus tap at page point [a] (2 px of movement).
Future<void> _tap(WidgetTester tester, EditorTestHandles h, Offset a) async {
  final at = h.toGlobal(0, a);
  await h.driver.down(1, at, kind: PointerDeviceKind.stylus);
  await h.driver.move(1, at + const Offset(2, 0));
  await h.driver.up(1);
  await tester.pump();
}

core.ShapeObject? _newShape(EditorTestHandles h, Set<String> before) {
  final added = [
    for (final o in _page(h).objects)
      if (!before.contains(o.id)) o,
  ];
  return added.length == 1 ? added.single as core.ShapeObject : null;
}

Set<String> _ids(EditorTestHandles h) => {
  for (final o in _page(h).objects) o.id,
};

void _expectRect(core.PageRect r, core.PageRect want) {
  expect(r.left, closeTo(want.left, 1e-6));
  expect(r.top, closeTo(want.top, 1e-6));
  expect(r.right, closeTo(want.right, 1e-6));
  expect(r.bottom, closeTo(want.bottom, 1e-6));
}

void main() {
  testWidgets('a drag previews the rectangle (same renderer, previewObjects) '
      '→ ONE AddObjects, the new shape selected (origin drawn), the tool '
      'kept', (tester) async {
    final h = await _pump(tester);
    final controller = h.controllerOf(0);
    final before = _ids(h);
    await _drag(
      tester,
      h,
      const Offset(100, 120),
      const Offset(260, 220),
      lift: false,
    );
    final preview = controller.previewObjects.single as core.ShapeObject;
    expect(preview.id, ShapeInteraction.previewId);
    expect(preview.shapeKind, core.ShapeKind.rectangle);
    _expectRect(preview.frame.rect, const core.PageRect(100, 120, 260, 220));
    expect(_edits(h), isEmpty);

    await h.driver.up(1);
    await tester.pump();
    expect(_edits(h), ['execute:add-objects']);
    expect(h.session.history.undoDepth, 1);
    expect(controller.previewObjects, isEmpty);
    final shape = _newShape(h, before)!;
    expect(shape.shapeKind, core.ShapeKind.rectangle);
    expect(shape.id, isNot(ShapeInteraction.previewId));
    _expectRect(shape.frame.rect, const core.PageRect(100, 120, 260, 220));
    final options = h.container.read(editorToolOptionsProvider);
    expect(shape.style, options.shapeStyle.normalized());
    expect(_selection(h)!.elementIds, {shape.id});
    expect(_selection(h)!.origin, SelectionOrigin.drawn);
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.shape);
    // Its handles at once (6.6.4: a polyline shape — 4 + 4 + rotate).
    expect(
      selectionFrameOnScreen(
        h.viewport,
        h.mountedPages,
        _selection(h),
      )!.handleCount,
      9,
    );
  });

  testWidgets('inside the rectangle drawn a moment ago: a circle → ONE more '
      'AddObjects (the new circle), the rectangle unchanged, the circle '
      'selected (review M-4)', (tester) async {
    final h = await _pump(tester);
    await _drag(tester, h, const Offset(100, 120), const Offset(260, 220));
    final rectangle = _selection(h)!.elementIds.single;
    final rectFrame = _page(h).objectById(rectangle)!.frame;
    h.container
        .read(editorToolOptionsProvider.notifier)
        .setShapeKind(core.ShapeKind.ellipse);
    await tester.pump();
    final before = _ids(h);

    await _drag(tester, h, const Offset(140, 150), const Offset(200, 190));
    expect(_edits(h), ['execute:add-objects', 'execute:add-objects']);
    expect(h.session.history.undoDepth, 2);
    final circle = _newShape(h, before)!;
    expect(circle.shapeKind, core.ShapeKind.ellipse);
    expect(circle.geometry, isA<core.EllipseGeometry>());
    expect(_page(h).objectById(rectangle)!.frame, rectFrame);
    expect(_selection(h)!.elementIds, {circle.id});
    expect(_selection(h)!.origin, SelectionOrigin.drawn);
  });

  testWidgets("the drawn rectangle's corner handle resizes it (the handle "
      'first), no new shape', (tester) async {
    final h = await _pump(tester);
    await _drag(tester, h, const Offset(100, 120), const Offset(260, 220));
    final id = _selection(h)!.elementIds.single;
    final before = _ids(h);
    // The bottom-right handle (on the frame) dragged outwards.
    await _drag(tester, h, const Offset(260, 220), const Offset(300, 245));
    expect(_edits(h), ['execute:add-objects', 'execute:transform']);
    expect(_ids(h), before);
    final r = _page(h).objectById(id)!.frame.rect;
    expect(r.left, closeTo(100, 1e-6));
    expect(r.top, closeTo(120, 1e-6));
    expect(r.right, greaterThan(270));
    expect(_selection(h)!.elementIds, {id});
  });

  testWidgets('under 8 px = a tap: an object there selected (origin tap), '
      'an empty place selects nothing — no command', (tester) async {
    final h = await _pump(tester);
    await _tap(tester, h, const Offset(400, 500)); // on the image
    expect(_edits(h), isEmpty);
    expect(_selection(h)!.elementIds, {_image.id});
    expect(_selection(h)!.origin, SelectionOrigin.tap);
    expect(h.controllerOf(0).previewObjects, isEmpty);

    await _tap(tester, h, const Offset(60, 700)); // nothing there
    expect(_edits(h), isEmpty);
    expect(_selection(h), isNull);
  });

  testWidgets("a tap-selected shape's body: a drag there starts a new shape "
      '(the selection dropped), not a move', (tester) async {
    final h = await _pump(tester);
    // On the triangle's base (y 260): INK hits an unfilled shape on its
    // outline only (03-ink 6.14).
    await _tap(tester, h, const Offset(395, 260));
    expect(_selection(h)!.elementIds, {_triangle.id});
    final before = _ids(h);
    await _drag(tester, h, const Offset(380, 200), const Offset(440, 240));
    expect(_edits(h), ['execute:add-objects']);
    expect(_page(h).objectById(_triangle.id)!.frame, _triangle.frame);
    final shape = _newShape(h, before)!;
    expect(_selection(h)!.elementIds, {shape.id});
  });

  testWidgets('cancel (the pointer cancelled) → the preview cleared, no '
      'command', (tester) async {
    final h = await _pump(tester);
    await _drag(
      tester,
      h,
      const Offset(100, 120),
      const Offset(260, 220),
      lift: false,
    );
    expect(h.controllerOf(0).previewObjects, hasLength(1));
    await h.driver.cancel(1);
    await tester.pump();
    expect(h.controllerOf(0).previewObjects, isEmpty);
    expect(_edits(h), isEmpty);
    expect(_selection(h), isNull);
  });

  testWidgets('a read-only note: no preview, no command', (tester) async {
    final h = await _pump(tester);
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    expect(h.container.read(editorReadOnlyProvider), isTrue);
    await _drag(
      tester,
      h,
      const Offset(100, 120),
      const Offset(260, 220),
      lift: false,
    );
    expect(h.controllerOf(0).previewObjects, isEmpty);
    await h.driver.up(1);
    await tester.pump();
    expect(_edits(h), isEmpty);
    expect(h.session.history.undoDepth, 0);
  });

  testWidgets('a page at the object limit → the notice, no command, the '
      'preview cleared', (tester) async {
    const max = core.PageObjectLimits.maxObjectsPerPage;
    final h = await _pump(tester, objects: _filler(max));
    expect(_page(h).objectCount, max);
    await _drag(tester, h, const Offset(100, 200), const Offset(260, 300));
    expect(_edits(h), isEmpty);
    expect(find.text(EditorStrings.objectLimitReached(max)), findsOneWidget);
    expect(_page(h).objectCount, max);
    expect(h.controllerOf(0).previewObjects, isEmpty);
    expect(_selection(h), isNull);
    await tester.pump(const Duration(seconds: 5)); // snackbar timer
  });

  testWidgets('a line keeps the tool style\'s heads (none); an arrow '
      'without heads is drawn with one at the end', (tester) async {
    final h = await _pump(tester, kind: core.ShapeKind.line);
    var before = _ids(h);
    await _drag(tester, h, const Offset(100, 600), const Offset(250, 640));
    final line = _newShape(h, before)!;
    expect(line.shapeKind, core.ShapeKind.line);
    expect(line.style.arrowHeads, core.ArrowHeads.none);
    h.container
        .read(editorToolOptionsProvider.notifier)
        .setShapeKind(core.ShapeKind.arrow);
    await tester.pump();
    before = _ids(h);
    await _drag(tester, h, const Offset(100, 700), const Offset(250, 760));
    final arrow = _newShape(h, before)!;
    expect(arrow.shapeKind, core.ShapeKind.arrow);
    expect(arrow.style.arrowHeads, core.ArrowHeads.end);
  });

  testWidgets('(revision 3) the auto-shape commit path: InkEdit(addShape) '
      'through commitInkEdit on the mounted page → ONE AddObjects, no '
      'stroke, one ShapeObject in content.objects', (tester) async {
    final h = await _pump(tester, objects: const []);
    final strokesBefore = _page(h).strokes.length;
    final shape = PageObjectFixtures.shape(
      pageId: h.pageId(0),
      id: 'auto-1',
      kind: core.ShapeKind.ellipse,
      rect: const core.PageRect(150, 300, 300, 400),
    );
    final edit = addShapeEdit(h.pageId(0), shape);
    expect(edit.kind, ink.InkEditKind.addShape);
    final accepted = h.container
        .read(editorCommandsProvider)
        .commitInkEdit(h.controllerOf(0), edit);
    await tester.pump();
    expect(accepted, isTrue);
    expect(_edits(h), ['execute:add-objects']);
    expect(h.session.history.undoDepth, 1);
    expect(_page(h).strokes, hasLength(strokesBefore));
    final objects = _page(h).objects;
    expect(objects, hasLength(1));
    expect(objects.single, isA<core.ShapeObject>());
    expect(objects.single.id, 'auto-1');
  });
}
