// Drag and drop (05-library 6.10, 8 L15), with touch AND stylus: a note onto
// a folder tile, several items onto a sidebar folder, a folder onto its own
// sub-folder (refused, no highlight), onto 홈, onto a breadcrumb crumb (and
// the '…' menu after 700 ms), onto 휴지통, reordering in the custom order, a
// collapsed folder expanding after 700 ms, the drawer opening at the left
// edge after 600 ms (portrait), and a long press released in place (only
// selects). Gestures follow 9.1: down → 450 ms → move 20 → target → up.
import 'package:feature_library/feature_library.dart';
import 'package:feature_library/src/dnd/library_draggable.dart';
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/model/item_key.dart';
import 'package:feature_library/src/model/section.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/ui/content/folder_tile.dart';
import 'package:feature_library/src/ui/content/new_note_tile.dart';
import 'package:feature_library/src/ui/content/note_tile.dart';
import 'package:feature_library/src/ui/content/tile_parts.dart';
import 'package:feature_library/src/ui/sidebar/library_sidebar.dart';
import 'package:feature_library/src/ui/sidebar/sidebar_rows.dart';
import 'package:feature_library/src/ui/top_bar/library_top_bar.dart';
import 'package:feature_library/src/ui/top_bar/selection_bar.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';

import '../support/fake_library_backend.dart';
import '../support/fixtures.dart';
import '../support/library_test_harness.dart';
import '../support/test_sizes.dart';

Finder tile(String name) => find.ancestor(
  of: find.text(name),
  matching: find.byWidgetPredicate((w) => w is NoteTile || w is FolderTile),
);
Finder treeRow(String name) => find.widgetWithText(SidebarTreeRow, name);
Finder navRow(String label) => find.widgetWithText(SidebarNavRow, label);
final Finder drawerSidebar = find.byWidgetPredicate(
  (w) => w is LibrarySidebar && w.inDrawer,
);

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  Future<SampleLibrary> seed(WidgetTester tester) =>
      real(tester, () => seedSampleLibrary(backend));

  Future<LibraryTestHarness> pumpAt(
    WidgetTester tester, {
    FolderId? folderId,
    Size size = TestSizes.ipad13Landscape,
  }) async {
    final h = LibraryTestHarness(backend, size: size);
    await h.pump(tester, folderId: folderId);
    await tester.pumpAndSettle();
    return h;
  }

  /// The display order of the home listing.
  List<String> homeOrder(WidgetTester tester) => [
    for (final k
        in containerOf(tester)
            .read(libraryContentProvider(const FolderSection(null)))
            .value!
            .orderedKeys)
      '${k.kind == LibraryItemKind.folder ? 'f' : 'n'}:${k.id}',
  ];

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.stylus]) {
    /// 9.1: down on [source] → 450 ms (the drag starts at 400) → 20 down.
    Future<TestGesture> startDrag(WidgetTester tester, Finder source) async {
      final gesture = await tester.startGesture(
        tester.getCenter(source),
        kind: kind,
      );
      await tester.pump(const Duration(milliseconds: 450));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      return gesture;
    }

    Future<void> moveTo(
      WidgetTester tester,
      TestGesture gesture,
      Offset to,
    ) async {
      await gesture.moveTo(to);
      await tester.pump();
    }

    Future<void> drop(WidgetTester tester, TestGesture gesture) async {
      await gesture.up();
      await tester.pumpAndSettle();
    }

    group(kind.name, () {
      testWidgets('a note onto a folder tile moves it there', (tester) async {
        final sample = await seed(tester);
        await pumpAt(tester);
        final note = sample.homeNotes[0]; // 회의록
        final g = await startDrag(tester, tile('회의록'));
        // The drag started selection mode with the note; the top bar (its
        // breadcrumb takes drops) and the '새 노트' tile stay while it runs.
        expect(containerOf(tester).read(librarySelectionProvider(null)).keys, [
          noteKey(note.id),
        ]);
        expect(find.byType(SelectionCheckBadge), findsNWidgets(7));
        expect(find.byType(SelectionBar), findsNothing);
        expect(find.byType(LibraryTopBar), findsOneWidget);
        expect(find.byType(NewNoteTile), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(LibraryDragFeedback),
            matching: find.text('회의록'),
          ),
          findsOneWidget,
        );
        await moveTo(tester, g, tester.getCenter(tile('수학')));
        final cover = tester.widget<TileCoverBox>(
          find.descendant(of: tile('수학'), matching: find.byType(TileCoverBox)),
        );
        expect(cover.dropInto, isTrue);
        await drop(tester, g);
        expect(backend.calls, [
          'moveItems [n:${note.id}] -> f:${sample.math.id}',
        ]);
        expect(find.text(LibraryStrings.movedTo('수학')), findsOneWidget);
        expect(find.text('회의록'), findsNothing);
        // Done: selection mode ends.
        expect(find.byType(SelectionBar), findsNothing);
        expect(find.byType(LibraryDragFeedback), findsNothing);
      });

      testWidgets('several selected items onto a sidebar folder', (
        tester,
      ) async {
        final sample = await seed(tester);
        await pumpAt(tester);
        await tester.longPress(tile('회의록'));
        await tester.pumpAndSettle();
        await tester.tap(tile('수학'));
        await tester.pump();
        final g = await startDrag(tester, tile('일기'));
        expect(
          find.descendant(
            of: find.byType(LibraryDragFeedback),
            matching: find.text(LibraryStrings.itemCount(3)),
          ),
          findsOneWidget,
        );
        await moveTo(tester, g, tester.getCenter(treeRow('영어')));
        expect(
          tester.widget<SidebarTreeRow>(treeRow('영어')).drop,
          SidebarDropLook.folder,
        );
        final order = homeOrder(tester);
        await drop(tester, g);
        final moved = [
          for (final id in order)
            if (id == 'f:${sample.math.id}' ||
                id == 'n:${sample.homeNotes[0].id}' ||
                id == 'n:${sample.homeNotes[3].id}')
              id,
        ];
        expect(backend.calls, [
          'moveItems [${moved.join(', ')}] -> f:${sample.english.id}',
        ]);
        expect(find.text(LibraryStrings.movedCountTo(3, '영어')), findsOneWidget);
        expect(find.byType(SelectionBar), findsNothing);
      });

      testWidgets('a folder onto its own sub-folder: no highlight, refused', (
        tester,
      ) async {
        await seed(tester);
        await pumpAt(tester);
        await tester.tap(
          find.descendant(
            of: treeRow('수학'),
            matching: find.byTooltip(LibraryStrings.expandFolder),
          ),
        );
        await tester.pumpAndSettle();
        // From the content.
        var g = await startDrag(tester, tile('수학'));
        await moveTo(tester, g, tester.getCenter(treeRow('미적분')));
        expect(
          tester.widget<SidebarTreeRow>(treeRow('미적분')).drop,
          SidebarDropLook.none,
        );
        await moveTo(tester, g, tester.getCenter(treeRow('수학')));
        expect(
          tester.widget<SidebarTreeRow>(treeRow('수학')).drop,
          SidebarDropLook.none,
        );
        await drop(tester, g);
        // From the sidebar row itself.
        g = await startDrag(tester, treeRow('수학'));
        await moveTo(tester, g, tester.getCenter(treeRow('미적분')));
        expect(
          tester.widget<SidebarTreeRow>(treeRow('미적분')).drop,
          SidebarDropLook.none,
        );
        await drop(tester, g);
        expect(backend.calls, isEmpty);
        expect(find.byType(SnackBar), findsNothing);
      });

      testWidgets('a sidebar row onto another folder row moves the folder', (
        tester,
      ) async {
        final sample = await seed(tester);
        await pumpAt(tester);
        final g = await startDrag(tester, treeRow('영어'));
        // A sidebar drag does not start selection mode.
        expect(find.byType(SelectionBar), findsNothing);
        await moveTo(tester, g, tester.getCenter(treeRow('과학')));
        expect(
          tester.widget<SidebarTreeRow>(treeRow('과학')).drop,
          SidebarDropLook.folder,
        );
        await drop(tester, g);
        expect(backend.calls, [
          'moveItems [f:${sample.english.id}] -> f:${sample.science.id}',
        ]);
        expect(find.text(LibraryStrings.movedTo('과학')), findsOneWidget);
      });

      testWidgets('onto 홈 (sidebar) from a folder; [실행 취소] moves back', (
        tester,
      ) async {
        final sample = await seed(tester);
        await pumpAt(tester, folderId: sample.math.id);
        final calculus = sample.nested[0]; // 미적분
        final g = await startDrag(tester, tile('미적분'));
        await moveTo(tester, g, tester.getCenter(navRow(LibraryStrings.home)));
        expect(
          tester.widget<SidebarNavRow>(navRow(LibraryStrings.home)).drop,
          SidebarDropLook.folder,
        );
        await drop(tester, g);
        expect(backend.calls, ['moveItems [f:${calculus.id}] -> home']);
        expect(
          find.text(LibraryStrings.movedTo(LibraryStrings.home)),
          findsOneWidget,
        );
        await tester.tap(
          find.widgetWithText(SnackBarAction, LibraryStrings.undo),
        );
        await tester.pumpAndSettle();
        expect(
          backend.calls.last,
          'moveItems [f:${calculus.id}] -> f:${sample.math.id}',
        );
      });

      testWidgets('onto a breadcrumb crumb, and the hidden path menu after '
          '700 ms', (tester) async {
        final sample = await seed(tester);
        // 홈 › … › 극한 › 연습 문제 (expanded keeps 4).
        await pumpAt(tester, folderId: sample.deepest.id);
        final deep = sample.deepNote;
        final crumb = find.widgetWithText(TextButton, '극한');
        var g = await startDrag(tester, tile('극한 정리'));
        await moveTo(tester, g, tester.getCenter(crumb));
        expect(
          tester
              .widget<DecoratedBox>(
                find
                    .ancestor(of: crumb, matching: find.byType(DecoratedBox))
                    .first,
              )
              .decoration,
          isA<BoxDecoration>().having(
            (d) => d.color,
            'color',
            Theme.of(tester.element(find.byType(LibraryScreen)))
                .colorScheme
                .primaryContainer,
          ),
        );
        await drop(tester, g);
        expect(backend.calls, [
          'moveItems [n:${deep.id}] -> f:${sample.nested[1].id}',
        ]);
        await tester.tap(
          find.widgetWithText(SnackBarAction, LibraryStrings.undo),
        );
        await tester.pumpAndSettle();
        backend.calls.clear();

        // '…' opens its menu after 700 ms of a drag; its items take drops.
        final more = find.byTooltip(LibraryStrings.hiddenPath);
        g = await startDrag(tester, tile('극한 정리'));
        await moveTo(tester, g, tester.getCenter(more));
        await tester.pump(const Duration(milliseconds: 650));
        await tester.pump();
        expect(find.widgetWithText(MenuItemButton, '수학'), findsNothing);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        final item = find.widgetWithText(MenuItemButton, '수학');
        expect(item, findsOneWidget);
        await moveTo(tester, g, tester.getCenter(item));
        await drop(tester, g);
        expect(backend.calls, [
          'moveItems [n:${deep.id}] -> f:${sample.math.id}',
        ]);
        expect(find.widgetWithText(MenuItemButton, '수학'), findsNothing);
      });

      testWidgets('onto 휴지통: trashed, [실행 취소] restores', (tester) async {
        final sample = await seed(tester);
        await pumpAt(tester);
        final note = sample.homeNotes[1]; // 독서 기록
        final g = await startDrag(tester, tile('독서 기록'));
        final trashRow = navRow(LibraryStrings.trash);
        await moveTo(tester, g, tester.getCenter(trashRow));
        expect(
          tester.widget<SidebarNavRow>(trashRow).drop,
          SidebarDropLook.trash,
        );
        await drop(tester, g);
        expect(backend.calls, ['trashItems [n:${note.id}]']);
        expect(find.text(LibraryStrings.droppedInTrash), findsOneWidget);
        expect(find.byType(SelectionBar), findsNothing);
        await tester.tap(
          find.widgetWithText(SnackBarAction, LibraryStrings.undo),
        );
        await tester.pumpAndSettle();
        expect(backend.calls.last, 'restore [n:${note.id}]');
        expect(find.text('독서 기록'), findsOneWidget);
      });

      testWidgets('custom order: before / after another tile reorders', (
        tester,
      ) async {
        final sample = await seed(tester);
        await pumpAt(tester);
        // Not in the custom order: a note over a note shows nothing.
        var g = await startDrag(tester, tile('회의록'));
        var rect = tester.getRect(tile('일기'));
        await moveTo(
          tester,
          g,
          Offset(rect.left + rect.width * 0.9, rect.center.dy),
        );
        expect(find.byType(DropInsertionBar), findsNothing);
        await drop(tester, g);
        expect(backend.calls, isEmpty);
        containerOf(tester).read(librarySelectionProvider(null).notifier).end();
        await containerOf(tester)
            .read(libraryPrefsProvider.notifier)
            .selectSort(LibrarySortField.custom);
        await tester.pumpAndSettle();

        final notes = sample.homeNotes; // custom = creation order
        g = await startDrag(tester, tile('회의록'));
        rect = tester.getRect(tile('일기'));
        await moveTo(
          tester,
          g,
          Offset(rect.left + rect.width * 0.9, rect.center.dy),
        );
        expect(find.byType(DropInsertionBar), findsOneWidget);
        await drop(tester, g);
        expect(backend.calls, [
          'reorderItem n:${notes[0].id} after:n:${notes[3].id}',
        ]);
        expect(find.byType(SelectionBar), findsNothing);

        g = await startDrag(tester, tile('일기'));
        rect = tester.getRect(tile('독서 기록'));
        await moveTo(
          tester,
          g,
          Offset(rect.left + rect.width * 0.1, rect.center.dy),
        );
        expect(find.byType(DropInsertionBar), findsOneWidget);
        await drop(tester, g);
        expect(
          backend.calls.last,
          'reorderItem n:${notes[3].id} before:n:${notes[1].id}',
        );
        final noteKeys = [
          for (final k in homeOrder(tester))
            if (k.startsWith('n:')) k,
        ];
        expect(noteKeys, [
          'n:${notes[3].id}',
          'n:${notes[1].id}',
          'n:${notes[2].id}',
          'n:${notes[0].id}',
        ]);
      });

      testWidgets('a collapsed folder row expands after 700 ms of a drag', (
        tester,
      ) async {
        final sample = await seed(tester);
        await pumpAt(tester);
        expect(treeRow('미적분'), findsNothing);
        final g = await startDrag(tester, tile('회의록'));
        await moveTo(tester, g, tester.getCenter(treeRow('수학')));
        await tester.pump(const Duration(milliseconds: 650));
        await tester.pump();
        expect(treeRow('미적분'), findsNothing);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        expect(treeRow('미적분'), findsOneWidget);
        await moveTo(tester, g, tester.getCenter(treeRow('미적분')));
        await drop(tester, g);
        expect(backend.calls, [
          'moveItems [n:${sample.homeNotes[0].id}] -> f:${sample.nested[0].id}',
        ]);
      });

      testWidgets('portrait: 600 ms at the left edge opens the drawer; its '
          'rows take the drop and it stays open', (tester) async {
        final sample = await seed(tester);
        await pumpAt(tester, size: TestSizes.ipad13Portrait);
        expect(drawerSidebar, findsNothing);
        final g = await startDrag(tester, tile('회의록'));
        final y = tester.getCenter(tile('회의록')).dy;
        await moveTo(tester, g, Offset(10, y));
        await tester.pump(const Duration(milliseconds: 550));
        await tester.pump();
        expect(drawerSidebar, findsNothing);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(drawerSidebar, findsOneWidget);
        final row = find.descendant(of: drawerSidebar, matching: treeRow('영어'));
        await moveTo(tester, g, tester.getCenter(row));
        await drop(tester, g);
        expect(backend.calls, [
          'moveItems [n:${sample.homeNotes[0].id}] -> f:${sample.english.id}',
        ]);
        expect(drawerSidebar, findsOneWidget);
      });

      testWidgets('a long press released in place only selects', (
        tester,
      ) async {
        await seed(tester);
        await pumpAt(tester);
        final g = await tester.startGesture(
          tester.getCenter(tile('아이디어')),
          kind: kind,
        );
        await tester.pump(const Duration(milliseconds: 450));
        expect(find.byType(LibraryDragFeedback), findsOneWidget);
        await g.up();
        await tester.pumpAndSettle();
        expect(find.byType(SelectionBar), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SelectionBar),
            matching: find.text(LibraryStrings.selectedCount(1)),
          ),
          findsOneWidget,
        );
        expect(find.byType(MenuItemButton), findsNothing);
        expect(backend.calls, isEmpty);
        expect(find.byType(LibraryDragFeedback), findsNothing);
      });

      testWidgets('a sidebar row released in place opens its menu', (
        tester,
      ) async {
        await seed(tester);
        await pumpAt(tester);
        final g = await tester.startGesture(
          tester.getCenter(treeRow('영어')),
          kind: kind,
        );
        await tester.pump(const Duration(milliseconds: 450));
        await g.up();
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(MenuItemButton, LibraryStrings.newSubfolder),
          findsOneWidget,
        );
        expect(find.byType(SelectionBar), findsNothing);
        expect(backend.calls, isEmpty);
      });
    });
  }
}
