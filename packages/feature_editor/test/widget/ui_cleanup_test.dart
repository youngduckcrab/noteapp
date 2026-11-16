// (v2.14-ui, UI stage 1 — m5-7/04-editor 'UI 정리 1단계') The editor's
// removed / merged / moved controls: one tape item in ⋯, only when the note
// has a tape; the page panel's '전체 N쪽' and its 페이지 넘김 row; the restore
// pill's [↶][↷] │ [🔍] │ [⌄]; the 12 built-in colours from the first run
// (the saved colours untouched); the title opening 노트 정보.
import 'package:feature_editor/src/state/color_palette.dart';
import 'package:feature_editor/src/state/settings/editor_settings.dart';
import 'package:feature_editor/src/state/settings/editor_settings_notifier.dart';
import 'package:feature_editor/src/state/tape_state.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/ui/chrome/editor_chrome.dart';
import 'package:feature_editor/src/ui/chrome/floating_layer.dart';
import 'package:feature_editor/src/ui/color/basic_colors_row.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/pages/page_panel.dart';
import 'package:feature_editor/src/ui/pen/pen_settings_popup.dart';
import 'package:feature_editor/src/ui/pen/quick_pen_popup.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/more_menu.dart';
import 'package:feature_editor/src/ui/toolbar/note_info_dialog.dart';
import 'package:feature_editor/src/ui/toolbar/undo_redo_buttons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

Future<void> _openMore(WidgetTester tester) async {
  await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
  await tester.pumpAndSettle();
}

Future<void> _closeMore(WidgetTester tester) async {
  await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
  await tester.pumpAndSettle();
}

core.Stroke _tape(String id) => lineStroke(
  id: id,
  x0: 100,
  y0: 300,
  x1: 400,
  y1: 300,
  tool: core.PenTool.tape,
);

void main() {
  group('⋯ tape item', () {
    testWidgets('no tape in the note: no tape item', (tester) async {
      await pumpEditor(
        tester,
        strokesByPageIndex: {
          0: [strokeA],
        },
      );
      await _openMore(tester);
      expect(find.byKey(EditorMoreMenu.tapesRevealAllKey), findsNothing);
      expect(find.byKey(EditorMoreMenu.tapesHideAllKey), findsNothing);
    });

    testWidgets('a tape: one item that shows the other action each time', (
      tester,
    ) async {
      final h = await pumpEditor(
        tester,
        strokesByPageIndex: {
          0: [_tape('tape-0')],
        },
      );
      await _openMore(tester);
      expect(find.byKey(EditorMoreMenu.tapesHideAllKey), findsNothing);
      await tester.tap(find.byKey(EditorMoreMenu.tapesRevealAllKey));
      await tester.pumpAndSettle();
      expect(h.container.read(editorTapesRevealedAllProvider), isTrue);

      await _openMore(tester);
      expect(find.byKey(EditorMoreMenu.tapesRevealAllKey), findsNothing);
      expect(find.text(EditorStrings.tapesHideAll), findsOneWidget);
      await tester.tap(find.byKey(EditorMoreMenu.tapesHideAllKey));
      await tester.pumpAndSettle();
      expect(h.container.read(editorTapesRevealedAllProvider), isFalse);
    });

    testWidgets('the tape pen chosen (nothing drawn yet): the item shows', (
      tester,
    ) async {
      final h = await pumpEditor(tester);
      h.container
          .read(editorToolProvider.notifier)
          .selectPenType(core.PenTool.tape);
      await tester.pump();
      await _openMore(tester);
      expect(find.byKey(EditorMoreMenu.tapesRevealAllKey), findsOneWidget);
      await _closeMore(tester);
      await tester.pump(const Duration(seconds: 1)); // debounced writes
    });
  });

  testWidgets("page panel: '전체 4쪽' and the 페이지 넘김 row (moved from ⋯)", (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 4);
    await tester.tap(find.byKey(EditorToolbar.pagePanelKey));
    await tester.pumpAndSettle();
    expect(find.text('전체 4쪽'), findsOneWidget);
    expect(find.text('페이지 4'), findsNothing);
    final row = find.byKey(PagePanel.pageFlipKey);
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('넘김: 세로 스크롤')),
      findsOneWidget,
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PagePanel.horizontalKey));
    await tester.pumpAndSettle();
    expect(
      h.container.read(editorSettingsProvider).pageFlipMode,
      PageFlipMode.horizontalPaged,
    );
    expect(
      find.descendant(of: row, matching: find.text('넘김: 좌우 넘기기')),
      findsOneWidget,
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PagePanel.verticalKey));
    await tester.pumpAndSettle();
    expect(
      h.container.read(editorSettingsProvider).pageFlipMode,
      PageFlipMode.verticalScroll,
    );
    await tester.pump(const Duration(seconds: 1)); // debounced writes
  });

  testWidgets('restore pill: [↶] [↷] │ [🔍] │ [⌄], left to right', (
    tester,
  ) async {
    await pumpEditor(tester, logicalSize: const Size(1280, 800));
    // (UI stage 2) ⋯ '집중 모드' (no [⌃] in the row any more).
    await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
    await tester.pump();
    await tester.tap(find.byKey(EditorChrome.moreHideKey));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final pill = find.byKey(MenuRestorePill.pillKey);
    expect(pill, findsOneWidget);
    double x(Finder f) => tester.getCenter(f).dx;
    final undo = find.byKey(UndoRedoButtons.pillUndoKey);
    final redo = find.byKey(UndoRedoButtons.pillRedoKey);
    final search = find.byKey(MenuRestorePill.searchKey);
    final show = find.byKey(MenuRestorePill.showKey);
    expect(x(undo), lessThan(x(redo)));
    expect(x(redo), lessThan(x(search)));
    expect(x(search), lessThan(x(show)));
    expect(
      find.descendant(of: pill, matching: find.byType(VerticalDivider)),
      findsNWidgets(2),
    );
    expect(tester.getSize(pill).width, MenuRestorePill.width);
    await tester.tap(show);
    await tester.pump(const Duration(seconds: 1));
    expect(pill, findsNothing);
  });

  group('기본 색 12개', () {
    test('the 12 colours, opaque, distinct, in the proposal order', () {
      expect(kBasicColors, hasLength(12));
      expect(kBasicColors.toSet(), hasLength(12));
      for (final c in kBasicColors) {
        expect(ColorPaletteState.opaque(c), c);
      }
      expect(kBasicColors.first, 0xFF1A1A1A);
    });

    testWidgets('in the pen settings and the quick pen from the first run; a '
        'tap sets the pen colour; the saved colours stay empty', (
      tester,
    ) async {
      final h = await pumpEditor(tester);
      expect(h.container.read(editorColorPaletteProvider).palette, isEmpty);
      await tester.tap(find.byKey(EditorToolbar.penKey)); // active pen again
      await tester.pumpAndSettle();
      expect(find.byKey(PenSettingsPanel.panelKey), findsOneWidget);
      // (v2.15-ui) the picker's '색' row: the 12 basic colours first.
      expect(find.text(EditorStrings.pickerColor), findsOneWidget);
      for (var i = 0; i < kBasicColors.length; i++) {
        expect(find.byKey(BasicColorsRow.swatchKey(i)), findsOneWidget);
      }
      final blue = find.byKey(BasicColorsRow.swatchKey(3));
      await tester.ensureVisible(blue);
      await tester.pumpAndSettle();
      await tester.tap(blue);
      await tester.pump();
      expect(
        h.container.read(editorToolProvider).currentPen.colorArgb,
        kBasicColors[3],
      );
      // Built in, never stored: the user palette is untouched.
      expect(h.container.read(editorColorPaletteProvider).palette, isEmpty);
      await tester.tapAt(const Offset(4, 400)); // closes the popup
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(EditorToolbar.penKey));
      await tester.pumpAndSettle();
      expect(find.byKey(QuickPenPanel.panelKey), findsOneWidget);
      expect(find.byKey(QuickPenPanel.colorKey(0)), findsOneWidget);
      await tester.pump(const Duration(seconds: 2)); // debounced writes
    });
  });

  testWidgets('a tap on the title opens 노트 정보', (tester) async {
    await pumpEditor(tester, title: '물리 노트');
    await tester.tap(find.byKey(EditorToolbar.titleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(NoteInfoDialog.dialogKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(NoteInfoDialog.dialogKey),
        matching: find.text('물리 노트'),
      ),
      findsOneWidget,
    );
  });
}
