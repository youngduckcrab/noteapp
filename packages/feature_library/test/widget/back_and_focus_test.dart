// System back and keyboard focus on the library screen (m5-7/05-library 16,
// v2.13-nav). Back: drawer → selection mode → search → 최근 / 즐겨찾기 /
// 휴지통 → 홈, a folder → its parent (nested), only 홈 itself exits the app.
// Focus: moving to 홈 / a folder / 휴지통 / settings / a note (and back)
// never gives the search field the focus (no soft keyboard without a tap),
// even when the field had it before (Android's back hides the keyboard but
// leaves the field focused).
import 'package:feature_library/feature_library.dart' show LibraryScreen;
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/model/section.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/ui/content/note_tile.dart';
import 'package:feature_library/src/ui/sidebar/sidebar_rows.dart';
import 'package:feature_library/src/ui/top_bar/library_search_field.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';

import '../support/fake_library_backend.dart';
import '../support/fixtures.dart';
import '../support/library_test_harness.dart';
import '../support/test_sizes.dart';

final Finder searchEditable = find.descendant(
  of: find.byType(LibrarySearchField),
  matching: find.byType(EditableText),
);
Finder navRow(String label) => find.widgetWithText(SidebarNavRow, label);
Finder treeRow(String name) => find.widgetWithText(SidebarTreeRow, name);
Finder noteTile(String title) => find.widgetWithText(NoteTile, title);

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));

bool searchFieldFocused(WidgetTester tester) =>
    searchEditable.evaluate().isNotEmpty &&
    tester.widget<EditableText>(searchEditable).focusNode.hasFocus;

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  Future<SampleLibrary> seed(WidgetTester tester) async =>
      (await tester.runAsync(() => seedSampleLibrary(backend)))!;

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

  LibrarySection sectionOf(WidgetTester tester, LibraryTestHarness h) =>
      containerOf(tester).read(librarySectionProvider(h.currentFolderId));

  bool selecting(WidgetTester tester, LibraryTestHarness h) =>
      containerOf(tester)
          .read(librarySelectionProvider(h.currentFolderId))
          .active;

  group('system back', () {
    /// Platform channel calls; SystemNavigator.pop is the app exiting.
    late List<String> platformCalls;

    setUp(() => platformCalls = []);

    void interceptPlatform(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          platformCalls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    int exits() =>
        platformCalls.where((m) => m == 'SystemNavigator.pop').length;

    Future<void> back(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    testWidgets('홈 exits the app', (tester) async {
      await seed(tester);
      await pumpAt(tester);
      interceptPlatform(tester);
      await back(tester);
      expect(exits(), 1);
    });

    testWidgets('nested folders go to the parent, a top-level one to 홈', (
      tester,
    ) async {
      final sample = await seed(tester);
      final h = await pumpAt(tester, folderId: sample.deepest.id);
      interceptPlatform(tester);

      final [calculus, limits, deepest] = sample.nested;
      expect(h.currentFolderId, deepest.id);
      await back(tester);
      expect(h.currentFolderId, limits.id);
      await back(tester);
      expect(h.currentFolderId, calculus.id);
      await back(tester);
      expect(h.currentFolderId, sample.math.id);
      await back(tester);
      expect(h.currentFolderId, isNull);
      expect(sectionOf(tester, h), const FolderSection(null));
      expect(exits(), 0);
      expect(h.log.entries, [
        'folder:${limits.id}',
        'folder:${calculus.id}',
        'folder:${sample.math.id}',
        'folder:home',
      ]);

      await back(tester);
      expect(exits(), 1);
    });

    testWidgets('a folder just opened from 홈 goes back to 홈', (tester) async {
      final sample = await seed(tester);
      final h = await pumpAt(tester);
      interceptPlatform(tester);
      await tester.tap(treeRow('수학'));
      await tester.pumpAndSettle();
      expect(h.currentFolderId, sample.math.id);

      await back(tester);
      expect(h.currentFolderId, isNull);
      expect(exits(), 0);
    });

    testWidgets('a folder missing from the tree goes back to 홈', (
      tester,
    ) async {
      await seed(tester);
      final h = await pumpAt(tester, folderId: 'no-such-folder');
      interceptPlatform(tester);
      await back(tester);
      expect(h.currentFolderId, isNull);
      expect(exits(), 0);
    });

    for (final (label, section) in const [
      (LibraryStrings.trash, TrashSection()),
      (LibraryStrings.recent, RecentSection()),
      (LibraryStrings.favorites, FavoritesSection()),
    ]) {
      testWidgets('$label goes back to 홈 (from 홈 and from a folder)', (
        tester,
      ) async {
        final sample = await seed(tester);
        final h = await pumpAt(tester);
        interceptPlatform(tester);

        await tester.tap(navRow(label));
        await tester.pumpAndSettle();
        expect(sectionOf(tester, h), section);
        await back(tester);
        expect(sectionOf(tester, h), const FolderSection(null));
        expect(h.currentFolderId, isNull);
        expect(exits(), 0);

        await h.goToFolder(tester, sample.math.id);
        await tester.pumpAndSettle();
        await tester.tap(navRow(label));
        await tester.pumpAndSettle();
        expect(sectionOf(tester, h), section);
        await back(tester);
        expect(h.currentFolderId, isNull);
        expect(sectionOf(tester, h), const FolderSection(null));
        expect(exits(), 0);
      });
    }

    testWidgets('a search closes first, back to where it started', (
      tester,
    ) async {
      final sample = await seed(tester);
      final h = await pumpAt(tester, folderId: sample.math.id);
      interceptPlatform(tester);
      await tester.tap(searchEditable);
      await tester.enterText(searchEditable, '극한');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(sectionOf(tester, h), isA<SearchSection>());

      await back(tester);
      expect(sectionOf(tester, h), FolderSection(sample.math.id));
      expect(h.currentFolderId, sample.math.id);
      expect(searchFieldFocused(tester), isFalse);
      expect(tester.testTextInput.isVisible, isFalse);

      // A search at 홈: back closes it, the next back exits.
      await back(tester); // → 홈
      await tester.tap(searchEditable);
      await tester.enterText(searchEditable, '극한');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await back(tester);
      expect(sectionOf(tester, h), const FolderSection(null));
      expect(exits(), 0);
      await back(tester);
      expect(exits(), 1);
    });

    testWidgets('the compact search bar closes first (even empty)', (
      tester,
    ) async {
      await seed(tester);
      final h = await pumpAt(tester, size: TestSizes.compact);
      interceptPlatform(tester);
      await tester.tap(find.byTooltip(LibraryStrings.search));
      await tester.pumpAndSettle();
      expect(find.byType(LibrarySearchField), findsOneWidget);

      await back(tester);
      expect(find.byType(LibrarySearchField), findsNothing);
      expect(sectionOf(tester, h), const FolderSection(null));
      expect(exits(), 0);
      await back(tester);
      expect(exits(), 1);
    });

    testWidgets('selection mode ends first', (tester) async {
      final sample = await seed(tester);
      final h = await pumpAt(tester, folderId: sample.math.id);
      interceptPlatform(tester);
      await tester.tap(find.text(LibraryStrings.select));
      await tester.pumpAndSettle();
      expect(selecting(tester, h), isTrue);

      await back(tester);
      expect(selecting(tester, h), isFalse);
      expect(h.currentFolderId, sample.math.id);
      await back(tester);
      expect(h.currentFolderId, isNull);

      // At 홈 too: selection ends, then the app exits.
      await tester.tap(find.text(LibraryStrings.select));
      await tester.pumpAndSettle();
      await back(tester);
      expect(selecting(tester, h), isFalse);
      expect(exits(), 0);
      await back(tester);
      expect(exits(), 1);
    });

    testWidgets('an open drawer closes first', (tester) async {
      final sample = await seed(tester);
      final h = await pumpAt(
        tester,
        size: TestSizes.ipad11Portrait,
        folderId: sample.math.id,
      );
      interceptPlatform(tester);
      await tester.tap(find.byTooltip(LibraryStrings.openMenu));
      await tester.pumpAndSettle();
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
      expect(scaffold.isDrawerOpen, isTrue);

      await back(tester);
      expect(scaffold.isDrawerOpen, isFalse);
      expect(h.currentFolderId, sample.math.id);
      await back(tester);
      expect(h.currentFolderId, isNull);

      // At 홈 the drawer closes too before the app exits.
      await tester.tap(find.byTooltip(LibraryStrings.openMenu));
      await tester.pumpAndSettle();
      await back(tester);
      expect(scaffold.isDrawerOpen, isFalse);
      expect(exits(), 0);
      await back(tester);
      expect(exits(), 1);
    });
  });

  group('search field focus', () {
    /// The user typed in the field, then Android's back hid the keyboard: the
    /// field still has the focus.
    Future<void> focusThenHideKeyboard(WidgetTester tester) async {
      await tester.tap(searchEditable);
      await tester.pump();
      expect(searchFieldFocused(tester), isTrue);
      tester.testTextInput.hide();
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);
    }

    void expectNoFocus(WidgetTester tester, String reason) {
      expect(searchFieldFocused(tester), isFalse, reason: reason);
      expect(tester.testTextInput.isVisible, isFalse, reason: reason);
    }

    for (final size in [TestSizes.ipad13Landscape, TestSizes.ipad11Portrait]) {
      final drawer = size == TestSizes.ipad11Portrait;
      testWidgets('홈 / folder / 휴지통 / 최근 never focus the field '
          '(${drawer ? 'drawer' : 'pinned sidebar'})', (tester) async {
        await seed(tester);
        await pumpAt(tester, size: size);
        expectNoFocus(tester, 'start');

        Future<void> go(Finder row, String reason) async {
          if (drawer) {
            await tester.tap(find.byTooltip(LibraryStrings.openMenu));
            await tester.pumpAndSettle();
          }
          await tester.tap(row.last);
          await tester.pumpAndSettle();
          expectNoFocus(tester, reason);
        }

        // Without the field ever focused.
        await go(navRow(LibraryStrings.trash), 'trash');
        await go(navRow(LibraryStrings.home), 'home');
        await go(treeRow('수학'), 'folder');
        await go(navRow(LibraryStrings.recent), 'recent');
        await go(navRow(LibraryStrings.home), 'home again');

        // After the field had the focus (keyboard hidden by back).
        for (final (row, reason) in [
          (navRow(LibraryStrings.trash), 'trash after typing'),
          (navRow(LibraryStrings.home), 'home after typing'),
          (treeRow('수학'), 'folder after typing'),
          (navRow(LibraryStrings.favorites), 'favorites after typing'),
          (navRow(LibraryStrings.home), 'home after typing 2'),
        ]) {
          await focusThenHideKeyboard(tester);
          await go(row, reason);
        }
      });
    }

    testWidgets('a drawer opened by an edge swipe does not hand the focus '
        'back when it closes', (tester) async {
      await seed(tester);
      await pumpAt(tester, size: TestSizes.ipad11Portrait);
      await focusThenHideKeyboard(tester);
      await tester.dragFrom(const Offset(2, 500), const Offset(300, 0));
      await tester.pumpAndSettle();
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
      expect(scaffold.isDrawerOpen, isTrue);
      scaffold.closeDrawer();

      await tester.pumpAndSettle();
      expectNoFocus(tester, 'drawer closed');
    });

    testWidgets('coming back from a note or settings does not focus it', (
      tester,
    ) async {
      await seed(tester);
      final h = await pumpAt(tester);
      final navigator = Navigator.of(
        tester.element(find.byType(LibraryScreen)),
      );
      Future<void> pushAndPop() async {
        navigator.push<void>(
          MaterialPageRoute<void>(builder: (_) => const Scaffold()),
        );
        await tester.pumpAndSettle();
        navigator.pop();
        await tester.pumpAndSettle();
      }

      await focusThenHideKeyboard(tester);
      await tester.tap(noteTile('회의록'));
      await tester.pumpAndSettle();
      expect(h.log.entries.last, startsWith('note:'));
      await pushAndPop();
      expectNoFocus(tester, 'back from the note');

      await focusThenHideKeyboard(tester);
      await tester.tap(find.byTooltip(LibraryStrings.settings));
      await tester.pumpAndSettle();
      expect(h.log.entries.last, 'settings');
      await pushAndPop();
      expectNoFocus(tester, 'back from settings');
    });

    testWidgets('a tap on the field still focuses it and opens the keyboard', (
      tester,
    ) async {
      await seed(tester);
      await pumpAt(tester);
      await tester.tap(searchEditable);
      await tester.pump();
      expect(searchFieldFocused(tester), isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });
  });
}
