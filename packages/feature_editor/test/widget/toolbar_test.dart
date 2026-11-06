// E-13: the toolbar (04-editor 6.9.1, 6.9.2): tool switching, the active pen
// / eraser tapped again → settings popup, long press → quick / eraser popup,
// the barrier closes and consumes, Esc closes, the finger toggle, the zoom
// chip, the title below 700 px and the more menu items.
// (v2, E2-13 — m5-7/04-editor 6.13.1) toolbar v2: the button order
// [▤] │ pen eraser lasso shape text │ [+] [🎤] │ [↶] [↷] │ [✋] [100%] [⋯],
// the shape / text buttons (active again or long press → their tool popup
// under the button), the title from 1000 px, [⋯도구] below the fold width
// (shape, text, the [+] rows started inside the press, 녹음), no overflow on
// iPad 13" portrait / landscape, the sideways scroll on a very narrow
// toolbar.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/panel.dart';
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/eraser/eraser_popup.dart';
import 'package:feature_editor/src/ui/pen/pen_settings_popup.dart';
import 'package:feature_editor/src/ui/pen/quick_pen_popup.dart';
import 'package:feature_editor/src/ui/popup_host.dart';
import 'package:feature_editor/src/ui/shape/shape_style_controls.dart';
import 'package:feature_editor/src/ui/text/text_style_controls.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/insert_menu.dart';
import 'package:feature_editor/src/ui/toolbar/mic_button.dart';
import 'package:feature_editor/src/ui/toolbar/more_menu.dart';
import 'package:feature_editor/src/ui/toolbar/note_info_dialog.dart';
import 'package:feature_editor/src/ui/toolbar/overflow_tools_menu.dart';
import 'package:feature_editor/src/ui/toolbar/tool_button.dart';
import 'package:feature_editor/src/ui/toolbar/undo_redo_buttons.dart';
import 'package:feature_editor/src/ui/toolbar/zoom_chip.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/fake_extensions.dart';
import '../helpers/fake_image_importer.dart';
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

  // (v2, 6.13.1) 1st round 700 → 1000.
  for (final (width, shown) in const [(999.0, false), (1000.0, true)]) {
    testWidgets('(v2) the title shows from 1000 px: $width → $shown', (
      tester,
    ) async {
      await pumpEditor(tester, title: '긴 제목', logicalSize: Size(width, 1000));
      expect(
        find.byKey(EditorToolbar.titleKey),
        shown ? findsOne : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

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

  group('(v2) toolbar v2', () {
    Future<EditorTestHandles> pumpV2(
      WidgetTester tester, {
      Size size = const Size(1032, 1376),
      List<EditorInsertMenuItem> items = const [],
      bool image = true,
      bool panel = true,
      bool fakeAudio = false,
    }) => pumpEditor(
      tester,
      logicalSize: size,
      fakeAudio: fakeAudio,
      imageImporter: image ? (s) => FakeImageImporter(store: s) : null,
      extensions: EditorExtensions(
        insertMenuItems: items,
        recordingPanel: panel ? TestRecordingPanelBuilder().builder : null,
      ),
    );

    double centreX(WidgetTester tester, Key key) =>
        tester.getCenter(find.byKey(key)).dx;

    for (final size in const [Size(1032, 1376), Size(1376, 1032)]) {
      testWidgets('order on ${size.width.toInt()}×${size.height.toInt()}: '
          '[▤] pen eraser lasso shape text [+] [🎤] [↶] [↷] [✋] [100%] [⋯]; '
          'no overflow', (tester) async {
        await pumpV2(tester, size: size);
        expect(tester.takeException(), isNull);
        final keys = <Key>[
          EditorToolbar.pagePanelKey,
          EditorToolbar.penKey,
          EditorToolbar.eraserKey,
          EditorToolbar.lassoKey,
          EditorToolbar.shapeKey,
          EditorToolbar.textKey,
          InsertMenu.buttonKey,
          MicButton.micKey,
          UndoRedoButtons.undoKey,
          UndoRedoButtons.redoKey,
          EditorToolbar.fingerKey,
          ZoomChip.chipKey,
          EditorMoreMenu.buttonKey,
        ];
        final xs = [for (final k in keys) centreX(tester, k)];
        for (var i = 1; i < xs.length; i++) {
          expect(xs[i], greaterThan(xs[i - 1]), reason: '${keys[i]}');
        }
        expect(find.byKey(EditorToolbar.overflowToolsKey), findsNothing);
        expect(find.byKey(EditorToolbar.titleKey), findsOneWidget);
        // Every button keeps a 48 px touch target.
        for (final k in keys.take(6)) {
          final r = tester.getRect(find.byKey(k));
          expect(r.width, greaterThanOrEqualTo(44), reason: '$k');
          expect(r.height, greaterThanOrEqualTo(44), reason: '$k');
        }
        expect(find.bySemanticsLabel(EditorStrings.shapeTool), findsOneWidget);
        expect(find.bySemanticsLabel(EditorStrings.textTool), findsOneWidget);
      });
    }

    testWidgets('shape: inactive → the shape tool; active again → the tool '
        'popup under the button; long press → the popup (tool kept)', (
      tester,
    ) async {
      final h = await pumpV2(tester);
      await tester.longPress(find.byKey(EditorToolbar.shapeKey));
      await tester.pump();
      expect(_active(h), EditorTool.pen);
      expect(_popup(h), const ShapeToolPopup(anchored: true));
      expect(find.byKey(ShapeToolPanel.panelKey), findsOneWidget);
      h.container.read(editorPopupProvider.notifier).close();
      await tester.pump();

      await tester.tap(find.byKey(EditorToolbar.shapeKey));
      await tester.pump();
      expect(_active(h), EditorTool.shape);
      expect(_popup(h), isNull);
      await tester.tap(find.byKey(EditorToolbar.shapeKey));
      await tester.pump();
      expect(_popup(h), const ShapeToolPopup(anchored: true));
      final button = tester.getRect(find.byKey(EditorToolbar.shapeKey));
      final panel = tester.getRect(find.byKey(ShapeToolPanel.panelKey));
      expect(panel.top, greaterThanOrEqualTo(button.bottom));
      expect(panel.left, closeTo(button.left, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('text: inactive → the text tool; active again → the text '
        'tool popup under the button; long press → the popup', (tester) async {
      final h = await pumpV2(tester);
      await tester.tap(find.byKey(EditorToolbar.textKey));
      await tester.pump();
      expect(_active(h), EditorTool.text);
      expect(_popup(h), isNull);
      await tester.tap(find.byKey(EditorToolbar.textKey));
      await tester.pump();
      expect(_popup(h), const TextToolPopup(anchored: true));
      final button = tester.getRect(find.byKey(EditorToolbar.textKey));
      final panel = tester.getRect(find.byKey(TextToolPanel.panelKey));
      expect(panel.top, greaterThanOrEqualTo(button.bottom));
      expect(panel.left, closeTo(button.left, 1));
      h.container.read(editorPopupProvider.notifier).close();
      await tester.pump();

      await tester.tap(find.byKey(EditorToolbar.penKey));
      await tester.pump();
      await tester.longPress(find.byKey(EditorToolbar.textKey));
      await tester.pump();
      expect(_active(h), EditorTool.pen);
      expect(_popup(h), const TextToolPopup(anchored: true));
    });

    testWidgets('a read-only note: shape and text disabled', (tester) async {
      final h = await pumpV2(tester);
      await h.store.library.trashItems([core.NoteRef(h.noteId)]);
      await tester.pump();
      expect(h.container.read(editorReadOnlyProvider), isTrue);
      await tester.tap(find.byKey(EditorToolbar.shapeKey));
      await tester.longPress(find.byKey(EditorToolbar.textKey));
      await tester.pump();
      expect(_active(h), EditorTool.pen);
      expect(_popup(h), isNull);
    });

    OverflowToolsMenuState overflow(WidgetTester tester) =>
        tester.state<OverflowToolsMenuState>(find.byType(OverflowToolsMenu));

    Future<void> openOverflow(WidgetTester tester) async {
      await tester.tap(find.byKey(EditorToolbar.overflowToolsKey));
      await tester.pump();
      expect(overflow(tester).isOpen, isTrue);
    }

    for (final width in const [819.0, 719.0, 690.0]) {
      testWidgets('$width px: shape, text, [+] and [🎤] fold into [⋯도구]; '
          'no overflow', (tester) async {
        await pumpV2(tester, size: Size(width, 1000));
        expect(tester.takeException(), isNull);
        expect(find.byKey(EditorToolbar.overflowToolsKey), findsOneWidget);
        for (final key in [
          EditorToolbar.shapeKey,
          EditorToolbar.textKey,
          InsertMenu.buttonKey,
          MicButton.micKey,
        ]) {
          expect(find.byKey(key), findsNothing, reason: '$key');
        }
        expect(find.bySemanticsLabel(EditorStrings.moreTools), findsOneWidget);
        // [⋯도구] sits between the lasso and the undo button.
        final x = centreX(tester, EditorToolbar.overflowToolsKey);
        expect(x, greaterThan(centreX(tester, EditorToolbar.lassoKey)));
        expect(x, lessThan(centreX(tester, UndoRedoButtons.undoKey)));
        await openOverflow(tester);
        for (final key in [
          EditorToolbar.shapeKey,
          EditorToolbar.textKey,
          InsertMenu.imageKey,
          MicButton.micKey,
        ]) {
          expect(find.byKey(key), findsOneWidget, reason: '$key');
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('820 px: not folded', (tester) async {
      await pumpV2(tester, size: const Size(820, 1000));
      expect(tester.takeException(), isNull);
      expect(find.byKey(EditorToolbar.overflowToolsKey), findsNothing);
      expect(find.byKey(EditorToolbar.shapeKey), findsOneWidget);
      expect(find.byKey(MicButton.micKey), findsOneWidget);
    });

    testWidgets('[⋯도구] shape / text: inactive → the tool (menu closes, the '
        'button shows it); active → its popup at the button', (tester) async {
      final h = await pumpV2(tester, size: const Size(700, 1000));
      await openOverflow(tester);
      await tester.tap(find.byKey(EditorToolbar.shapeKey));
      await tester.pump();
      expect(_active(h), EditorTool.shape);
      expect(overflow(tester).isOpen, isFalse);
      expect(_popup(h), isNull);
      final toolButton = find.descendant(
        of: find.byKey(EditorToolbar.overflowToolsKey),
        matching: find.byType(ToolButton),
      );
      expect(tester.widget<ToolButton>(toolButton).active, isTrue);
      expect(tester.widget<ToolButton>(toolButton).icon, Icons.interests);

      await openOverflow(tester);
      await tester.tap(find.byKey(EditorToolbar.shapeKey));
      await tester.pump();
      expect(overflow(tester).isOpen, isFalse);
      final popup = _popup(h)! as ShapeToolPopup;
      expect(popup.anchored, isFalse);
      final button = tester.getRect(find.byKey(EditorToolbar.overflowToolsKey));
      expect(popup.globalPosition, button.bottomLeft);
      expect(find.byKey(ShapeToolPanel.panelKey), findsOneWidget);
      final panel = tester.getRect(find.byKey(ShapeToolPanel.panelKey));
      expect(panel.top, greaterThanOrEqualTo(button.bottom));
      h.container.read(editorPopupProvider.notifier).close();
      await tester.pump();

      await openOverflow(tester);
      await tester.tap(find.byKey(EditorToolbar.textKey));
      await tester.pump();
      expect(_active(h), EditorTool.text);
      expect(tester.widget<ToolButton>(toolButton).icon, Icons.text_fields);
      await openOverflow(tester);
      await tester.tap(find.byKey(EditorToolbar.textKey));
      await tester.pump();
      expect(_popup(h), isA<TextToolPopup>());
      expect(find.byKey(TextToolPanel.panelKey), findsOneWidget);

      await tester.tap(find.byKey(EditorToolbar.penKey)); // barrier closes
      await tester.pump();
      await tester.tap(find.byKey(EditorToolbar.penKey));
      await tester.pump();
      expect(_active(h), EditorTool.pen);
      expect(tester.widget<ToolButton>(toolButton).active, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('[⋯도구] insert rows start inside the press (menu open), then '
        'the menu closes; the image submenu picks', (tester) async {
      final item = RecordingInsertItem(id: 'recog.mathPad', label: '수식');
      final h = await pumpV2(
        tester,
        size: const Size(700, 1000),
        items: [item.item],
      );
      await openOverflow(tester);
      bool? openAtRun;
      item.onRun = (_) => openAtRun = overflow(tester).isOpen;
      await tester.tap(find.byKey(InsertMenu.extensionKey('recog.mathPad')));
      expect(item.calls, hasLength(1));
      expect(openAtRun, isTrue);
      expect(overflow(tester).isOpen, isFalse);
      expect(item.calls.single.menu.pageId, h.pageId(0));
      await tester.pump();

      await openOverflow(tester);
      await tester.tap(find.byKey(InsertMenu.imageKey));
      await tester.pump();
      final importer = h.imageImporter!;
      bool? openAtPick;
      importer.onPick = (_) => openAtPick = overflow(tester).isOpen;
      await tester.tap(
        find.byKey(InsertMenu.imageSourceKey(core.ImageImportSource.photos)),
      );
      expect(
        [for (final c in importer.calls) c.source],
        [core.ImageImportSource.photos],
      );
      expect(openAtPick, isTrue);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(overflow(tester).isOpen, isFalse);
      expect(h.recorder!.calls, contains('executeAsync:add-objects'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('[⋯도구] on a read-only note: shape, text and insert rows '
        'disabled; 녹음 still works', (tester) async {
      final h = await pumpV2(tester, size: const Size(700, 1000));
      await h.store.library.trashItems([core.NoteRef(h.noteId)]);
      await tester.pump();
      await openOverflow(tester);
      VoidCallback? onPressed(Key key) => tester
          .widget<TextButton>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byWidgetPredicate((w) => w is TextButton),
            ),
          )
          .onPressed;
      expect(onPressed(EditorToolbar.shapeKey), isNull);
      expect(onPressed(EditorToolbar.textKey), isNull);
      await tester.tap(find.byKey(InsertMenu.imageKey));
      await tester.pump();
      expect(
        onPressed(InsertMenu.imageSourceKey(core.ImageImportSource.photos)),
        isNull,
      );
      expect(onPressed(MicButton.micKey), isNotNull);
    });

    testWidgets('[⋯도구] 녹음 opens / closes the panel; the button carries '
        'the recording dot', (tester) async {
      final h = await pumpV2(
        tester,
        size: const Size(700, 1000),
        fakeAudio: true,
      );
      final toolButton = find.descendant(
        of: find.byKey(EditorToolbar.overflowToolsKey),
        matching: find.byType(ToolButton),
      );
      expect(tester.widget<ToolButton>(toolButton).dotColor, isNull);
      await openOverflow(tester);
      await tester.tap(find.byKey(MicButton.micKey));
      await tester.pump();
      expect(h.container.read(editorPanelProvider), isTrue);
      expect(overflow(tester).isOpen, isFalse);
      expect(find.byKey(testPanelKey), findsOneWidget);

      await h.audioRecorder!.start(recordingId: 'rec-1', noteId: h.noteId);
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<ToolButton>(toolButton).dotColor,
        MicButton.recordingDotColor,
      );

      await openOverflow(tester);
      await tester.tap(find.byKey(MicButton.micKey));
      await tester.pump();
      expect(h.container.read(editorPanelProvider), isFalse);
      await h.audioRecorder!.cancel();
      await tester.pump();
      await tester.pump();
      expect(tester.widget<ToolButton>(toolButton).dotColor, isNull);
    });

    testWidgets('a very narrow toolbar scrolls sideways (no overflow)', (
      tester,
    ) async {
      await pumpV2(tester, size: const Size(420, 900));
      expect(tester.takeException(), isNull);
      expect(find.byKey(EditorToolbar.scrollKey), findsOneWidget);
      await tester.drag(
        find.byKey(EditorToolbar.scrollKey),
        const Offset(-400, 0),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
      await tester.pumpAndSettle();
      expect(find.byKey(EditorMoreMenu.clearPageKey), findsOneWidget);
    });
  });

  test('formatLocalDateTime is yyyy-MM-dd HH:mm in local time', () {
    final at = DateTime(2026, 3, 7, 9, 5).millisecondsSinceEpoch;
    expect(formatLocalDateTime(at), '2026-03-07 09:05');
  });
}
