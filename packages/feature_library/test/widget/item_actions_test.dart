// Item actions (05-library 6.11, 6.8 ⋯ menu, 6.5 tree row menu; 8 L13):
// every action from the ⋯ menu reaches CORE through LibraryActions, the
// result snack bars use the right particles, [실행 취소] restores / moves
// back, failures show the 6.19 messages, and the sidebar tree row opens its
// menu on a long press released in place or a secondary click.
import 'package:feature_library/src/appearance/cover_palette.dart';
import 'package:feature_library/src/appearance/folder_appearance.dart';
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/ui/content/folder_tile.dart';
import 'package:feature_library/src/ui/content/item_list.dart';
import 'package:feature_library/src/ui/content/note_tile.dart';
import 'package:feature_library/src/ui/dialogs/cover_dialog.dart';
import 'package:feature_library/src/ui/dialogs/folder_appearance_dialog.dart';
import 'package:feature_library/src/ui/dialogs/folder_picker_dialog.dart';
import 'package:feature_library/src/ui/dialogs/new_folder_dialog.dart';
import 'package:feature_library/src/ui/dialogs/rename_dialog.dart';
import 'package:feature_library/src/ui/sidebar/sidebar_rows.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';

import '../support/fake_library_backend.dart';
import '../support/fixtures.dart';
import '../support/library_test_harness.dart';
import '../support/test_sizes.dart';

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
    FolderId? folderId,
    Size size = TestSizes.ipad13Landscape,
  }) async {
    final h = LibraryTestHarness(backend, size: size);
    await h.pump(tester, folderId: folderId);
    await tester.pumpAndSettle();
    return h;
  }

  /// Opens the ⋯ menu of the item named [name] and picks [entry].
  Future<void> menu(WidgetTester tester, String name, String entry) async {
    final button = find.byTooltip(LibraryStrings.itemMenu(name));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, entry));
    await tester.pumpAndSettle();
  }

  List<String> menuEntries(WidgetTester tester) => [
    for (final e in find.byType(MenuItemButton).evaluate())
      ((e.widget as MenuItemButton).child! as Text).data!,
  ];

  Future<void> tapUndo(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(SnackBarAction, LibraryStrings.undo));
    await tester.pumpAndSettle();
  }

  Future<Note?> noteNow(WidgetTester tester, NoteId id) =>
      real(tester, () => backend.store.library.getNote(id));

  Future<Folder?> folderNow(WidgetTester tester, FolderId id) =>
      real(tester, () => backend.store.library.getFolder(id));

  FilledButton filled(WidgetTester tester, String label) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

  group('menus', () {
    testWidgets('note ⋯: 이름 변경 · 표지 변경 · 즐겨찾기 · 복사 · 이동… · 휴지통', (
      tester,
    ) async {
      await seed(tester);
      await pumpAt(tester);
      await tester.tap(find.byTooltip(LibraryStrings.itemMenu('회의록')));
      await tester.pumpAndSettle();
      expect(menuEntries(tester), [
        LibraryStrings.rename,
        LibraryStrings.changeCover,
        LibraryStrings.favoriteAdd,
        LibraryStrings.copy,
        LibraryStrings.moveTo,
        LibraryStrings.moveToTrash,
      ]);
      // The PDF slot is null in the foundation stage: no export entry.
      expect(find.text(LibraryStrings.exportPdfOne), findsNothing);
    });

    testWidgets('folder ⋯: 이름 변경 · 꾸미기 · 복사 · 이동… · 휴지통', (tester) async {
      await seed(tester);
      await pumpAt(tester);
      await tester.tap(find.byTooltip(LibraryStrings.itemMenu('수학')));
      await tester.pumpAndSettle();
      expect(menuEntries(tester), [
        LibraryStrings.rename,
        LibraryStrings.customize,
        LibraryStrings.copy,
        LibraryStrings.moveTo,
        LibraryStrings.moveToTrash,
      ]);
    });

    testWidgets('the ⋯ of a tile is 44 × 44 next to the title', (tester) async {
      await seed(tester);
      await pumpAt(tester);
      final button = find.descendant(
        of: find.widgetWithText(NoteTile, '회의록'),
        matching: find.byTooltip(LibraryStrings.itemMenu('회의록')),
      );
      expect(button, findsOneWidget);
      expect(tester.getSize(button), const Size(44, 44));
      final tile = tester.getRect(find.widgetWithText(NoteTile, '회의록'));
      expect(tester.getRect(button).right, moreOrLessEquals(tile.right));
    });
  });

  group('rename', () {
    testWidgets('a note: name selected, [저장] only when changed, Enter saves', (
      tester,
    ) async {
      final sample = await seed(tester);
      final h = await pumpAt(tester);
      await menu(tester, '회의록', LibraryStrings.rename);
      expect(find.byType(RenameDialog), findsOneWidget);
      final field = find.byType(TextField);
      final controller = tester.widget<TextField>(field).controller!;
      expect(controller.text, '회의록');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 3),
      );
      expect(filled(tester, LibraryStrings.save).onPressed, isNull);
      await tester.enterText(field, '   ');
      await tester.pump();
      expect(filled(tester, LibraryStrings.save).onPressed, isNull);
      await tester.enterText(field, '회의록 ');
      await tester.pump();
      expect(filled(tester, LibraryStrings.save).onPressed, isNull);
      await tester.enterText(field, ' 주간 회의록 ');
      await tester.pump();
      expect(filled(tester, LibraryStrings.save).onPressed, isNotNull);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(RenameDialog), findsNothing);
      final id = sample.homeNotes[0].id;
      expect(backend.calls, ["renameNote n:$id '주간 회의록'"]);
      expect((await noteNow(tester, id))!.title, '주간 회의록');
      expect(find.widgetWithText(NoteTile, '주간 회의록'), findsOneWidget);
      // Success shows nothing; nothing navigates.
      expect(find.byType(SnackBar), findsNothing);
      expect(h.log.entries, isEmpty);
    });

    testWidgets('a folder via [저장]; [취소] changes nothing', (tester) async {
      final sample = await seed(tester);
      await pumpAt(tester);
      await menu(tester, '영어', LibraryStrings.rename);
      await tester.tap(find.text(LibraryStrings.cancel));
      await tester.pumpAndSettle();
      expect(backend.calls, isEmpty);

      await menu(tester, '영어', LibraryStrings.rename);
      await tester.enterText(find.byType(TextField), '외국어');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, LibraryStrings.save));
      await tester.pumpAndSettle();
      expect(backend.calls, ["renameFolder f:${sample.english.id} '외국어'"]);
      // Tile and sidebar row both follow the CORE stream.
      expect(find.widgetWithText(FolderTile, '외국어'), findsOneWidget);
      expect(find.widgetWithText(SidebarTreeRow, '외국어'), findsOneWidget);
    });

    testWidgets('the counter shows from 180 characters; 200 at most', (
      tester,
    ) async {
      final name = 'ㄱ' * 179;
      await real(tester, () => backend.seedNote(name));
      await pumpAt(tester);
      await menu(tester, name, LibraryStrings.rename);
      expect(find.text(LibraryStrings.characterCount(179, 200)), findsNothing);
      await tester.enterText(find.byType(TextField), 'ㄴ' * 180);
      await tester.pump();
      expect(
        find.text(LibraryStrings.characterCount(180, 200)),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'ㄴ' * 205);
      await tester.pump();
      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      expect(controller.text.length, 200);
      expect(
        find.text(LibraryStrings.characterCount(200, 200)),
        findsOneWidget,
      );
      expect(filled(tester, LibraryStrings.save).onPressed, isNotNull);
    });

    testWidgets('a failed rename shows the generic error (reported)', (
      tester,
    ) async {
      await seed(tester);
      await pumpAt(tester);
      await menu(tester, '일기', LibraryStrings.rename);
      await tester.enterText(find.byType(TextField), '일기장');
      await tester.pump();
      backend.failNextMutation = StateError('disk');
      await tester.tap(find.widgetWithText(FilledButton, LibraryStrings.save));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isA<StateError>());
      expect(find.text(LibraryStrings.errorGeneric), findsOneWidget);
      expect(find.widgetWithText(NoteTile, '일기'), findsOneWidget);
    });
  });

  testWidgets('꾸미기: preview, color and icon → setFolderAppearance', (
    tester,
  ) async {
    final sample = await seed(tester);
    await pumpAt(tester);
    final id = sample.math.id;
    await menu(tester, '수학', LibraryStrings.customize);
    expect(find.byType(FolderAppearanceDialog), findsOneWidget);
    expect(find.text(LibraryStrings.preview), findsOneWidget);
    expect(filled(tester, LibraryStrings.save).onPressed, isNull);
    await tester.tap(find.byTooltip(FolderPalette.names[3]));
    await tester.pump();
    await tester.tap(find.byTooltip(FolderIcons.labelFor('calculate')));
    await tester.pump();
    // The preview follows the choice.
    final preview = find.descendant(
      of: find.byType(FolderAppearanceDialog),
      matching: find.byIcon(Icons.calculate),
    );
    expect(preview, findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, LibraryStrings.save));
    await tester.pumpAndSettle();
    final color = FolderPalette.colors[3];
    final hex = color.toRadixString(16).toUpperCase().padLeft(8, '0');
    expect(backend.calls, [
      'setFolderAppearance f:$id color:0x$hex icon:calculate',
    ]);
    final stored = (await folderNow(tester, id))!;
    expect(stored.colorArgb, color);
    expect(stored.icon, 'calculate');
    expect(find.byType(SnackBar), findsNothing);

    // Back to 없음 + the default icon → both cleared.
    await menu(tester, '수학', LibraryStrings.customize);
    await tester.tap(find.text(LibraryStrings.colorNone));
    await tester.pump();
    await tester.tap(
      find.byTooltip(FolderIcons.labelFor(FolderIcons.defaultKey)),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, LibraryStrings.save));
    await tester.pumpAndSettle();
    expect(
      backend.calls.last,
      'setFolderAppearance f:$id clearColor clearIcon',
    );
    final cleared = (await folderNow(tester, id))!;
    expect(cleared.colorArgb, isNull);
    expect(cleared.icon, isNull);
  });

  testWidgets('표지 변경: a color cover → setCover; the same cover saves nothing', (
    tester,
  ) async {
    final sample = await seed(tester);
    await pumpAt(tester);
    final id = sample.homeNotes[2].id;
    await menu(tester, '아이디어', LibraryStrings.changeCover);
    expect(find.byType(CoverDialog), findsOneWidget);
    // Current = 첫 페이지: [저장] waits for a change.
    expect(filled(tester, LibraryStrings.save).onPressed, isNull);
    await tester.tap(find.byTooltip(CoverPalette.names[0]));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, LibraryStrings.save));
    await tester.pumpAndSettle();
    final argb = CoverPalette.colors[0];
    final hex = argb.toRadixString(16).toUpperCase().padLeft(8, '0');
    expect(backend.calls, ['setCover n:$id color:0x$hex']);
    expect((await noteNow(tester, id))!.cover, ColorCover(argb));

    await menu(tester, '아이디어', LibraryStrings.changeCover);
    await tester.tap(find.byTooltip(CoverPalette.names[1]));
    await tester.pump();
    await tester.tap(find.byTooltip(CoverPalette.names[0]));
    await tester.pump();
    expect(filled(tester, LibraryStrings.save).onPressed, isNull);
    await tester.tap(find.text(LibraryStrings.coverFirstPage));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, LibraryStrings.save));
    await tester.pumpAndSettle();
    expect(backend.calls.last, 'setCover n:$id firstPage');
  });

  testWidgets('즐겨찾기 from the menu, then 즐겨찾기 해제', (tester) async {
    final sample = await seed(tester);
    await pumpAt(tester);
    final id = sample.homeNotes[1].id;
    await menu(tester, '독서 기록', LibraryStrings.favoriteAdd);
    expect(backend.calls, ['setFavorite [n:$id] true']);
    expect((await noteNow(tester, id))!.isFavorite, isTrue);
    await tester.tap(find.byTooltip(LibraryStrings.itemMenu('독서 기록')));
    await tester.pumpAndSettle();
    expect(menuEntries(tester), contains(LibraryStrings.favoriteRemove));
    await tester.tap(
      find.widgetWithText(MenuItemButton, LibraryStrings.favoriteRemove),
    );
    await tester.pumpAndSettle();
    expect(backend.calls.last, 'setFavorite [n:$id] false');
    expect(find.byType(SnackBar), findsNothing);
  });

  group('copy', () {
    testWidgets("a note: same folder with ' 사본' → '복사했어요'", (tester) async {
      final sample = await seed(tester);
      await pumpAt(tester, folderId: sample.deepest.id);
      await menu(tester, '극한 정리', LibraryStrings.copy);
      final note = sample.deepNote.id, folder = sample.deepest.id;
      expect(backend.calls, ["copyItems [n:$note] -> f:$folder suffix:' 사본'"]);
      expect(find.text(LibraryStrings.copied), findsOneWidget);
      expect(find.text('복사했어요'), findsOneWidget);
      expect(find.widgetWithText(NoteTile, '극한 정리 사본'), findsOneWidget);
      // No undo for a copy.
      expect(find.byType(SnackBarAction), findsNothing);
    });

    testWidgets('a folder at home copies into home', (tester) async {
      final sample = await seed(tester);
      await pumpAt(tester);
      await menu(tester, '과학', LibraryStrings.copy);
      expect(backend.calls, [
        "copyItems [f:${sample.science.id}] -> home suffix:' 사본'",
      ]);
      expect(find.widgetWithText(FolderTile, '과학 사본'), findsOneWidget);
    });
  });

  group('move', () {
    testWidgets("a note into '영어' → \"'영어'로 옮겼어요\" + 실행 취소", (tester) async {
      final sample = await seed(tester);
      await pumpAt(tester);
      final id = sample.homeNotes[0].id;
      await menu(tester, '회의록', LibraryStrings.moveTo);
      expect(find.byType(FolderPickerDialog), findsOneWidget);
      expect(find.text(LibraryStrings.moveDestination), findsOneWidget);
      // Already at home: confirming 홈 would change nothing.
      expect(filled(tester, LibraryStrings.moveHere).onPressed, isNull);
      await tester.tap(find.widgetWithText(FolderPickerRow, '영어'));
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, LibraryStrings.moveHere),
      );
      await tester.pumpAndSettle();

      expect(backend.calls, ['moveItems [n:$id] -> f:${sample.english.id}']);
      expect(find.text("'영어'로 옮겼어요"), findsOneWidget);
      expect(find.text(LibraryStrings.movedTo('영어')), findsOneWidget);
      expect(find.widgetWithText(NoteTile, '회의록'), findsNothing);
      expect((await noteNow(tester, id))!.folderId, sample.english.id);

      await tapUndo(tester);
      expect(backend.calls.last, 'moveItems [n:$id] -> home');
      expect((await noteNow(tester, id))!.folderId, isNull);
      expect(find.widgetWithText(NoteTile, '회의록'), findsOneWidget);
    });

    testWidgets("a folder into '수학' → \"'수학'으로 옮겼어요\"; back to 홈", (
      tester,
    ) async {
      final sample = await seed(tester);
      await pumpAt(tester);
      final id = sample.science.id;
      await menu(tester, '과학', LibraryStrings.moveTo);
      // The moved folder itself is disabled.
      expect(
        tester
            .widget<FolderPickerRow>(find.widgetWithText(FolderPickerRow, '과학'))
            .enabled,
        isFalse,
      );
      await tester.tap(find.widgetWithText(FolderPickerRow, '수학'));
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, LibraryStrings.moveHere),
      );
      await tester.pumpAndSettle();
      expect(backend.calls, ['moveItems [f:$id] -> f:${sample.math.id}']);
      expect(find.text("'수학'으로 옮겼어요"), findsOneWidget);
      expect((await folderNow(tester, id))!.parentId, sample.math.id);

      // From inside 수학, move it to 홈.
      await tester.tap(find.widgetWithText(FolderTile, '수학'));
      await tester.pumpAndSettle();
      await menu(tester, '과학', LibraryStrings.moveTo);
      expect(filled(tester, LibraryStrings.moveHere).onPressed, isNull);
      await tester.tap(
        find.widgetWithText(FolderPickerRow, LibraryStrings.home),
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, LibraryStrings.moveHere),
      );
      await tester.pumpAndSettle();
      expect(backend.calls.last, 'moveItems [f:$id] -> home');
      expect(find.text("'홈'으로 옮겼어요"), findsOneWidget);
    });

    testWidgets('a cycle from a race shows errorCycle and is not reported', (
      tester,
    ) async {
      final sample = await seed(tester);
      await pumpAt(tester);
      await menu(tester, '영어', LibraryStrings.moveTo);
      await tester.tap(find.widgetWithText(FolderPickerRow, '수학'));
      await tester.pump();
      backend.failNextMutation = const FolderCycleException('race');
      await tester.tap(
        find.widgetWithText(FilledButton, LibraryStrings.moveHere),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(LibraryStrings.errorCycle), findsOneWidget);
      expect((await folderNow(tester, sample.english.id))!.parentId, isNull);
    });

    testWidgets('a failed undo shows errorNotFound (reported)', (tester) async {
      final sample = await seed(tester);
      await pumpAt(tester);
      await menu(tester, '일기', LibraryStrings.moveTo);
      await tester.tap(find.widgetWithText(FolderPickerRow, '과학'));
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, LibraryStrings.moveHere),
      );
      await tester.pumpAndSettle();
      backend.failNextMutation = const EntityNotFoundException('gone');
      await tapUndo(tester);
      expect(tester.takeException(), isA<EntityNotFoundException>());
      expect(find.text(LibraryStrings.errorNotFound), findsOneWidget);
      expect(
        (await noteNow(tester, sample.homeNotes[3].id))!.folderId,
        sample.science.id,
      );
    });
  });

  group('trash', () {
    testWidgets("folder '수학' → \"'수학'을 휴지통으로 옮겼어요\" + 실행 취소 → restore", (
      tester,
    ) async {
      final sample = await seed(tester);
      await pumpAt(tester);
      final id = sample.math.id;
      await menu(tester, '수학', LibraryStrings.moveToTrash);
      // No confirmation.
      expect(find.byType(Dialog), findsNothing);
      expect(backend.calls, ['trashItems [f:$id]']);
      expect(find.text("'수학'을 휴지통으로 옮겼어요"), findsOneWidget);
      expect(find.widgetWithText(FolderTile, '수학'), findsNothing);
      expect(find.widgetWithText(SidebarTreeRow, '수학'), findsNothing);
      expect((await folderNow(tester, id))!.isDeleted, isTrue);

      await tapUndo(tester);
      expect(backend.calls.last, 'restore [f:$id]');
      expect((await folderNow(tester, id))!.isDeleted, isFalse);
      expect(find.widgetWithText(FolderTile, '수학'), findsOneWidget);
    });

    testWidgets("note '아이디어' → '를'; 'Math' → '을(를)'", (tester) async {
      await seed(tester);
      await real(tester, () => backend.seedNote('Math'));
      await pumpAt(tester);
      await menu(tester, '아이디어', LibraryStrings.moveToTrash);
      expect(find.text("'아이디어'를 휴지통으로 옮겼어요"), findsOneWidget);
      await menu(tester, 'Math', LibraryStrings.moveToTrash);
      // The new snack bar replaces the previous one.
      await tester.pumpAndSettle();
      expect(find.text("'Math'을(를) 휴지통으로 옮겼어요"), findsOneWidget);
      expect(find.text("'아이디어'를 휴지통으로 옮겼어요"), findsNothing);
    });

    testWidgets('the same action on the same item runs once at a time', (
      tester,
    ) async {
      final sample = await seed(tester);
      await pumpAt(tester);
      // Long enough that the menu animations below cannot outlast it.
      backend.latency = const Duration(seconds: 30);
      await menu(tester, '일기', LibraryStrings.moveToTrash);
      // Still pending: the tile is there; trash it again from its menu.
      expect(find.widgetWithText(NoteTile, '일기'), findsOneWidget);
      await menu(tester, '일기', LibraryStrings.moveToTrash);
      expect(find.widgetWithText(NoteTile, '일기'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(backend.calls, ['trashItems [n:${sample.homeNotes[3].id}]']);
      expect(find.text("'일기'를 휴지통으로 옮겼어요"), findsOneWidget);
    });
  });

  testWidgets('list rows have the same ⋯ menu', (tester) async {
    final sample = await seed(tester);
    await pumpAt(tester);
    await tester.tap(find.byTooltip(LibraryStrings.viewAsList));
    await tester.pumpAndSettle();
    final row = find.widgetWithText(NoteListRow, '회의록');
    final button = find.descendant(
      of: row,
      matching: find.byTooltip(LibraryStrings.itemMenu('회의록')),
    );
    expect(tester.getSize(button), const Size(44, 44));
    await menu(tester, '회의록', LibraryStrings.moveToTrash);
    expect(backend.calls, ['trashItems [n:${sample.homeNotes[0].id}]']);
    await menu(tester, '영어', LibraryStrings.copy);
    expect(find.widgetWithText(FolderListRow, '영어 사본'), findsOneWidget);
  });

  group('sidebar tree row menu', () {
    const sidebarEntries = [
      LibraryStrings.rename,
      LibraryStrings.customize,
      LibraryStrings.newSubfolder,
      LibraryStrings.moveTo,
      LibraryStrings.moveToTrash,
    ];

    testWidgets('long press released in place → menu; 새 하위 폴더', (tester) async {
      final sample = await seed(tester);
      final h = await pumpAt(tester);
      await tester.longPress(find.widgetWithText(SidebarTreeRow, '영어'));
      await tester.pumpAndSettle();
      expect(menuEntries(tester), sidebarEntries);
      await tester.tap(
        find.widgetWithText(MenuItemButton, LibraryStrings.newSubfolder),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NewFolderDialog), findsOneWidget);
      expect(find.text('홈 › 영어'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, LibraryStrings.create),
      );
      await tester.pumpAndSettle();
      expect(backend.calls, ["createFolder f:${sample.english.id} '새 폴더'"]);
      // The parent opens in the tree; nothing navigates.
      expect(find.widgetWithText(SidebarTreeRow, '새 폴더'), findsOneWidget);
      expect(h.log.entries, isEmpty);
    });

    testWidgets('a secondary click opens the menu; rename from it', (
      tester,
    ) async {
      final sample = await seed(tester);
      await pumpAt(tester);
      await tester.tap(
        find.widgetWithText(SidebarTreeRow, '과학'),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(menuEntries(tester), sidebarEntries);
      await tester.tap(
        find.widgetWithText(MenuItemButton, LibraryStrings.rename),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '물리');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(backend.calls, ["renameFolder f:${sample.science.id} '물리'"]);
    });

    testWidgets('a long press that moves away opens nothing; a tap opens the '
        'folder', (tester) async {
      final sample = await seed(tester);
      final h = await pumpAt(tester);
      final row = find.widgetWithText(SidebarTreeRow, '영어');
      final gesture = await tester.startGesture(tester.getCenter(row));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      expect(h.log.entries, isEmpty);

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      expect(h.log.entries, ['folder:${sample.english.id}']);
    });

    testWidgets('trash from the tree row; move from the tree row', (
      tester,
    ) async {
      final sample = await seed(tester);
      await pumpAt(tester);
      await tester.longPress(find.widgetWithText(SidebarTreeRow, '과학'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(MenuItemButton, LibraryStrings.moveToTrash),
      );
      await tester.pumpAndSettle();
      expect(backend.calls, ['trashItems [f:${sample.science.id}]']);
      expect(find.text("'과학'을 휴지통으로 옮겼어요"), findsOneWidget);

      await tester.longPress(find.widgetWithText(SidebarTreeRow, '영어'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(MenuItemButton, LibraryStrings.moveTo),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FolderPickerRow, '수학'));
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, LibraryStrings.moveHere),
      );
      await tester.pumpAndSettle();
      expect(
        backend.calls.last,
        'moveItems [f:${sample.english.id}] -> f:${sample.math.id}',
      );
    });

    testWidgets('the menu works from the drawer (portrait)', (tester) async {
      final sample = await seed(tester);
      await pumpAt(tester, size: TestSizes.ipad13Portrait);
      await tester.tap(find.byTooltip(LibraryStrings.openMenu));
      await tester.pumpAndSettle();
      await tester.longPress(find.widgetWithText(SidebarTreeRow, '영어'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(MenuItemButton, LibraryStrings.moveToTrash),
      );
      await tester.pumpAndSettle();
      expect(backend.calls, ['trashItems [f:${sample.english.id}]']);
      expect(find.text("'영어'를 휴지통으로 옮겼어요"), findsOneWidget);
    });
  });
}
