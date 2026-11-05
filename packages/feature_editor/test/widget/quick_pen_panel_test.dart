// E-15: the quick pen popup (04-editor 6.9.1 long press on the pen, 6.9.3
// '빠른 팝업'): 300 wide; width row + the same PenPreviewPainter call, opacity,
// the 12 recent colours and the first 16 palette colours (tap only).
import 'package:feature_editor/src/state/color_palette.dart';
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/color/opacity_slider.dart';
import 'package:feature_editor/src/ui/color/recent_colors_row.dart';
import 'package:feature_editor/src/ui/color/user_palette_grid.dart';
import 'package:feature_editor/src/ui/pen/pen_preview.dart';
import 'package:feature_editor/src/ui/pen/quick_pen_popup.dart';
import 'package:feature_editor/src/ui/pen/width_slider.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';

core.StrokeStyle _pen(EditorTestHandles h) =>
    h.container.read(editorToolProvider).currentPen;

Future<EditorTestHandles> _open(WidgetTester tester) async {
  final h = await pumpEditor(tester);
  await tester.tap(find.byKey(EditorToolbar.lassoKey)); // pen not active
  await tester.pump();
  await tester.longPress(find.byKey(EditorToolbar.penKey));
  await tester.pump();
  expect(h.container.read(editorPopupProvider), const QuickPenPopup());
  expect(find.byKey(QuickPenPanel.panelKey), findsOneWidget);
  return h;
}

void main() {
  testWidgets('300 wide; width [+] and the slider edit the current pen', (
    tester,
  ) async {
    final h = await _open(tester);
    expect(tester.getSize(find.byKey(QuickPenPanel.panelKey)).width, 300);
    await tester.tap(find.byKey(WidthSlider.plusKey));
    await tester.pump();
    expect(_pen(h).width, 1.7);
    tester.widget<Slider>(find.byKey(WidthSlider.sliderKey)).onChanged!(0.2);
    await tester.pump();
    expect(_pen(h).width, 1.3);
    // Editing does not switch the tool (the lasso stays active).
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.lasso);
  });

  testWidgets('preview: the same ink.PenPreviewPainter call (style, grain)', (
    tester,
  ) async {
    final h = await _open(tester);
    final painter =
        tester.widget<CustomPaint>(find.byKey(PenPreview.paintKey)).painter!
            as ink.PenPreviewPainter;
    expect(painter.style, _pen(h));
    expect(
      identical(painter.pencilGrain, h.container.read(ink.pencilGrainProvider)),
      isTrue,
    );
    // Fits the 268 px inner width.
    expect(
      tester.getSize(
        find
            .ancestor(
              of: find.byKey(PenPreview.paintKey),
              matching: find.byType(Container),
            )
            .first,
      ),
      const Size(268, 56),
    );
  });

  testWidgets('opacity, recent colours and the first 16 palette colours; '
      'no [+] and no delete here', (tester) async {
    final h = await pumpEditor(tester);
    final palette = h.container.read(editorColorPaletteProvider.notifier);
    for (var i = 0; i < 20; i++) {
      palette.addToPalette(0xFF100000 + i);
    }
    palette.pushRecent(0xFF00AA00);
    await tester.longPress(find.byKey(EditorToolbar.penKey));
    await tester.pump();

    final opacity = find.byKey(OpacitySlider.sliderKey);
    await tester.ensureVisible(opacity);
    await tester.pump();
    await tester.tapAt(tester.getRect(opacity).centerLeft + const Offset(1, 0));
    await tester.pump();
    expect(_pen(h).opacity, core.StrokeStyle.minOpacity);

    final recent = find.byKey(RecentColorsRow.swatchKey(0));
    await tester.ensureVisible(recent);
    await tester.pump();
    await tester.tap(recent);
    await tester.pump();
    expect(_pen(h).colorArgb, 0xFF00AA00);

    final last = find.byKey(UserPaletteGrid.swatchKey(15));
    await tester.ensureVisible(last);
    await tester.pump();
    expect(find.byKey(UserPaletteGrid.swatchKey(16)), findsNothing);
    expect(find.byKey(UserPaletteGrid.addKey), findsNothing);
    await tester.tap(last);
    await tester.pump();
    expect(_pen(h).colorArgb, 0xFF10000F);

    await tester.longPress(last);
    await tester.pumpAndSettle();
    expect(find.byKey(UserPaletteGrid.deleteKey), findsNothing);
    expect(h.container.read(editorColorPaletteProvider).palette, hasLength(20));
  });
}
