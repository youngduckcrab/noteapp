// E-17: the page panel (04-editor 6.11.1): the toolbar [▤] opens it, a tap
// moves to the page, the ⋯ menu (앞에 / 뒤에 페이지 추가, 복제, 삭제 — 삭제
// off on a one-page note), the deletion snack bar's [되돌리기], dragging →
// MovePages (forward, backward, to the front) undone in one step, the
// current page border and the list following the current page. EDITOR-3-1:
// a rejected deletion (rejectNext) never leaves the button handler.
import 'package:feature_editor/src/commands/editor_commands.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/page_panel.dart';
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/ui/editor_body.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/pages/page_panel.dart';
import 'package:feature_editor/src/ui/pages/page_panel_thumbnail.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';

Future<void> _openPanel(WidgetTester tester) async {
  await tester.tap(find.byKey(EditorToolbar.pagePanelKey));
  await tester.pump();
  await tester.pump();
}

/// Lets a 250 ms camera animation finish.
Future<void> _settleCamera(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// EditorCommands.undo, pumping while it may scroll to the affected page
/// (the camera animation needs frames).
Future<void> _undo(WidgetTester tester, EditorCommands commands) async {
  final done = commands.undo();
  await _settleCamera(tester);
  await done;
}

/// Opens the ⋯ menu of [pageId] and picks [action] (MenuItemButton runs
/// onPressed after the next frame).
Future<void> _menu(
  WidgetTester tester,
  String pageId,
  PageMenuAction action,
) async {
  await tester.tap(find.byKey(PagePanel.menuKey(pageId)));
  await tester.pump();
  await tester.pump();
  await tester.tap(find.byKey(PagePanel.menuItemKey(pageId, action)));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

/// The CORE command calls the recorder saw (page opens / closes left out).
List<String> _commandCalls(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (!c.startsWith('openPage:') && !c.startsWith('closePage:')) c,
];

List<String> _ids(EditorTestHandles h) => [
  for (final p in h.session.pages) p.id,
];

/// Width of the thumbnail border of the item of [pageId] (2 = current).
double _borderWidth(WidgetTester tester, String pageId) {
  final boxes = tester.widgetList<DecoratedBox>(
    find.descendant(
      of: find.byKey(PagePanel.itemKey(pageId)),
      matching: find.byType(DecoratedBox),
    ),
  );
  for (final box in boxes) {
    final decoration = box.decoration;
    if (box.position == DecorationPosition.foreground &&
        decoration is BoxDecoration &&
        decoration.border is Border) {
      return (decoration.border! as Border).top.width;
    }
  }
  throw StateError('no thumbnail border for $pageId');
}

void main() {
  testWidgets('[▤] opens and closes the panel; header, items, tap → page', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 3);
    expect(find.byKey(PagePanel.panelKey), findsNothing);
    await _openPanel(tester);
    expect(find.byKey(PagePanel.panelKey), findsOneWidget);
    expect(h.container.read(editorPagePanelProvider).isOpen, isTrue);
    expect(find.text(EditorStrings.pageCount(3)), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(PagePanel.itemKey(h.pageId(i))), findsOneWidget);
    }
    expect(find.byType(PagePanelThumbnail), findsNWidgets(3));
    // The panel overlays the viewport: the page area keeps its size.
    expect(tester.getSize(find.byKey(PagePanel.panelKey)).width, 176);

    expect(_borderWidth(tester, h.pageId(0)), 2);
    expect(_borderWidth(tester, h.pageId(2)), 1);
    await tester.tap(find.byKey(PagePanel.itemKey(h.pageId(2))));
    await _settleCamera(tester);
    expect(h.viewport.currentPageIndex.value, 2);
    await tester.pump();
    expect(_borderWidth(tester, h.pageId(2)), 2);
    expect(_borderWidth(tester, h.pageId(0)), 1);

    await tester.tap(find.byKey(EditorToolbar.pagePanelKey));
    await tester.pump();
    expect(find.byKey(PagePanel.panelKey), findsNothing);
  });

  testWidgets('⋯ menu: four items; 앞에 / 뒤에 페이지 추가 open the sheet at '
      'that page', (tester) async {
    final h = await pumpEditor(tester, pages: 3);
    await _openPanel(tester);
    final id = h.pageId(1);
    await tester.tap(find.byKey(PagePanel.menuKey(id)));
    await tester.pump();
    await tester.pump();
    for (final action in PageMenuAction.values) {
      expect(find.byKey(PagePanel.menuItemKey(id, action)), findsOneWidget);
    }
    expect(find.text(EditorStrings.addPageBefore), findsOneWidget);
    expect(find.text(EditorStrings.addPageAfter), findsOneWidget);
    await tester.tap(
      find.byKey(PagePanel.menuItemKey(id, PageMenuAction.addBefore)),
    );
    await tester.pump();
    await tester.pump();
    expect(
      h.container.read(editorPopupProvider),
      AddPagePopup(initialPlacement: AddPagePlacement.before, anchorPageId: id),
    );
    h.container.read(editorPopupProvider.notifier).close();
    await tester.pump();

    await _menu(tester, id, PageMenuAction.addAfter);
    expect(
      h.container.read(editorPopupProvider),
      AddPagePopup(anchorPageId: id),
    );
    h.container.read(editorPopupProvider.notifier).close();
    await tester.pump();
  });

  testWidgets('⋯ 복제 → DuplicatePages (copy right after, one undo step); '
      '삭제 → DeletePages + snack bar whose 되돌리기 brings it back', (tester) async {
    final h = await pumpEditor(tester, pages: 3);
    await _openPanel(tester);
    final rec = h.recorder!..clearCalls();

    await _menu(tester, h.pageId(1), PageMenuAction.duplicate);
    expect(rec.calls, contains('executeAsync:duplicate-pages'));
    final ids = _ids(h);
    expect(ids, hasLength(4));
    expect(ids[0], h.pageId(0));
    expect(ids[1], h.pageId(1));
    expect(ids[3], h.pageId(2));
    final copy = ids[2];
    expect(h.session.history.undoLabel, 'duplicate-pages');
    await _settleCamera(tester);
    expect(h.viewport.currentPageIndex.value, 2, reason: 'moved to the copy');
    await tester.pump();
    expect(find.text(EditorStrings.pageCount(4)), findsOneWidget);

    rec.clearCalls();
    await _menu(tester, copy, PageMenuAction.delete);
    expect(rec.calls, contains('execute:delete-pages'));
    expect(_ids(h), [h.pageId(0), h.pageId(1), h.pageId(2)]);
    expect(find.text(EditorStrings.pagesDeleted), findsOneWidget);
    expect(find.byKey(CommandMessages.undoDeleteKey), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500)); // slides in
    await tester.tap(find.byKey(CommandMessages.undoDeleteKey));
    await _settleCamera(tester);
    expect(_commandCalls(h).last, 'undo');
    expect(_ids(h), [h.pageId(0), h.pageId(1), copy, h.pageId(2)]);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a one-page note: 삭제 is disabled', (tester) async {
    final h = await pumpEditor(tester, pages: 1);
    await _openPanel(tester);
    final id = h.pageId(0);
    await tester.tap(find.byKey(PagePanel.menuKey(id)));
    await tester.pump();
    await tester.pump();
    final delete = tester.widget<MenuItemButton>(
      find.byKey(PagePanel.menuItemKey(id, PageMenuAction.delete)),
    );
    expect(delete.onPressed, isNull);
    final duplicate = tester.widget<MenuItemButton>(
      find.byKey(PagePanel.menuItemKey(id, PageMenuAction.duplicate)),
    );
    expect(duplicate.onPressed, isNotNull);
    // The command also refuses to delete the last page.
    h.recorder!.clearCalls();
    h.container.read(editorCommandsProvider).deletePages([id]);
    expect(_commandCalls(h), isEmpty);
  });

  testWidgets('EDITOR-3-1: a rejected deletion (read-only race) stays inside '
      'EditorCommands — notice, no snack bar 되돌리기, pages unchanged', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 3);
    await _openPanel(tester);
    h.recorder!
      ..clearCalls()
      ..rejectNext(const core.ReadOnlyNoteException('race'));
    await _menu(tester, h.pageId(1), PageMenuAction.delete);
    expect(tester.takeException(), isNull);
    expect(_commandCalls(h), ['execute:delete-pages:rejected']);
    expect(_ids(h), [h.pageId(0), h.pageId(1), h.pageId(2)]);
    expect(find.text(EditorStrings.readOnlyToast), findsOneWidget);
    expect(find.text(EditorStrings.pagesDeleted), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  group('drag → MovePages, one undo step', () {
    testWidgets('a long press then a drag moves the page forward', (
      tester,
    ) async {
      final h = await pumpEditor(tester, pages: 3);
      await _openPanel(tester);
      h.recorder!.clearCalls();
      final item = find.byKey(PagePanel.itemKey(h.pageId(0)));
      final height = tester.getSize(item).height;
      final gesture = await tester.startGesture(tester.getCenter(item));
      await tester.pump(const Duration(milliseconds: 600)); // long press
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(Offset(0, height * 0.1));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(h.recorder!.calls, contains('execute:move-pages'));
      expect(_ids(h), [h.pageId(1), h.pageId(0), h.pageId(2)]);
      await _undo(tester, h.container.read(editorCommandsProvider));
      expect(_ids(h), [h.pageId(0), h.pageId(1), h.pageId(2)]);
    });

    testWidgets('onReorderItem indexes: forward, backward, to the front, '
        'to the end; the same place → no command', (tester) async {
      final h = await pumpEditor(tester, pages: 4);
      await _openPanel(tester);
      final p = [for (var i = 0; i < 4; i++) h.pageId(i)];
      void reorder(int from, int to) => tester
          .widget<ReorderableListView>(find.byKey(PagePanel.listKey))
          .onReorderItem!(from, to);
      final commands = h.container.read(editorCommandsProvider);

      Future<void> check(int from, int to, List<String> expected) async {
        h.recorder!.clearCalls();
        reorder(from, to);
        await tester.pump();
        expect(_commandCalls(h), ['execute:move-pages'], reason: '$from→$to');
        expect(_ids(h), expected, reason: '$from→$to');
        expect(h.session.history.undoLabel, 'move-pages');
        await _undo(tester, commands);
        expect(_ids(h), p, reason: 'undo $from→$to');
      }

      await check(1, 2, [p[0], p[2], p[1], p[3]]); // forward
      await check(3, 1, [p[0], p[3], p[1], p[2]]); // backward
      await check(2, 0, [p[2], p[0], p[1], p[3]]); // to the front
      await check(0, 3, [p[1], p[2], p[3], p[0]]); // to the end

      h.recorder!.clearCalls();
      reorder(2, 2);
      await tester.pump();
      expect(_commandCalls(h), isEmpty);
    });

    testWidgets('read-only: no drag listener, ⋯ items and [+] disabled', (
      tester,
    ) async {
      final h = await pumpEditor(tester, pages: 3);
      await h.store.library.trashItems([core.NoteRef(h.noteId)]);
      await tester.pump();
      await _openPanel(tester);
      expect(
        find.descendant(
          of: find.byKey(PagePanel.panelKey),
          matching: find.byType(ReorderableDelayedDragStartListener),
        ),
        findsNothing,
      );
      expect(
        tester.widget<IconButton>(find.byKey(PagePanel.addKey)).onPressed,
        isNull,
      );
      final id = h.pageId(0);
      await tester.tap(find.byKey(PagePanel.menuKey(id)));
      await tester.pump();
      await tester.pump();
      for (final action in PageMenuAction.values) {
        expect(
          tester
              .widget<MenuItemButton>(
                find.byKey(PagePanel.menuItemKey(id, action)),
              )
              .onPressed,
          isNull,
          reason: action.name,
        );
      }
      await tester.pump(const Duration(seconds: 3));
    });
  });

  testWidgets('the list follows the current page (200 ms scroll)', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 12);
    await _openPanel(tester);
    final list = find.byKey(PagePanel.listKey);
    final listRect = tester.getRect(list);
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    expect(scrollable.position.pixels, 0);

    await h.viewport.jumpToPage(10, animate: false);
    await tester.pump(); // current page → provider
    await tester.pump(); // post-frame: scroll starts
    await tester.pump(const Duration(milliseconds: 250));
    expect(scrollable.position.pixels, greaterThan(0));
    final item = find.byKey(PagePanel.itemKey(h.pageId(10)));
    expect(item, findsOneWidget);
    final itemRect = tester.getRect(item);
    expect(itemRect.top, greaterThanOrEqualTo(listRect.top - 0.5));
    expect(itemRect.bottom, lessThanOrEqualTo(listRect.bottom + 0.5));
    expect(_borderWidth(tester, h.pageId(10)), 2);

    // Back to page 1: the list scrolls up again.
    await h.viewport.jumpToPage(1, animate: false);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final first = tester.getRect(find.byKey(PagePanel.itemKey(h.pageId(1))));
    expect(first.top, greaterThanOrEqualTo(listRect.top - 0.5));
  });
}
