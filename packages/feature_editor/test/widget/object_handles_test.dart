// m5-7/04-editor 8.2 E2-08, 6.6.4 / 6.6.5: a single object's handles through
// the whole editor (fake CORE, R2-B3 INK). The handles of each kind (the
// 6.6.4 table), an edge drag → an edited copy previewed with the same id
// (controller.previewObjects) → ONE UpdateObjects, the same id selected
// again, the preview cleared; a text box's width handle (the height
// re-measured); an image's edges only once its aspect is unlocked ('⋯');
// a turned text box's corner → ONE TransformElements with fontSizePt × s
// (CP-2); a remote delete during the drag → no command, no snackbar, no
// FlutterError report, the preview cleared (review S-1).
import 'dart:math' as math;

import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/tools/object_resize.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/selection_hit_test.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/overlays/selection_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

const double _deg = math.pi / 180;

final core.ShapeObject _rectangle = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'rect-1',
  rect: const core.PageRect(100, 120, 260, 220),
  createdAt: 5,
);

final core.ShapeObject _line = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'line-1',
  kind: core.ShapeKind.line,
  rect: const core.PageRect(320, 120, 480, 180),
  createdAt: 6,
);

final core.ShapeObject _arrow = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'arrow-1',
  kind: core.ShapeKind.arrow,
  rect: const core.PageRect(320, 230, 480, 230),
  createdAt: 7,
);

final core.ShapeObject _ellipse =
    PageObjectFixtures.shape(
      pageId: 'x',
      id: 'ellipse-1',
      kind: core.ShapeKind.ellipse,
      createdAt: 8,
    ).copyWith(
      geometry: const core.EllipseGeometry(
        core.ElementFrame(
          core.PageRect(100, 300, 260, 380),
          rotation: 30 * _deg,
        ),
      ),
    );

final core.TextBoxObject _text = PageObjectFixtures.textBox(
  pageId: 'x',
  id: 'text-1',
  text: '안녕 hello',
  rect: const core.PageRect(320, 300, 520, 340),
  createdAt: 9,
);

final core.ImageObject _image = PageObjectFixtures.image(
  pageId: 'x',
  id: 'image-1',
  assetId: 'missing-asset',
  rect: const core.PageRect(100, 450, 260, 550),
  createdAt: 10,
);

final core.MathObject _math = PageObjectFixtures.math(
  pageId: 'x',
  id: 'math-1',
  rect: const core.PageRect(320, 450, 420, 500),
  createdAt: 11,
);

final core.UnknownObject _unknown = PageObjectFixtures.unknown(
  pageId: 'x',
  id: 'unknown-1',
  rect: const core.PageRect(120, 650, 200, 720),
);

/// A 20° text box for the corner drag (CP-2).
final core.TextBoxObject _turnedText = _text.copyWith(
  frame: const core.ElementFrame(
    core.PageRect(320, 600, 520, 640),
    rotation: 20 * _deg,
  ),
);

Future<EditorTestHandles> _pump(
  WidgetTester tester, {
  List<core.PageObject>? objects,
}) async {
  final h = await pumpEditor(
    tester,
    strokesByPageIndex: {
      0: [strokeA, strokeB],
    },
    objectsByPageIndex: {
      0:
          objects ??
          [_rectangle, _line, _arrow, _ellipse, _text, _image, _math, _unknown],
    },
  );
  h.container.read(editorCommandsProvider).selectTool(EditorTool.lasso);
  await tester.pump();
  return h;
}

Future<void> _select(
  WidgetTester tester,
  EditorTestHandles h,
  Set<String> ids,
) async {
  h.container
      .read(editorSelectionProvider.notifier)
      .select(h.pageId(0), ids, origin: SelectionOrigin.tap);
  await tester.pump();
  expect(h.container.read(editorSelectionProvider)!.elementIds, ids);
}

EditorSelection? _selection(EditorTestHandles h) =>
    h.container.read(editorSelectionProvider);

SelectionFrameShape _frame(EditorTestHandles h) =>
    selectionFrameOnScreen(h.viewport, h.mountedPages, _selection(h))!;

/// [handle]'s position in global coordinates.
Offset _at(EditorTestHandles h, ink.SelectionHandle handle) =>
    h.viewportToGlobal(_frame(h).quad.handlePosition(handle));

List<String> _edits(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

core.PageContent _page(EditorTestHandles h) =>
    h.session.pageIfLoaded(h.pageId(0))!;

/// The stylus from [from] by [by] (global px) in 4 steps; the pen stays down.
Future<void> _drag(
  WidgetTester tester,
  EditorTestHandles h,
  Offset from,
  Offset by,
) async {
  await h.driver.down(1, from, kind: PointerDeviceKind.stylus);
  for (var i = 1; i <= 4; i++) {
    await h.driver.move(1, from + by * (i / 4));
  }
  await tester.pump();
}

Future<List<FlutterErrorDetails>> _reports(Future<void> Function() body) async {
  final reported = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = reported.add;
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return reported;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await useInkTestFonts();
  });

  testWidgets('the handles of each kind = the 6.6.4 table', (tester) async {
    final h = await _pump(tester);
    const corners = SelectionHitTest.cornerHandles;
    const all = SelectionHitTest.allHandles;

    // Several elements: 4 corners + the rotate handle.
    await _select(tester, h, {strokeA.id, _rectangle.id});
    var f = _frame(h);
    expect(f.handles, corners);
    expect(f.rotatable, isTrue);
    expect(f.vertices, isEmpty);
    expect(f.handleCount, 5);

    // A polyline shape: 4 corners + 4 edges + the rotate handle.
    await _select(tester, h, {_rectangle.id});
    f = _frame(h);
    expect(f.handles.toSet(), all.toSet());
    expect(f.rotatable, isTrue);
    expect(f.handleCount, 9);
    expect(f.boxed, isTrue);

    // A line / an arrow: the 2 end points, no box, no rotation.
    for (final shape in [_line, _arrow]) {
      await _select(tester, h, {shape.id});
      f = _frame(h);
      expect(f.handles, isEmpty, reason: shape.id);
      expect(f.rotatable, isFalse, reason: shape.id);
      expect(f.boxed, isFalse, reason: shape.id);
      expect(f.handleCount, 2, reason: shape.id);
      final points = (shape.geometry as core.PolylineGeometry).points;
      for (var i = 0; i < 2; i++) {
        final p = h.viewport.pageToScreen(0, Offset(points[i].x, points[i].y));
        expect(f.vertices[i].dx, closeTo(p.dx, 1e-9));
        expect(f.vertices[i].dy, closeTo(p.dy, 1e-9));
      }
    }

    // A turned ellipse: its rotated frame, 4 corners + 4 edges + rotate.
    await _select(tester, h, {_ellipse.id});
    f = _frame(h);
    expect(f.handles.toSet(), all.toSet());
    expect(f.handleCount, 9);
    expect(f.quad.angle, closeTo(30 * _deg, 1e-9));

    // A text box: 4 corners + left / right + rotate.
    await _select(tester, h, {_text.id});
    f = _frame(h);
    expect(f.handles.toSet(), {
      ...corners,
      ink.SelectionHandle.left,
      ink.SelectionHandle.right,
    });
    expect(f.handleCount, 7);

    // An image: 4 corners + rotate; unlocked → + 4 edges.
    await _select(tester, h, {_image.id});
    f = _frame(h);
    expect(f.handles, corners);
    expect(f.handleCount, 5);
    h.container.read(editorSelectionProvider.notifier).setAspectUnlocked(true);
    await tester.pump();
    expect(_frame(h).handles.toSet(), all.toSet());
    expect(_frame(h).handleCount, 9);

    // A math object: 4 corners + rotate.
    await _select(tester, h, {_math.id});
    expect(_selection(h)!.aspectUnlocked, isFalse); // a new selection
    f = _frame(h);
    expect(f.handles, corners);
    expect(f.handleCount, 5);

    // An unknown object: none.
    await _select(tester, h, {_unknown.id});
    expect(_frame(h).handleCount, 0);
  });

  testWidgets('a rectangle edge dragged: the edited copy previewed with the '
      'same id → ONE UpdateObjects, the same id selected again, the preview '
      'cleared', (tester) async {
    final h = await _pump(tester);
    await _select(tester, h, {_rectangle.id});
    final controller = h.controllerOf(0);
    final from = _at(h, ink.SelectionHandle.right);
    final fromPage = h.toPage(0, from);

    await _drag(tester, h, from, const Offset(60, 25));
    // While dragging: a preview copy (same id), no command, the menu hidden.
    expect(controller.previewObjects, hasLength(1));
    expect(controller.previewObjects.single.id, _rectangle.id);
    expect(_edits(h), isEmpty);
    expect(_selection(h)!.isDragging, isTrue);
    expect(find.byKey(SelectionMenu.cutKey), findsNothing);
    // The frame follows the copy.
    final dx = h.toPage(0, from + const Offset(60, 25)).dx - fromPage.dx;
    final moving = h.toPage(
      0,
      h.viewportToGlobal(
        _frame(h).quad.handlePosition(ink.SelectionHandle.right),
      ),
    );
    expect(moving.dx, closeTo(260 + dx, 1e-6));

    await h.driver.up(1);
    await tester.pump();
    expect(_edits(h), ['execute:update-objects']);
    expect(h.session.history.undoDepth, 1);
    expect(controller.previewObjects, isEmpty);
    final shape = _page(h).objectById(_rectangle.id)! as core.ShapeObject;
    expect(shape.frame.rect.left, closeTo(100, 1e-6));
    expect(shape.frame.rect.right, closeTo(260 + dx, 1e-6));
    expect(shape.frame.rect.top, closeTo(120, 1e-6));
    expect(shape.frame.rect.bottom, closeTo(220, 1e-6));
    expect(shape.style.strokeWidth, _rectangle.style.strokeWidth);
    expect(_selection(h)!.elementIds, {_rectangle.id});
    expect(_selection(h)!.origin, SelectionOrigin.tap);
    expect(_selection(h)!.isDragging, isFalse);
    expect(find.byKey(SelectionMenu.cutKey), findsOneWidget);

    // One undo brings the old rectangle back.
    await h.container.read(editorCommandsProvider).undo();
    await tester.pump();
    expect(_page(h).objectById(_rectangle.id)!.frame.rect.right, 260);
  });

  testWidgets('a turned ellipse edge → UpdateObjects: its local rect grows, '
      'the angle stays', (tester) async {
    final h = await _pump(tester);
    await _select(tester, h, {_ellipse.id});
    final from = _at(h, ink.SelectionHandle.bottom);
    // 40 px along the ellipse's own y axis (30° turned).
    final along = Offset(-math.sin(30 * _deg), math.cos(30 * _deg)) * 40;
    final wanted = h.toPage(0, from + along) - h.toPage(0, from);
    await _drag(tester, h, from, along);
    await h.driver.up(1);
    await tester.pump();

    expect(_edits(h), ['execute:update-objects']);
    final shape = _page(h).objectById(_ellipse.id)! as core.ShapeObject;
    final f = (shape.geometry as core.EllipseGeometry).ellipseFrame;
    expect(f.rotation, closeTo(30 * _deg, 1e-9));
    expect(f.rect.right - f.rect.left, closeTo(160, 1e-6));
    expect(f.rect.bottom - f.rect.top, closeTo(80 + wanted.distance, 1e-6));
  });

  testWidgets('a text box width handle: the width follows (≥ 40 pt), the '
      'height re-measured → ONE UpdateObjects', (tester) async {
    final h = await _pump(tester);
    await _select(tester, h, {_text.id});
    final from = _at(h, ink.SelectionHandle.right);
    await _drag(tester, h, from, const Offset(-400, 0)); // far past the left
    final preview =
        h.controllerOf(0).previewObjects.single as core.TextBoxObject;
    expect(preview.id, _text.id);
    expect(
      preview.frame.rect.right - preview.frame.rect.left,
      closeTo(ObjectResize.minTextWidthPt, 1e-9),
    );
    await h.driver.up(1);
    await tester.pump();

    expect(_edits(h), ['execute:update-objects']);
    final box = _page(h).objectById(_text.id)! as core.TextBoxObject;
    expect(box.frame.rect.left, closeTo(320, 1e-9));
    expect(box.frame.rect.right, closeTo(360, 1e-9));
    expect(box.text, _text.text);
    expect(box.style, _text.style);
    final measured = ink.InkTextLayout.measureSync(
      box.text,
      box.style,
      widthPt: 40,
    )!;
    expect(box.frame.rect.top, closeTo(300, 1e-9)); // the top kept
    expect(
      box.frame.rect.bottom - box.frame.rect.top,
      closeTo(measured.height, 1e-9),
    );
    expect(measured.height, greaterThan(40)); // wrapped onto more lines
  });

  testWidgets("an image's edges come with '비율 고정 풀기' ('⋯'): an edge drag "
      "→ UpdateObjects (a free resize); '비율 고정 잠그기' hides them again", (
    tester,
  ) async {
    final h = await _pump(tester);
    await _select(tester, h, {_image.id});
    expect(_frame(h).handles, SelectionHitTest.cornerHandles);

    await tester.tap(find.byKey(SelectionMenu.moreKey));
    await tester.pump();
    expect(
      find.widgetWithText(TextButton, EditorStrings.selectionUnlockAspect),
      findsOneWidget,
    );
    await tester.tap(find.byKey(SelectionMenu.aspectKey));
    await tester.pump();
    expect(_selection(h)!.aspectUnlocked, isTrue);
    expect(_frame(h).handles.toSet(), SelectionHitTest.allHandles.toSet());

    final from = _at(h, ink.SelectionHandle.right);
    await _drag(tester, h, from, const Offset(50, 0));
    await h.driver.up(1);
    await tester.pump();
    expect(_edits(h), ['execute:update-objects']);
    final image = _page(h).objectById(_image.id)! as core.ImageObject;
    expect(image.frame.rect.left, closeTo(100, 1e-9));
    expect(image.frame.rect.right, greaterThan(260 + 10));
    expect(image.frame.rect.top, closeTo(450, 1e-9));
    expect(image.frame.rect.bottom, closeTo(550, 1e-9)); // aspect not kept
    expect(image.assetId, 'missing-asset');
    // The mode survives the re-selection after the drag.
    expect(_selection(h)!.aspectUnlocked, isTrue);

    await tester.tap(find.byKey(SelectionMenu.moreKey));
    await tester.pump();
    expect(
      find.widgetWithText(TextButton, EditorStrings.selectionLockAspect),
      findsOneWidget,
    );
    await tester.tap(find.byKey(SelectionMenu.aspectKey));
    await tester.pump();
    expect(_selection(h)!.aspectUnlocked, isFalse);
    expect(_frame(h).handles, SelectionHitTest.cornerHandles);
  });

  testWidgets('a 20° text box corner → ONE TransformElements: fontSizePt × s '
      '(CP-2), the rotated opposite corner kept', (tester) async {
    final h = await _pump(tester, objects: [_turnedText]);
    await _select(tester, h, {_turnedText.id});
    final f = _frame(h);
    expect(f.quad.angle, closeTo(20 * _deg, 1e-9));
    final from = _at(h, ink.SelectionHandle.bottomRight);
    final diagonal = from - h.viewportToGlobal(f.quad.topLeft);
    await _drag(tester, h, from, diagonal / diagonal.distance * 60);
    expect(h.controllerOf(0).previewObjects, isEmpty); // a transform preview
    await h.driver.up(1);
    await tester.pump();

    expect(_edits(h), ['execute:transform']);
    expect(h.session.history.undoDepth, 1);
    final box = _page(h).objectById(_turnedText.id)! as core.TextBoxObject;
    final w = box.frame.rect.right - box.frame.rect.left;
    final s = w / 200;
    expect(s, greaterThan(1.1));
    expect(
      box.style.fontSizePt,
      closeTo(_turnedText.style.fontSizePt * s, 1e-6),
    );
    expect(box.frame.rotation, closeTo(20 * _deg, 1e-9));
    final o = _turnedText.frame.corners[0], o2 = box.frame.corners[0];
    expect(o2.x, closeTo(o.x, 1e-6));
    expect(o2.y, closeTo(o.y, 1e-6));
  });

  for (final (label, by, font) in const [
    ('bigger', Offset(2000, 2000), 144.0),
    ('smaller', Offset(-2000, -2000), 6.0),
  ]) {
    testWidgets('(math resize fix) a formula corner dragged far $label: ONE '
        'TransformElements, the font size stops at $font pt and the frame '
        'with it (aspect kept, opposite corner kept); undo / redo exact', (
      tester,
    ) async {
      final h = await _pump(tester, objects: [_math]);
      await _select(tester, h, {_math.id});
      final from = _at(h, ink.SelectionHandle.bottomRight);
      await _drag(tester, h, from, by);
      await h.driver.up(1);
      await tester.pump();

      expect(_edits(h), ['execute:transform']);
      final m = _page(h).objectById(_math.id)! as core.MathObject;
      expect(m.style.fontSizePt, closeTo(font, 1e-6));
      final r = m.frame.rect, r0 = _math.frame.rect;
      expect(r.width / r.height, closeTo(r0.width / r0.height, 1e-6));
      expect(
        r.width / m.style.fontSizePt,
        closeTo(r0.width / _math.style.fontSizePt, 1e-6),
        reason: 'the frame is the laid-out size at the new font size',
      );
      expect(r.left, closeTo(r0.left, 1e-6));
      expect(r.top, closeTo(r0.top, 1e-6));

      await h.session.undo();
      await tester.pump();
      final back = _page(h).objectById(_math.id)! as core.MathObject;
      expect(back.frame, _math.frame);
      expect(back.style, _math.style);
      await h.session.redo();
      await tester.pump();
      final again = _page(h).objectById(_math.id)! as core.MathObject;
      expect(again.frame, m.frame);
      expect(again.style, m.style);
    });
  }

  testWidgets('the object deleted elsewhere during an edge drag: the end '
      'sends no command, no snackbar, no FlutterError report, the preview '
      'cleared, the selection dropped (review S-1)', (tester) async {
    final h = await _pump(tester);
    await _select(tester, h, {_rectangle.id});
    final controller = h.controllerOf(0);
    final from = _at(h, ink.SelectionHandle.left);
    await _drag(tester, h, from, const Offset(-30, 0));
    expect(controller.previewObjects, hasLength(1));

    // A delete that does not come from this drag (another window — the
    // session directly, not the recorded wrapper).
    h.session.execute(
      core.RemoveElements(pageId: h.pageId(0), elementIds: [_rectangle.id]),
    );
    await tester.pump();
    expect(_page(h).objectById(_rectangle.id), isNull);

    final reported = await _reports(() async {
      await h.driver.move(1, from + const Offset(-40, 0));
      await h.driver.up(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    });
    expect(_edits(h), isEmpty);
    expect(reported, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(controller.previewObjects, isEmpty);
    expect(_selection(h), isNull);
  });

  testWidgets('cancel (a second finger) clears the preview, no command', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _select(tester, h, {_rectangle.id});
    final controller = h.controllerOf(0);
    await _drag(
      tester,
      h,
      _at(h, ink.SelectionHandle.top),
      const Offset(0, -30),
    );
    expect(controller.previewObjects, hasLength(1));
    await h.driver.cancel(1);
    await tester.pump();
    expect(controller.previewObjects, isEmpty);
    expect(_edits(h), isEmpty);
    expect(_selection(h)!.isDragging, isFalse);
    expect(_page(h).objectById(_rectangle.id)!.frame, _rectangle.frame);
  });
}
