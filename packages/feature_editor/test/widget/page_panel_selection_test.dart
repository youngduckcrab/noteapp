// E-17: the page panel selection mode (04-editor 6.11.2, EDITOR-M9): enter
// with [선택], a tap toggles a page (no move), 모두 선택, selectedPageIds in
// note order whatever the tap order (also in the more menu's
// EditorMenuContext), batch delete / duplicate as one undo step each,
// delete disabled with every page selected, deleted pages leave the
// selection, and Esc / 완료 / closing the panel empty it.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/page_panel.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/pages/page_panel.dart';
import 'package:feature_editor/src/ui/pages/page_panel_selection_bar.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/more_menu.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';

Future<void> _openSelecting(WidgetTester tester) async {
  await tester.tap(find.byKey(EditorToolbar.pagePanelKey));
  await tester.pump();
  await tester.pump();
  await tester.tap(find.byKey(PagePanel.selectModeKey));
  await tester.pump();
}

Future<void> _tapPage(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(PagePanel.itemKey(id)));
  await tester.pump();
}

PagePanelState _panel(EditorTestHandles h) =>
    h.container.read(editorPagePanelProvider);

List<String> _ids(EditorTestHandles h) => [
  for (final p in h.session.pages) p.id,
];

List<String> _commandCalls(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (!c.startsWith('openPage:') && !c.startsWith('closePage:')) c,
];

void main() {
  testWidgets('enter, toggle by tap (no move), select all, note order — also '
      'in the more menu context', (tester) async {
    final received = <EditorMenuContext>[];
    final h = await pumpEditor(
      tester,
      pages: 4,
      overrides: [
        editorExtensionsProvider.overrideWithValue(
          EditorExtensions(
            moreMenuItems: [
              EditorMenuItem(
                id: 'test.selected',
                label: '선택한 페이지 내보내기',
                icon: Icons.ios_share,
                onSelected: (context, menu) async => received.add(menu),
              ),
            ],
          ),
        ),
      ],
    );
    await _openSelecting(tester);
    expect(_panel(h).isSelecting, isTrue);
    expect(find.byKey(PagePanelSelectionBar.barKey), findsOneWidget);
    expect(find.byKey(PagePanel.checkKey(h.pageId(0))), findsOneWidget);
    expect(find.text(EditorStrings.pagesSelected(0)), findsOneWidget);
    // Nothing selected → 복제 / 삭제 disabled.
    expect(
      tester
          .widget<IconButton>(find.byKey(PagePanelSelectionBar.deleteKey))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(PagePanelSelectionBar.duplicateKey))
          .onPressed,
      isNull,
    );

    // Tapped 3 → 0: the order is the note's.
    await _tapPage(tester, h.pageId(3));
    await _tapPage(tester, h.pageId(0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(h.viewport.currentPageIndex.value, 0, reason: 'taps do not move');
    expect(_panel(h).selectedIds, {h.pageId(3), h.pageId(0)});
    expect(_panel(h).orderedSelection(_ids(h)), [h.pageId(0), h.pageId(3)]);
    expect(find.text(EditorStrings.pagesSelected(2)), findsOneWidget);
    // Toggle off and on again.
    await _tapPage(tester, h.pageId(3));
    expect(_panel(h).selectedIds, {h.pageId(0)});
    await _tapPage(tester, h.pageId(2));
    await _tapPage(tester, h.pageId(3));

    // More menu: selectedPageIds in note order.
    await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(EditorMoreMenu.itemKey('test.selected')));
    await tester.pumpAndSettle();
    expect(received.single.selectedPageIds, [
      h.pageId(0),
      h.pageId(2),
      h.pageId(3),
    ]);
    expect(received.single.pageIds, _ids(h));

    // 모두 선택 → every page; deleting all of them is not allowed.
    await tester.tap(find.byKey(PagePanelSelectionBar.selectAllKey));
    await tester.pump();
    expect(_panel(h).selectedIds, _ids(h).toSet());
    expect(
      tester
          .widget<IconButton>(find.byKey(PagePanelSelectionBar.deleteKey))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(PagePanelSelectionBar.duplicateKey))
          .onPressed,
      isNotNull,
    );
    // Delete key with every page selected: ignored too.
    h.recorder!.clearCalls();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(_commandCalls(h), isEmpty);
    expect(_ids(h), hasLength(4));

    // Outside the selection mode the context has no selection.
    await tester.tap(find.byKey(PagePanelSelectionBar.doneKey));
    await tester.pump();
    received.clear();
    await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(EditorMoreMenu.itemKey('test.selected')));
    await tester.pumpAndSettle();
    expect(received.single.selectedPageIds, isEmpty);
  });

  testWidgets('batch delete and duplicate: one undo step each', (tester) async {
    final h = await pumpEditor(tester, pages: 4);
    final p = [for (var i = 0; i < 4; i++) h.pageId(i)];
    await _openSelecting(tester);
    await _tapPage(tester, p[2]);
    await _tapPage(tester, p[0]);
    h.recorder!.clearCalls();
    final depth = h.session.history.undoDepth;

    await tester.tap(find.byKey(PagePanelSelectionBar.duplicateKey));
    await tester.pump();
    await tester.pump();
    expect(_commandCalls(h), ['executeAsync:duplicate-pages']);
    expect(h.session.history.undoDepth, depth + 1);
    final afterDup = _ids(h);
    expect(afterDup, hasLength(6));
    expect(afterDup[0], p[0]);
    expect(afterDup[2], p[1]);
    expect(afterDup[3], p[2]);
    expect(afterDup[5], p[3]);

    final undo = h.container.read(editorCommandsProvider).undo();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await undo;
    expect(_ids(h), p);
    expect(_panel(h).selectedIds, {p[0], p[2]}, reason: 'still selected');

    h.recorder!.clearCalls();
    await tester.tap(find.byKey(PagePanelSelectionBar.deleteKey));
    await tester.pump();
    expect(_commandCalls(h), ['execute:delete-pages']);
    expect(_ids(h), [p[1], p[3]]);
    expect(h.session.history.undoLabel, 'delete-pages');
    expect(_panel(h).selectedIds, isEmpty, reason: 'deleted pages left');
    expect(find.text(EditorStrings.pagesDeleted), findsOneWidget);

    final undo2 = h.container.read(editorCommandsProvider).undo();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await undo2;
    expect(_ids(h), p, reason: 'one undo brings both back');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Delete key in the selection mode (no stroke selection) '
      'deletes the selected pages', (tester) async {
    final h = await pumpEditor(tester, pages: 3);
    await _openSelecting(tester);
    await _tapPage(tester, h.pageId(1));
    h.recorder!.clearCalls();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(_commandCalls(h), ['execute:delete-pages']);
    expect(_ids(h), [h.pageId(0), h.pageId(2)]);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('pages deleted another way leave the selection', (tester) async {
    final h = await pumpEditor(tester, pages: 4);
    await _openSelecting(tester);
    await _tapPage(tester, h.pageId(1));
    await _tapPage(tester, h.pageId(2));

    // Local, outside the panel (another command path).
    h.session.execute(core.DeletePages(pageIds: [h.pageId(2)]));
    await tester.pump();
    expect(_panel(h).selectedIds, {h.pageId(1)});
    expect(find.byKey(PagePanel.itemKey(h.pageId(2))), findsNothing);

    // Remote deletions reach EDITOR the same way — a pagesStream list
    // without the page (the fake store has no remote path, so the notifier
    // is fed that list directly).
    h.container.read(editorPagePanelProvider.notifier).retainExisting({
      h.pageId(0),
      h.pageId(3),
    });
    expect(_panel(h).selectedIds, isEmpty);
  });

  testWidgets('Esc, 완료 and closing the panel empty the selection', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 3);
    await _openSelecting(tester);
    await _tapPage(tester, h.pageId(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(_panel(h).isSelecting, isFalse);
    expect(_panel(h).selectedIds, isEmpty);
    expect(_panel(h).isOpen, isTrue);

    await tester.tap(find.byKey(PagePanel.selectModeKey));
    await tester.pump();
    await _tapPage(tester, h.pageId(0));
    await tester.tap(find.byKey(PagePanelSelectionBar.doneKey));
    await tester.pump();
    expect(_panel(h).isSelecting, isFalse);
    expect(_panel(h).selectedIds, isEmpty);

    await tester.tap(find.byKey(PagePanel.selectModeKey));
    await tester.pump();
    await _tapPage(tester, h.pageId(2));
    await tester.tap(find.byKey(EditorToolbar.pagePanelKey));
    await tester.pump();
    expect(_panel(h), const PagePanelState());
  });

  test('PagePanelState: orderedSelection, value equality', () {
    const a = PagePanelState(isOpen: true, isSelecting: true);
    final b = a.copyWith(selectedIds: {'x', 'y'});
    expect(b.orderedSelection(['y', 'z', 'x']), ['y', 'x']);
    expect(
      b,
      PagePanelState(isOpen: true, isSelecting: true, selectedIds: {'y', 'x'}),
    );
    expect(b.hashCode, a.copyWith(selectedIds: {'y', 'x'}).hashCode);
    expect(b, isNot(a));
  });
}
