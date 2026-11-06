// m5-7/04-editor 8.2 E2-22, 6.6.4 / 6.6.5: a single object's handles as
// EDITOR draws them (the 6.6.4 table) — a rectangle (a polyline shape: 4
// corners + 4 edges + the rotate handle = 9), an ellipse turned 30° (its own
// rotated frame, the handles with it), a text box (4 corners + its left /
// right width handles), an image whose aspect is unlocked (4 corners + 4
// edges), a pentagon in vertex mode (a handle on each of its 5 points, no
// box handles, no rotate handle) and a line (its 2 end points, no box).
// Only the frame's own layer is captured (SelectionFrame's RepaintBoundary)
// — INK's output (fixed to a flat page) is not in the images. Same frame as
// selection_frame_v2_golden_test.dart (E2-06).
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

const double _deg = math.pi / 180;

/// INK output fixed to one flat colour (9.1 golden rule).
final _flatPages = ink.pageBackgroundBuildersProvider.overrideWithValue(const [
  ink_testing.SolidBackgroundBuilder(
    kind: ink.InkBackgroundKind.blank,
    colorArgb: 0xFFFFFFFF,
  ),
]);

final core.ShapeObject _rectangle = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'rect-1',
  rect: const core.PageRect(100, 120, 260, 220),
  createdAt: 5,
);

final core.ShapeObject _ellipse =
    PageObjectFixtures.shape(
      pageId: 'x',
      id: 'ellipse-1',
      kind: core.ShapeKind.ellipse,
      createdAt: 6,
    ).copyWith(
      geometry: const core.EllipseGeometry(
        core.ElementFrame(
          core.PageRect(320, 120, 480, 200),
          rotation: 30 * _deg,
        ),
      ),
    );

final core.TextBoxObject _text = PageObjectFixtures.textBox(
  pageId: 'x',
  id: 'text-1',
  text: 'hello',
  rect: const core.PageRect(100, 300, 300, 340),
  createdAt: 7,
);

final core.ImageObject _image = PageObjectFixtures.image(
  pageId: 'x',
  id: 'image-1',
  assetId: 'missing-asset',
  rect: const core.PageRect(340, 280, 500, 380),
  createdAt: 8,
);

final core.ShapeObject _pentagon = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'polygon-1',
  kind: core.ShapeKind.polygon, // a pentagon
  rect: const core.PageRect(100, 440, 280, 600),
  createdAt: 9,
);

final core.ShapeObject _line = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'line-1',
  kind: core.ShapeKind.line,
  rect: const core.PageRect(340, 460, 500, 560),
  createdAt: 10,
);

/// The selection frame layer (transparent outside the frame).
Finder get _frameLayer => find.descendant(
  of: find.byType(SelectionFrame),
  matching: find.byType(RepaintBoundary),
);

/// Opens a note with the six objects on page 0 (lasso tool active) and
/// selects [id] alone (the notifier directly, as a tap selection does).
Future<EditorTestHandles> _selected(
  WidgetTester tester,
  String id, {
  bool vertexMode = false,
  bool aspectUnlocked = false,
}) async {
  final h = await pumpEditor(
    tester,
    objectsByPageIndex: {
      0: [_rectangle, _ellipse, _text, _image, _pentagon, _line],
    },
    overrides: [_flatPages],
  );
  h.container.read(editorCommandsProvider).selectTool(EditorTool.lasso);
  await tester.pump();
  h.container
      .read(editorSelectionProvider.notifier)
      .select(
        h.pageId(0),
        {id},
        origin: SelectionOrigin.tap,
        vertexMode: vertexMode,
        aspectUnlocked: aspectUnlocked,
      );
  await tester.pump();
  final selection = h.container.read(editorSelectionProvider)!;
  expect(selection.elementIds, {id});
  expect(selection.vertexMode, vertexMode);
  expect(selection.aspectUnlocked, aspectUnlocked);
  return h;
}

/// The frame EDITOR draws for the current selection (what the image shows).
SelectionFrameShape _frame(EditorTestHandles h) => selectionFrameOnScreen(
  h.viewport,
  h.mountedPages,
  h.container.read(editorSelectionProvider),
)!;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ink_testing.useInkTestFonts();
  });

  testWidgets('a rectangle: 4 corners + 4 edges + the rotate handle (9)', (
    tester,
  ) async {
    final h = await _selected(tester, _rectangle.id);
    final f = _frame(h);
    expect(f.handles, hasLength(8));
    expect(f.rotatable, isTrue);
    expect(f.handleCount, 9);
    await expectLater(
      _frameLayer,
      matchesGoldenFile('object_handles_rectangle.png'),
    );
  });

  testWidgets('an ellipse turned 30°: its rotated frame, the 8 handles and '
      'the rotate handle turned with it', (tester) async {
    final h = await _selected(tester, _ellipse.id);
    final f = _frame(h);
    expect(f.handles, hasLength(8));
    expect(f.rotatable, isTrue);
    await expectLater(
      _frameLayer,
      matchesGoldenFile('object_handles_ellipse_rotated.png'),
    );
  });

  testWidgets('a text box: 4 corners + the left / right width handles', (
    tester,
  ) async {
    final h = await _selected(tester, _text.id);
    final f = _frame(h);
    expect(f.handles, hasLength(6));
    expect(f.rotatable, isTrue);
    await expectLater(
      _frameLayer,
      matchesGoldenFile('object_handles_text_width.png'),
    );
  });

  testWidgets('an image, aspect unlocked: 4 corners + 4 edges', (tester) async {
    final h = await _selected(tester, _image.id, aspectUnlocked: true);
    final f = _frame(h);
    expect(f.handles, hasLength(8));
    await expectLater(
      _frameLayer,
      matchesGoldenFile('object_handles_image_unlocked.png'),
    );
  });

  testWidgets('a pentagon in vertex mode: a handle on each of its 5 points, '
      'no box handles, no rotate handle', (tester) async {
    final h = await _selected(tester, _pentagon.id, vertexMode: true);
    final f = _frame(h);
    expect(f.handles, isEmpty);
    expect(f.vertices, hasLength(5));
    expect(f.rotatable, isFalse);
    expect(f.boxed, isTrue);
    await expectLater(
      _frameLayer,
      matchesGoldenFile('object_handles_vertex_mode.png'),
    );
  });

  testWidgets('a line: its 2 end points, no box, no rotate handle', (
    tester,
  ) async {
    final h = await _selected(tester, _line.id);
    final f = _frame(h);
    expect(f.handles, isEmpty);
    expect(f.vertices, hasLength(2));
    expect(f.rotatable, isFalse);
    expect(f.boxed, isFalse);
    await expectLater(
      _frameLayer,
      matchesGoldenFile('object_handles_line_endpoints.png'),
    );
  });
}
