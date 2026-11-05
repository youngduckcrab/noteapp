// Folder picker dialog (05-library 6.11, 8 L13): disabled sub-folders,
// choosing 홈, a new folder made inside the dialog, the confirm button
// disabled for a no-op target; its own expansion state, its size, cancel.
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/ui/dialogs/folder_picker_dialog.dart';
import 'package:feature_library/src/ui/dialogs/new_folder_dialog.dart';
import 'package:feature_library/src/ui/top_bar/library_top_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  /// ⋯ › 이동… of the item named [name] (opens the picker).
  Future<void> openMove(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip(LibraryStrings.itemMenu(name)));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(MenuItemButton, LibraryStrings.moveTo),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FolderPickerDialog), findsOneWidget);
  }

  Finder row(String label) => find.widgetWithText(FolderPickerRow, label);

  FolderPickerRow rowWidget(WidgetTester tester, String label) =>
      tester.widget<FolderPickerRow>(row(label));

  /// Labels of the picker rows, top to bottom.
  List<String> rowLabels(WidgetTester tester) => [
    for (final e in find.byType(FolderPickerRow).evaluate())
      (e.widget as FolderPickerRow).label,
  ];

  VoidCallback? confirm(WidgetTester tester, String label) => tester
      .widget<FilledButton>(find.widgetWithText(FilledButton, label))
      .onPressed;

  VoidCallback? newFolderButton(WidgetTester tester) => tester
      .widget<TextButton>(
        find.ancestor(
          of: find.descendant(
            of: find.byType(FolderPickerDialog),
            matching: find.text(LibraryStrings.newFolder),
          ),
          matching: find.byWidgetPredicate((w) => w is TextButton),
        ),
      )
      .onPressed;

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(row(label));
    await tester.pump();
  }

  testWidgets('disabled sub-folders: opacity 0.38, cannot be chosen', (
    tester,
  ) async {
    final sample = await seed(tester);
    await pumpAt(tester);
    final context = tester.element(find.byType(LibraryTopBar));
    final math = sample.math.id;
    final disabled = {math, for (final f in sample.nested) f.id};
    final result = showFolderPickerDialog(
      context,
      title: LibraryStrings.moveDestination,
      confirmLabel: LibraryStrings.moveHere,
      initialFolderId: sample.deepest.id,
      disabled: disabled,
    );
    await tester.pumpAndSettle();

    // The path to the initial folder is open; top-level folders by name.
    expect(rowLabels(tester), [
      LibraryStrings.home,
      '과학',
      '수학',
      '미적분',
      '극한',
      '연습 문제',
      '영어',
    ]);
    for (final name in ['수학', '미적분', '극한', '연습 문제']) {
      expect(rowWidget(tester, name).enabled, isFalse, reason: name);
      final opacity = tester.widget<Opacity>(
        find.descendant(of: row(name), matching: find.byType(Opacity)),
      );
      expect(opacity.opacity, 0.38, reason: name);
    }
    for (final name in [LibraryStrings.home, '과학', '영어']) {
      expect(rowWidget(tester, name).enabled, isTrue, reason: name);
      expect(
        find.descendant(of: row(name), matching: find.byType(Opacity)),
        findsNothing,
      );
    }
    // The initial (disabled) folder cannot be confirmed or built into.
    expect(rowWidget(tester, '연습 문제').selected, isTrue);
    expect(confirm(tester, LibraryStrings.moveHere), isNull);
    expect(newFolderButton(tester), isNull);
    // A disabled row ignores taps and has no ▸ / ▾.
    await choose(tester, '극한');
    expect(rowWidget(tester, '극한').selected, isFalse);
    expect(
      find.descendant(
        of: row('수학'),
        matching: find.byTooltip(LibraryStrings.collapseFolder),
      ),
      findsNothing,
    );

    await choose(tester, '영어');
    expect(rowWidget(tester, '영어').selected, isTrue);
    expect(confirm(tester, LibraryStrings.moveHere), isNotNull);
    await tester.tap(
      find.widgetWithText(FilledButton, LibraryStrings.moveHere),
    );
    await tester.pumpAndSettle();
    expect(await result, FolderPickerResult(sample.english.id));
    expect(backend.calls, isEmpty);
  });

  testWidgets('move: the moved folder is disabled from the ⋯ flow', (
    tester,
  ) async {
    await seed(tester);
    await pumpAt(tester);
    await openMove(tester, '수학');
    expect(rowWidget(tester, '수학').enabled, isFalse);
    // Its sub-folders cannot even be shown (no ▸ on a disabled row).
    expect(rowLabels(tester), [LibraryStrings.home, '과학', '수학', '영어']);
    await choose(tester, '수학');
    expect(rowWidget(tester, LibraryStrings.home).selected, isTrue);
  });

  testWidgets('홈 is a valid choice', (tester) async {
    final sample = await seed(tester);
    await pumpAt(tester, folderId: sample.deepest.id);
    await openMove(tester, '극한 정리');
    // Starts at the note's folder with the path open; that is a no-op.
    expect(rowWidget(tester, '연습 문제').selected, isTrue);
    expect(rowLabels(tester), containsAllInOrder(['수학', '미적분', '극한', '연습 문제']));
    expect(confirm(tester, LibraryStrings.moveHere), isNull);
    await choose(tester, LibraryStrings.home);
    expect(rowWidget(tester, LibraryStrings.home).selected, isTrue);
    expect(confirm(tester, LibraryStrings.moveHere), isNotNull);
    await tester.tap(
      find.widgetWithText(FilledButton, LibraryStrings.moveHere),
    );
    await tester.pumpAndSettle();
    expect(backend.calls, ['moveItems [n:${sample.deepNote.id}] -> home']);
    expect(find.text("'홈'으로 옮겼어요"), findsOneWidget);
  });

  testWidgets('no-op target: the confirm button is disabled only there', (
    tester,
  ) async {
    final sample = await seed(tester);
    await pumpAt(tester, folderId: sample.math.id);
    await openMove(tester, '미적분');
    expect(rowWidget(tester, '수학').selected, isTrue);
    expect(rowWidget(tester, '미적분').enabled, isFalse);
    expect(confirm(tester, LibraryStrings.moveHere), isNull);
    await choose(tester, '과학');
    expect(confirm(tester, LibraryStrings.moveHere), isNotNull);
    await choose(tester, '수학');
    expect(confirm(tester, LibraryStrings.moveHere), isNull);
    await choose(tester, LibraryStrings.home);
    expect(confirm(tester, LibraryStrings.moveHere), isNotNull);
  });

  testWidgets('새 폴더 inside the dialog: made in the chosen folder, chosen', (
    tester,
  ) async {
    final sample = await seed(tester);
    await pumpAt(tester);
    final note = sample.homeNotes[0];
    await openMove(tester, '회의록');
    await choose(tester, '영어');
    await tester.tap(
      find.descendant(
        of: find.byType(FolderPickerDialog),
        matching: find.text(LibraryStrings.newFolder),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NewFolderDialog), findsOneWidget);
    expect(find.text('홈 › 영어'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, LibraryStrings.fieldName),
      '단어장',
    );
    await tester.tap(find.widgetWithText(FilledButton, LibraryStrings.create));
    await tester.pumpAndSettle();
    expect(find.byType(NewFolderDialog), findsNothing);
    expect(find.byType(FolderPickerDialog), findsOneWidget);

    expect(backend.calls, ["createFolder f:${sample.english.id} '단어장'"]);
    // 영어 opened, the new folder below it is chosen.
    final labels = rowLabels(tester);
    expect(labels.indexOf('단어장'), labels.indexOf('영어') + 1);
    expect(rowWidget(tester, '단어장').selected, isTrue);
    expect(rowWidget(tester, '단어장').depth, rowWidget(tester, '영어').depth + 1);
    await tester.tap(
      find.widgetWithText(FilledButton, LibraryStrings.moveHere),
    );
    await tester.pumpAndSettle();
    final created = (await real(
      tester,
      () => backend.store.library.watchFolderTree().first,
    )).childrenOf(sample.english.id).single;
    expect(backend.calls.last, 'moveItems [n:${note.id}] -> f:${created.id}');
    expect(find.text("'단어장'으로 옮겼어요"), findsOneWidget);
  });

  testWidgets('새 폴더 with 홈 chosen; cancelling it keeps the picker', (
    tester,
  ) async {
    final sample = await seed(tester);
    await pumpAt(tester, folderId: sample.math.id);
    await openMove(tester, '미적분');
    await choose(tester, LibraryStrings.home);
    final newFolder = find.descendant(
      of: find.byType(FolderPickerDialog),
      matching: find.text(LibraryStrings.newFolder),
    );
    await tester.tap(newFolder);
    await tester.pumpAndSettle();
    await tester.tap(find.text(LibraryStrings.cancel).last);
    await tester.pumpAndSettle();
    expect(find.byType(FolderPickerDialog), findsOneWidget);
    expect(backend.calls, isEmpty);
    expect(newFolderButton(tester), isNotNull);

    await tester.tap(newFolder);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, LibraryStrings.create));
    await tester.pumpAndSettle();
    expect(backend.calls, ["createFolder home '새 폴더'"]);
    expect(rowWidget(tester, '새 폴더').selected, isTrue);
    expect(rowWidget(tester, '새 폴더').depth, 1);
  });

  testWidgets(
    '[취소] returns nothing; ▸ in the picker leaves the sidebar alone',
    (tester) async {
      final sample = await seed(tester);
      final h = await pumpAt(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryTopBar)),
      );
      expect(container.read(folderExpansionProvider), isEmpty);
      await openMove(tester, '회의록');
      expect(rowLabels(tester), [LibraryStrings.home, '과학', '수학', '영어']);
      await tester.tap(
        find.descendant(
          of: row('수학'),
          matching: find.byTooltip(LibraryStrings.expandFolder),
        ),
      );
      await tester.pump();
      expect(rowLabels(tester), [LibraryStrings.home, '과학', '수학', '미적분', '영어']);
      expect(container.read(folderExpansionProvider), isEmpty);
      // A ▸ tap does not choose the row.
      expect(rowWidget(tester, LibraryStrings.home).selected, isTrue);
      await tester.tap(
        find.descendant(
          of: row('수학'),
          matching: find.byTooltip(LibraryStrings.collapseFolder),
        ),
      );
      await tester.pump();
      expect(rowLabels(tester), [LibraryStrings.home, '과학', '수학', '영어']);

      await choose(tester, '수학');
      await tester.tap(find.text(LibraryStrings.cancel));
      await tester.pumpAndSettle();
      expect(find.byType(FolderPickerDialog), findsNothing);
      expect(backend.calls, isEmpty);
      expect(h.log.entries, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      final note = await real(
        tester,
        () => backend.store.library.getNote(sample.homeNotes[0].id),
      );
      expect(note!.folderId, isNull);
    },
  );

  testWidgets('at most 480 × 600; full screen in the compact class', (
    tester,
  ) async {
    await seed(tester);
    await pumpAt(tester);
    await openMove(tester, '회의록');
    final body = find
        .descendant(
          of: find.byType(FolderPickerDialog),
          matching: find.byType(Column),
        )
        .first;
    expect(tester.getSize(body).width, lessThanOrEqualTo(480));
    expect(tester.getSize(body).height, lessThanOrEqualTo(600));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.tap(find.text(LibraryStrings.cancel));
    await tester.pumpAndSettle();
  });

  testWidgets('compact: full screen, no overflow', (tester) async {
    final sample = await seed(tester);
    await pumpAt(tester, size: TestSizes.compact);
    await openMove(tester, '영어');
    final body = find
        .descendant(
          of: find.byType(FolderPickerDialog),
          matching: find.byType(Column),
        )
        .first;
    expect(tester.getSize(body).width, TestSizes.compact.width);
    expect(find.byType(Dialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await choose(tester, '과학');
    await tester.tap(
      find.widgetWithText(FilledButton, LibraryStrings.moveHere),
    );
    await tester.pumpAndSettle();
    expect(backend.calls, [
      'moveItems [f:${sample.english.id}] -> f:${sample.science.id}',
    ]);
  });
}
