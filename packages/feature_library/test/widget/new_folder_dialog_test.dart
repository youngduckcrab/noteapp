// New folder dialog (05-library 6.12, 8 L12): color and icon reach
// createFolder, the parent is expanded in the sidebar and nothing navigates;
// default name / location, empty name, cancel, the three entry points
// (sidebar '폴더' '+', empty state, top bar '새로 만들기'), failures.
import 'package:feature_library/src/appearance/folder_appearance.dart';
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/ui/content/folder_tile.dart';
import 'package:feature_library/src/ui/dialogs/new_folder_dialog.dart';
import 'package:feature_library/src/ui/sidebar/sidebar_rows.dart';
import 'package:feature_library/src/ui/top_bar/library_top_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';

import '../support/fake_library_backend.dart';
import '../support/library_test_harness.dart';
import '../support/test_sizes.dart';

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

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

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(LibraryTopBar)));

  /// 새로 만들기 › 새 폴더 (v2.14-ui: where the sidebar '폴더 +' went).
  Future<void> openFromNewMenu(WidgetTester tester) async {
    await tester.tap(find.text(LibraryStrings.newMenu));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(MenuItemButton, LibraryStrings.newFolder),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NewFolderDialog), findsOneWidget);
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> create(WidgetTester tester) async {
    await tapVisible(
      tester,
      find.widgetWithText(FilledButton, LibraryStrings.create),
    );
    expect(find.byType(NewFolderDialog), findsNothing);
  }

  TextEditingController nameController(WidgetTester tester) => tester
      .widget<TextField>(
        find.widgetWithText(TextField, LibraryStrings.fieldName),
      )
      .controller!;

  testWidgets('color and icon reach createFolder; the parent is expanded', (
    tester,
  ) async {
    final math = await real(tester, () => backend.seedFolder('수학'));
    final h = await pumpAt(tester, folderId: math.id);
    // The route shows 수학 but it has no children yet: collapsed.
    expect(containerOf(tester).read(folderExpansionProvider), isEmpty);
    await openFromNewMenu(tester);
    expect(nameController(tester).text, LibraryStrings.defaultFolderName);
    expect(find.text('홈 › 수학'), findsOneWidget);
    await tapVisible(tester, find.byTooltip(FolderPalette.names[1])); // 초록
    await tapVisible(tester, find.byTooltip(FolderIcons.labelFor('book')));
    await create(tester);

    expect(backend.calls, [
      "createFolder f:${math.id} '새 폴더' color:0xFF4CAF7A icon:book",
    ]);
    expect(containerOf(tester).read(folderExpansionProvider), {math.id});
    // Not opened: no navigation; the new folder shows in the tree and in
    // the listing of 수학.
    expect(h.log.entries, isEmpty);
    expect(find.widgetWithText(SidebarTreeRow, '새 폴더'), findsOneWidget);
    expect(find.widgetWithText(FolderTile, '새 폴더'), findsOneWidget);
    final created = (await real(
      tester,
      () => backend.store.library.watchFolderTree().first,
    )).childrenOf(math.id).single;
    expect(created.colorArgb, FolderPalette.colors[1]);
    expect(created.icon, 'book');
  });

  testWidgets('no color and the default icon → neither is stored', (
    tester,
  ) async {
    await pumpAt(tester);
    await openFromNewMenu(tester);
    // Pick a color and an icon, then go back to 없음 and the folder icon.
    await tapVisible(tester, find.byTooltip(FolderPalette.names[0]));
    await tapVisible(tester, find.byTooltip(FolderIcons.labelFor('music')));
    await tapVisible(tester, find.text(LibraryStrings.colorNone));
    await tapVisible(
      tester,
      find.byTooltip(FolderIcons.labelFor(FolderIcons.defaultKey)),
    );
    await create(tester);
    expect(backend.calls, ["createFolder home '새 폴더'"]);
  });

  testWidgets("default name '새 폴더 2'; empty name → default; ancestors open", (
    tester,
  ) async {
    final math = await real(tester, () => backend.seedFolder('수학'));
    final calculus = await real(
      tester,
      () => backend.seedFolder('미적분', parentId: math.id),
    );
    await real(tester, () => backend.seedFolder('새 폴더', parentId: calculus.id));
    await pumpAt(tester, folderId: calculus.id);
    final container = containerOf(tester);
    // Showing 미적분 reveals it (its parent 수학 opens).
    expect(container.read(folderExpansionProvider), {math.id});
    await openFromNewMenu(tester);
    expect(nameController(tester).text, '새 폴더 2');
    expect(find.text('홈 › 수학 › 미적분'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, LibraryStrings.fieldName),
      '',
    );
    await create(tester);
    expect(backend.calls, ["createFolder f:${calculus.id} '새 폴더 2'"]);
    expect(container.read(folderExpansionProvider), {math.id, calculus.id});
  });

  testWidgets('[취소] creates nothing', (tester) async {
    final h = await pumpAt(tester);
    await openFromNewMenu(tester);
    await tester.tap(find.text(LibraryStrings.cancel));
    await tester.pumpAndSettle();
    expect(find.byType(NewFolderDialog), findsNothing);
    expect(backend.calls, isEmpty);
    expect(h.log.entries, isEmpty);
  });

  testWidgets('sidebar + outside a folder section → 홈', (tester) async {
    final math = await real(tester, () => backend.seedFolder('수학'));
    await pumpAt(tester, folderId: math.id);
    await tester.tap(find.text(LibraryStrings.favorites));
    await tester.pumpAndSettle();
    await openFromNewMenu(tester);
    expect(find.text(LibraryStrings.home), findsWidgets);
    await create(tester);
    expect(backend.calls, ["createFolder home '새 폴더'"]);
  });

  testWidgets('empty state [새 폴더] and top bar 새로 만들기 › 새 폴더', (tester) async {
    await pumpAt(tester);
    await tester.tap(
      find.widgetWithText(OutlinedButton, LibraryStrings.newFolder),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NewFolderDialog), findsOneWidget);
    await create(tester);
    expect(backend.calls.last, "createFolder home '새 폴더'");
    // It shows in the home listing right away.
    expect(find.widgetWithText(FolderTile, '새 폴더'), findsOneWidget);

    await tester.tap(find.text(LibraryStrings.newMenu));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(MenuItemButton, LibraryStrings.newFolder),
    );
    await tester.pumpAndSettle();
    expect(nameController(tester).text, '새 폴더 2');
    await create(tester);
    expect(backend.calls.last, "createFolder home '새 폴더 2'");
  });

  testWidgets('a failed createFolder shows the generic error', (tester) async {
    await pumpAt(tester);
    await openFromNewMenu(tester);
    backend.failNextMutation = StateError('x');
    await create(tester);
    expect(tester.takeException(), isA<StateError>());
    await tester.pump();
    expect(find.text(LibraryStrings.errorGeneric), findsOneWidget);
  });

  testWidgets('no 새로 만들기 in the trash', (tester) async {
    await pumpAt(tester);
    await tester.tap(find.text(LibraryStrings.trash));
    await tester.pumpAndSettle();
    expect(find.text(LibraryStrings.newMenu), findsNothing);
  });

  testWidgets('the dialog lays out in the compact class', (tester) async {
    await pumpAt(tester, size: TestSizes.compact);
    await tester.tap(find.byTooltip(LibraryStrings.newMenu));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(MenuItemButton, LibraryStrings.newFolder),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NewFolderDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await create(tester);
    expect(backend.calls, ["createFolder home '새 폴더'"]);
  });
}
