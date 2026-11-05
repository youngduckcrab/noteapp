// E-22: the selection frame as EDITOR draws it (04-editor 6.6.5): a dashed
// 1 px rectangle around INK's selection bounds and the four 12 px corner
// handles, in viewport coordinates. Only the frame's own layer is captured
// (SelectionFrame's RepaintBoundary) — INK's strokes and page background are
// not in the image (9.1: EDITOR output only, no text).
@Tags(['golden'])
@TestOn('vm')
library;

import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/overlays/selection_frame_painter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:material_ui/material_ui.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

/// INK output fixed to one flat colour (9.1 golden rule).
final _flatPages = ink.pageBackgroundBuildersProvider.overrideWithValue(const [
  ink_testing.SolidBackgroundBuilder(
    kind: ink.InkBackgroundKind.blank,
    colorArgb: 0xFFFFFFFF,
  ),
]);

/// The selection frame layer (transparent outside the frame).
Finder get _frameLayer => find.descendant(
  of: find.byType(SelectionFrame),
  matching: find.byType(RepaintBoundary),
);

/// Opens a note with strokeA / strokeB on page 0 and selects [ids] with the
/// lasso tool active (no pointer input — the selection notifier directly).
Future<EditorTestHandles> _selected(
  WidgetTester tester,
  Set<String> ids,
) async {
  final h = await pumpEditor(
    tester,
    strokesByPageIndex: {
      0: [strokeA, strokeB],
    },
    overrides: [_flatPages],
  );
  h.container.read(editorCommandsProvider).selectTool(EditorTool.lasso);
  await tester.pump();
  h.container.read(editorSelectionProvider.notifier).select(h.pageId(0), ids);
  await tester.pump();
  expect(h.container.read(editorSelectionProvider)!.strokeIds, ids);
  return h;
}

void main() {
  testWidgets('two strokes selected at fit zoom', (tester) async {
    await _selected(tester, {strokeA.id, strokeB.id});
    await expectLater(_frameLayer, matchesGoldenFile('selection_frame.png'));
  });

  testWidgets('at 200 %: the frame grows, handles and dashes stay the same', (
    tester,
  ) async {
    final h = await _selected(tester, {strokeA.id, strokeB.id});
    final frame = h.viewport.pageToScreen(0, const Offset(180, 275));
    h.viewport
      ..zoomBy(2, frame)
      ..settleNow();
    await tester.pump();
    await tester.pump();
    expect(h.viewport.zoom, closeTo(2, 1e-9));
    await expectLater(
      _frameLayer,
      matchesGoldenFile('selection_frame_zoom_200.png'),
    );
  });
}
