// E-13: the toolbar (04-editor 6.9.1, 6.9.2): tool switching, the active pen
// / eraser tapped again → settings popup, long press → quick / eraser popup,
// the barrier closes and consumes, Esc closes, the finger toggle, the zoom
// chip, the title below 700 px and the more menu items.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/eraser/eraser_popup.dart';
import 'package:feature_editor/src/ui/pen/pen_settings_popup.dart';
import 'package:feature_editor/src/ui/pen/quick_pen_popup.dart';
import 'package:feature_editor/src/ui/popup_host.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/more_menu.dart';
import 'package:feature_editor/src/ui/toolbar/note_info_dialog.dart';
import 'package:feature_editor/src/ui/toolbar/zoom_chip.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

EditorTool _active(EditorTestHandles h) =>
    h.container.read(editorToolProvider).activeTool;

EditorPopup? _popup(EditorTestHandles h) =>
    h.container.read(editorPopupProvider);

/// Lets a camera animation (250 ms) run to its end.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openMore(WidgetTester tester) async {
  await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tapping an inactive tool selects it', (tester) async {
    final h = await pumpEditor(tester);
    expect(_active(h), EditorTool.pen);
    await tester.tap(find.byKey(EditorToolbar.eraserKey));
    await tester.pump();
    expect(_active(h), EditorTool.eraser);
    await tester.tap(find.byKey(EditorToolbar.lassoKey));
    await tester.pump();
    expect(_active(h), EditorTool.lasso);
    await tester.tap(find.byKey(EditorToolbar.penKey));
    await tester.pump();
    expect(_active(h), EditorTool.pen);
    expect(_popup(h), isNull);
    expect(find.bySemanticsLabel(RegExp('^${EditorStrings.pen} ')), findsOne);
    expect(find.bySemanticsLabel(EditorStrings.eraser), findsOneWidget);
    expect(find.bySemanticsLabel(EditorStrings.lasso), findsOneWidget);
  });

  testWidgets('the active pen tapped again → pen settings popup; the barrier '
      'closes it and the touch draws nothing', (tester) async {
    final h = await pumpEditor(tester);
    await tester.tap(find.byKey(EditorToolbar.penKey));
    await tester.pump();
    expect(_popup(h), const PenSettingsPopup());
    expect(find.byKey(PenSettingsPanel.panelKey), findsOneWidget);
    // Below the pen button.
    final button = tester.getRect(find.byKey(EditorToolbar.penKey));
    final panel = tester.getRect(find.byKey(PenSettingsPanel.panelKey));
    expect(panel.top, greaterThanOrEqualTo(button.bottom));
    expect(panel.left, closeTo(button.left, 1));

    await h.driver.stylusStroke(
      pathThrough(h, 0, const [Offset(100, 300), Offset(200, 320)]),
    );
    await tester.pump();
    expect(_popup(h), isNull);
    expect(find.byKey(PenSettingsPanel.panelKey), findsNothing);
    expect(h.recorder!.calls.where((c) => c.startsWith('execute')), isEmpty);
  });

  testWidgets('long press on the pen → quick popup, active or not; Esc closes '
      'it', (tester) async {
    final h = await pumpEditor(tester);
    await tester.tap(find.byKey(EditorToolbar.lassoKey));
    await tester.pump();
    await tester.longPress(find.byKey(EditorToolbar.penKey));
    await tester.pump();
    expect(_popup(h), const QuickPenPopup());
    expect(find.byKey(QuickPenPanel.panelKey), findsOneWidget);
    expect(_active(h), EditorTool.lasso);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(_popup(h), isNull);
    expect(find.byKey(QuickPenPanel.panelKey), findsNothing);
  });

  testWidgets('eraser: active + tap → eraser popup, long press → eraser '
      'popup; one-finger tap on the canvas closes', (tester) async {
    final h = await pumpEditor(tester);
    await tester.longPress(find.byKey(EditorToolbar.eraserKey));
    await tester.pump();
    expect(_popup(h), const EraserSettingsPopup());
    expect(find.byKey(EraserSettingsPanel.panelKey), findsOneWidget);
    h.container.read(editorPopupProvider.notifier).close();
    await tester.pump();

    await tester.tap(find.byKey(EditorToolbar.eraserKey));
    await tester.pump();
    expect(_popup(h), isNull);
    await tester.tap(find.byKey(EditorToolbar.eraserKey));
    await tester.pump();
    expect(_popup(h), const EraserSettingsPopup());

    // The router's one-finger tap closes a popup as well (6.6.2).
    h.container.read(editorInteractionHostProvider).tapGesture(1, Offset.zero);
    await tester.pump();
    expect(_popup(h), isNull);
    expect(find.byKey(PopupHost.barrierKey), findsNothing);
  });

  testWidgets('[✋] toggles finger drawing (penOnly ↔ fingerDrawing)', (
    tester,
  ) async {
    final h = await pumpEditor(tester);
    InputMode mode() => h.container.read(editorSettingsProvider).inputMode;
    expect(mode(), InputMode.auto);
    expect(find.bySemanticsLabel(EditorStrings.fingerDrawingOn), findsOne);

    await tester.tap(find.byKey(EditorToolbar.fingerKey));
    await tester.pump();
    expect(mode(), InputMode.penOnly);
    expect(find.bySemanticsLabel(EditorStrings.fingerDrawingOff), findsOne);

    await tester.tap(find.byKey(EditorToolbar.fingerKey));
    await tester.pump();
    expect(mode(), InputMode.fingerDrawing);
    expect(find.bySemanticsLabel(EditorStrings.fingerDrawingOn), findsOne);
    await tester.pump(const Duration(seconds: 1)); // debounced write
  });

  testWidgets('the zoom chip shows the zoom; tap → fit width', (tester) async {
    final h = await pumpEditor(tester);
    expect(find.text('100%'), findsOneWidget);
    h.container.read(editorCommandsProvider).zoomIn();
    await _frames(tester);
    expect(find.text(ZoomChip.labelFor(1.25)), findsOneWidget);

    await tester.tap(find.byKey(ZoomChip.chipKey));
    await _frames(tester);
    expect(h.viewport.zoom, closeTo(1, 1e-9));
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('the title is hidden below 700 px', (tester) async {
    await pumpEditor(tester, title: '긴 제목', logicalSize: const Size(690, 900));
    expect(find.byKey(EditorToolbar.titleKey), findsNothing);
    expect(find.text('긴 제목'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("more menu: '설정' only with onOpenSettings", (tester) async {
    var opened = 0;
    await pumpEditor(tester, onOpenSettings: () => opened++);
    await _openMore(tester);
    await tester.tap(find.byKey(EditorMoreMenu.settingsKey));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('more menu: page flip, developer overlay, note info, clear '
      'page', (tester) async {
    final h = await pumpEditor(
      tester,
      title: '정보 노트',
      strokesByPageIndex: {
        0: [strokeA, strokeB],
      },
    );
    expect(find.byKey(EditorMoreMenu.settingsKey), findsNothing);

    await _openMore(tester);
    expect(find.byKey(EditorMoreMenu.settingsKey), findsNothing);
    await tester.tap(find.byKey(EditorMoreMenu.pageFlipKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(EditorMoreMenu.horizontalKey));
    await tester.pumpAndSettle();
    expect(
      h.container.read(editorSettingsProvider).pageFlipMode,
      PageFlipMode.horizontalPaged,
    );
    h.container
        .read(editorCommandsProvider)
        .setPageFlipMode(PageFlipMode.verticalScroll);
    await tester.pump();

    await _openMore(tester);
    await tester.tap(find.byKey(EditorMoreMenu.devOverlayKey));
    await tester.pumpAndSettle();
    expect(h.container.read(editorSettingsProvider).showDevOverlay, isTrue);

    await _openMore(tester);
    await tester.tap(find.byKey(EditorMoreMenu.noteInfoKey));
    await tester.pumpAndSettle();
    expect(find.byKey(NoteInfoDialog.dialogKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(NoteInfoDialog.dialogKey),
        matching: find.text('정보 노트'),
      ),
      findsOneWidget,
    );
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text(EditorStrings.close));
    await tester.pumpAndSettle();

    await _openMore(tester);
    await tester.tap(find.byKey(EditorMoreMenu.clearPageKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ClearPageDialog.confirmKey));
    await tester.pumpAndSettle();
    expect(h.recorder!.countOf('executeAsync:clear-page'), 1);
    expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, isEmpty);
    await tester.pump(const Duration(seconds: 1)); // debounced writes
  });

  test('formatLocalDateTime is yyyy-MM-dd HH:mm in local time', () {
    final at = DateTime(2026, 3, 7, 9, 5).millisecondsSinceEpoch;
    expect(formatLocalDateTime(at), '2026-03-07 09:05');
  });
}
