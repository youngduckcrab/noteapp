// m5-7/04-editor 8.2 E2-08, 6.6.4 / 6.6.5: vertex handles through the whole
// editor (fake CORE, R2-B3 INK). A line's end point → ONE UpdateObjects (its
// angle snapped from the other end, shapeKind kept); '꼭짓점 편집' ('⋯') on a
// polygon → a handle on each of its N points, a vertex drag → UpdateObjects
// (no snapping, shapeKind kept, the mode kept after the re-selection); the
// mode ends with the selection; the menu item only for a polyline shape
// that is not a line / an arrow / a star (P-C).
import 'dart:math' as math;

import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/selection_hit_test.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/overlays/selection_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';

const double _deg = math.pi / 180;

final core.ShapeObject _line = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'line-1',
  kind: core.ShapeKind.line,
  rect: const core.PageRect(120, 150, 300, 150), // horizontal, 180 pt
  createdAt: 5,
);

final core.ShapeObject _polygon = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'polygon-1',
  kind: core.ShapeKind.polygon, // a pentagon
  rect: const core.PageRect(120, 300, 320, 480),
  createdAt: 6,
);

final core.ShapeObject _rectangle = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'rect-1',
  rect: const core.PageRect(380, 300, 500, 380),
  createdAt: 7,
);

final core.ShapeObject _star = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'star-1',
  kind: core.ShapeKind.star,
  rect: const core.PageRect(380, 450, 500, 560),
  createdAt: 8,
);

final core.ShapeObject _arrow = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'arrow-1',
  kind: core.ShapeKind.arrow,
  rect: const core.PageRect(120, 620, 300, 700),
  createdAt: 9,
);

final core.ShapeObject _ellipse = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'ellipse-1',
  kind: core.ShapeKind.ellipse,
  rect: const core.PageRect(380, 620, 500, 700),
  createdAt: 10,
);

final core.ShapeObject _triangle = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'triangle-1',
  kind: core.ShapeKind.triangle,
  rect: const core.PageRect(120, 520, 240, 600),
  createdAt: 11,
);

Future<EditorTestHandles> _pump(WidgetTester tester) async {
  final h = await pumpEditor(
    tester,
    objectsByPageIndex: {
      0: [_line, _polygon, _rectangle, _star, _arrow, _ellipse, _triangle],
    },
  );
  h.container.read(editorCommandsProvider).selectTool(EditorTool.lasso);
  await tester.pump();
  return h;
}

Future<void> _select(
  WidgetTester tester,
  EditorTestHandles h,
  String id,
) async {
  h.container.read(editorSelectionProvider.notifier).select(h.pageId(0), {id});
  await tester.pump();
}

EditorSelection? _selection(EditorTestHandles h) =>
    h.container.read(editorSelectionProvider);

SelectionFrameShape _frame(EditorTestHandles h) =>
    selectionFrameOnScreen(h.viewport, h.mountedPages, _selection(h))!;

List<String> _edits(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

core.ShapeObject _shape(EditorTestHandles h, String id) =>
    h.session.pageIfLoaded(h.pageId(0))!.objectById(id)! as core.ShapeObject;

List<core.PagePoint> _points(core.ShapeObject shape) =>
    (shape.geometry as core.PolylineGeometry).points;

/// The stylus from [from] to [to] (global) in 5 steps, then up.
Future<void> _drag(
  WidgetTester tester,
  EditorTestHandles h,
  Offset from,
  Offset to,
) async {
  await h.driver.down(1, from, kind: PointerDeviceKind.stylus);
  for (var i = 1; i <= 5; i++) {
    await h.driver.move(1, Offset.lerp(from, to, i / 5)!);
  }
  await h.driver.up(1);
  await tester.pump();
}

Future<void> _openMore(WidgetTester tester) async {
  await tester.tap(find.byKey(SelectionMenu.moreKey));
  await tester.pump();
}

void main() {
  testWidgets("a line's end point dragged to 47° → ONE UpdateObjects: the "
      'angle snapped to 45° from the other end (its length kept), shapeKind '
      'kept', (tester) async {
    final h = await _pump(tester);
    await _select(tester, h, _line.id);
    final f = _frame(h);
    expect(f.vertices, hasLength(2));
    expect(f.handles, isEmpty);
    expect(f.rotatable, isFalse);

    const length = 120.0;
    final target = Offset(
      120 + math.cos(47 * _deg) * length,
      150 + math.sin(47 * _deg) * length,
    );
    await _drag(
      tester,
      h,
      h.viewportToGlobal(f.vertices[1]),
      h.toGlobal(0, target),
    );

    expect(_edits(h), ['execute:update-objects']);
    expect(h.session.history.undoDepth, 1);
    final line = _shape(h, _line.id);
    expect(line.shapeKind, core.ShapeKind.line);
    final p = _points(line);
    expect(p[0], const core.PagePoint(120, 150));
    final d = Offset(p[1].x - 120, p[1].y - 150);
    expect(d.direction, closeTo(45 * _deg, 1e-9));
    expect(d.distance, closeTo(length, 1e-6));
    expect(_selection(h)!.elementIds, {_line.id});
    expect(h.controllerOf(0).previewObjects, isEmpty);
    // The frame follows the new end point.
    final end = h.toPage(0, h.viewportToGlobal(_frame(h).vertices[1]));
    expect(end.dx, closeTo(p[1].x, 1e-6));
    expect(end.dy, closeTo(p[1].y, 1e-6));
  });

  testWidgets("'꼭짓점 편집' on a pentagon → a handle on each of its 5 points; "
      'a vertex drag → UpdateObjects (no snapping), shapeKind and the mode '
      'kept; clearing the selection ends the mode', (tester) async {
    final h = await _pump(tester);
    await _select(tester, h, _polygon.id);
    expect(_frame(h).vertices, isEmpty);
    expect(_frame(h).handles.toSet(), SelectionHitTest.allHandles.toSet());

    await _openMore(tester);
    expect(find.byKey(SelectionMenu.verticesKey), findsOneWidget);
    await tester.tap(find.byKey(SelectionMenu.verticesKey));
    await tester.pump();
    expect(_selection(h)!.vertexMode, isTrue);
    final f = _frame(h);
    final before = _points(_polygon);
    expect(f.vertices, hasLength(before.length));
    expect(f.handles, isEmpty);
    expect(f.rotatable, isFalse);
    for (var i = 0; i < before.length; i++) {
      final p = h.toPage(0, h.viewportToGlobal(f.vertices[i]));
      expect(p.dx, closeTo(before[i].x, 1e-6));
      expect(p.dy, closeTo(before[i].y, 1e-6));
    }

    // Vertex 2 moved by (+17, +9) pt — no snapping for a polygon.
    final from = h.viewportToGlobal(f.vertices[2]);
    final to = h.toGlobal(0, Offset(before[2].x + 17, before[2].y + 9));
    await _drag(tester, h, from, to);
    expect(_edits(h), ['execute:update-objects']);
    final polygon = _shape(h, _polygon.id);
    expect(polygon.shapeKind, core.ShapeKind.polygon);
    final after = _points(polygon);
    expect(after[2].x, closeTo(before[2].x + 17, 1e-6));
    expect(after[2].y, closeTo(before[2].y + 9, 1e-6));
    for (final i in [0, 1, 3, 4]) {
      expect(after[i], before[i]);
    }
    expect(_selection(h)!.vertexMode, isTrue); // kept after the re-selection
    expect(_frame(h).vertices, hasLength(5));

    // The check while on; the item again turns it off.
    await _openMore(tester);
    expect(
      find.descendant(
        of: find.byKey(SelectionMenu.verticesKey),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(SelectionMenu.verticesKey));
    await tester.pump();
    expect(_selection(h)!.vertexMode, isFalse);
    expect(_frame(h).vertices, isEmpty);

    // On again, then the selection goes: off for the next selection.
    h.container.read(editorSelectionProvider.notifier).setVertexMode(true);
    await tester.pump();
    expect(_frame(h).vertices, hasLength(5));
    h.container.read(editorCommandsProvider).clearSelection();
    await tester.pump();
    expect(_selection(h), isNull);
    await _select(tester, h, _polygon.id);
    expect(_selection(h)!.vertexMode, isFalse);
    expect(_frame(h).vertices, isEmpty);
  });

  testWidgets("'꼭짓점 편집' only for a polyline shape that is not a line, an "
      'arrow or a star (P-C)', (tester) async {
    final h = await _pump(tester);
    for (final (shape, offered) in [
      (_polygon, true),
      (_rectangle, true),
      (_triangle, true),
      (_star, false),
      (_line, false),
      (_arrow, false),
      (_ellipse, false),
    ]) {
      await _select(tester, h, shape.id);
      await _openMore(tester);
      expect(
        find.byKey(SelectionMenu.verticesKey),
        offered ? findsOneWidget : findsNothing,
        reason: shape.id,
      );
      await _openMore(tester); // close
      // setVertexMode follows the same rule.
      h.container.read(editorSelectionProvider.notifier).setVertexMode(true);
      await tester.pump();
      expect(_selection(h)!.vertexMode, offered, reason: shape.id);
    }
  });

  testWidgets('a triangle vertex in vertex mode moves freely (no '
      'snapping), shapeKind kept', (tester) async {
    final h = await _pump(tester);
    await _select(tester, h, _triangle.id);
    h.container.read(editorSelectionProvider.notifier).setVertexMode(true);
    await tester.pump();
    final before = _points(_triangle);
    final f = _frame(h);
    expect(f.vertices, hasLength(3));
    await _drag(
      tester,
      h,
      h.viewportToGlobal(f.vertices[0]),
      h.toGlobal(0, Offset(before[0].x - 11, before[0].y - 23)),
    );
    expect(_edits(h), ['execute:update-objects']);
    final after = _points(_shape(h, _triangle.id));
    expect(after[0].x, closeTo(before[0].x - 11, 1e-6));
    expect(after[0].y, closeTo(before[0].y - 23, 1e-6));
    expect(_shape(h, _triangle.id).shapeKind, core.ShapeKind.triangle);
  });
}
