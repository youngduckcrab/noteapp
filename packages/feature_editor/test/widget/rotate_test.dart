// m5-7/04-editor 8.2 E2-06 (part 2), 6.6.4 / 6.6.6: the rotate handle through
// the whole editor (fake CORE, R2-B3 INK). Several elements and a polyline
// shape rotate by the relative angle (snapAngle(φ − φ₀) about the bounds
// centre), an object whose frame rotates by the absolute one (snapAngle(θ +
// Δφ) − θ about its frame centre); 15° snapping within ±3° — the test angles
// stay ≥ 1° away from the snap borders (review S-2 · S-12(f)); the angle tag;
// 90° rotate (one step, no preview — the V5 path); a rejected commit
// (discardEdit, selection kept); a single rotated object's frame, its corner
// drag (ObjectResize.cornerScale — the rotated opposite corner stays) and an
// unknown object (no handles, no move).
import 'dart:math' as math;

import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/selection_hit_test.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/overlays/rotation_label.dart';
import 'package:feature_editor/src/ui/overlays/selection_frame_painter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart' show Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

const double _deg = math.pi / 180;

final core.ImageObject _image =
    PageObjectFixtures.image(
      pageId: 'x',
      id: 'image-1',
      assetId: 'missing-asset',
      rect: const core.PageRect(300, 450, 450, 560),
      createdAt: 5,
    ).copyWith(
      frame: const core.ElementFrame(
        core.PageRect(300, 450, 450, 560),
        rotation: 10 * _deg,
      ),
    );

final core.ShapeObject _rectangle = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'shape-1',
  rect: const core.PageRect(320, 120, 440, 200),
  createdAt: 6,
);

final core.UnknownObject _unknown = PageObjectFixtures.unknown(
  pageId: 'x',
  id: 'unknown-1',
  rect: const core.PageRect(120, 650, 200, 720),
);

Future<EditorTestHandles> _pump(WidgetTester tester) async {
  final h = await pumpEditor(
    tester,
    strokesByPageIndex: {
      0: [strokeA, strokeB],
    },
    objectsByPageIndex: {
      0: [_image, _rectangle, _unknown],
    },
  );
  h.container.read(editorCommandsProvider).selectTool(EditorTool.lasso);
  await tester.pump();
  return h;
}

void _select(
  EditorTestHandles h,
  Set<String> ids, {
  SelectionOrigin origin = SelectionOrigin.lasso,
}) => h.container
    .read(editorSelectionProvider.notifier)
    .select(h.pageId(0), ids, origin: origin);

EditorSelection? _selection(EditorTestHandles h) =>
    h.container.read(editorSelectionProvider);

List<String> _edits(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

core.PageContent _page(EditorTestHandles h) =>
    h.session.pageIfLoaded(h.pageId(0))!;

/// The frame as drawn, in global coordinates (for the PointerDriver).
SelectionQuad _quad(EditorTestHandles h) => selectionFrameOnScreen(
  h.viewport,
  h.mountedPages,
  _selection(h),
)!.quad.shift(h.viewportOrigin);

/// [p] turned by [radians] about [c].
core.PagePoint _turn(core.PagePoint p, Offset c, double radians) {
  final (x, y) = core.Affine2.rotation(
    radians,
    originX: c.dx,
    originY: c.dy,
  ).apply(p.x, p.y);
  return core.PagePoint(x, y);
}

/// Puts the stylus on the rotate handle and moves it [degrees] around the
/// frame centre in 6 steps (an arc — the radius stays). Leaves the pen down.
Future<void> _rotateBy(
  WidgetTester tester,
  EditorTestHandles h,
  double degrees,
) async {
  final quad = _quad(h);
  final c = quad.center;
  final start = quad.rotateHandlePosition;
  final r = (start - c).distance;
  final from = (start - c).direction;
  await h.driver.down(1, start, kind: PointerDeviceKind.stylus);
  for (var i = 1; i <= 6; i++) {
    final a = from + degrees * _deg * i / 6;
    await h.driver.move(1, c + Offset(math.cos(a), math.sin(a)) * r);
  }
  await tester.pump();
}

String? _label(WidgetTester tester) {
  final tag = find.descendant(
    of: find.byKey(RotationLabel.labelKey),
    matching: find.byType(Text),
  );
  if (tag.evaluate().isEmpty) return null;
  return tester.widget<Text>(tag).data;
}

void main() {
  testWidgets('several strokes: the rotate handle dragged 47° → snapped to '
      '45° (relative, about the bounds centre), the tag shows 45°, one '
      'TransformElements step, the same ids selected', (tester) async {
    final h = await _pump(tester);
    _select(h, {strokeA.id, strokeB.id});
    await tester.pump();
    final sel = h.controllerOf(0).selection!;
    final centre = sel.bounds.center;

    // The keyed hit area (appendix C) sits on the rotate handle.
    final quad = _quad(h);
    expect(
      tester.getCenter(find.byKey(SelectionFrame.rotateHandleKey)),
      quad.rotateHandlePosition,
    );
    // Straight above the top edge's middle (an axis-aligned frame).
    expect(quad.angle, 0);
    expect(
      quad.rotateHandlePosition,
      quad.rotateHandleBase -
          const Offset(0, SelectionHitTest.rotateHandleOffset),
    );

    await _rotateBy(tester, h, 47);
    expect(_label(tester), EditorStrings.rotationLabel(45));
    expect(_selection(h)!.isDragging, isTrue);
    // The preview frame turns with it (transformedCorners).
    expect(_quad(h).angle, closeTo(45 * _deg, 1e-9));
    await h.driver.up(1);
    await tester.pump();

    expect(_edits(h), ['execute:transform']);
    expect(h.session.history.undoDepth, 1);
    final a = _page(h).strokeById(strokeA.id)!;
    final expected = _turn(
      core.PagePoint(strokeA.points.x(0), strokeA.points.y(0)),
      centre,
      45 * _deg,
    );
    // CORE stores stroke points to 0.01 pt (float32).
    expect(a.points.x(0), closeTo(expected.x, 0.006));
    expect(a.points.y(0), closeTo(expected.y, 0.006));
    expect(_selection(h)!.elementIds, {strokeA.id, strokeB.id});
    expect(_selection(h)!.origin, SelectionOrigin.lasso);
    expect(_selection(h)!.isDragging, isFalse);
    expect(_label(tester), isNull); // the tag goes with the drag
    // Re-selected: an axis-aligned frame around the rotated strokes.
    expect(_quad(h).angle, 0);
  });

  testWidgets('20° is not near a 15° step → rotated by 20° (no snapping)', (
    tester,
  ) async {
    final h = await _pump(tester);
    _select(h, {strokeA.id, strokeB.id});
    await tester.pump();
    final centre = h.controllerOf(0).selection!.bounds.center;
    await _rotateBy(tester, h, 20);
    expect(_label(tester), EditorStrings.rotationLabel(20));
    await h.driver.up(1);
    await tester.pump();
    expect(_edits(h), ['execute:transform']);
    final b = _page(h).strokeById(strokeB.id)!;
    final expected = _turn(
      core.PagePoint(strokeB.points.x(19), strokeB.points.y(19)),
      centre,
      20 * _deg,
    );
    // 0.01 pt points, and an unsnapped angle carries the pointer's rounding.
    expect(b.points.x(19), closeTo(expected.x, 1e-2));
    expect(b.points.y(19), closeTo(expected.y, 1e-2));
  });

  testWidgets('a single image turned 10°: its frame (and handles) turn with '
      'it; dragged +22° → 32° → snapped to the absolute 30° about its frame '
      'centre, the tag shows 30°', (tester) async {
    final h = await _pump(tester);
    _select(h, {_image.id}, origin: SelectionOrigin.tap);
    await tester.pump();

    // The frame = the image's rotated frame corners on screen.
    final quad = _quad(h);
    final corners = _image.frame.corners;
    for (var i = 0; i < 4; i++) {
      final p = h.toGlobal(0, Offset(corners[i].x, corners[i].y));
      expect(quad.corners[i].dx, closeTo(p.dx, 1e-9));
      expect(quad.corners[i].dy, closeTo(p.dy, 1e-9));
    }
    expect(quad.angle, closeTo(10 * _deg, 1e-9));

    await _rotateBy(tester, h, 22);
    expect(_label(tester), EditorStrings.rotationLabel(30));
    await h.driver.up(1);
    await tester.pump();

    expect(_edits(h), ['execute:transform']);
    expect(h.session.history.undoDepth, 1);
    final image = _page(h).objectById(_image.id)!;
    expect(image.frame.rotation, closeTo(30 * _deg, 1e-9));
    expect(image.frame.center.x, closeTo(_image.frame.center.x, 1e-9));
    expect(image.frame.center.y, closeTo(_image.frame.center.y, 1e-9));
    expect(image.frame.rect.right - image.frame.rect.left, closeTo(150, 1e-9));
    // Same id, origin kept, the frame now at 30°.
    expect(_selection(h)!.elementIds, {_image.id});
    expect(_selection(h)!.origin, SelectionOrigin.tap);
    expect(_quad(h).angle, closeTo(30 * _deg, 1e-9));
  });

  testWidgets('a polyline shape rotates by the relative angle (its frame has '
      'no rotation): 47° → 45° about the bounds centre, the tag shows the '
      'relative 45°', (tester) async {
    final h = await _pump(tester);
    _select(h, {_rectangle.id});
    await tester.pump();
    final centre = h.controllerOf(0).selection!.bounds.center;
    expect(_quad(h).angle, 0);

    await _rotateBy(tester, h, 47);
    expect(_label(tester), EditorStrings.rotationLabel(45));
    await h.driver.up(1);
    await tester.pump();

    expect(_edits(h), ['execute:transform']);
    final shape = _page(h).objectById(_rectangle.id)! as core.ShapeObject;
    final points = (shape.geometry as core.PolylineGeometry).points;
    final before = (_rectangle.geometry as core.PolylineGeometry).points;
    for (var i = 0; i < before.length; i++) {
      final expected = _turn(before[i], centre, 45 * _deg);
      expect(points[i].x, closeTo(expected.x, 1e-6));
      expect(points[i].y, closeTo(expected.y, 1e-6));
    }
    // A polyline's frame is the points' box again (rotation 0).
    expect(shape.frame.rotation, 0);
    expect(_quad(h).angle, 0);
  });

  testWidgets('90° rotate: one TransformElements step, no preview, the same '
      'ids selected with their origin', (tester) async {
    final h = await _pump(tester);
    _select(h, {strokeA.id, _image.id}, origin: SelectionOrigin.paste);
    await tester.pump();
    final sel = h.controllerOf(0).selection!;
    final centre = sel.bounds.center;

    h.container.read(editorCommandsProvider).rotateSelection90();
    await tester.pump();

    expect(_edits(h), ['execute:transform']);
    expect(h.session.history.undoDepth, 1);
    final a = _page(h).strokeById(strokeA.id)!;
    final expected = _turn(
      core.PagePoint(strokeA.points.x(0), strokeA.points.y(0)),
      centre,
      math.pi / 2,
    );
    expect(a.points.x(0), closeTo(expected.x, 0.006)); // 0.01 pt points
    expect(a.points.y(0), closeTo(expected.y, 0.006));
    final image = _page(h).objectById(_image.id)!;
    expect(image.frame.rotation, closeTo(100 * _deg, 1e-9));
    expect(_selection(h)!.elementIds, {strokeA.id, _image.id});
    expect(_selection(h)!.origin, SelectionOrigin.paste);

    // Unknown objects only: nothing to rotate, no command.
    _select(h, {_unknown.id});
    await tester.pump();
    h.container.read(editorCommandsProvider).rotateSelection90();
    await tester.pump();
    expect(_edits(h), ['execute:transform']);
    expect(h.controllerOf(0).selection!.previewTransform.isIdentity, isTrue);
  });

  testWidgets('a rejected rotation: discardEdit (old place), the selection '
      'stays, no undo step', (tester) async {
    final h = await _pump(tester);
    _select(h, {strokeA.id, strokeB.id});
    await tester.pump();
    final bounds = h.controllerOf(0).selection!.bounds;
    h.recorder!.rejectNext(const core.ReadOnlyNoteException('race'));

    await _rotateBy(tester, h, 47);
    await h.driver.up(1);
    await tester.pump();

    expect(_edits(h), ['execute:transform:rejected']);
    final controller = h.controllerOf(0);
    expect(controller.pendingIds, isEmpty);
    final sel = controller.selection!;
    expect(sel.previewTransform.isIdentity, isTrue);
    expect(sel.previewBounds, bounds);
    expect(_page(h).strokeById(strokeA.id)!.points.x(0), strokeA.points.x(0));
    expect(h.session.history.undoDepth, 0);
    expect(_selection(h)!.elementIds, {strokeA.id, strokeB.id});
    expect(_selection(h)!.isDragging, isFalse);
    expect(_label(tester), isNull);
    expect(find.text(EditorStrings.readOnlyToast), findsOneWidget);

    // 90° rotate rejected the same way.
    h.recorder!.rejectNext(const core.ReadOnlyNoteException('race'));
    h.container.read(editorCommandsProvider).rotateSelection90();
    await tester.pump();
    expect(_edits(h).last, 'execute:transform:rejected');
    expect(controller.selection!.previewTransform.isIdentity, isTrue);
    expect(_selection(h)!.elementIds, {strokeA.id, strokeB.id});
    expect(h.session.history.undoDepth, 0);
    await tester.pump(const Duration(seconds: 5)); // snackbar timer
  });

  testWidgets('a single turned image: its corner drag scales about the '
      'rotated opposite corner (ObjectResize.cornerScale) — rotation and '
      'ratio kept', (tester) async {
    final h = await _pump(tester);
    _select(h, {_image.id});
    await tester.pump();
    final quad = _quad(h);
    final br = quad.handlePosition(ink.SelectionHandle.bottomRight);
    final tl = quad.handlePosition(ink.SelectionHandle.topLeft);
    final out = (br - tl) / (br - tl).distance * 60; // along the diagonal
    await h.driver.stylusStroke([br, br + out * 0.5, br + out]);
    await tester.pump();

    expect(_edits(h), ['execute:transform']);
    final image = _page(h).objectById(_image.id)!;
    expect(image.frame.rotation, closeTo(10 * _deg, 1e-9));
    final w = image.frame.rect.right - image.frame.rect.left;
    final hgt = image.frame.rect.bottom - image.frame.rect.top;
    expect(w / hgt, closeTo(150 / 110, 1e-9));
    expect(w, greaterThan(150));
    // The rotated top-left corner stayed put.
    final o = _image.frame.corners[0], o2 = image.frame.corners[0];
    expect(o2.x, closeTo(o.x, 1e-6));
    expect(o2.y, closeTo(o.y, 1e-6));
  });

  testWidgets('an unknown object: its frame without handles, a body drag '
      'moves nothing and sends no command', (tester) async {
    final h = await _pump(tester);
    _select(h, {_unknown.id});
    await tester.pump();
    final frame = selectionFrameOnScreen(
      h.viewport,
      h.mountedPages,
      _selection(h),
    )!;
    expect(frame.handles, isEmpty);
    expect(frame.rotatable, isFalse);
    expect(find.byKey(SelectionFrame.rotateHandleKey), findsNothing);

    final c = _quad(h).center;
    await h.driver.stylusStroke([
      c,
      c + const Offset(20, 0),
      c + const Offset(40, 10),
    ]);
    await tester.pump();
    expect(_edits(h), isEmpty);
    expect(h.controllerOf(0).selection!.previewTransform.isIdentity, isTrue);
    expect(_page(h).objectById(_unknown.id)!.frame, _unknown.frame);
    expect(_selection(h)!.elementIds, {_unknown.id});
  });
}
