// E-15: the quick pen popup (04-editor 6.9.1 long press on the pen, 6.9.3
// '빠른 팝업'). (v2.15-ui, 22.2) 400 wide: the pen's name and real stroke, 8
// colours, 5 real-width strokes, then 순서 바꾸기 / 펜 고르기 (and 트레이에서
// 빼기 for a tray pen — pen_tray_test).
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/color/basic_colors_row.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/pen/pen_art_view.dart';
import 'package:feature_editor/src/ui/pen/quick_pen_popup.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
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
  expect(h.container.read(editorPopupProvider), isA<QuickPenPopup>());
  expect(find.byKey(QuickPenPanel.panelKey), findsOneWidget);
  return h;
}

void main() {
  testWidgets('400 wide; the 8 colours and 5 widths edit the current pen', (
    tester,
  ) async {
    final h = await _open(tester);
    expect(
      tester.getSize(find.byKey(QuickPenPanel.panelKey)).width,
      QuickPenPanel.width,
    );
    expect(find.text(EditorStrings.penTypeName(_pen(h).tool)), findsWidgets);
    for (var i = 0; i < QuickPenPanel.colorsShown; i++) {
      expect(find.byKey(QuickPenPanel.colorKey(i)), findsOneWidget);
    }
    // One row of colours.
    expect(
      tester.getCenter(find.byKey(QuickPenPanel.colorKey(7))).dy,
      tester.getCenter(find.byKey(QuickPenPanel.colorKey(0))).dy,
    );
    await tester.tap(find.byKey(QuickPenPanel.colorKey(3)));
    await tester.pump();
    expect(_pen(h).colorArgb, kBasicColors[3]);
    final widths = penWidthChoices(_pen(h).tool);
    expect(widths, hasLength(5));
    await tester.tap(find.byKey(QuickPenPanel.widthKey(0)));
    await tester.pump();
    expect(_pen(h).width, widths[0]);
    // The pen tool stays as it was (the lasso).
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.lasso);
  });

  testWidgets('the strokes are the real INK preview of the pen', (
    tester,
  ) async {
    final h = await _open(tester);
    final strokes = tester.widgetList<InkStroke>(
      find.descendant(
        of: find.byKey(QuickPenPanel.panelKey),
        matching: find.byType(InkStroke),
      ),
    );
    expect(strokes.length, 6); // the header stroke + the 5 widths
    expect(strokes.first.style, _pen(h));
    expect(strokes.first.shape, ink.PenPreviewShape.line);
  });

  testWidgets('순서 바꾸기 → the preset manager; 펜 고르기 → the picker', (
    tester,
  ) async {
    final h = await _open(tester);
    expect(find.byKey(QuickPenPanel.unpinKey), findsOneWidget);
    await tester.tap(find.byKey(QuickPenPanel.reorderKey));
    await tester.pump();
    expect(h.container.read(editorPopupProvider), const PresetManagerPopup());
    h.container.read(editorPopupProvider.notifier).open(const QuickPenPopup());
    await tester.pump();
    expect(find.byKey(QuickPenPanel.unpinKey), findsNothing);
    await tester.tap(find.byKey(QuickPenPanel.pickerKey));
    await tester.pump();
    expect(h.container.read(editorPopupProvider), const PenSettingsPopup());
  });
}
