// Title search (05-library 6.14, 8 L17): the top bar field (300 ms debounce,
// Enter at once, the clear button and an empty value go back, the field is
// cleared when the section stops being a search, Hangul being composed
// counts), the results view (groups with locations, empty groups hidden, the
// view setting, the truncated hint, the highlighted match), opening results,
// asking again after an action on a result, and the compact search bar.
import 'package:feature_library/feature_library.dart' show LibraryScreen;
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/model/section.dart';
import 'package:feature_library/src/settings/library_settings_keys.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/ui/content/item_list.dart';
import 'package:feature_library/src/ui/content/note_tile.dart';
import 'package:feature_library/src/ui/content/search_results_view.dart';
import 'package:feature_library/src/ui/sidebar/sidebar_rows.dart';
import 'package:feature_library/src/ui/top_bar/breadcrumb_bar.dart';
import 'package:feature_library/src/ui/top_bar/library_search_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';

import '../support/fake_library_backend.dart';
import '../support/fixtures.dart';
import '../support/library_test_harness.dart';
import '../support/test_sizes.dart';

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));

final Finder searchInput = find.descendant(
  of: find.byType(LibrarySearchField),
  matching: find.byType(TextField),
);

String searchText(WidgetTester tester) =>
    tester.widget<TextField>(searchInput).controller!.text;

Finder noteTile(String title) => find.widgetWithText(NoteTile, title);
Finder folderRow(String name) => find.widgetWithText(FolderListRow, name);

/// The parts of [title] drawn bold (w700) inside [of], with their colors.
List<(String, Color?)> boldParts(WidgetTester tester, Finder of, String title) {
  final text = tester
      .widgetList<Text>(find.descendant(of: of, matching: find.byType(Text)))
      .singleWhere((t) => t.textSpan?.toPlainText() == title);
  final parts = <(String, Color?)>[];
  text.textSpan!.visitChildren((span) {
    if (span is TextSpan && span.style?.fontWeight == FontWeight.w700) {
      parts.add((span.text!, span.style!.color));
    }
    return true;
  });
  return parts;
}

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
    Size size = TestSizes.ipad13Landscape,
    FolderId? folderId,
  }) async {
    final h = LibraryTestHarness(backend, size: size);
    await h.pump(tester, folderId: folderId);
    await tester.pumpAndSettle();
    return h;
  }

  int searches(String query) => backend.queries
      .where((q) => q == "searchLibrary '$query' limit:50")
      .length;

  int allSearches() =>
      backend.queries.where((q) => q.startsWith('searchLibrary')).length;

  LibrarySection sectionOf(WidgetTester tester, LibraryTestHarness h) =>
      containerOf(tester).read(librarySectionProvider(h.currentFolderId));

  /// Types [text] and waits for the debounce and the results.
  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(searchInput, text);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  group('input', () {
    testWidgets('no query 299 ms after the last change; one at 300 ms', (
      tester,
    ) async {
      await seed(tester);
      final h = await pumpAt(tester);
      await tester.enterText(searchInput, '수');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(searchInput, '수학');
      await tester.pump(const Duration(milliseconds: 299));
      expect(allSearches(), 0);
      expect(sectionOf(tester, h), const FolderSection(null));

      await tester.pump(const Duration(milliseconds: 1));
      expect(
        sectionOf(tester, h),
        const SearchSection('수학', returnTo: FolderSection(null)),
      );
      await tester.pumpAndSettle();
      expect(searches('수학'), 1);
      expect(allSearches(), 1);
      expect(find.text(LibraryStrings.searchResultsTitle('수학')), findsOne);
      expect(find.byType(SearchResultsView), findsOneWidget);
    });

    testWidgets('Enter searches at once (trimmed)', (tester) async {
      await seed(tester);
      final h = await pumpAt(tester);
      await tester.enterText(searchInput, ' 극한 ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(
        sectionOf(tester, h),
        const SearchSection('극한', returnTo: FolderSection(null)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(searches('극한'), 1);
      expect(allSearches(), 1);
    });

    testWidgets('an empty value goes back to the section before the search', (
      tester,
    ) async {
      final sample = await seed(tester);
      final h = await pumpAt(tester, folderId: sample.math.id);
      await search(tester, '극한');
      expect(find.byType(BreadcrumbBar), findsNothing);

      await tester.enterText(searchInput, '  ');
      await tester.pump(const Duration(milliseconds: 299));
      expect(sectionOf(tester, h), isA<SearchSection>());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(sectionOf(tester, h), FolderSection(sample.math.id));
      expect(find.byType(BreadcrumbBar), findsOneWidget);
      expect(find.byType(SearchResultsView), findsNothing);
      expect(searchText(tester), isEmpty);
    });

    testWidgets('the clear button goes back at once and empties the field', (
      tester,
    ) async {
      await seed(tester);
      final h = await pumpAt(tester);
      expect(find.byTooltip(LibraryStrings.clearSearch), findsNothing);
      await search(tester, '극한');
      await tester.tap(find.byTooltip(LibraryStrings.clearSearch));
      await tester.pump();
      expect(sectionOf(tester, h), const FolderSection(null));
      expect(searchText(tester), isEmpty);
      await tester.pumpAndSettle();
      expect(find.byTooltip(LibraryStrings.clearSearch), findsNothing);
      expect(find.byType(SearchResultsView), findsNothing);
    });

    testWidgets('a section change clears the field and a pending search', (
      tester,
    ) async {
      await seed(tester);
      final h = await pumpAt(tester);
      await search(tester, '극한');
      await tester.tap(
        find.widgetWithText(SidebarNavRow, LibraryStrings.recent),
      );
      await tester.pumpAndSettle();
      expect(sectionOf(tester, h), const RecentSection());
      expect(searchText(tester), isEmpty);

      // Typed, then 즐겨찾기 before the debounce: no search at all.
      await tester.enterText(searchInput, '일기');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.widgetWithText(SidebarNavRow, LibraryStrings.favorites),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(sectionOf(tester, h), const FavoritesSection());
      expect(searchText(tester), isEmpty);
      expect(searches('일기'), 0);
    });

    testWidgets('Hangul being composed is part of the query', (tester) async {
      await seed(tester);
      final h = await pumpAt(tester);
      await tester.showKeyboard(searchInput);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '일기',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 1, end: 2),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(
        sectionOf(tester, h),
        const SearchSection('일기', returnTo: FolderSection(null)),
      );
      expect(searches('일기'), 1);
      expect(noteTile('일기'), findsOneWidget);
    });

    testWidgets('expanded: 240 wide, hint 노트 검색 (v2)', (tester) async {
      await pumpAt(tester);
      expect(tester.getSize(find.byType(LibrarySearchField)).width, 240);
      expect(
        tester.widget<TextField>(searchInput).decoration!.hintText,
        LibraryStrings.searchHint,
      );
    });

    testWidgets('medium: 200 wide', (tester) async {
      await pumpAt(tester, size: TestSizes.ipad13Portrait);
      expect(tester.getSize(find.byType(LibrarySearchField)).width, 200);
    });
  });

  group('results', () {
    testWidgets('groups with locations; the whole library is searched', (
      tester,
    ) async {
      final sample = await seed(tester);
      await pumpAt(tester, folderId: sample.english.id);
      await search(tester, '극한');
      expect(find.text(LibraryStrings.searchFolderGroup(1)), findsOneWidget);
      expect(find.text(LibraryStrings.searchNoteGroup(1)), findsOneWidget);
      // 극한 is in 홈 › 수학 › 미적분; 극한 정리 four folders deep.
      expect(
        find.descendant(
          of: folderRow('극한'),
          matching: find.text('홈 › 수학 › 미적분'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: noteTile('극한 정리'),
          matching: find.text('홈 › … › 극한 › 연습 문제'),
        ),
        findsOneWidget,
      );
      // Group order: folders above notes.
      expect(
        tester.getTopLeft(folderRow('극한')).dy,
        lessThan(tester.getTopLeft(noteTile('극한 정리')).dy),
      );
      expect(find.text(LibraryStrings.searchTruncated), findsNothing);
    });

    testWidgets('an empty group is not shown; notes follow the list view', (
      tester,
    ) async {
      await seed(tester);
      await real(
        tester,
        () => backend.store.settings.set(LibrarySettingsKeys.viewMode, 'list'),
      );
      await pumpAt(tester);
      await search(tester, '기');
      // 독서 기록, 일기 — no folder matches.
      expect(find.byType(SearchGroupHeader), findsOneWidget);
      expect(find.text(LibraryStrings.searchNoteGroup(2)), findsOneWidget);
      expect(find.byType(NoteTile), findsNothing);
      expect(find.byType(NoteListRow), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.widgetWithText(NoteListRow, '일기'),
          matching: find.text(LibraryStrings.home),
        ),
        findsOneWidget,
      );
    });

    testWidgets('nothing found → the empty state', (tester) async {
      await seed(tester);
      await pumpAt(tester);
      await search(tester, '없는 제목');
      expect(find.text(LibraryStrings.emptySearch('없는 제목')), findsOneWidget);
      expect(find.byType(SearchResultsView), findsNothing);
    });

    testWidgets('50 hits (the limit) → the hint at the bottom', (tester) async {
      await real(tester, () async {
        for (var i = 1; i <= 50; i++) {
          await backend.seedNote('노트 $i');
        }
      });
      await pumpAt(tester);
      final results = find.descendant(
        of: find.byType(SearchResultsView),
        matching: find.byType(Scrollable),
      );
      await search(tester, '노트 1');
      // 노트 1, 노트 10 … 19: 11 hits, under the limit.
      expect(find.text(LibraryStrings.searchNoteGroup(11)), findsOneWidget);
      await tester.drag(results, const Offset(0, -5000));
      await tester.pumpAndSettle();
      expect(find.text(LibraryStrings.searchTruncated), findsNothing);

      await search(tester, '노트');
      expect(find.text(LibraryStrings.searchNoteGroup(50)), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(LibraryStrings.searchTruncated),
        500,
        scrollable: results,
      );
      expect(find.text(LibraryStrings.searchTruncated), findsOneWidget);
    });

    testWidgets('the match is bold in the primary color, case-insensitive', (
      tester,
    ) async {
      await seed(tester);
      await real(tester, () => backend.seedNote('Math 정리'));
      await pumpAt(tester);
      await search(tester, '정리');
      final primary = Theme.of(tester.element(find.byType(SearchResultsView)))
          .colorScheme
          .primary;
      expect(boldParts(tester, noteTile('극한 정리'), '극한 정리'), [('정리', primary)]);

      await search(tester, 'math');
      expect(boldParts(tester, noteTile('Math 정리'), 'Math 정리'), [
        ('Math', primary),
      ]);

      await search(tester, '극한');
      expect(boldParts(tester, folderRow('극한'), '극한'), [('극한', primary)]);
    });

    testWidgets('a title CORE matches only after normalizing: no highlight', (
      tester,
    ) async {
      // '수학 정리' with decomposed Hangul (NFD); the query is composed.
      const nfd = '\u1109\u116e\u1112\u1161\u11a8 정리';
      await real(tester, () => backend.seedNote(nfd));
      await pumpAt(tester);
      await search(tester, '수학');
      expect(find.byType(NoteTile), findsOneWidget);
      expect(boldParts(tester, find.byType(NoteTile), nfd), isEmpty);
    });

    testWidgets('a folder result opens with onOpenFolder; the field empties', (
      tester,
    ) async {
      final sample = await seed(tester);
      final h = await pumpAt(tester);
      await search(tester, '극한');
      await tester.tap(folderRow('극한'));
      await tester.pumpAndSettle();
      final limit = sample.nested[1];
      expect(h.log.entries, ['folder:${limit.id}']);
      expect(h.currentFolderId, limit.id);
      expect(sectionOf(tester, h), FolderSection(limit.id));
      expect(searchText(tester), isEmpty);
      expect(find.byType(BreadcrumbBar), findsOneWidget);
    });

    testWidgets('a note result opens with onOpenNote only', (tester) async {
      final sample = await seed(tester);
      final h = await pumpAt(tester);
      await search(tester, '극한');
      await tester.tap(noteTile('극한 정리'));
      await tester.pumpAndSettle();
      expect(h.log.entries, ['note:${sample.deepNote.id}']);
      expect(backend.calls, isEmpty);
    });

    testWidgets('renaming or trashing a result asks CORE again', (
      tester,
    ) async {
      await seed(tester);
      await pumpAt(tester);
      await search(tester, '극한');
      expect(searches('극한'), 1);

      await tester.tap(find.byTooltip(LibraryStrings.itemMenu('극한 정리')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(MenuItemButton, LibraryStrings.rename),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        ),
        '극한 요약',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, LibraryStrings.save));
      await tester.pumpAndSettle();
      expect(searches('극한'), 2);
      expect(noteTile('극한 요약'), findsOneWidget);
      expect(noteTile('극한 정리'), findsNothing);

      await tester.tap(find.byTooltip(LibraryStrings.itemMenu('극한')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(MenuItemButton, LibraryStrings.moveToTrash),
      );
      await tester.pumpAndSettle();
      expect(searches('극한'), 3);
      // The folder and the note inside it went to the trash together.
      expect(find.byType(SearchResultsView), findsNothing);
      expect(find.text(LibraryStrings.emptySearch('극한')), findsOneWidget);
    });

    testWidgets('a new note while searching goes to 홈', (tester) async {
      final sample = await seed(tester);
      await pumpAt(tester, folderId: sample.math.id);
      await search(tester, '극한');
      await tester.tap(find.text(LibraryStrings.newMenu));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(MenuItemButton, LibraryStrings.newNote),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, LibraryStrings.create),
      );
      await tester.pumpAndSettle();
      expect(backend.calls.single, startsWith('createNote home '));
    });
  });

  group('compact', () {
    testWidgets('the search icon turns the bar into the field; ← closes it', (
      tester,
    ) async {
      await seed(tester);
      final h = await pumpAt(tester, size: TestSizes.compact);
      expect(find.byType(LibrarySearchField), findsNothing);
      await tester.tap(find.byTooltip(LibraryStrings.search));
      await tester.pumpAndSettle();
      expect(find.byType(LibrarySearchField), findsOneWidget);
      expect(find.byTooltip(LibraryStrings.openMenu), findsNothing);
      expect(tester.takeException(), isNull);

      await search(tester, '극한');
      expect(find.byType(SearchResultsView), findsOneWidget);
      // Clearing keeps the bar a search field.
      await tester.tap(find.byTooltip(LibraryStrings.clearSearch));
      await tester.pumpAndSettle();
      expect(sectionOf(tester, h), const FolderSection(null));
      expect(find.byType(LibrarySearchField), findsOneWidget);

      await search(tester, '극한');
      await tester.tap(find.byTooltip(LibraryStrings.closeSearch));
      await tester.pumpAndSettle();
      expect(sectionOf(tester, h), const FolderSection(null));
      expect(find.byType(LibrarySearchField), findsNothing);
      expect(find.byTooltip(LibraryStrings.openMenu), findsOneWidget);
      expect(find.byType(BreadcrumbBar), findsOneWidget);
    });
  });
}
