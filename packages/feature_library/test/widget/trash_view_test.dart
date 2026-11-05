// The trash view (05-library 6.13, 8 L16): rows with info, deleted date and
// days left (30 / 3 / 0, ≤ 3 in errorContainer), newest first; a row's menu
// restores (snack bar [보기] → the parent folder through onOpenFolder) or
// purges after a confirmation ([취소] calls nothing); 휴지통 비우기 asks
// first; selection mode restores / purges several; the empty state.
import 'package:feature_library/feature_library.dart';
import 'package:feature_library/src/l10n/library_date_format.dart';
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/ui/dialogs/confirm_dialog.dart';
import 'package:feature_library/src/ui/top_bar/selection_bar.dart';
import 'package:feature_library/src/ui/trash/trash_row.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';

import '../support/fake_library_backend.dart';
import '../support/fixtures.dart';
import '../support/library_test_harness.dart';
import '../support/test_sizes.dart';

Finder trashRow(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(TrashRow));

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  /// Trashes [refs] with the clock at [at], then puts the clock back.
  Future<void> trashAt(
    WidgetTester tester,
    List<LibraryItemRef> refs,
    DateTime at,
  ) => real(tester, () async {
    final now = backend.clock.current;
    backend.clock.current = at;
    await backend.store.library.trashItems(refs);
    backend.clock.current = now;
  });

  /// Sample library; 회의록 trashed now (30 days left), 영어 10 days ago,
  /// 수학 (3 sub-folders, 1 note) 27 days ago (3 left), 아이디어 30 days ago
  /// (오늘 삭제), '단어장' in 영어 … see [withWordNote].
  Future<SampleLibrary> seedTrash(WidgetTester tester) async {
    final sample = await real(tester, () => seedSampleLibrary(backend));
    final now = backend.clock.current;
    await trashAt(tester, [
      NoteRef(sample.homeNotes[2].id),
    ], now.subtract(const Duration(days: 30)));
    await trashAt(tester, [
      FolderRef(sample.math.id),
    ], now.subtract(const Duration(days: 27)));
    await trashAt(tester, [
      FolderRef(sample.english.id),
    ], now.subtract(const Duration(days: 10)));
    await trashAt(tester, [NoteRef(sample.homeNotes[0].id)], now);
    return sample;
  }

  Future<LibraryTestHarness> pumpTrash(
    WidgetTester tester, {
    Size size = TestSizes.ipad13Landscape,
  }) async {
    final h = LibraryTestHarness(backend, size: size);
    await h.pump(tester);
    await tester.pumpAndSettle();
    ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)))
        .read(librarySectionProvider(null).notifier)
        .showTrash();
    await tester.pumpAndSettle();
    return h;
  }

  Future<void> rowMenu(WidgetTester tester, String name, String entry) async {
    await tester.tap(find.byTooltip(LibraryStrings.itemMenu(name)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, entry));
    await tester.pumpAndSettle();
  }

  testWidgets('rows: newest first, info, deleted date, 30 / 3 / 0 days left', (
    tester,
  ) async {
    final sample = await seedTrash(tester);
    final pages = sample.homeNotes[0].pageCount;
    await pumpTrash(tester);
    expect(find.text(LibraryStrings.trashNotice), findsOneWidget);
    expect(
      find.widgetWithText(TextButton, LibraryStrings.emptyTrash),
      findsOneWidget,
    );
    final names = ['회의록', '영어', '수학', '아이디어'];
    final ys = [for (final n in names) tester.getCenter(trashRow(n)).dy];
    expect([...ys]..sort(), ys);

    TrashDaysChip chip(String name) => tester.widget<TrashDaysChip>(
      find.descendant(of: trashRow(name), matching: find.byType(TrashDaysChip)),
    );
    expect(chip('회의록').label, '30일 남음');
    expect(chip('회의록').warn, isFalse);
    expect(chip('영어').label, '20일 남음');
    expect(chip('수학').label, '3일 남음');
    expect(chip('수학').warn, isTrue);
    expect(chip('아이디어').label, '오늘 삭제');
    expect(chip('아이디어').warn, isTrue);

    Finder inRow(String name, String text) =>
        find.descendant(of: trashRow(name), matching: find.text(text));
    expect(
      inRow(
        '수학',
        LibraryStrings.trashedFolderInfo(noteCount: 1, folderCount: 3),
      ),
      findsOneWidget,
    );
    expect(inRow('수학', '폴더 · 노트 1개, 폴더 3개 포함'), findsOneWidget);
    expect(inRow('영어', LibraryStrings.folders), findsOneWidget);
    expect(inRow('회의록', LibraryStrings.trashedNoteInfo(pages)), findsOneWidget);
    expect(LibraryStrings.trashedNoteInfo(3), '노트 · 3페이지');
    final now = backend.clock.current;
    expect(
      inRow(
        '회의록',
        LibraryStrings.deletedOn(
          formatLibraryDate(now.millisecondsSinceEpoch, now: now),
        ),
      ),
      findsOneWidget,
    );
    // The listing items are not here (only the trash).
    expect(find.text('일기'), findsNothing);
  });

  testWidgets('a tap opens [복원] [영구 삭제]; 영구 삭제 asks first', (tester) async {
    final sample = await seedTrash(tester);
    await pumpTrash(tester);
    backend.calls.clear();
    await tester.tap(trashRow('회의록'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(MenuItemButton, LibraryStrings.restore),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(MenuItemButton, LibraryStrings.purge));
    await tester.pumpAndSettle();
    expect(find.byType(ConfirmDialog), findsOneWidget);
    expect(find.text(LibraryStrings.purgeTitle), findsOneWidget);
    expect(find.text(LibraryStrings.purgeMessageOne('회의록')), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, LibraryStrings.cancel));
    await tester.pumpAndSettle();
    expect(backend.calls, isEmpty);
    expect(trashRow('회의록'), findsOneWidget);

    await rowMenu(tester, '회의록', LibraryStrings.purge);
    await tester.tap(
      find.descendant(
        of: find.byType(ConfirmDialog),
        matching: find.widgetWithText(FilledButton, LibraryStrings.purge),
      ),
    );
    await tester.pumpAndSettle();
    expect(backend.calls, ['purge [n:${sample.homeNotes[0].id}]']);
    expect(trashRow('회의록'), findsNothing);
  });

  testWidgets('restore: snack bar, [보기] opens the parent folder', (
    tester,
  ) async {
    final sample = await seedTrash(tester);
    final word = await real(
      tester,
      () => backend.seedNote('단어장', folderId: sample.science.id),
    );
    await trashAt(tester, [NoteRef(word.id)], backend.clock.current);
    final h = await pumpTrash(tester);
    backend.calls.clear();
    await rowMenu(tester, '단어장', LibraryStrings.restore);
    expect(backend.calls, ['restore [n:${word.id}]']);
    expect(find.text(LibraryStrings.restoredOne('단어장')), findsOneWidget);
    expect(trashRow('단어장'), findsNothing);
    await tester.tap(find.widgetWithText(SnackBarAction, LibraryStrings.show));
    await tester.pumpAndSettle();
    expect(h.log.entries, ['folder:${sample.science.id}']);
    expect(h.currentFolderId, sample.science.id);
    expect(find.text('단어장'), findsOneWidget);
  });

  testWidgets('휴지통 비우기: [취소] nothing, confirm → emptyTrash, then the '
      'empty state', (tester) async {
    await seedTrash(tester);
    await pumpTrash(tester);
    backend.calls.clear();
    final button = find.widgetWithText(TextButton, LibraryStrings.emptyTrash);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text(LibraryStrings.emptyTrashTitle), findsOneWidget);
    expect(find.text(LibraryStrings.emptyTrashMessage(4)), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, LibraryStrings.cancel));
    await tester.pumpAndSettle();
    expect(backend.calls, isEmpty);

    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, LibraryStrings.emptyTrash),
    );
    await tester.pumpAndSettle();
    expect(backend.calls, ['emptyTrash']);
    expect(find.byType(TrashRow), findsNothing);
    expect(find.text(LibraryStrings.emptyTrashView), findsOneWidget);
    expect(find.text(LibraryStrings.trashNotice), findsNothing);
  });

  testWidgets('selection mode: 복원 / 영구 삭제 of several in display order', (
    tester,
  ) async {
    final sample = await seedTrash(tester);
    await pumpTrash(tester);
    backend.calls.clear();
    await tester.tap(find.widgetWithText(TextButton, LibraryStrings.select));
    await tester.pumpAndSettle();
    final bar = find.byType(SelectionBar);
    expect(bar, findsOneWidget);
    // A tap toggles (no menu) in selection mode.
    await tester.tap(trashRow('아이디어'));
    await tester.pump();
    await tester.tap(trashRow('회의록'));
    await tester.pump();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(
      find.descendant(
        of: bar,
        matching: find.text(LibraryStrings.selectedCount(2)),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: bar, matching: find.text(LibraryStrings.restore)),
    );
    await tester.pumpAndSettle();
    expect(backend.calls, [
      'restore [n:${sample.homeNotes[0].id}, n:${sample.homeNotes[2].id}]',
    ]);
    expect(find.text(LibraryStrings.restoredCount(2)), findsOneWidget);
    expect(bar, findsNothing);

    // 모두 선택 → 영구 삭제 (confirm).
    await tester.tap(find.widgetWithText(TextButton, LibraryStrings.select));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: bar, matching: find.text(LibraryStrings.selectAll)),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(of: bar, matching: find.text(LibraryStrings.purge)),
    );
    await tester.pumpAndSettle();
    expect(find.text(LibraryStrings.purgeMessageCount(2)), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(ConfirmDialog),
        matching: find.widgetWithText(FilledButton, LibraryStrings.purge),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      backend.calls.last,
      'purge [f:${sample.english.id}, f:${sample.math.id}]',
    );
    expect(find.text(LibraryStrings.emptyTrashView), findsOneWidget);
    expect(bar, findsNothing);
  });

  testWidgets('a long press starts selection mode with the row', (
    tester,
  ) async {
    await seedTrash(tester);
    await pumpTrash(tester);
    await tester.longPress(trashRow('영어'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(SelectionBar),
        matching: find.text(LibraryStrings.selectedCount(1)),
      ),
      findsOneWidget,
    );
  });

  testWidgets('empty trash: the empty state, no notice', (tester) async {
    await real(tester, () => seedSampleLibrary(backend));
    await pumpTrash(tester);
    expect(find.text(LibraryStrings.emptyTrashView), findsOneWidget);
    expect(find.text(LibraryStrings.trashNotice), findsNothing);
    expect(find.byType(TrashRow), findsNothing);
  });

  testWidgets('compact: the deleted date joins the info line, no overflow', (
    tester,
  ) async {
    final sample = await seedTrash(tester);
    final pages = sample.homeNotes[0].pageCount;
    await pumpTrash(tester, size: TestSizes.compact);
    expect(tester.takeException(), isNull);
    final now = backend.clock.current;
    final deleted = LibraryStrings.deletedOn(
      formatLibraryDate(now.millisecondsSinceEpoch, now: now),
    );
    expect(
      find.descendant(
        of: trashRow('회의록'),
        matching: find.text(
          '${LibraryStrings.trashedNoteInfo(pages)} · $deleted',
        ),
      ),
      findsOneWidget,
    );
  });
}
