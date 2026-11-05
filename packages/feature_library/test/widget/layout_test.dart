// Layout shell (05-library 6.1 / 6.2, 8 L8): no overflow at the 8 test sizes,
// the sidebar is pinned only at width >= 1100, ☰ opens the drawer below that,
// and the sidebar toggle of the expanded class is saved.
import 'package:feature_library/feature_library.dart' show LibraryScreen;
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/model/section.dart';
import 'package:feature_library/src/settings/library_settings_keys.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/ui/layout/library_metrics.dart';
import 'package:feature_library/src/ui/sidebar/library_sidebar.dart';
import 'package:feature_library/src/ui/top_bar/library_top_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_library_backend.dart';
import '../support/fixtures.dart';
import '../support/library_test_harness.dart';
import '../support/pump_library.dart';
import '../support/test_sizes.dart';

/// The sidebar pinned in the body (not the one inside the drawer).
final Finder pinnedSidebar = find.byWidgetPredicate(
  (w) => w is LibrarySidebar && !w.inDrawer,
);
final Finder drawerSidebar = find.byWidgetPredicate(
  (w) => w is LibrarySidebar && w.inDrawer,
);

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(LibraryTopBar)));

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  Future<LibraryTestHarness> pumpAt(
    WidgetTester tester,
    Size size, {
    String? folderId,
  }) async {
    final h = LibraryTestHarness(backend, size: size);
    await h.pump(tester, folderId: folderId);
    await tester.pumpAndSettle();
    return h;
  }

  for (final size in TestSizes.all) {
    final pinned = size.width >= LibraryMetrics.expandedBreakpoint;
    testWidgets(
      '${size.width.toInt()} × ${size.height.toInt()}: no overflow, sidebar '
      '${pinned ? 'pinned' : 'in the drawer'}',
      (tester) async {
        await tester.runAsync(() => seedSampleLibrary(backend));
        await pumpAt(tester, size);
        expect(tester.takeException(), isNull);
        expect(find.byType(LibraryTopBar), findsOneWidget);
        expect(pinnedSidebar, pinned ? findsOneWidget : findsNothing);
        expect(drawerSidebar, findsNothing);
        if (pinned) {
          expect(tester.getSize(pinnedSidebar).width, 280);
          expect(find.byTooltip(LibraryStrings.hideSidebar), findsOneWidget);
          expect(find.byTooltip(LibraryStrings.openMenu), findsNothing);
          // Content pane = screen − 281.
          expect(
            tester.getSize(find.byType(LibraryTopBar)).width,
            size.width - 281,
          );
        } else {
          expect(find.byTooltip(LibraryStrings.openMenu), findsOneWidget);
          expect(tester.getSize(find.byType(LibraryTopBar)).width, size.width);
          // The drawer opens and lays out without overflow too.
          await tester.tap(find.byTooltip(LibraryStrings.openMenu));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(drawerSidebar, findsOneWidget);
        }

        // Every section body lays out at this size as well.
        final section = containerOf(tester)
            .read(librarySectionProvider(null).notifier);
        for (final show in <void Function()>[
          section.showRecent,
          section.showFavorites,
          section.showTrash,
          () => section.search('극한'),
          section.showRouteFolder,
        ]) {
          show();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('13" portrait: ☰ opens the 320 wide drawer, settings closes it', (
    tester,
  ) async {
    final h = await pumpAt(tester, TestSizes.ipad13Portrait);
    expect(find.byType(Drawer), findsNothing);
    await tester.tap(find.byTooltip(LibraryStrings.openMenu));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(tester.getSize(find.byType(Drawer)).width, 320);
    expect(drawerSidebar, findsOneWidget);

    await tester.tap(find.byTooltip(LibraryStrings.settings));
    await tester.pumpAndSettle();
    expect(h.log.entries, ['settings']);
    expect(find.byType(Drawer), findsNothing);
  });

  testWidgets('phone width: the drawer too', (tester) async {
    await pumpAt(tester, TestSizes.compact);
    expect(pinnedSidebar, findsNothing);
    await tester.tap(find.byTooltip(LibraryStrings.openMenu));
    await tester.pumpAndSettle();
    expect(drawerSidebar, findsOneWidget);
  });

  testWidgets('13" landscape: hiding the sidebar is applied and saved', (
    tester,
  ) async {
    await pumpAt(tester, TestSizes.ipad13Landscape);
    expect(pinnedSidebar, findsOneWidget);

    await tester.tap(find.byTooltip(LibraryStrings.hideSidebar));
    await tester.pumpAndSettle();
    expect(pinnedSidebar, findsNothing);
    expect(tester.getSize(find.byType(LibraryTopBar)).width, 1376);
    expect(find.byTooltip(LibraryStrings.showSidebar), findsOneWidget);
    expect(
      await tester.runAsync(
        () => backend.store.settings.get(LibrarySettingsKeys.sidebarVisible),
      ),
      isFalse,
    );
    // Hidden in the expanded class does not turn on the drawer.
    expect(find.byTooltip(LibraryStrings.openMenu), findsNothing);

    await tester.tap(find.byTooltip(LibraryStrings.showSidebar));
    await tester.pumpAndSettle();
    expect(pinnedSidebar, findsOneWidget);
    expect(
      await tester.runAsync(
        () => backend.store.settings.get(LibrarySettingsKeys.sidebarVisible),
      ),
      isTrue,
    );
  });

  testWidgets('a stored hidden sidebar is used from the start', (tester) async {
    await tester.runAsync(
      () =>
          backend.store.settings.set(LibrarySettingsKeys.sidebarVisible, false),
    );
    await pumpAt(tester, TestSizes.ipad13Landscape);
    expect(pinnedSidebar, findsNothing);
  });

  testWidgets('rotation keeps the State: landscape → portrait → landscape', (
    tester,
  ) async {
    await pumpAt(tester, TestSizes.ipad13Landscape);
    expect(pinnedSidebar, findsOneWidget);
    final screenState = tester.state(find.byType(LibraryScreen));

    setTestSize(tester, TestSizes.ipad13Portrait);
    await tester.pumpAndSettle();
    expect(pinnedSidebar, findsNothing);
    expect(find.byTooltip(LibraryStrings.openMenu), findsOneWidget);

    setTestSize(tester, TestSizes.ipad13Landscape);
    await tester.pumpAndSettle();
    expect(pinnedSidebar, findsOneWidget);
    expect(tester.state(find.byType(LibraryScreen)), same(screenState));
  });

  testWidgets('section titles in the top bar', (tester) async {
    late final String mathId;
    await tester.runAsync(() async {
      mathId = (await seedSampleLibrary(backend)).math.id;
    });
    final h = await pumpAt(tester, TestSizes.ipad13Landscape);
    expect(
      find.descendant(
        of: find.byType(LibraryTopBar),
        matching: find.text(LibraryStrings.home),
      ),
      findsOneWidget,
    );
    final container = containerOf(tester);
    final section = container.read(librarySectionProvider(null).notifier);
    final expected = <(void Function(), String)>[
      (section.showRecent, LibraryStrings.recent),
      (section.showFavorites, LibraryStrings.favorites),
      (section.showTrash, LibraryStrings.trash),
      (() => section.search('수학'), '"수학" 검색 결과'),
    ];
    for (final (show, title) in expected) {
      show();
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(LibraryTopBar),
          matching: find.text(title),
        ),
        findsOneWidget,
        reason: title,
      );
    }
    expect(container.read(librarySectionProvider(null)), isA<SearchSection>());

    await h.goToFolder(tester, mathId);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(LibraryTopBar),
        matching: find.text('수학'),
      ),
      findsOneWidget,
    );
    expect(
      container.read(librarySectionProvider(mathId)),
      FolderSection(mathId),
    );
  });
}
