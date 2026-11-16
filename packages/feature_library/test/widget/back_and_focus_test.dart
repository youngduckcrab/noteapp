// System back and keyboard focus on the library screen (m5-7/05-library 16,
// v2.13-nav). Back: drawer → selection mode → search → 최근 / 즐겨찾기 /
// 휴지통 → 홈, a folder → its parent (nested), only 홈 itself exits the app.
// Focus: moving to 홈 / a folder / 휴지통 / settings / a note (and back)
// never gives the search field the focus (no soft keyboard without a tap),
// even when the field had it before (Android's back hides the keyboard but
// leaves the field focused).
import 'dart:async' show StreamController;

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
        // (v2.14-ui) The trash has no search field: it comes last.
        for (final (row, reason) in [
          (treeRow('수학'), 'folder after typing'),
          (navRow(LibraryStrings.favorites), 'favorites after typing'),
          (navRow(LibraryStrings.home), 'home after typing'),
          (navRow(LibraryStrings.trash), 'trash after typing'),
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

  // (review fixes) Each test below failed before its fix.
  group('review fixes', () {
    late List<String> platformCalls;

    setUp(() => platformCalls = []);

    void interceptPlatform(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          platformCalls.add('${call.method}:${call.arguments}');
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
        platformCalls.where((m) => m.startsWith('SystemNavigator.pop')).length;

    Future<void> back(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    void expectNoFocus(WidgetTester tester, String reason) {
      expect(searchFieldFocused(tester), isFalse, reason: reason);
      expect(tester.testTextInput.isVisible, isFalse, reason: reason);
    }

    /// The user taps the field, the soft keyboard slides up (bottom inset),
    /// then Android's back hides it (the inset goes back to 0).
    Future<void> typeThenKeyboardDown(WidgetTester tester) async {
      addTearDown(tester.view.resetViewInsets);
      await tester.tap(searchEditable);
      await tester.pump();
      expect(searchFieldFocused(tester), isTrue);
      tester.view.viewInsets = const FakeViewPadding(bottom: 600);
      await tester.pump();
      expect(searchFieldFocused(tester), isTrue, reason: 'keyboard up');
      tester.testTextInput.hide();
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
    }

    testWidgets('the keyboard going down lets go of the field: a menu or '
        'dialog closing never hands the focus back', (tester) async {
      await seed(tester);
      await pumpAt(tester);
      await typeThenKeyboardDown(tester);
      expectNoFocus(tester, 'keyboard hidden');

      // 새로 만들기 menu opened and closed.
      await tester.tap(find.text(LibraryStrings.newMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text(LibraryStrings.newMenu));
      await tester.pumpAndSettle();
      expectNoFocus(tester, 'menu closed');

      // 새로 만들기 → 새 폴더 → 취소.
      await typeThenKeyboardDown(tester);
      await tester.tap(find.text(LibraryStrings.newMenu));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(MenuItemButton, LibraryStrings.newFolder),
      );
      await tester.pumpAndSettle();
      tester.testTextInput.hide();
      await tester.tap(find.text(LibraryStrings.cancel).last);
      await tester.pumpAndSettle();
      expectNoFocus(tester, 'dialog cancelled');

      // The app going to the background and back (notification shade).
      await typeThenKeyboardDown(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expectNoFocus(tester, 'resumed');
    });

    testWidgets('compact: the end of selection mode does not focus the '
        'search bar again', (tester) async {
      await seed(tester);
      final h = await pumpAt(tester, size: TestSizes.compact);
      await tester.tap(find.byTooltip(LibraryStrings.search));
      await tester.pumpAndSettle();
      expect(searchFieldFocused(tester), isTrue, reason: 'icon pressed');
      await tester.enterText(searchEditable, '극한');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      tester.testTextInput.hide();
      await tester.pumpAndSettle();

      final selection = containerOf(tester)
          .read(librarySelectionProvider(h.currentFolderId).notifier);
      selection.begin();
      await tester.pumpAndSettle();
      selection.end();
      await tester.pumpAndSettle();
      expect(find.byType(LibrarySearchField), findsOneWidget);
      expectNoFocus(tester, 'selection ended');
    });

    testWidgets('compact: leaving the search during selection mode closes '
        'the search bar', (tester) async {
      await seed(tester);
      final h = await pumpAt(tester, size: TestSizes.compact);
      await tester.tap(find.byTooltip(LibraryStrings.search));
      await tester.pumpAndSettle();
      await tester.enterText(searchEditable, '극한');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      final container = containerOf(tester);
      final selection = container.read(
        librarySelectionProvider(h.currentFolderId).notifier,
      );
      selection.begin();
      await tester.pumpAndSettle();
      container
          .read(librarySectionProvider(h.currentFolderId).notifier)
          .showTrash();
      await tester.pumpAndSettle();
      selection.end();
      await tester.pumpAndSettle();
      expect(sectionOf(tester, h), const TrashSection());
      expect(find.byType(LibrarySearchField), findsNothing);
      // (v2.14-ui) The trash has no search icon either.
      expect(find.byTooltip(LibraryStrings.search), findsNothing);
    });

    testWidgets('back before the folder tree loads waits for it, then goes '
        'to the parent', (tester) async {
      final sample = await seed(tester);
      final tree = (await tester.runAsync(
        () => backend.store.library.watchFolderTree().first,
      ))!;
      final trees = StreamController<FolderTree>();
      addTearDown(trees.close);
      final h = LibraryTestHarness(
        backend,
        extraOverrides: [
          folderTreeProvider.overrideWith((ref) => trees.stream),
        ],
      );
      await h.pump(tester, folderId: sample.deepest.id);
      await tester.pump();
      interceptPlatform(tester);

      await back(tester);
      expect(h.currentFolderId, sample.deepest.id, reason: 'still loading');
      expect(exits(), 0);

      trees.add(tree);
      await tester.pumpAndSettle();
      expect(h.currentFolderId, sample.nested[1].id);
      expect(exits(), 0);
    });

    for (final size in [TestSizes.ipad13Landscape, TestSizes.ipad11Portrait]) {
      testWidgets('홈: a focused or typed-in search field takes the back '
          'first (${size.width.toInt()} wide)', (tester) async {
        await seed(tester);
        final h = await pumpAt(tester, size: size);
        interceptPlatform(tester);

        // Focused and empty (a hardware or floating keyboard: no inset).
        await tester.tap(searchEditable);
        await tester.pump();
        await back(tester);
        expect(exits(), 0);
        expectNoFocus(tester, 'focused field');

        // Typed, the search not applied yet (debounce pending).
        await tester.tap(searchEditable);
        await tester.pump();
        tester.testTextInput.enterText('극');
        await tester.pump();
        expect(sectionOf(tester, h), const FolderSection(null));
        await back(tester);
        expect(exits(), 0);
        expectNoFocus(tester, 'typed field');
        expect(
          tester.widget<EditableText>(searchEditable).controller.text,
          isEmpty,
        );
        expect(sectionOf(tester, h), const FolderSection(null));

        await back(tester);
        expect(exits(), 1);
      });
    }

    group('Android 14+ predictive back (setFrameworkHandlesBack)', () {
      bool? handlesBack() {
        final calls = platformCalls
            .where(
              (c) => c.startsWith('SystemNavigator.setFrameworkHandlesBack'),
            )
            .toList();
        if (calls.isEmpty) return null;
        return calls.last.endsWith(':true');
      }

      testWidgets('a folder / 휴지통 / the drawer at 홈 handle back; 홈 '
          'itself does not', (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await seed(tester);
        interceptPlatform(tester);
        final h = await pumpAt(tester, size: TestSizes.ipad11Portrait);
        expect(handlesBack(), isNot(isTrue), reason: '홈');

        // The drawer open at 홈: back must close it, not exit.
        await tester.tap(find.byTooltip(LibraryStrings.openMenu));
        await tester.pumpAndSettle();
        expect(handlesBack(), isTrue, reason: 'drawer at 홈');
        await back(tester);
        expect(handlesBack(), isFalse, reason: 'drawer closed at 홈');
        expect(exits(), 0);

        await h.goToFolder(tester, 'no-such-folder');
        await tester.pumpAndSettle();
        expect(handlesBack(), isTrue, reason: 'folder');
        await back(tester);
        expect(h.currentFolderId, isNull);
        expect(handlesBack(), isFalse, reason: 'back at 홈');

        await tester.tap(find.byTooltip(LibraryStrings.openMenu));
        await tester.pumpAndSettle();
        await tester.tap(navRow(LibraryStrings.trash).last);
        await tester.pumpAndSettle();
        expect(handlesBack(), isTrue, reason: '휴지통');
        await back(tester);
        expect(handlesBack(), isFalse, reason: '홈 again');
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));
    });
  });
}
