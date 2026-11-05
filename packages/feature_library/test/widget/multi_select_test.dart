// Multi-select (05-library 6.9, 4.3 export slot; 8 L14): long press starts
// selection mode with the item, a tap toggles, batch actions get the items in
// display order and end selection mode, 즐겨찾기 / PDF 내보내기 need a note,
// the export slot (hidden when null) gets the LibraryScreen context, runs
// once at a time, and its exception shows errorGeneric; section changes end
// selection mode.
import 'dart:async';

import 'package:feature_library/feature_library.dart';
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/ui/content/folder_tile.dart';
import 'package:feature_library/src/ui/content/item_list.dart';
import 'package:feature_library/src/ui/content/note_tile.dart';
import 'package:feature_library/src/ui/content/tile_parts.dart';
import 'package:feature_library/src/ui/dialogs/folder_picker_dialog.dart';
import 'package:feature_library/src/ui/top_bar/library_top_bar.dart';
import 'package:feature_library/src/ui/top_bar/selection_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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

  Finder tile(String name) => find.ancestor(
    of: find.text(name),
    matching: find.byWidgetPredicate((w) => w is NoteTile || w is FolderTile),
  );

  /// Long press on the first name, taps on the others.
  Future<void> select(WidgetTester tester, List<String> names) async {
    await tester.longPress(tile(names.first));
    await tester.pumpAndSettle();
    for (final name in names.skip(1)) {
      await tester.tap(tile(name));
      await tester.pump();
    }
  }

  Finder inBar(String text) =>
      find.descendant(of: find.byType(SelectionBar), matching: find.text(text));

  ButtonStyleButton barButton(WidgetTester tester, String label) =>
      tester.widget<ButtonStyleButton>(
        find
            .ancestor(
              of: inBar(label),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            )
            .first,
      );

  Future<void> pressBar(WidgetTester tester, String label) async {
    await tester.tap(inBar(label));
    await tester.pumpAndSettle();
  }

  bool selecting(WidgetTester tester) =>
      find.byType(SelectionBar).evaluate().isNotEmpty;

  Future<void> pickAndConfirm(
    WidgetTester tester,
    String row,
    String confirm,
  ) async {
    await tester.tap(find.widgetWithText(FolderPickerRow, row));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, confirm));
    await tester.pumpAndSettle();
  }

  group('selection mode', () {
    testWidgets('long press starts it with the item; a tap toggles', (
      tester,
    ) async {
      await seed(tester);
      final h = await pumpAt(tester);
      expect(find.byType(SelectionCheckBadge), findsNothing);
      await tester.longPress(tile('회의록'));
      await tester.pumpAndSettle();
      expect(selecting(tester), isTrue);
      expect(find.byType(LibraryTopBar), findsNothing);
      expect(inBar(LibraryStrings.selectedCount(1)), findsOneWidget);
      // Every tile shows the check mark; the ⋯ buttons are gone.
      expect(find.byType(SelectionCheckBadge), findsNWidgets(7));
      expect(find.byTooltip(LibraryStrings.itemMenu('회의록')), findsNothing);
      final cover = tester.widget<TileCoverBox>(
        find.descendant(of: tile('회의록'), matching: find.byType(TileCoverBox)),
      );
      expect(cover.selected, isTrue);

      await tester.tap(tile('일기'));
      await tester.pump();
      await tester.tap(tile('수학'));
      await tester.pump();
      expect(inBar(LibraryStrings.selectedCount(3)), findsOneWidget);
      await tester.tap(tile('회의록'));
      await tester.pump();
      expect(inBar(LibraryStrings.selectedCount(2)), findsOneWidget);
      expect(
        tester
            .widget<TileCoverBox>(
              find.descendant(
                of: tile('회의록'),
                matching: find.byType(TileCoverBox),
              ),
            )
            .selected,
        isFalse,
      );
      // Taps in selection mode open nothing.
      expect(h.log.entries, isEmpty);
      expect(backend.calls, isEmpty);
    });

    testWidgets('semantics: selected on the tiles, the count is live', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await seed(tester);
      await pumpAt(tester);
      await select(tester, ['회의록']);
      expect(
        tester.getSemantics(find.bySemanticsLabel('노트, 회의록, 수정 11월 1일')),
        isSemantics(hasSelectedState: true, isSelected: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('노트, 일기, 수정 11월 1일')),
        isSemantics(hasSelectedState: true, isSelected: false),
      );
      expect(
        tester.getSemantics(inBar(LibraryStrings.selectedCount(1))),
        isSemantics(isLiveRegion: true),
      );
      handle.dispose();
    });

    testWidgets("'선택' starts it empty; 모두 선택 / 모두 해제; ✕ ends it", (
      tester,
    ) async {
      await seed(tester);
      await pumpAt(tester);
      await tester.tap(find.widgetWithText(TextButton, LibraryStrings.select));
      await tester.pumpAndSettle();
      expect(inBar(LibraryStrings.selectedCount(0)), findsOneWidget);
      // Nothing selected: every action is disabled.
      for (final label in [
        LibraryStrings.favoriteAdd,
        LibraryStrings.copy,
        LibraryStrings.move,
        LibraryStrings.trash,
      ]) {
        expect(barButton(tester, label).enabled, isFalse, reason: label);
      }
      await pressBar(tester, LibraryStrings.selectAll);
      expect(inBar(LibraryStrings.selectedCount(7)), findsOneWidget);
      expect(inBar(LibraryStrings.selectAll), findsNothing);
      await pressBar(tester, LibraryStrings.deselectAll);
      expect(inBar(LibraryStrings.selectedCount(0)), findsOneWidget);
      // Still in selection mode with 0.
      expect(selecting(tester), isTrue);
      await tester.tap(find.byTooltip(LibraryStrings.done));
      await tester.pumpAndSettle();
      expect(selecting(tester), isFalse);
      expect(find.byType(LibraryTopBar), findsOneWidget);
      expect(find.byTooltip(LibraryStrings.itemMenu('회의록')), findsOneWidget);
    });

    testWidgets('a section change ends it', (tester) async {
      await seed(tester);
      await pumpAt(tester);
      await select(tester, ['회의록', '수학']);
      await tester.tap(find.text(LibraryStrings.recent));
      await tester.pumpAndSettle();
      expect(selecting(tester), isFalse);
    });

    testWidgets('list rows: checkbox, toggle, no ⋯', (tester) async {
      await seed(tester);
      final h = await pumpAt(tester);
      await tester.tap(find.byTooltip(LibraryStrings.viewAsList));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      await tester.longPress(find.widgetWithText(NoteListRow, '아이디어'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNWidgets(7));
      expect(find.byTooltip(LibraryStrings.itemMenu('아이디어')), findsNothing);
      await tester.tap(find.widgetWithText(FolderListRow, '영어'));
      await tester.pump();
      expect(inBar(LibraryStrings.selectedCount(2)), findsOneWidget);
      final checked = find.descendant(
        of: find.widgetWithText(FolderListRow, '영어'),
        matching: find.byType(Checkbox),
      );
      expect(tester.widget<Checkbox>(checked).value, isTrue);
      expect(h.log.entries, isEmpty);
    });
  });

  group('batch actions', () {
    testWidgets('이동: display order, one call, ends; 실행 취소 moves back', (
      tester,
    ) async {
      final sample = await seed(tester);
      await pumpAt(tester);
      final meeting = sample.homeNotes[0].id, diary = sample.homeNotes[3].id;
      // Selection order 회의록, 일기; display order (newest first) 일기, 회의록.
      await select(tester, ['회의록', '일기']);
      await pressBar(tester, LibraryStrings.move);
      expect(find.text(LibraryStrings.moveDestination), findsOneWidget);
      await pickAndConfirm(tester, '영어', LibraryStrings.moveHere);
      expect(backend.calls, [
        'moveItems [n:$diary, n:$meeting] -> f:${sample.english.id}',
      ]);
      expect(find.text("항목 2개를 '영어'로 옮겼어요"), findsOneWidget);
      expect(selecting(tester), isFalse);

      await tester.tap(
        find.widgetWithText(SnackBarAction, LibraryStrings.undo),
      );
      await tester.pumpAndSettle();
      expect(backend.calls.last, 'moveItems [n:$diary, n:$meeting] -> home');
      expect(find.widgetWithText(NoteTile, '회의록'), findsOneWidget);
    });

    testWidgets('a cancelled picker keeps selection mode', (tester) async {
      await seed(tester);
      await pumpAt(tester);
      await select(tester, ['회의록', '수학']);
      await pressBar(tester, LibraryStrings.move);
      // 수학 is one of the moved folders.
      expect(
        tester
            .widget<FolderPickerRow>(find.widgetWithText(FolderPickerRow, '수학'))
            .enabled,
        isFalse,
      );
      await tester.tap(find.text(LibraryStrings.cancel));
      await tester.pumpAndSettle();
      expect(selecting(tester), isTrue);
      expect(inBar(LibraryStrings.selectedCount(2)), findsOneWidget);
      expect(backend.calls, isEmpty);
    });

    testWidgets('휴지통: folders then notes, 항목 n개, 실행 취소 → restore', (
      tester,
    ) async {
      final sample = await seed(tester);
      await pumpAt(tester);
      final idea = sample.homeNotes[2].id, math = sample.math.id;
      await select(tester, ['아이디어', '수학']);
      await pressBar(tester, LibraryStrings.trash);
      expect(backend.calls, ['trashItems [f:$math, n:$idea]']);
      expect(find.text('항목 2개를 휴지통으로 옮겼어요'), findsOneWidget);
      expect(selecting(tester), isFalse);
      await tester.tap(
        find.widgetWithText(SnackBarAction, LibraryStrings.undo),
      );
      await tester.pumpAndSettle();
      expect(backend.calls.last, 'restore [f:$math, n:$idea]');
      expect(find.widgetWithText(FolderTile, '수학'), findsOneWidget);
    });

    testWidgets("휴지통 with one item names it: \"'일기'를 휴지통으로 옮겼어요\"", (
      tester,
    ) async {
      await seed(tester);
      await pumpAt(tester);
      await select(tester, ['일기']);
      await pressBar(tester, LibraryStrings.trash);
      expect(find.text("'일기'를 휴지통으로 옮겼어요"), findsOneWidget);
    });

    testWidgets("복사: starts at the folder; same folder ' 사본', other none", (
      tester,
    ) async {
      final sample = await seed(tester);
      await pumpAt(tester, folderId: sample.math.id);
      final calculus = sample.nested[0].id;
      await select(tester, ['미적분']);
      await pressBar(tester, LibraryStrings.copy);
      expect(find.text(LibraryStrings.copyDestination), findsOneWidget);
      final initial = tester.widget<FolderPickerRow>(
        find.widgetWithText(FolderPickerRow, '수학'),
      );
      expect(initial.selected, isTrue);
      await tester.tap(
        find.widgetWithText(FilledButton, LibraryStrings.copyHere),
      );
      await tester.pumpAndSettle();
      expect(backend.calls, [
        "copyItems [f:$calculus] -> f:${sample.math.id} suffix:' 사본'",
      ]);
      expect(find.text(LibraryStrings.copiedCount(1)), findsOneWidget);
      expect(find.text('항목 1개를 복사했어요'), findsOneWidget);
      expect(selecting(tester), isFalse);
      expect(find.widgetWithText(FolderTile, '미적분 사본'), findsOneWidget);

      await select(tester, ['미적분', '미적분 사본']);
      await pressBar(tester, LibraryStrings.copy);
      await pickAndConfirm(
        tester,
        LibraryStrings.home,
        LibraryStrings.copyHere,
      );
      expect(backend.calls.last, startsWith('copyItems [f:'));
      expect(backend.calls.last, endsWith("-> home suffix:''"));
      expect(find.text('항목 2개를 복사했어요'), findsOneWidget);
    });

    testWidgets('즐겨찾기: needs a note; ☆ for the notes; all ★ → 해제', (
      tester,
    ) async {
      final sample = await seed(tester);
      await pumpAt(tester);
      final meeting = sample.homeNotes[0].id, diary = sample.homeNotes[3].id;
      await select(tester, ['수학']);
      expect(barButton(tester, LibraryStrings.favoriteAdd).enabled, isFalse);
      await tester.tap(tile('회의록'));
      await tester.tap(tile('일기'));
      await tester.pump();
      expect(barButton(tester, LibraryStrings.favoriteAdd).enabled, isTrue);
      await pressBar(tester, LibraryStrings.favoriteAdd);
      // Notes only, display order.
      expect(backend.calls, ['setFavorite [n:$diary, n:$meeting] true']);
      expect(selecting(tester), isFalse);

      await select(tester, ['일기', '회의록']);
      expect(inBar(LibraryStrings.favoriteRemove), findsOneWidget);
      await pressBar(tester, LibraryStrings.favoriteRemove);
      expect(backend.calls.last, 'setFavorite [n:$diary, n:$meeting] false');
      // One favorite, one not → ☆ again.
      await real(
        tester,
        () => backend.store.library.setFavorite([diary], true),
      );
      await tester.pumpAndSettle();
      await select(tester, ['일기', '회의록']);
      expect(inBar(LibraryStrings.favoriteAdd), findsOneWidget);
    });

    testWidgets('a failed batch action keeps selection mode', (tester) async {
      await seed(tester);
      await pumpAt(tester);
      await select(tester, ['일기', '회의록']);
      backend.failNextMutation = StateError('disk');
      await pressBar(tester, LibraryStrings.trash);
      expect(tester.takeException(), isA<StateError>());
      expect(find.text(LibraryStrings.errorGeneric), findsOneWidget);
      expect(selecting(tester), isTrue);
    });
  });

  group('PDF 내보내기', () {
    late List<(BuildContext, List<String>)> exports;
    late Completer<void>? gate;
    Error? failWith;

    Future<void> fakeExport(BuildContext context, List<String> ids) async {
      exports.add((context, ids));
      final wait = gate;
      if (wait != null) await wait.future;
      final error = failWith;
      if (error != null) throw error;
    }

    setUp(() {
      exports = [];
      gate = null;
      failWith = null;
    });

    List<Override> slot() => [
      libraryPdfExportActionProvider.overrideWithValue(fakeExport),
    ];

    testWidgets('slot null → no button', (tester) async {
      await seed(tester);
      await pumpAt(tester);
      await select(tester, ['회의록']);
      expect(inBar(LibraryStrings.exportPdfBulk), findsNothing);
      expect(find.byTooltip(LibraryStrings.exportPdfBulk), findsNothing);
    });

    testWidgets('notes only, display order, the screen context; then ends', (
      tester,
    ) async {
      final sample = await seed(tester);
      await pumpAt(tester, overrides: slot());
      await select(tester, ['회의록', '수학', '아이디어']);
      await pressBar(tester, LibraryStrings.exportPdfBulk);
      expect(exports, hasLength(1));
      final (context, ids) = exports.single;
      expect(ids, [sample.homeNotes[2].id, sample.homeNotes[0].id]);
      expect(context, same(tester.element(find.byType(LibraryScreen))));
      expect(selecting(tester), isFalse);
      expect(backend.calls, isEmpty);
    });

    testWidgets('folders only → disabled with a hint', (tester) async {
      await seed(tester);
      await pumpAt(tester, overrides: slot());
      await select(tester, ['수학', '영어']);
      expect(barButton(tester, LibraryStrings.exportPdfBulk).enabled, isFalse);
      expect(find.byTooltip(LibraryStrings.exportNeedsNote), findsOneWidget);
      await tester.tap(inBar(LibraryStrings.exportPdfBulk));
      await tester.pumpAndSettle();
      expect(exports, isEmpty);
    });

    testWidgets('pressed twice while running → one call', (tester) async {
      await seed(tester);
      await pumpAt(tester, overrides: slot());
      gate = Completer<void>();
      await select(tester, ['회의록']);
      await tester.tap(inBar(LibraryStrings.exportPdfBulk));
      await tester.tap(inBar(LibraryStrings.exportPdfBulk));
      await tester.pump();
      expect(barButton(tester, LibraryStrings.exportPdfBulk).enabled, isFalse);
      await tester.tap(inBar(LibraryStrings.exportPdfBulk));
      await tester.pump();
      expect(exports, hasLength(1));
      expect(selecting(tester), isTrue);
      gate!.complete();
      await tester.pumpAndSettle();
      expect(exports, hasLength(1));
      expect(selecting(tester), isFalse);
    });

    testWidgets('an exception → reported + errorGeneric; selection ends', (
      tester,
    ) async {
      await seed(tester);
      await pumpAt(tester, overrides: slot());
      failWith = StateError('pdf');
      await select(tester, ['일기']);
      await pressBar(tester, LibraryStrings.exportPdfBulk);
      expect(tester.takeException(), isA<StateError>());
      expect(find.text(LibraryStrings.errorGeneric), findsOneWidget);
      expect(selecting(tester), isFalse);
    });

    testWidgets('no export in the trash section', (tester) async {
      await seed(tester);
      await pumpAt(tester, overrides: slot());
      await tester.tap(find.text(LibraryStrings.trash));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, LibraryStrings.select));
      await tester.pumpAndSettle();
      expect(selecting(tester), isTrue);
      expect(inBar(LibraryStrings.exportPdfBulk), findsNothing);
      expect(inBar(LibraryStrings.move), findsNothing);
    });
  });

  testWidgets('compact: 이동 · 휴지통 as icons, the rest in ⋯', (tester) async {
    await seed(tester);
    await pumpAt(
      tester,
      size: TestSizes.compact,
      overrides: [
        libraryPdfExportActionProvider.overrideWithValue((_, _) async {}),
      ],
    );
    await tester.tap(find.byTooltip(LibraryStrings.moreActions));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(MenuItemButton, LibraryStrings.select),
    );
    await tester.pumpAndSettle();
    expect(selecting(tester), isTrue);
    expect(find.byTooltip(LibraryStrings.move), findsOneWidget);
    expect(find.byTooltip(LibraryStrings.trash), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(SelectionBar),
        matching: find.byTooltip(LibraryStrings.moreActions),
      ),
    );
    await tester.pumpAndSettle();
    final entries = [
      for (final e in find.byType(MenuItemButton).evaluate())
        ((e.widget as MenuItemButton).child! as Text).data,
    ];
    expect(entries, [
      LibraryStrings.selectAll,
      LibraryStrings.favoriteAdd,
      LibraryStrings.copy,
      LibraryStrings.exportPdfBulk,
    ]);
    await tester.tap(
      find.widgetWithText(MenuItemButton, LibraryStrings.selectAll),
    );
    await tester.pumpAndSettle();
    expect(inBar(LibraryStrings.selectedCount(7)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the selection bar lays out at every size', (tester) async {
    await seed(tester);
    for (final size in TestSizes.all) {
      await pumpAt(
        tester,
        size: size,
        overrides: [
          libraryPdfExportActionProvider.overrideWithValue((_, _) async {}),
        ],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryTopBar)),
      );
      container.read(librarySelectionProvider(null).notifier).begin();
      await tester.pumpAndSettle();
      expect(selecting(tester), isTrue, reason: '$size');
      expect(tester.takeException(), isNull, reason: '$size');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
