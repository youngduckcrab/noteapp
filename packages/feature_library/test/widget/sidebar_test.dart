// Sidebar (05-library 6.5 / 6.16.1, 8 L9): nav rows and tree rows open
// folders / change the section, ▸ toggles, the route folder's ancestors are
// expanded, the trash count, the sync status (default, 5 overrides, provider
// error reported once) and its tap → onOpenSettings.
import 'dart:async';

import 'package:feature_library/feature_library.dart' show LibraryScreen;
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/model/section.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/ui/sidebar/library_sidebar.dart';
import 'package:feature_library/src/ui/sidebar/sidebar_rows.dart';
import 'package:feature_library/src/ui/sidebar/sync_badge_indicator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';

import '../support/fake_library_backend.dart';
import '../support/fixtures.dart';
import '../support/library_test_harness.dart';
import '../support/test_sizes.dart';

Finder treeRow(String name) => find.widgetWithText(SidebarTreeRow, name);
Finder navRow(String label) => find.widgetWithText(SidebarNavRow, label);
final Finder drawerSidebar = find.byWidgetPredicate(
  (w) => w is LibrarySidebar && w.inDrawer,
);

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));

/// The selected background of a sidebar row, or null when not selected.
Color? rowBackground(WidgetTester tester, Finder row) {
  final material = tester.widget<Material>(
    find.descendant(of: row, matching: find.byType(Material)).first,
  );
  return material.type == MaterialType.transparency ? null : material.color;
}

Color secondaryContainer(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(LibraryScreen)))
        .colorScheme
        .secondaryContainer;

/// Collects FlutterError reports during [body] (restored before returning).
Future<List<FlutterErrorDetails>> collectReports(
  Future<void> Function() body,
) async {
  final reports = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = reports.add;
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return reports;
}

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

  group('navigation', () {
    testWidgets('최근 / 즐겨찾기 / 휴지통 change the section only; 홈 returns', (
      tester,
    ) async {
      await seed(tester);
      final h = await pumpAt(tester);
      final container = containerOf(tester);
      LibrarySection section() => container.read(librarySectionProvider(null));

      expect(
        rowBackground(tester, navRow(LibraryStrings.home)),
        secondaryContainer(tester),
      );
      final expected = <String, LibrarySection>{
        LibraryStrings.recent: const RecentSection(),
        LibraryStrings.favorites: const FavoritesSection(),
        LibraryStrings.trash: const TrashSection(),
      };
      for (final MapEntry(key: label, value: target) in expected.entries) {
        await tester.tap(navRow(label));
        await tester.pumpAndSettle();
        expect(section(), target, reason: label);
        expect(
          rowBackground(tester, navRow(label)),
          secondaryContainer(tester),
        );
        expect(rowBackground(tester, navRow(LibraryStrings.home)), isNull);
      }

      await tester.tap(navRow(LibraryStrings.home));
      await tester.pumpAndSettle();
      expect(section(), const FolderSection(null));
      expect(h.log.entries, isEmpty); // the route folder: no navigation
      expect(h.currentFolderId, isNull);
    });

    testWidgets('a tree row opens its folder with onOpenFolder', (
      tester,
    ) async {
      final sample = await seed(tester);
      final h = await pumpAt(tester);
      expect(rowBackground(tester, treeRow('수학')), isNull);

      await tester.tap(treeRow('수학'));
      await tester.pumpAndSettle();
      expect(h.log.entries, ['folder:${sample.math.id}']);
      expect(h.currentFolderId, sample.math.id);
      expect(rowBackground(tester, treeRow('수학')), secondaryContainer(tester));
      expect(rowBackground(tester, navRow(LibraryStrings.home)), isNull);

      // From 최근, the route folder's row comes back without navigating.
      await tester.tap(navRow(LibraryStrings.recent));
      await tester.pumpAndSettle();
      expect(rowBackground(tester, treeRow('수학')), isNull);
      await tester.tap(treeRow('수학'));
      await tester.pumpAndSettle();
      expect(h.log.entries, ['folder:${sample.math.id}']);
      expect(
        containerOf(tester).read(librarySectionProvider(sample.math.id)),
        FolderSection(sample.math.id),
      );

      await tester.tap(navRow(LibraryStrings.home));
      await tester.pumpAndSettle();
      expect(h.log.entries, ['folder:${sample.math.id}', 'folder:home']);
      expect(h.currentFolderId, isNull);
    });
  });

  group('tree', () {
    testWidgets('▸ expands, ▾ collapses; leaves have no toggle', (
      tester,
    ) async {
      final sample = await seed(tester);
      final h = await pumpAt(tester);
      expect(treeRow('미적분'), findsNothing);
      // Home folders without children: no toggle button.
      expect(
        find.descendant(of: treeRow('영어'), matching: find.byType(IconButton)),
        findsNothing,
      );

      await tester.tap(
        find.descendant(
          of: treeRow('수학'),
          matching: find.byTooltip(LibraryStrings.expandFolder),
        ),
      );
      await tester.pumpAndSettle();
      expect(treeRow('미적분'), findsOneWidget);
      expect(treeRow('극한'), findsNothing);
      expect(containerOf(tester).read(folderExpansionProvider), {
        sample.math.id,
      });
      expect(h.log.entries, isEmpty); // the toggle does not open the folder

      await tester.tap(
        find.descendant(
          of: treeRow('수학'),
          matching: find.byTooltip(LibraryStrings.collapseFolder),
        ),
      );
      await tester.pumpAndSettle();
      expect(treeRow('미적분'), findsNothing);
      expect(containerOf(tester).read(folderExpansionProvider), isEmpty);
    });

    testWidgets('the indent stops at 8 levels', (tester) async {
      final ids = <FolderId>[];
      await tester.runAsync(() async {
        FolderId? parent;
        for (var d = 0; d < 11; d++) {
          final f = await backend.seedFolder('d$d', parentId: parent);
          ids.add(f.id);
          parent = f.id;
        }
      });
      await pumpAt(tester);
      containerOf(tester).read(folderExpansionProvider.notifier).expandAll(ids);
      await tester.pumpAndSettle();

      double iconLeft(int depth) => tester
          .getTopLeft(
            find.descendant(
              of: treeRow('d$depth'),
              matching: find.byKey(SidebarTreeRow.folderArtKey),
            ),
          )
          .dx;
      final base = iconLeft(0);
      for (var d = 1; d <= 10; d++) {
        expect(iconLeft(d) - base, (d < 8 ? d : 8) * 16.0, reason: 'd$d');
      }
      expect(SidebarTreeRow.indentFor(50), 128);
      expect(
        find.descendant(of: treeRow('d10'), matching: find.byType(IconButton)),
        findsNothing,
      );
    });

    testWidgets('folder color and icon key are drawn', (tester) async {
      await tester.runAsync(
        () => backend.seedFolder('색 폴더', colorArgb: 0xFF4CAF7A, icon: 'book'),
      );
      await pumpAt(tester);
      final icon = tester.widget<Icon>(
        find.descendant(
          of: treeRow('색 폴더'),
          matching: find.byIcon(Icons.menu_book),
        ),
      );
      expect(icon.color, const Color(0xFF4CAF7A));
    });

    testWidgets('a deep route folder expands its ancestors (first build)', (
      tester,
    ) async {
      final sample = await seed(tester);
      await pumpAt(tester, folderId: sample.deepest.id);
      for (final name in ['수학', '미적분', '극한', '연습 문제']) {
        expect(treeRow(name), findsOneWidget, reason: name);
      }
      expect(
        rowBackground(tester, treeRow('연습 문제')),
        secondaryContainer(tester),
      );
      expect(containerOf(tester).read(folderExpansionProvider), {
        sample.math.id,
        sample.nested[0].id,
        sample.nested[1].id,
      });
    });

    testWidgets('the reveal waits for the first tree while it loads', (
      tester,
    ) async {
      final sample = await seed(tester);
      final trees = StreamController<FolderTree>();
      addTearDown(trees.close);
      await pumpAt(
        tester,
        folderId: sample.deepest.id,
        overrides: [folderTreeProvider.overrideWith((ref) => trees.stream)],
      );
      expect(containerOf(tester).read(folderExpansionProvider), isEmpty);

      final tree = await tester.runAsync(
        () => backend.store.library.watchFolderTree().first,
      );
      trees.add(tree!);
      await tester.pumpAndSettle();
      expect(containerOf(tester).read(folderExpansionProvider), {
        sample.math.id,
        sample.nested[0].id,
        sample.nested[1].id,
      });
      expect(treeRow('연습 문제'), findsOneWidget);
    });

    testWidgets('a route change reveals the new folder', (tester) async {
      final sample = await seed(tester);
      final h = await pumpAt(tester);
      expect(treeRow('극한'), findsNothing);

      await h.goToFolder(tester, sample.nested[1].id); // 극한
      await tester.pumpAndSettle();
      expect(treeRow('미적분'), findsOneWidget);
      expect(treeRow('극한'), findsOneWidget);
      expect(treeRow('연습 문제'), findsNothing); // 극한 itself stays collapsed
      expect(rowBackground(tester, treeRow('극한')), secondaryContainer(tester));

      // A top-level route folder has no ancestors: nothing more is expanded.
      await h.goToFolder(tester, sample.english.id);
      await tester.pumpAndSettle();
      expect(containerOf(tester).read(folderExpansionProvider), {
        sample.math.id,
        sample.nested[0].id,
      });
    });

    testWidgets('a tree load error shows 다시 시도, reported once', (tester) async {
      await seed(tester);
      var builds = 0;
      late final List<FlutterErrorDetails> reports;
      reports = await collectReports(() async {
        await pumpAt(
          tester,
          overrides: [
            folderTreeProvider.overrideWith((ref) {
              builds++;
              if (builds == 1) return Stream.error(StateError('tree down'));
              return ref.watch(libraryRepositoryProvider).watchFolderTree();
            }),
          ],
        );
        expect(find.text(LibraryStrings.loadFailed), findsOneWidget);
        expect(treeRow('수학'), findsNothing);
        // Rebuilding the sidebar does not report again.
        await tester.tap(navRow(LibraryStrings.recent));
        await tester.pumpAndSettle();
      });
      expect(reports, hasLength(1));
      expect(reports.single.exception, isA<StateError>());
      expect(reports.single.library, 'feature_library');

      await tester.tap(find.text(LibraryStrings.retry));
      await tester.pumpAndSettle();
      expect(find.text(LibraryStrings.loadFailed), findsNothing);
      expect(treeRow('수학'), findsOneWidget);
    });
  });

  testWidgets('the trash row shows the number of trash entries', (
    tester,
  ) async {
    final sample = await seed(tester);
    await pumpAt(tester);
    expect(
      find.descendant(
        of: navRow(LibraryStrings.trash),
        matching: find.text('0'),
      ),
      findsNothing,
    );

    await tester.runAsync(
      () => backend.seedTrashed([
        NoteRef(sample.homeNotes[0].id),
        FolderRef(sample.math.id),
      ], at: DateTime(2026, 11, 3)),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: navRow(LibraryStrings.trash),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(treeRow('수학'), findsNothing);

    await tester.runAsync(
      () => backend.remoteChange(
        (store) => store.trash.restore([FolderRef(sample.math.id)]),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: navRow(LibraryStrings.trash),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(treeRow('수학'), findsOneWidget);
  });

  group('sync status', () {
    Finder indicatorText(String text) => find.descendant(
      of: find.byType(SyncBadgeIndicator),
      matching: find.text(text),
    );

    testWidgets('without an override (sync off): nothing (v2.14-ui — the '
        'floppy 이 기기에 저장 is gone)', (tester) async {
      await pumpAt(tester);
      expect(indicatorText(LibraryStrings.syncOff), findsNothing);
      expect(find.byTooltip(LibraryStrings.syncOffTooltip), findsNothing);
      expect(find.byIcon(Icons.save_outlined), findsNothing);
      // The settings button stays in that row.
      expect(find.byTooltip(LibraryStrings.settings), findsOneWidget);
    });

    final cases = <(SyncBadge, String, String)>[
      (
        SyncBadge(
          display: SyncDisplayState.done,
          lastSyncedAt: DateTime(2026, 11, 4, 13).millisecondsSinceEpoch,
        ),
        '동기화됨',
        '마지막 동기화 오늘 오후 1:00',
      ),
      (
        const SyncBadge(
          display: SyncDisplayState.inProgress,
          pendingChanges: 3,
        ),
        '동기화 중 · 3',
        '보내는 중인 변경 3개',
      ),
      (
        const SyncBadge(display: SyncDisplayState.offline),
        '오프라인',
        '연결되면 자동으로 동기화해요',
      ),
      (
        const SyncBadge(
          display: SyncDisplayState.error,
          issueCode: 'quotaExceeded',
        ),
        '동기화 오류',
        '동기화하지 못한 변경이 있어요. 설정에서 확인해 주세요.',
      ),
    ];
    for (final (badge, label, tooltip) in cases) {
      testWidgets('override ${badge.display.name} → $label', (tester) async {
        await pumpAt(
          tester,
          overrides: [
            syncBadgeProvider.overrideWith((ref) => Stream.value(badge)),
          ],
        );
        expect(indicatorText(label), findsOneWidget);
        expect(find.byTooltip(tooltip), findsOneWidget);
        final colors = Theme.of(tester.element(find.byType(SyncBadgeIndicator)))
            .colorScheme;
        final text = tester.widget<Text>(indicatorText(label));
        expect(text.style?.color, switch (badge.display) {
          SyncDisplayState.inProgress => colors.primary,
          SyncDisplayState.error => colors.error,
          _ => colors.onSurfaceVariant,
        });
      });
    }

    testWidgets('a later value replaces the shown badge', (tester) async {
      final badges = StreamController<SyncBadge>();
      addTearDown(badges.close);
      await pumpAt(
        tester,
        overrides: [syncBadgeProvider.overrideWith((ref) => badges.stream)],
      );
      expect(indicatorText(LibraryStrings.syncOff), findsNothing); // loading
      badges.add(const SyncBadge(display: SyncDisplayState.offline));
      await tester.pumpAndSettle();
      expect(indicatorText(LibraryStrings.syncOffline), findsOneWidget);
    });

    testWidgets('a provider error is treated as off (nothing) and reported '
        'once', (tester) async {
      final reports = await collectReports(() async {
        await pumpAt(
          tester,
          size: TestSizes.ipad13Portrait,
          overrides: [
            syncBadgeProvider.overrideWith(
              (ref) => Stream.error(StateError('sync down')),
            ),
          ],
        );
        // The drawer builds a new indicator each time it opens.
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.byTooltip(LibraryStrings.openMenu));
          await tester.pumpAndSettle();
          expect(indicatorText(LibraryStrings.syncOff), findsNothing);
          await tester.tap(navRow(LibraryStrings.recent));
          await tester.pumpAndSettle();
          expect(drawerSidebar, findsNothing);
        }
      });
      expect(reports, hasLength(1));
      expect(reports.single.exception, isA<StateError>());
      expect(reports.single.library, 'feature_library');
    });

    testWidgets('tapping the status row calls onOpenSettings', (tester) async {
      final h = await pumpAt(
        tester,
        overrides: [
          syncBadgeProvider.overrideWith(
            (ref) => Stream.value(
              const SyncBadge(display: SyncDisplayState.offline),
            ),
          ),
        ],
      );
      await tester.tap(find.byType(SyncBadgeIndicator));
      await tester.pump();
      expect(h.log.entries, ['settings']);
    });
  });

  group('in the drawer', () {
    testWidgets('a folder row closes the drawer; ▸ keeps it open', (
      tester,
    ) async {
      final sample = await seed(tester);
      final h = await pumpAt(tester, size: TestSizes.ipad13Portrait);
      await tester.tap(find.byTooltip(LibraryStrings.openMenu));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: treeRow('수학'),
          matching: find.byTooltip(LibraryStrings.expandFolder),
        ),
      );
      await tester.pumpAndSettle();
      expect(drawerSidebar, findsOneWidget);
      expect(treeRow('미적분'), findsOneWidget);

      await tester.tap(treeRow('미적분'));
      await tester.pumpAndSettle();
      expect(drawerSidebar, findsNothing);
      expect(h.log.entries, ['folder:${sample.nested[0].id}']);
    });

    testWidgets('최근 closes the drawer and changes the section', (tester) async {
      await pumpAt(tester, size: TestSizes.ipad11Portrait);
      await tester.tap(find.byTooltip(LibraryStrings.openMenu));
      await tester.pumpAndSettle();
      await tester.tap(navRow(LibraryStrings.recent));
      await tester.pumpAndSettle();
      expect(drawerSidebar, findsNothing);
      expect(
        containerOf(tester).read(librarySectionProvider(null)),
        const RecentSection(),
      );
    });
  });

  testWidgets('sidebar tap targets: 44 × 44 and labeled', (tester) async {
    final semantics = tester.ensureSemantics();
    final sample = await seed(tester);
    await pumpAt(tester, folderId: sample.deepest.id);
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });
}
