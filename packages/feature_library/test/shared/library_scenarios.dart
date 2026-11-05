// test/shared/library_scenarios.dart — 05-library 5.7 / 8 L0, L21.
//
// Core scenarios run by widget/scenarios_on_fake_test.dart (the CORE fake,
// all of them) AND by integration/core_contract_test.dart (real CORE,
// needsFaults == false only — L21). A scenario only uses the harness, the
// backend's wrappers / seed helpers and the screen, so the same body gives the
// same result on both stores. Entries for the L21 list are added with the
// tasks that build the screens they need (L10 … L18).
import 'package:feature_library/feature_library.dart';
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/model/names.dart';
import 'package:feature_library/src/settings/library_settings_keys.dart';
import 'package:feature_library/src/ui/content/note_tile.dart';
import 'package:feature_library/src/ui/dialogs/folder_picker_dialog.dart';
import 'package:feature_library/src/ui/sidebar/sidebar_rows.dart';
import 'package:feature_library/src/ui/top_bar/library_search_field.dart';
import 'package:feature_library/src/ui/trash/trash_row.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show FolderCycleException, FolderRef, LibraryQuery, LibrarySortField;

import '../support/fixtures.dart';
import '../support/library_test_harness.dart';

typedef LibraryScenarioBody = Future<void> Function(
  WidgetTester tester,
  LibraryTestHarness h,
);

@immutable
final class LibraryScenario {
  const LibraryScenario(this.name, this.body, {this.needsFaults = false});

  final String name;
  final LibraryScenarioBody body;

  /// Uses h.backend.faults (CORE fake only). L21 runs only scenarios with
  /// needsFaults == false.
  final bool needsFaults;
}

/// Registered with testWidgets by widget/scenarios_on_fake_test.dart (all) and
/// by integration/core_contract_test.dart (needsFaults == false only).
final List<LibraryScenario> libraryScenarios = [
  LibraryScenario(
    'harness: a route change keeps the LibraryScreen State',
    _routeChangeKeepsState,
  ),
  LibraryScenario(
    'folders: create, move through the picker, no move into the own subtree',
    _createMoveNoCycle,
  ),
  LibraryScenario(
    "copy: ' 사본' of a 200-character title stays 200 characters",
    _copyLongTitle,
  ),
  LibraryScenario(
    'custom order: two selected notes dragged after a third move together',
    _customReorderSeveral,
  ),
  LibraryScenario(
    'trash: a note trashed in a folder is restored there; [보기] opens it',
    _trashRestoresInPlace,
  ),
  LibraryScenario(
    'search: decomposed (NFD) titles and queries match composed ones',
    _searchNfd,
  ),
  LibraryScenario(
    'recent: a note shows only after openSession (no markOpened here)',
    _recentAfterOpenSession,
  ),
];

Future<T> _real<T>(WidgetTester tester, Future<T> Function() body) async =>
    (await tester.runAsync(body)) as T;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// ⋯ of the item named [name] → [entry].
Future<void> _menu(WidgetTester tester, String name, String entry) async {
  await _tap(tester, find.byTooltip(LibraryStrings.itemMenu(name)));
  await _tap(tester, find.widgetWithText(MenuItemButton, entry));
}

/// Fills the open new folder dialog with [name] and creates it.
Future<void> _createFolderNamed(WidgetTester tester, String name) async {
  await tester.enterText(
    find.widgetWithText(TextField, LibraryStrings.fieldName),
    name,
  );
  await _tap(tester, find.widgetWithText(FilledButton, LibraryStrings.create));
}

/// Folder A (empty state [새 폴더]) with B inside (sidebar row menu › 새 하위
/// 폴더) and C (top bar 새로 만들기 › 새 폴더). Moving A: A is disabled in
/// the picker and 홈 (where it is) cannot be confirmed; CORE refuses A → B
/// (C-4). A → C through the picker, then [실행 취소] puts it back.
Future<void> _createMoveNoCycle(
  WidgetTester tester,
  LibraryTestHarness h,
) async {
  final library = h.backend.store.library;
  await h.pump(tester);
  await tester.pumpAndSettle();
  await _tap(
    tester,
    find.widgetWithText(OutlinedButton, LibraryStrings.newFolder),
  );
  await _createFolderNamed(tester, 'A');
  await tester.longPress(find.widgetWithText(SidebarTreeRow, 'A'));
  await tester.pumpAndSettle();
  await _tap(
    tester,
    find.widgetWithText(MenuItemButton, LibraryStrings.newSubfolder),
  );
  await _createFolderNamed(tester, 'B');
  await _tap(tester, find.text(LibraryStrings.newMenu));
  await _tap(
    tester,
    find.widgetWithText(MenuItemButton, LibraryStrings.newFolder),
  );
  await _createFolderNamed(tester, 'C');

  var tree = await _real(tester, () => library.watchFolderTree().first);
  final a = tree.roots.singleWhere((f) => f.name == 'A');
  final c = tree.roots.singleWhere((f) => f.name == 'C');
  final b = tree.childrenOf(a.id).single;
  expect(b.name, 'B');

  await _menu(tester, 'A', LibraryStrings.moveTo);
  final rowA = tester.widget<FolderPickerRow>(
    find.widgetWithText(FolderPickerRow, 'A'),
  );
  expect(rowA.enabled, isFalse);
  FilledButton confirm() => tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, LibraryStrings.moveHere),
  );
  expect(confirm().onPressed, isNull); // 홈: already there
  await _tap(tester, find.widgetWithText(FolderPickerRow, 'A'));
  expect(confirm().onPressed, isNull); // a disabled row cannot be chosen

  // CORE refuses a cycle and changes nothing (C-4).
  final refused = await _real<Object?>(tester, () async {
    try {
      await h.backend.library.moveItems([
        FolderRef(a.id),
      ], targetFolderId: b.id);
      return null;
    } on Object catch (error) {
      return error;
    }
  });
  expect(refused, isA<FolderCycleException>());
  tree = await _real(tester, () => library.watchFolderTree().first);
  expect(tree.byId(a.id)!.parentId, isNull);

  await _tap(tester, find.widgetWithText(FolderPickerRow, 'C'));
  await _tap(
    tester,
    find.widgetWithText(FilledButton, LibraryStrings.moveHere),
  );
  expect(find.text(LibraryStrings.movedTo('C')), findsOneWidget);
  tree = await _real(tester, () => library.watchFolderTree().first);
  expect(tree.byId(a.id)!.parentId, c.id);
  expect(tree.byId(b.id)!.parentId, a.id);

  await _tap(tester, find.widgetWithText(SnackBarAction, LibraryStrings.undo));
  tree = await _real(tester, () => library.watchFolderTree().first);
  expect(tree.byId(a.id)!.parentId, isNull);
  expect(h.log.entries, isEmpty);
}

/// ⋯ › 복사 of a note whose title is 200 characters: CORE cuts the
/// original name so name + ' 사본' is 200 (C-5).
Future<void> _copyLongTitle(WidgetTester tester, LibraryTestHarness h) async {
  final title = '가' * kMaxItemNameLength;
  final note = await _real(tester, () => h.backend.seedNote(title));
  await h.pump(tester);
  await tester.pumpAndSettle();
  await _menu(tester, title, LibraryStrings.copy);
  expect(find.text(LibraryStrings.copied), findsOneWidget);
  final listing = await _real(
    tester,
    () => h.backend.store.library.watchListing(const LibraryQuery()).first,
  );
  final copy = listing.notes.singleWhere((n) => n.id != note.id);
  expect(copy.title.length, kMaxItemNameLength);
  expect(
    copy.title,
    '${'가' * (kMaxItemNameLength - LibraryStrings.copySuffix.length)}'
    '${LibraryStrings.copySuffix}',
  );
}

Future<void> _routeChangeKeepsState(
  WidgetTester tester,
  LibraryTestHarness h,
) async {
  final sample = await seedSampleLibrary(h.backend);
  await h.pump(tester);
  final state = tester.state(find.byType(LibraryScreen));
  expect(h.screen(tester).folderId, isNull);

  await h.goToFolder(tester, sample.math.id);
  expect(h.currentFolderId, sample.math.id);
  expect(h.screen(tester).folderId, sample.math.id);
  expect(tester.state(find.byType(LibraryScreen)), same(state));

  await h.goToFolder(tester, null);
  expect(h.screen(tester).folderId, isNull);
  expect(tester.state(find.byType(LibraryScreen)), same(state));
  // A route change made by the test is not a callback of the screen.
  expect(h.log.entries, isEmpty);
  expect(h.backend.calls, isEmpty);
}

/// Custom order (6.10.3): 노트 1 and 노트 2 selected, dragged onto the right
/// part of 노트 4 → ONE reorderItems after 노트 4, their relative order kept
/// (contract 7.2.9); the listing reads 3, 4, 1, 2.
Future<void> _customReorderSeveral(
  WidgetTester tester,
  LibraryTestHarness h,
) async {
  final notes = await _real(tester, () async {
    final made = [
      for (var i = 1; i <= 4; i++) await h.backend.seedNote('노트 $i'),
    ];
    await h.backend.store.settings.set(
      LibrarySettingsKeys.sortField,
      LibrarySortField.custom.name,
    );
    return made;
  });
  await h.pump(tester);
  await tester.pumpAndSettle();
  Finder tile(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(NoteTile));

  await tester.longPress(tile('노트 1'));
  await tester.pumpAndSettle();
  await tester.tap(tile('노트 2'));
  await tester.pump();
  final gesture = await tester.startGesture(tester.getCenter(tile('노트 2')));
  await tester.pump(const Duration(milliseconds: 450));
  await gesture.moveBy(const Offset(0, 20));
  await tester.pump();
  final target = tester.getRect(tile('노트 4'));
  await gesture.moveTo(
    Offset(target.left + target.width * 0.9, target.center.dy),
  );
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();

  final ids = [for (final n in notes) n.id];
  expect(h.backend.calls, [
    'reorderItems [n:${ids[0]}, n:${ids[1]}] after:n:${ids[3]}',
  ]);
  final listing = await _real(
    tester,
    () => h.backend.store.library
        .watchListing(
          const LibraryQuery(sort: LibrarySortField.custom, descending: false),
        )
        .first,
  );
  expect(
    [for (final n in listing.notes) n.id],
    [ids[2], ids[3], ids[0], ids[1]],
  );
}

/// 6.13 / C-3: ⋯ › 휴지통으로 이동 of a note in 영어 → 휴지통 → ⋯ › 복원 →
/// the note is back in 영어 (not 홈); [보기] → onOpenFolder(영어).
Future<void> _trashRestoresInPlace(
  WidgetTester tester,
  LibraryTestHarness h,
) async {
  final (folder, note) = await _real(tester, () async {
    final folder = await h.backend.seedFolder('영어');
    final note = await h.backend.seedNote('단어장', folderId: folder.id);
    return (folder, note);
  });
  await h.pump(tester, folderId: folder.id);
  await tester.pumpAndSettle();
  await _menu(tester, '단어장', LibraryStrings.moveToTrash);
  expect(find.text('단어장'), findsNothing);

  await _tap(tester, find.widgetWithText(SidebarNavRow, LibraryStrings.trash));
  expect(find.byType(TrashRow), findsOneWidget);
  await _menu(tester, '단어장', LibraryStrings.restore);
  expect(find.byType(TrashRow), findsNothing);
  final restored = await _real(
    tester,
    () => h.backend.store.library.getNote(note.id),
  );
  expect(restored!.deletedAt, isNull);
  expect(restored.folderId, folder.id);

  // The route is still 영어 (the trash was a section of it): [보기] shows it.
  await _tap(tester, find.widgetWithText(SnackBarAction, LibraryStrings.show));
  expect(find.text('단어장'), findsOneWidget);
  expect(find.byType(TrashRow), findsNothing);
}

/// Types [text] into the top bar search field and waits for the debounce
/// (300 ms) and the results.
Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(LibrarySearchField),
      matching: find.byType(TextField),
    ),
    text,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Set<String> _noteTileIds(WidgetTester tester) => {
  for (final t in tester.widgetList<NoteTile>(find.byType(NoteTile))) t.note.id,
};

/// 6.14 / CORE 6.8: a title stored with decomposed Hangul jamo (as macOS
/// file names give it) is found by the composed query, and a decomposed query
/// finds a composed title; the whole library is searched.
Future<void> _searchNfd(WidgetTester tester, LibraryTestHarness h) async {
  const decomposedMath = '\u1109\u116e\u1112\u1161\u11a8'; // 수학
  final (nfdNote, nfcNote) = await _real(tester, () async {
    final folder = await h.backend.seedFolder('수학 자료');
    final nfdNote = await h.backend.seedNote('$decomposedMath 정리');
    final nfcNote = await h.backend.seedNote('수학 숙제', folderId: folder.id);
    await h.backend.seedNote('영어 단어');
    return (nfdNote, nfcNote);
  });
  await h.pump(tester);
  await tester.pumpAndSettle();

  await _search(tester, '수학');
  expect(h.backend.queries, contains("searchLibrary '수학' limit:50"));
  expect(find.text(LibraryStrings.searchFolderGroup(1)), findsOneWidget);
  expect(find.text(LibraryStrings.searchNoteGroup(2)), findsOneWidget);
  expect(_noteTileIds(tester), {nfdNote.id, nfcNote.id});

  await _search(tester, '$decomposedMath 숙제');
  expect(_noteTileIds(tester), {nfcNote.id});
  expect(find.text(LibraryStrings.searchFolderGroup(1)), findsNothing);
  expect(h.log.entries, isEmpty);
  expect(h.backend.calls, isEmpty);
}

/// 6.14 / S-5: opening a note from the library is only onOpenNote; the note
/// joins 최근 when a session opens it (the editor's openSession, N-6).
Future<void> _recentAfterOpenSession(
  WidgetTester tester,
  LibraryTestHarness h,
) async {
  final note = await _real(tester, () => h.backend.seedNote('일기'));
  await h.pump(tester);
  await tester.pumpAndSettle();
  Finder nav(String label) => find.widgetWithText(SidebarNavRow, label);

  await _tap(tester, nav(LibraryStrings.recent));
  expect(find.text(LibraryStrings.emptyRecent), findsOneWidget);
  await _tap(tester, nav(LibraryStrings.home));
  await _tap(tester, find.widgetWithText(NoteTile, '일기'));
  expect(h.log.entries, ['note:${note.id}']);
  expect(h.backend.calls, isEmpty);

  await _tap(tester, nav(LibraryStrings.recent));
  expect(find.text(LibraryStrings.emptyRecent), findsOneWidget);
  await _real(tester, () => h.backend.seedOpened(note.id));
  await tester.pumpAndSettle();
  expect(find.text(LibraryStrings.emptyRecent), findsNothing);
  expect(_noteTileIds(tester), {note.id});
}
