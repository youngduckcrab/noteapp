// (v2.14-ui, UI stage 1 review — m5-7/04-editor 'UI 정리 1단계') Fixes after
// the review of the cleanup: the tools stay put when [100%] / [☁] come and
// go; 노트에서 찾기 is in ⋯ below the width with [🔍]; the ⋯ tape item
// remembers a tape seen in this session; 기본 색 12개 at the top of the pen
// settings (검정 = the default ink, selected at first run, Korean names); the
// end hint keeps off the page when zoomed out; 손가락으로 그리기 says what it
// did; the title has a ▾ and 노트 정보 renames; ⋯ items have icons.
import 'dart:async';

import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/note_search.dart';
import 'package:feature_editor/src/state/settings/editor_settings.dart';
import 'package:feature_editor/src/state/settings/editor_settings_notifier.dart';
import 'package:feature_editor/src/state/tape_state.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/ui/color/basic_colors_row.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/overlays/end_of_document_hint.dart';
import 'package:feature_editor/src/ui/pen/pen_settings_popup.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/more_menu.dart';
import 'package:feature_editor/src/ui/toolbar/note_info_dialog.dart';
import 'package:feature_editor/src/ui/toolbar/sync_badge_icon.dart';
import 'package:feature_editor/src/ui/toolbar/zoom_chip.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

Future<void> _openMore(WidgetTester tester) async {
  await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
  await tester.pumpAndSettle();
}

Future<void> _frames(WidgetTester tester, [int n = 5]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final width in [1280.0, 900.0]) {
    testWidgets('$width px: the tools do not move when [100%] and [☁] '
        'appear or go', (tester) async {
      final sync = StreamController<core.SyncBadge>.broadcast();
      addTearDown(sync.close);
      final h = await pumpEditor(
        tester,
        logicalSize: Size(width, 900),
        overrides: [core.syncBadgeProvider.overrideWith((ref) => sync.stream)],
      );
      double penX() => tester.getRect(find.byKey(EditorToolbar.penKey)).left;
      double moreX() =>
          tester.getRect(find.byKey(EditorMoreMenu.buttonKey)).left;
      final pen = penX();
      final more = moreX();
      expect(find.byKey(ZoomChip.chipKey), findsNothing);

      sync.add(const core.SyncBadge(display: core.SyncDisplayState.inProgress));
      await _frames(tester);
      expect(find.byKey(EditorSyncBadgeIcon.iconKey), findsOneWidget);
      expect(penX(), pen);
      expect(moreX(), more);

      h.container.read(editorCommandsProvider).zoomIn();
      await _frames(tester);
      expect(find.byKey(ZoomChip.chipKey), findsOneWidget);
      expect(penX(), pen);
      expect(moreX(), more);
      // Both sit before the tools (on the title side).
      expect(
        tester.getRect(find.byKey(ZoomChip.chipKey)).right,
        lessThanOrEqualTo(pen),
      );

      sync.add(const core.SyncBadge(display: core.SyncDisplayState.done));
      await _frames(tester);
      expect(find.byKey(EditorSyncBadgeIcon.iconKey), findsNothing);
      expect(penX(), pen);
      expect(tester.takeException(), isNull);
    });
  }

  group('노트에서 찾기 below the [🔍] width', () {
    testWidgets('700 px: no toolbar [🔍]; ⋯ has it first, and it opens the '
        'search', (tester) async {
      final h = await pumpEditor(tester, logicalSize: const Size(700, 1000));
      expect(find.byKey(EditorToolbar.noteSearchKey), findsNothing);
      await _openMore(tester);
      final item = find.byKey(EditorMoreMenu.noteSearchKey);
      expect(item, findsOneWidget);
      await tester.tap(item);
      await tester.pumpAndSettle();
      expect(h.container.read(editorNoteSearchProvider).isOpen, isTrue);
    });

    testWidgets('(v2.15-ui) from 852 px: the toolbar [🔍], not in ⋯', (
      tester,
    ) async {
      await pumpEditor(tester, logicalSize: const Size(852, 1000));
      expect(find.byKey(EditorToolbar.noteSearchKey), findsOneWidget);
      await _openMore(tester);
      expect(find.byKey(EditorMoreMenu.noteSearchKey), findsNothing);
    });
  });

  group('⋯ tape item remembers a tape seen in this session', () {
    testWidgets('a mounted page with a tape sets the flag', (tester) async {
      final h = await pumpEditor(
        tester,
        strokesByPageIndex: {
          0: [
            lineStroke(
              id: 't',
              x0: 100,
              y0: 300,
              x1: 400,
              y1: 300,
              tool: core.PenTool.tape,
            ),
          ],
        },
      );
      expect(h.container.read(editorNoteHadTapeProvider), isTrue);
    });

    testWidgets('the flag alone (the page with the tape no longer loaded) '
        'shows the item', (tester) async {
      final h = await pumpEditor(
        tester,
        strokesByPageIndex: {
          0: [strokeA],
        },
      );
      expect(h.container.read(editorNoteHadTapeProvider), isFalse);
      await _openMore(tester);
      expect(find.byKey(EditorMoreMenu.tapesRevealAllKey), findsNothing);
      await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
      await tester.pumpAndSettle();
      h.container.read(editorNoteHadTapeProvider.notifier).noteStrokes([
        lineStroke(id: 'x', x0: 0, y0: 0, x1: 10, y1: 10),
      ]);
      expect(h.container.read(editorNoteHadTapeProvider), isFalse);
      h.container.read(editorNoteHadTapeProvider.notifier).noteStrokes([
        lineStroke(
          id: 'y',
          x0: 0,
          y0: 0,
          x1: 10,
          y1: 10,
          tool: core.PenTool.tape,
        ),
      ]);
      await _openMore(tester);
      expect(find.byKey(EditorMoreMenu.tapesRevealAllKey), findsOneWidget);
    });
  });

  testWidgets('기본 색 at the top of the pen settings, in view at 1280×800; '
      '검정 is the default ink and shows selected; Korean names', (tester) async {
    final h = await pumpEditor(tester, logicalSize: const Size(1280, 800));
    expect(
      h.container.read(editorToolProvider).currentPen.colorArgb,
      kBasicColors.first,
    );
    await tester.tap(find.byKey(EditorToolbar.penKey));
    await tester.pumpAndSettle();
    expect(find.byKey(PenSettingsPanel.panelKey), findsOneWidget);
    for (var i = 0; i < kBasicColors.length; i++) {
      final swatch = find.byKey(BasicColorsRow.swatchKey(i));
      expect(swatch.hitTestable(), findsOneWidget, reason: 'swatch $i');
      expect(tester.getRect(swatch).bottom, lessThan(800));
    }
    expect(
      tester.getSemantics(find.byKey(BasicColorsRow.swatchKey(0))),
      isSemantics(label: '검정', isButton: true, isSelected: true),
    );
    expect(EditorStrings.basicColorNames, hasLength(kBasicColors.length));
    await tester.pump(const Duration(seconds: 1));
  });

  for (final flip in PageFlipMode.values) {
    testWidgets('${flip.name}: zoomed out to the least, the end hint keeps '
        '${EndOfDocumentHint.minGap} px off the last page', (tester) async {
      final h = await pumpEditor(
        tester,
        settings: EditorSettings(pageFlipMode: flip),
      );
      for (var i = 0; i < 8; i++) {
        h.container.read(editorCommandsProvider).zoomOut();
        await _frames(tester, 3);
      }
      final viewport = h.viewport;
      final rect = EndOfDocumentHint.rectOf(viewport)!;
      final last = viewport.layout.rectOf(viewport.layout.length - 1);
      final camera = viewport.camera;
      if (flip == PageFlipMode.verticalScroll) {
        final edge = camera.docToScreen(Offset(last.center.dx, last.bottom));
        expect(
          rect.top - edge.dy,
          greaterThanOrEqualTo(EndOfDocumentHint.minGap - 0.01),
        );
      } else {
        final edge = camera.docToScreen(Offset(last.right, last.center.dy));
        expect(
          rect.left - edge.dx,
          greaterThanOrEqualTo(EndOfDocumentHint.minGap - 0.01),
        );
      }
      await tester.pump(const Duration(seconds: 1));
    });
  }

  group('⋯ 손가락으로 그리기', () {
    testWidgets("자동: '자동' beside it; a tap says the new state and that "
        '자동 was left; the next tap says only the state', (tester) async {
      final h = await pumpEditor(tester);
      expect(
        h.container.read(editorSettingsProvider).inputMode,
        InputMode.auto,
      );
      await _openMore(tester);
      expect(
        find.descendant(
          of: find.byKey(EditorMoreMenu.fingerDrawingKey),
          matching: find.text(EditorStrings.fingerDrawingAuto),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(EditorMoreMenu.fingerDrawingKey));
      await tester.pumpAndSettle();
      final mode = h.container.read(editorSettingsProvider).inputMode;
      expect(mode, isNot(InputMode.auto));
      final first = mode == InputMode.fingerDrawing
          ? EditorStrings.fingerDrawingOn
          : EditorStrings.fingerDrawingOff;
      expect(
        find.text('$first\n${EditorStrings.fingerDrawingLeftAuto}'),
        findsOneWidget,
      );

      await _openMore(tester);
      expect(find.text(EditorStrings.fingerDrawingAuto), findsNothing);
      await tester.tap(find.byKey(EditorMoreMenu.fingerDrawingKey));
      await tester.pumpAndSettle();
      final second = mode == InputMode.fingerDrawing
          ? EditorStrings.fingerDrawingOff
          : EditorStrings.fingerDrawingOn;
      expect(find.text(second), findsOneWidget);
      expect(
        find.textContaining(EditorStrings.fingerDrawingLeftAuto),
        findsNothing,
      );
      // The same words as settings › 입력.
      expect(
        EditorStrings.inputModeFingerDrawing,
        EditorStrings.fingerDrawingMenu,
      );
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('title ▾ and 이름 바꾸기', () {
    testWidgets('▾ after the title; 노트 정보 › 이름 바꾸기 renames the note in '
        'CORE and the toolbar title follows', (tester) async {
      final h = await pumpEditor(
        tester,
        title: '물리 노트',
        logicalSize: const Size(1280, 800),
      );
      expect(find.byKey(EditorToolbar.titleAffordanceKey), findsOneWidget);
      await tester.tap(find.byKey(EditorToolbar.titleKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(NoteInfoDialog.renameKey));
      await tester.pumpAndSettle();
      expect(find.byKey(NoteRenameDialog.dialogKey), findsOneWidget);
      final save = find.byKey(NoteRenameDialog.saveKey);
      // Unchanged / empty: [바꾸기] is off.
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(find.byKey(NoteRenameDialog.fieldKey), '   ');
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(find.byKey(NoteRenameDialog.fieldKey), '  화학 노트 ');
      await tester.pump();
      await tester.tap(save);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.byKey(NoteRenameDialog.dialogKey), findsNothing);
      expect(find.byKey(NoteInfoDialog.dialogKey), findsNothing);
      final note = await tester.runAsync(
        () => h.store.library.watchNote(h.noteId).first,
      );
      expect(note!.title, '화학 노트');
      await tester.pumpAndSettle();
      expect(h.container.read(editorNoteTitleProvider), '화학 노트');
      expect(
        find.descendant(
          of: find.byKey(EditorToolbar.titleKey),
          matching: find.text('화학 노트'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('narrow (title hidden): ⋯ 노트 정보 and 설정 have icons like the '
        'other items', (tester) async {
      await pumpEditor(
        tester,
        logicalSize: const Size(800, 1280),
        onOpenSettings: () {},
      );
      await _openMore(tester);
      for (final key in [
        EditorMoreMenu.noteInfoKey,
        EditorMoreMenu.settingsKey,
        EditorMoreMenu.fingerDrawingKey,
      ]) {
        expect(
          tester.widget<MenuItemButton>(find.byKey(key)).leadingIcon,
          isNotNull,
          reason: '$key',
        );
      }
    });
  });
}
