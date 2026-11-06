// m5-7/04-editor 8.2 E2-06 (part 2), 6.6.4: the selection frame v2 as EDITOR
// draws it — several elements (an axis-aligned frame, 4 corners and the
// rotate handle joined to the top edge's middle), the same frame under a
// rotation preview (turned corners), a single rotated object's own frame and
// its rotate handle at 200 %. Only the frame's own layer is captured
// (SelectionFrame's RepaintBoundary) — INK's output (fixed to a flat page)
// and the angle tag (RotationLabel, another layer — 9.2) are not in the
// images.
@Tags(['golden'])
@TestOn('vm')
library;

import 'dart:math' as math;

import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/overlays/selection_frame_painter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

/// INK output fixed to one flat colour (9.1 golden rule).
final _flatPages = ink.pageBackgroundBuildersProvider.overrideWithValue(const [
  ink_testing.SolidBackgroundBuilder(
    kind: ink.InkBackgroundKind.blank,
    colorArgb: 0xFFFFFFFF,
  ),
]);

final core.ShapeObject _shape = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'shape-1',
  rect: const core.PageRect(300, 120, 420, 200),
  createdAt: 5,
);

final core.ImageObject _image =
    PageObjectFixtures.image(
      pageId: 'x',
      id: 'image-1',
      assetId: 'missing-asset',
      rect: const core.PageRect(300, 450, 450, 560),
      createdAt: 6,
    ).copyWith(
      frame: const core.ElementFrame(
        core.PageRect(300, 450, 450, 560),
        rotation: 20 * math.pi / 180,
      ),
    );

/// The selection frame layer (transparent outside the frame).
Finder get _frameLayer => find.descendant(
  of: find.byType(SelectionFrame),
  matching: find.byType(RepaintBoundary),
);

/// Opens a note with two strokes, a rectangle and a 20° image on page 0 and
/// selects [ids] with the lasso tool active (the notifier directly).
Future<EditorTestHandles> _selected(
  WidgetTester tester,
  Set<String> ids,
) async {
  final h = await pumpEditor(
    tester,
    strokesByPageIndex: {
      0: [strokeA, strokeB],
    },
    objectsByPageIndex: {
      0: [_shape, _image],
    },
    overrides: [_flatPages],
  );
  h.container.read(editorCommandsProvider).selectTool(EditorTool.lasso);
  await tester.pump();
  h.container.read(editorSelectionProvider.notifier).select(h.pageId(0), ids);
  await tester.pump();
  expect(h.container.read(editorSelectionProvider)!.elementIds, ids);
  return h;
}

void main() {
  testWidgets('several elements (strokes + a shape): the axis-aligned frame, '
      '4 corners and the rotate handle', (tester) async {
    await _selected(tester, {strokeA.id, strokeB.id, _shape.id});
    await expectLater(
      _frameLayer,
      matchesGoldenFile('selection_frame_v2_multi.png'),
    );
  });

  testWidgets('the same frame under a 30° rotation preview: a turned '
      'rectangle, the handles with it', (tester) async {
    final h = await _selected(tester, {strokeA.id, strokeB.id, _shape.id});
    final sel = h.controllerOf(0).selection!;
    sel.setPreviewTransform(
      ink.SelectionGeometry.rotate(bounds: sel.bounds, radians: math.pi / 6),
    );
    await tester.pump();
    await expectLater(
      _frameLayer,
      matchesGoldenFile('selection_frame_v2_rotating.png'),
    );
  });

  testWidgets('a single image turned 20°: its own rotated frame', (
    tester,
  ) async {
    await _selected(tester, {_image.id});
    await expectLater(
      _frameLayer,
      matchesGoldenFile('selection_frame_v2_single_rotated.png'),
    );
  });

  testWidgets('the rotate handle at 200 %: the same 12 px circle and '
      '28 px line, the frame grows', (tester) async {
    final h = await _selected(tester, {_image.id});
    final centre = h.viewport.pageToScreen(0, const Offset(375, 505));
    h.viewport
      ..zoomBy(2, centre)
      ..settleNow();
    await tester.pump();
    await tester.pump();
    expect(h.viewport.zoom, closeTo(2, 1e-9));
    await expectLater(
      _frameLayer,
      matchesGoldenFile('selection_frame_v2_rotate_handle_200.png'),
    );
  });
}
