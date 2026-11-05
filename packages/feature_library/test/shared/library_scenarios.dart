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
