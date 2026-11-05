// Browser smoke of the library screen (05-library 8 L20; contract 7.4.8): on
// dart2js, over CORE's createFakeNoteStore() (web-safe, in memory) through
// FakeLibraryBackend — the screen shows; 새로 만들기 › 새 폴더 creates a
// folder; a note dragged with the stylus onto it moves there; the folder goes
// to the trash from its ⋯ menu; the trash restores it with the note inside.
// The view setting written on the web (a string) is read back too.
@TestOn('browser')
library;

import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/settings/library_settings_keys.dart';
import 'package:feature_library/src/ui/content/folder_tile.dart';
import 'package:feature_library/src/ui/content/item_list.dart';
import 'package:feature_library/src/ui/content/note_tile.dart';
import 'package:feature_library/src/ui/dialogs/new_folder_dialog.dart';
import 'package:feature_library/src/ui/sidebar/sidebar_rows.dart';
import 'package:feature_library/src/ui/trash/trash_row.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_library_backend.dart';
import '../support/library_test_harness.dart';
import '../support/test_sizes.dart';

Finder noteTile(String title) => find.widgetWithText(NoteTile, title);
Finder folderTile(String name) => find.widgetWithText(FolderTile, name);
Finder navRow(String label) => find.widgetWithText(SidebarNavRow, label);
Finder trashRow(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(TrashRow));

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('show → new folder → stylus drag into it → trash → restore', (
    tester,
  ) async {
    final notes = await real(tester, () async {
      final first = await backend.seedNote('회의록', at: DateTime(2026, 11, 1, 9));
      final second = await backend.seedNote(
        '독서 기록',
        at: DateTime(2026, 11, 1, 9, 1),
      );
      backend.clock.current = DateTime(2026, 11, 4, 14, 5);
      return [first, second];
    });
    final h = LibraryTestHarness(backend, size: TestSizes.ipad13Landscape);
    await h.pump(tester);
    await tester.pumpAndSettle();

    // 1. The screen: sidebar, the two notes at 홈.
    expect(navRow(LibraryStrings.home), findsOneWidget);
    expect(noteTile('회의록'), findsOneWidget);
    expect(noteTile('독서 기록'), findsOneWidget);

    // 2. 새로 만들기 › 새 폴더, named '프로젝트'.
    await tapAndSettle(tester, find.text(LibraryStrings.newMenu));
    await tapAndSettle(
      tester,
      find.widgetWithText(MenuItemButton, LibraryStrings.newFolder),
    );
    expect(find.byType(NewFolderDialog), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, LibraryStrings.fieldName),
      '프로젝트',
    );
    await tester.pump();
    await tapAndSettle(
      tester,
      find.widgetWithText(FilledButton, LibraryStrings.create),
    );
    expect(backend.calls, ["createFolder home '프로젝트'"]);
    expect(folderTile('프로젝트'), findsOneWidget);
    final folder = (await real(
      tester,
      () => backend.store.library.watchFolderTree().first,
    )).roots.single;
    expect(folder.name, '프로젝트');

    // 3. '회의록' dragged with the stylus onto the folder tile (9.1: down →
    // 450 ms → 20 down → the target → up).
    final gesture = await tester.startGesture(
      tester.getCenter(noteTile('회의록')),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump(const Duration(milliseconds: 450));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(folderTile('프로젝트')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      backend.calls.last,
      'moveItems [n:${notes[0].id}] -> f:${folder.id}',
    );
    expect(find.text(LibraryStrings.movedTo('프로젝트')), findsOneWidget);
    expect(noteTile('회의록'), findsNothing);
    expect(noteTile('독서 기록'), findsOneWidget);
    final moved = await real(
      tester,
      () => backend.store.library.getNote(notes[0].id),
    );
    expect(moved!.folderId, folder.id);

    // 4. The folder (with the note) to the trash from its ⋯ menu.
    await tapAndSettle(tester, find.byTooltip(LibraryStrings.itemMenu('프로젝트')));
    await tapAndSettle(
      tester,
      find.widgetWithText(MenuItemButton, LibraryStrings.moveToTrash),
    );
    expect(backend.calls.last, 'trashItems [f:${folder.id}]');
    expect(folderTile('프로젝트'), findsNothing);

    // 5. 휴지통 › the folder's row › 복원: back at 홈 with the note inside.
    await tapAndSettle(tester, navRow(LibraryStrings.trash));
    expect(trashRow('프로젝트'), findsOneWidget);
    await tapAndSettle(tester, find.byTooltip(LibraryStrings.itemMenu('프로젝트')));
    await tapAndSettle(
      tester,
      find.widgetWithText(MenuItemButton, LibraryStrings.restore),
    );
    expect(backend.calls.last, 'restore [f:${folder.id}]');
    expect(find.text(LibraryStrings.restoredOne('프로젝트')), findsOneWidget);
    expect(trashRow('프로젝트'), findsNothing);

    await tapAndSettle(tester, navRow(LibraryStrings.home));
    expect(folderTile('프로젝트'), findsOneWidget);
    await tapAndSettle(tester, folderTile('프로젝트'));
    expect(h.log.entries.last, 'folder:${folder.id}');
    expect(noteTile('회의록'), findsOneWidget);
  });

  testWidgets('the list view setting is written and read back on the web', (
    tester,
  ) async {
    await real(tester, () => backend.seedNote('회의록'));
    await LibraryTestHarness(backend).pump(tester);
    await tester.pumpAndSettle();
    await tapAndSettle(tester, find.byTooltip(LibraryStrings.viewAsList));
    expect(find.byType(NoteListRow), findsOneWidget);
    expect(
      await real(
        tester,
        () => backend.store.settings.get(LibrarySettingsKeys.viewMode),
      ),
      'list',
    );
    // A new screen over the same store starts in the list.
    await tester.pumpWidget(const SizedBox());
    await LibraryTestHarness(backend).pump(tester);
    await tester.pumpAndSettle();
    expect(find.byType(NoteListRow), findsOneWidget);
    expect(find.byType(NoteTile), findsNothing);
  });
}
