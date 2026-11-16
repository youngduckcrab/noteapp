// (v2.14-ui, UI stage 1 '정리만' — m5-7/05-library 'UI 정리 1단계') The
// library's removed or merged controls: no dashed '새 노트' grid tile, no
// sidebar '폴더 +', no search field / '선택' in the trash, no floppy
// '이 기기에 저장' while sync is off, no ☆ on non-favourite list rows, no
// 'PDF 가져오기 · 준비 중' without the import slot, and '새 버전 필요' as words.
// Each removed action stays reachable (asserted here too).
import 'package:feature_library/feature_library.dart' show LibraryScreen;
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/ui/content/folder_tile.dart';
import 'package:feature_library/src/ui/content/item_list.dart';
import 'package:feature_library/src/ui/content/note_tile.dart';
import 'package:feature_library/src/ui/dialogs/new_folder_dialog.dart';
import 'package:feature_library/src/ui/dialogs/new_note_dialog.dart';
import 'package:feature_library/src/ui/sidebar/library_sidebar.dart';
import 'package:feature_library/src/ui/sidebar/sync_badge_indicator.dart';
import 'package:feature_library/src/ui/top_bar/library_search_field.dart';
import 'package:feature_library/src/ui/top_bar/selection_bar.dart';
import 'package:feature_library/src/ui/trash/trash_row.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:ui_kit/ui_kit.dart';

import '../support/fake_library_backend.dart';
import '../support/fixtures.dart';
import '../support/library_test_harness.dart';
import '../support/test_sizes.dart';

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  Future<SampleLibrary> seed(WidgetTester tester) async =>
      (await tester.runAsync(() => seedSampleLibrary(backend)))!;

  Future<LibraryTestHarness> pumpAt(
    WidgetTester tester, {
    Size size = TestSizes.ipad13Landscape,
    String? folderId,
    List<Override> overrides = const [],
  }) async {
    final h = LibraryTestHarness(
      backend,
      size: size,
      extraOverrides: overrides,
    );
    await h.pump(tester, folderId: folderId);
    await tester.pumpAndSettle();
    return h;
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));

  Future<void> showTrash(WidgetTester tester) async {
    containerOf(tester).read(librarySectionProvider(null).notifier).showTrash();
    await tester.pumpAndSettle();
  }

  Future<void> openNewMenu(WidgetTester tester) async {
    await tester.tap(find.text(LibraryStrings.newMenu));
    await tester.pumpAndSettle();
  }

  testWidgets('the grid starts with the folders: no dashed 새 노트 cell, and '
      '새로 만들기 › 새 노트 makes a note in this folder', (tester) async {
    final sample = await seed(tester);
    await pumpAt(tester, folderId: sample.math.id);
    expect(find.text(LibraryStrings.newNote), findsNothing);
    final first = tester.getTopLeft(find.byType(FolderTile).first);
    expect(
      find
          .byWidgetPredicate((w) => w is FolderTile || w is NoteTile)
          .evaluate()
          .map((e) => tester.getTopLeft(find.byWidget(e.widget)).dx),
      everyElement(greaterThanOrEqualTo(first.dx)),
    );
    await openNewMenu(tester);
    await tester.tap(
      find.widgetWithText(MenuItemButton, LibraryStrings.newNote),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NewNoteDialog), findsOneWidget);
  });

  testWidgets('the sidebar 폴더 header has no +; 새로 만들기 › 새 폴더 makes '
      'one in the current folder', (tester) async {
    final sample = await seed(tester);
    await pumpAt(tester, folderId: sample.math.id);
    final sidebar = find.byType(LibrarySidebar);
    expect(
      find.descendant(of: sidebar, matching: find.text(LibraryStrings.folders)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sidebar, matching: find.byIcon(Icons.add)),
      findsNothing,
    );
    expect(find.byTooltip(LibraryStrings.newFolder), findsNothing);
    await openNewMenu(tester);
    await tester.tap(
      find.widgetWithText(MenuItemButton, LibraryStrings.newFolder),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NewFolderDialog), findsOneWidget);
  });

  for (final size in [TestSizes.ipad13Landscape, TestSizes.compact]) {
    testWidgets('trash ($size): no search, no sort, no 선택, no 새로 만들기; a '
        'long press still selects', (tester) async {
      final sample = await seed(tester);
      await tester.runAsync(
        () =>
            backend.store.library.trashItems([NoteRef(sample.homeNotes[0].id)]),
      );
      await pumpAt(tester, size: size);
      // Outside the trash both are there.
      if (size == TestSizes.compact) {
        expect(find.byTooltip(LibraryStrings.search), findsOneWidget);
        expect(find.byTooltip(LibraryStrings.moreActions), findsOneWidget);
      } else {
        expect(find.byType(LibrarySearchField), findsOneWidget);
        expect(
          find.widgetWithText(TextButton, LibraryStrings.select),
          findsOneWidget,
        );
      }
      await showTrash(tester);
      expect(find.byType(LibrarySearchField), findsNothing);
      expect(find.byTooltip(LibraryStrings.search), findsNothing);
      expect(find.byTooltip(LibraryStrings.moreActions), findsNothing);
      expect(
        find.widgetWithText(TextButton, LibraryStrings.select),
        findsNothing,
      );
      expect(find.text(LibraryStrings.newMenu), findsNothing);
      expect(find.byTooltip(LibraryStrings.sort), findsNothing);
      await tester.longPress(find.byType(TrashRow).first);
      await tester.pumpAndSettle();
      expect(find.byType(SelectionBar), findsOneWidget);
    });
  }

  testWidgets('sync status: nothing while off; shown while on or with a '
      'problem', (tester) async {
    await pumpAt(tester);
    expect(find.text(LibraryStrings.syncOff), findsNothing);
    expect(find.byIcon(Icons.save_outlined), findsNothing);

    for (final (badge, label) in [
      (
        const SyncBadge(display: SyncDisplayState.done),
        LibraryStrings.syncDone,
      ),
      (
        const SyncBadge(display: SyncDisplayState.error),
        LibraryStrings.syncError,
      ),
    ]) {
      await tester.pumpWidget(const SizedBox());
      await pumpAt(
        tester,
        overrides: [
          syncBadgeProvider.overrideWith((ref) => Stream.value(badge)),
        ],
      );
      expect(
        find.descendant(
          of: find.byType(SyncBadgeIndicator),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('list rows: ★ only on favourites', (tester) async {
    final sample = await seed(tester);
    await tester.runAsync(
      () => backend.store.library.setFavorite([sample.homeNotes[1].id], true),
    );
    await pumpAt(tester);
    await tester.tap(find.byTooltip(LibraryStrings.viewAsList));
    await tester.pumpAndSettle();
    final rows = find.byType(NoteListRow);
    expect(rows, findsWidgets);
    expect(
      find.descendant(
        of: rows,
        matching: find.byIcon(AppIconKind.favorite.material),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: rows,
        matching: find.byIcon(AppIconKind.favoriteOn.material),
      ),
      findsOneWidget,
    );
  });

  testWidgets('새로 만들기 without the PDF slot: 새 노트 · 새 폴더 only', (tester) async {
    await seed(tester);
    await pumpAt(tester);
    await openNewMenu(tester);
    expect(find.byType(MenuItemButton), findsNWidgets(2));
    expect(find.text(LibraryStrings.importPdf), findsNothing);
    expect(find.text('준비 중'), findsNothing);
  });

  testWidgets('a note from a newer app: the words 새 버전 필요 on its cover', (
    tester,
  ) async {
    final sample = await seed(tester);
    await pumpAt(
      tester,
      overrides: [
        libraryListingProvider.overrideWith(
          (ref, query) => ref
              .watch(libraryRepositoryProvider)
              .watchListing(query)
              .map(
                (l) => LibraryListing(
                  folderId: l.folderId,
                  folders: l.folders,
                  notes: [
                    for (final n in l.notes)
                      n.id == sample.homeNotes[0].id
                          ? n.copyWith(schemaVersion: kNoteSchemaVersion + 1)
                          : n,
                  ],
                ),
              ),
        ),
      ],
    );
    expect(find.text(LibraryStrings.requiresNewerAppBadge), findsOneWidget);
    expect(find.byIcon(Icons.upgrade), findsNothing);
  });
}
