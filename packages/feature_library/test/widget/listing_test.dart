// Note listing (05-library 6.7 / 6.8, 8 L10): folders first, the sort menu
// passes each choice to CORE as a LibraryQuery, the view toggle is kept, a
// note tap → onOpenNote only (no markOpened), a folder tap → onOpenFolder;
// the '새 노트' tile, empty / loading / error states, the newer-app badge.
import 'dart:async';

import 'package:feature_library/feature_library.dart' show LibraryScreen;
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/settings/library_settings_keys.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/ui/content/folder_tile.dart';
import 'package:feature_library/src/ui/content/item_list.dart';
import 'package:feature_library/src/ui/content/note_tile.dart';
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

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));

/// Grid cells in display order: `'f:<name>'`, `'n:<title>'`.
List<String> gridCells(WidgetTester tester) => [
  for (final w in tester.widgetList(
    find.byWidgetPredicate((w) => w is FolderTile || w is NoteTile),
  ))
    switch (w) {
      FolderTile(:final folder) => 'f:${folder.name}',
      NoteTile(:final note) => 'n:${note.title}',
      _ => '?',
    },
];

List<String> noteTitles(WidgetTester tester) => [
  for (final t in tester.widgetList<NoteTile>(find.byType(NoteTile)))
    t.note.title,
];

Finder noteTile(String title) => find.widgetWithText(NoteTile, title);
Finder folderTile(String name) => find.widgetWithText(FolderTile, name);

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
    bool settle = true,
  }) async {
    final h = LibraryTestHarness(
      backend,
      size: size,
      extraOverrides: overrides,
    );
    await h.pump(tester, folderId: folderId);
    if (settle) await tester.pumpAndSettle();
    return h;
  }

  Future<void> chooseSort(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip(LibraryStrings.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, label));
    await tester.pumpAndSettle();
  }

  testWidgets('folders first, then notes (no 새 노트 tile — v2.14-ui)', (
    tester,
  ) async {
    await seed(tester);
    await pumpAt(tester);
    // Default sort: modified, newest first (folders and notes each).
    expect(gridCells(tester), [
      'f:과학',
      'f:영어',
      'f:수학',
      'n:일기',
      'n:아이디어',
      'n:독서 기록',
      'n:회의록',
    ]);
    expect(
      backend.queries,
      contains('watchListing LibraryQuery(folder: null, updatedAt, desc)'),
    );
  });

  testWidgets('13" landscape grid: 5 columns of 193.4', (tester) async {
    await seed(tester);
    await pumpAt(tester);
    expect(
      tester.getSize(find.byType(NoteTile).first).width,
      moreOrLessEquals(193.4, epsilon: 0.01),
    );
    final xs = {
      for (final e in find.byType(FolderTile).evaluate())
        tester.getTopLeft(find.byWidget(e.widget)).dx.roundToDouble(),
      for (final e in find.byType(NoteTile).evaluate().take(2))
        tester.getTopLeft(find.byWidget(e.widget)).dx.roundToDouble(),
    };
    expect(xs, hasLength(5)); // 3 folders + 2 notes on the first row
  });

  testWidgets('each sort choice reaches CORE as a LibraryQuery', (
    tester,
  ) async {
    await seed(tester);
    await pumpAt(tester);

    await chooseSort(tester, LibraryStrings.sortName);
    expect(
      backend.queries.last,
      'watchListing LibraryQuery(folder: null, name, asc)',
    );
    expect(noteTitles(tester), ['독서 기록', '아이디어', '일기', '회의록']);
    expect(gridCells(tester).sublist(0, 3), ['f:과학', 'f:수학', 'f:영어']);

    await chooseSort(tester, LibraryStrings.sortCreated);
    expect(
      backend.queries.last,
      'watchListing LibraryQuery(folder: null, createdAt, desc)',
    );
    expect(noteTitles(tester), ['일기', '아이디어', '독서 기록', '회의록']);

    await chooseSort(tester, LibraryStrings.sortUpdated);
    expect(
      backend.queries.last,
      'watchListing LibraryQuery(folder: null, updatedAt, desc)',
    );

    // The same choice again flips the direction.
    await chooseSort(tester, LibraryStrings.sortUpdated);
    expect(
      backend.queries.last,
      'watchListing LibraryQuery(folder: null, updatedAt, asc)',
    );
    expect(noteTitles(tester), ['회의록', '독서 기록', '아이디어', '일기']);

    await chooseSort(tester, LibraryStrings.sortCustom);
    expect(
      backend.queries.last,
      'watchListing LibraryQuery(folder: null, custom, asc)',
    );

    // The menu marks the current choice; the sort is saved.
    await tester.tap(find.byTooltip(LibraryStrings.sort));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MenuItemButton>(
            find.widgetWithText(MenuItemButton, LibraryStrings.sortCustom),
          )
          .leadingIcon,
      isA<Icon>().having((i) => i.icon, 'icon', AppIconKind.check.material),
    );
    expect(
      await tester.runAsync(
        () => backend.store.settings.get(LibrarySettingsKeys.sortField),
      ),
      'custom',
    );
  });

  testWidgets('sort is disabled outside folder sections', (tester) async {
    await pumpAt(tester);
    containerOf(tester)
        .read(librarySectionProvider(null).notifier)
        .showRecent();
    await tester.pumpAndSettle();
    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byWidgetPredicate(
          (w) => w is AppIcon && w.kind == AppIconKind.sort,
        ),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(button.tooltip, LibraryStrings.sortFixed);
    expect(find.byTooltip(LibraryStrings.viewAsList), findsOneWidget);

    containerOf(tester).read(librarySectionProvider(null).notifier).showTrash();
    await tester.pumpAndSettle();
    expect(find.byTooltip(LibraryStrings.viewAsList), findsNothing);
  });

  testWidgets('the view mode is saved and kept across folders and restarts', (
    tester,
  ) async {
    final sample = await seed(tester);
    final h = await pumpAt(tester);
    expect(find.byType(NoteListRow), findsNothing);

    await tester.tap(find.byTooltip(LibraryStrings.viewAsList));
    await tester.pumpAndSettle();
    expect(find.byType(NoteTile), findsNothing);
    expect(find.byType(NoteListRow), findsNWidgets(4));
    expect(find.byType(FolderListRow), findsNWidgets(3));
    expect(find.byTooltip(LibraryStrings.viewAsGrid), findsOneWidget);
    expect(
      await tester.runAsync(
        () => backend.store.settings.get(LibrarySettingsKeys.viewMode),
      ),
      'list',
    );

    await h.goToFolder(tester, sample.math.id);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FolderListRow, '미적분'), findsOneWidget);

    // A new screen over the same store starts in the list.
    await tester.pumpWidget(const SizedBox());
    await pumpAt(tester);
    expect(find.byType(NoteListRow), findsNWidgets(4));
    expect(find.byType(NoteTile), findsNothing);
  });

  testWidgets('a note tap → onOpenNote only (no markOpened, no write)', (
    tester,
  ) async {
    final sample = await seed(tester);
    final h = await pumpAt(tester);
    await tester.tap(noteTile('회의록'));
    await tester.pump();
    expect(h.log.entries, ['note:${sample.homeNotes[0].id}']);
    expect(backend.calls, isEmpty);

    await tester.tap(find.byTooltip(LibraryStrings.viewAsList));
    await tester.pumpAndSettle();
    backend.calls.clear(); // nothing but the settings write went through
    await tester.tap(find.widgetWithText(NoteListRow, '일기'));
    await tester.pump();
    expect(h.log.entries.last, 'note:${sample.homeNotes[3].id}');
    expect(backend.calls, isEmpty);
    expect(backend.calls.where((c) => c.startsWith('markOpened')), isEmpty);
  });

  testWidgets('a folder tap → onOpenFolder', (tester) async {
    final sample = await seed(tester);
    final h = await pumpAt(tester);
    await tester.tap(folderTile('수학'));
    await tester.pumpAndSettle();
    expect(h.log.entries, ['folder:${sample.math.id}']);
    expect(gridCells(tester), ['f:미적분']);

    await tester.tap(find.byTooltip(LibraryStrings.viewAsList));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FolderListRow, '미적분'));
    await tester.pumpAndSettle();
    expect(h.log.entries.last, 'folder:${sample.nested[0].id}');
  });

  testWidgets('새로 만들기 › 새 노트 creates a note in the folder and opens it '
      '(v2.14-ui: was the grid\'s 새 노트 tile)', (tester) async {
    final sample = await seed(tester);
    final h = await pumpAt(tester, folderId: sample.math.id);
    await tester.tap(find.text(LibraryStrings.newMenu));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(MenuItemButton, LibraryStrings.newNote),
    );
    await tester.pumpAndSettle(); // the new note dialog (L12)
    await tester.tap(find.text(LibraryStrings.create));
    await tester.pumpAndSettle();
    expect(backend.calls, [
      "createNote f:${sample.math.id} '제목 없는 노트' pages:1 cover:firstPage",
    ]);
    expect(h.log.entries, hasLength(1));
    expect(h.log.entries.single, startsWith('note:'));
    expect(noteTile(LibraryStrings.defaultNoteTitle), findsOneWidget);
  });

  group('empty states', () {
    testWidgets('home and folder: text + 새 노트 + 새 폴더', (tester) async {
      final h = await pumpAt(tester);
      expect(find.text(LibraryStrings.emptyHome), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, LibraryStrings.newNote),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, LibraryStrings.newFolder),
        findsOneWidget,
      );

      late final Folder empty;
      await tester.runAsync(() async {
        empty = await backend.seedFolder('빈 폴더');
      });
      await h.goToFolder(tester, empty.id);
      await tester.pumpAndSettle();
      expect(find.text(LibraryStrings.emptyFolder), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, LibraryStrings.newNote),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(LibraryStrings.create));
      await tester.pumpAndSettle();
      expect(backend.calls.single, startsWith('createNote f:${empty.id} '));
      expect(h.log.entries.last, startsWith('note:'));
    });

    testWidgets('최근 and 즐겨찾기', (tester) async {
      await pumpAt(tester);
      final section = containerOf(tester)
          .read(librarySectionProvider(null).notifier);
      section.showRecent();
      await tester.pumpAndSettle();
      expect(find.text(LibraryStrings.emptyRecent), findsOneWidget);
      section.showFavorites();
      await tester.pumpAndSettle();
      expect(find.text(LibraryStrings.emptyFavorites), findsOneWidget);
    });
  });

  testWidgets('loading: the spinner appears only after 300 ms', (tester) async {
    final pending = StreamController<LibraryListing>();
    addTearDown(pending.close);
    await pumpAt(
      tester,
      settle: false,
      overrides: [
        libraryListingProvider.overrideWith((ref, query) => pending.stream),
      ],
    );
    await tester.pump(const Duration(milliseconds: 299));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.add(const LibraryListing(folderId: null, folders: [], notes: []));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(LibraryStrings.emptyHome), findsOneWidget);
  });

  testWidgets('an error shows 다시 시도 (reported once); retry loads', (
    tester,
  ) async {
    await seed(tester);
    var builds = 0;
    final reports = await collectReports(() async {
      await pumpAt(
        tester,
        overrides: [
          libraryListingProvider.overrideWith((ref, query) {
            builds++;
            if (builds == 1) return Stream.error(StateError('listing down'));
            return ref.watch(libraryRepositoryProvider).watchListing(query);
          }),
        ],
      );
      expect(find.text(LibraryStrings.listLoadFailed), findsOneWidget);
      // Rebuilding (another view mode) does not report again.
      await tester.tap(find.byTooltip(LibraryStrings.viewAsList));
      await tester.pumpAndSettle();
    });
    expect(reports, hasLength(1));
    expect(reports.single.library, 'feature_library');

    await tester.tap(find.text(LibraryStrings.retry));
    await tester.pumpAndSettle();
    expect(find.text(LibraryStrings.listLoadFailed), findsNothing);
    expect(find.byType(NoteListRow), findsNWidgets(4));
  });

  testWidgets('a note from a newer app: badge, meta, and it does not open', (
    tester,
  ) async {
    await seed(tester);
    final h = await pumpAt(
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
                      n.title == '일기'
                          ? n.copyWith(schemaVersion: kNoteSchemaVersion + 1)
                          : n,
                  ],
                ),
              ),
        ),
      ],
    );
    // (v2.14-ui) a '새 버전 필요' label on the cover, no 'upgrade' arrow.
    expect(
      find.descendant(
        of: noteTile('일기'),
        matching: find.text(LibraryStrings.requiresNewerAppBadge),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.upgrade), findsNothing);
    expect(
      find.descendant(
        of: noteTile('일기'),
        matching: find.text(LibraryStrings.requiresNewerApp),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: noteTile('회의록'),
        matching: find.text(LibraryStrings.requiresNewerAppBadge),
      ),
      findsNothing,
    );

    await tester.tap(noteTile('일기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750)); // snack bar in
    expect(h.log.entries, isEmpty);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(LibraryStrings.requiresNewerApp),
      ),
      findsOneWidget,
    );
  });

  testWidgets('favorites: ★ on the grid tile; in the list ★ only on a '
      'favourite (v2.14-ui), added from ⋯ and removed with ★', (tester) async {
    final sample = await seed(tester);
    await tester.runAsync(
      () => backend.store.library.setFavorite([sample.homeNotes[1].id], true),
    );
    await pumpAt(tester);
    expect(
      find.descendant(
        of: noteTile('독서 기록'),
        matching: find.byIcon(AppIconKind.favoriteOn.material),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: noteTile('회의록'),
        matching: find.byIcon(AppIconKind.favoriteOn.material),
      ),
      findsNothing,
    );

    await tester.tap(find.byTooltip(LibraryStrings.viewAsList));
    await tester.pumpAndSettle();
    backend.calls.clear();
    final row = find.widgetWithText(NoteListRow, '회의록');
    // Not a favourite: no ☆ on the row.
    expect(
      find.descendant(
        of: row,
        matching: find.byIcon(AppIconKind.favorite.material),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.byIcon(AppIconKind.favoriteOn.material),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(NoteListRow, '독서 기록'),
        matching: find.byTooltip(LibraryStrings.favoriteRemove),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip(LibraryStrings.itemMenu('회의록')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(MenuItemButton, LibraryStrings.favoriteAdd),
    );
    await tester.pumpAndSettle();
    expect(backend.calls, ['setFavorite [n:${sample.homeNotes[0].id}] true']);
    final star = find.descendant(
      of: row,
      matching: find.byTooltip(LibraryStrings.favoriteRemove),
    );
    expect(star, findsOneWidget);
    backend.calls.clear();
    await tester.tap(star);
    await tester.pumpAndSettle();
    expect(backend.calls, ['setFavorite [n:${sample.homeNotes[0].id}] false']);
    expect(
      find.descendant(
        of: row,
        matching: find.byIcon(AppIconKind.favoriteOn.material),
      ),
      findsNothing,
    );
  });

  testWidgets('compact: sort and view live in ⋯', (tester) async {
    await seed(tester);
    await pumpAt(tester, size: TestSizes.compact);
    expect(find.byTooltip(LibraryStrings.sort), findsNothing);
    await tester.tap(find.byTooltip(LibraryStrings.moreActions));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(SubmenuButton, LibraryStrings.sort),
      findsOneWidget,
    );
    await tester.tap(
      find.widgetWithText(MenuItemButton, LibraryStrings.viewAsList),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NoteListRow), findsWidgets);
  });

  testWidgets('listing tap targets: 44 × 44 and labeled', (tester) async {
    final semantics = tester.ensureSemantics();
    await seed(tester);
    await pumpAt(tester);
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.tap(find.byTooltip(LibraryStrings.viewAsList));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });
}
