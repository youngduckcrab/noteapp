// Recent and favorites (05-library 6.14, 8 L17): notes only (no folders, no
// '새 노트' tile), last opened / last modified first, the meta line with the
// location (grid and list), the sort menu fixed and the view toggle applied,
// the empty states, opening a note (onOpenNote only, no markOpened), ⋯ and
// selection, and a drag onto a sidebar folder.
import 'package:feature_library/feature_library.dart' show LibraryScreen;
import 'package:feature_library/src/l10n/library_date_format.dart';
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/settings/library_settings_keys.dart';
import 'package:feature_library/src/ui/content/folder_tile.dart';
import 'package:feature_library/src/ui/content/item_list.dart';
import 'package:feature_library/src/ui/content/new_note_tile.dart';
import 'package:feature_library/src/ui/content/note_tile.dart';
import 'package:feature_library/src/ui/sidebar/sidebar_rows.dart';
import 'package:feature_library/src/ui/top_bar/selection_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_library_backend.dart';
import '../support/fixtures.dart';
import '../support/library_test_harness.dart';

Finder noteTile(String title) => find.widgetWithText(NoteTile, title);
Finder noteRow(String title) => find.widgetWithText(NoteListRow, title);
Finder navRow(String label) => find.widgetWithText(SidebarNavRow, label);
Finder treeRow(String name) => find.widgetWithText(SidebarTreeRow, name);

List<String> tileTitles(WidgetTester tester) => [
  for (final t in tester.widgetList<NoteTile>(find.byType(NoteTile)))
    t.note.title,
];

/// '홈 › … › 극한 › 연습 문제': where the sample's '극한 정리' is.
const String deepLocation = '홈 › … › 극한 › 연습 문제';

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  /// The TestClock default: 2026-11-04 14:05.
  final now = DateTime(2026, 11, 4, 14, 5);
  String dateOf(DateTime at) =>
      formatLibraryDate(at.millisecondsSinceEpoch, now: now);

  Future<LibraryTestHarness> pumpSection(
    WidgetTester tester,
    String navLabel, {
    bool list = false,
  }) async {
    if (list) {
      await real(
        tester,
        () => backend.store.settings.set(LibrarySettingsKeys.viewMode, 'list'),
      );
    }
    final h = LibraryTestHarness(backend);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(navRow(navLabel));
    await tester.pumpAndSettle();
    return h;
  }

  group('최근', () {
    final yesterday = DateTime(2026, 11, 3, 10);
    final thisMorning = DateTime(2026, 11, 4, 9, 30);

    /// Sample library; 회의록 opened yesterday 10:00, 극한 정리 today 9:30.
    Future<SampleLibrary> seedOpened(WidgetTester tester) =>
        real(tester, () async {
          final sample = await seedSampleLibrary(backend);
          await backend.seedOpened(sample.homeNotes[0].id, at: yesterday);
          await backend.seedOpened(sample.deepNote.id, at: thisMorning);
          backend.clock.current = now;
          return sample;
        });

    testWidgets('notes only, last opened first; meta = location · opened', (
      tester,
    ) async {
      await seedOpened(tester);
      await pumpSection(tester, LibraryStrings.recent);
      expect(tileTitles(tester), ['극한 정리', '회의록']);
      expect(find.byType(FolderTile), findsNothing);
      expect(find.byType(NewNoteTile), findsNothing);
      expect(
        find.descendant(
          of: noteTile('극한 정리'),
          matching: find.text(
            LibraryStrings.recentNoteMeta(deepLocation, dateOf(thisMorning)),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: noteTile('회의록'),
          matching: find.text(
            LibraryStrings.recentNoteMeta('홈', dateOf(yesterday)),
          ),
        ),
        findsOneWidget,
      );
      expect(dateOf(yesterday), startsWith('어제'));
    });

    testWidgets('list rows carry the same meta (no page count)', (
      tester,
    ) async {
      await seedOpened(tester);
      await pumpSection(tester, LibraryStrings.recent, list: true);
      expect(find.byType(NoteListRow), findsNWidgets(2));
      expect(
        find.descendant(
          of: noteRow('회의록'),
          matching: find.text(
            LibraryStrings.recentNoteMeta('홈', dateOf(yesterday)),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the sort is fixed; the view toggle applies', (tester) async {
      await seedOpened(tester);
      await pumpSection(tester, LibraryStrings.recent);
      final sort = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.sort),
      );
      expect(sort.onPressed, isNull);
      expect(find.byTooltip(LibraryStrings.sortFixed), findsOneWidget);

      await tester.tap(find.byTooltip(LibraryStrings.viewAsList));
      await tester.pumpAndSettle();
      expect(find.byType(NoteTile), findsNothing);
      expect(find.byType(NoteListRow), findsNWidgets(2));
    });

    testWidgets('a tap opens the note with onOpenNote only', (tester) async {
      final sample = await seedOpened(tester);
      final h = await pumpSection(tester, LibraryStrings.recent);
      await tester.tap(noteTile('회의록'));
      await tester.pumpAndSettle();
      expect(h.log.entries, ['note:${sample.homeNotes[0].id}']);
      expect(backend.calls, isEmpty); // no markOpened (S-5)
    });

    testWidgets('a note dragged onto a sidebar folder moves there', (
      tester,
    ) async {
      final sample = await seedOpened(tester);
      await pumpSection(tester, LibraryStrings.recent);
      final gesture = await tester.startGesture(
        tester.getCenter(noteTile('회의록')),
      );
      await tester.pump(const Duration(milliseconds: 450));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(treeRow('영어')));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(backend.calls, [
        'moveItems [n:${sample.homeNotes[0].id}] -> f:${sample.english.id}',
      ]);
      // Still a recent note, now in 영어; selection mode ended.
      expect(
        find.descendant(
          of: noteTile('회의록'),
          matching: find.text(
            LibraryStrings.recentNoteMeta('홈 › 영어', dateOf(yesterday)),
          ),
        ),
        findsOneWidget,
      );
      expect(find.byType(SelectionBar), findsNothing);
    });

    testWidgets('nothing opened yet → the empty state', (tester) async {
      await real(tester, () => seedSampleLibrary(backend));
      await pumpSection(tester, LibraryStrings.recent);
      expect(find.text(LibraryStrings.emptyRecent), findsOneWidget);
      expect(find.byType(NoteTile), findsNothing);
    });
  });

  group('즐겨찾기', () {
    final monday = DateTime(2026, 11, 2, 8, 15);
    final thisMorning = DateTime(2026, 11, 4, 11);

    /// Sample library; 독서 기록 made a favorite on Monday, 극한 정리 this
    /// morning (setFavorite changes updatedAt).
    Future<SampleLibrary> seedFavorites(WidgetTester tester) =>
        real(tester, () async {
          final sample = await seedSampleLibrary(backend);
          final library = backend.store.library;
          backend.clock.current = monday;
          await library.setFavorite([sample.homeNotes[1].id], true);
          backend.clock.current = thisMorning;
          await library.setFavorite([sample.deepNote.id], true);
          backend.clock.current = now;
          return sample;
        });

    testWidgets('favorites, modified first; meta = location · 수정 date', (
      tester,
    ) async {
      await seedFavorites(tester);
      await pumpSection(tester, LibraryStrings.favorites);
      expect(tileTitles(tester), ['극한 정리', '독서 기록']);
      expect(find.byType(FolderTile), findsNothing);
      expect(find.byType(NewNoteTile), findsNothing);
      expect(
        find.descendant(
          of: noteTile('독서 기록'),
          matching: find.text(
            LibraryStrings.favoriteNoteMeta('홈', dateOf(monday)),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: noteTile('극한 정리'),
          matching: find.text(
            LibraryStrings.favoriteNoteMeta(deepLocation, dateOf(thisMorning)),
          ),
        ),
        findsOneWidget,
      );
      expect(LibraryStrings.favoriteNoteMeta('홈', '11월 2일'), '홈 · 수정 11월 2일');
    });

    testWidgets('★ in a list row takes the note out of the view', (
      tester,
    ) async {
      final sample = await seedFavorites(tester);
      await pumpSection(tester, LibraryStrings.favorites, list: true);
      expect(find.byType(NoteListRow), findsNWidgets(2));
      await tester.tap(
        find.descendant(
          of: noteRow('독서 기록'),
          matching: find.byTooltip(LibraryStrings.favoriteRemove),
        ),
      );
      await tester.pumpAndSettle();
      expect(backend.calls, [
        'setFavorite [n:${sample.homeNotes[1].id}] false',
      ]);
      expect(noteRow('독서 기록'), findsNothing);
      expect(find.byType(NoteListRow), findsOneWidget);
    });

    testWidgets('⋯ on every note; selection ends favorites in screen order', (
      tester,
    ) async {
      final sample = await seedFavorites(tester);
      await pumpSection(tester, LibraryStrings.favorites);
      expect(find.byTooltip(LibraryStrings.itemMenu('독서 기록')), findsOneWidget);
      expect(find.byTooltip(LibraryStrings.itemMenu('극한 정리')), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, LibraryStrings.select));
      await tester.pumpAndSettle();
      await tester.tap(noteTile('독서 기록'));
      await tester.pump();
      await tester.tap(noteTile('극한 정리'));
      await tester.pump();
      expect(find.text(LibraryStrings.selectedCount(2)), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(SelectionBar),
          matching: find.text(LibraryStrings.favoriteRemove),
        ),
      );
      await tester.pumpAndSettle();
      final ids = 'n:${sample.deepNote.id}, n:${sample.homeNotes[1].id}';
      expect(backend.calls, ['setFavorite [$ids] false']);
      expect(find.byType(SelectionBar), findsNothing);
      expect(find.text(LibraryStrings.emptyFavorites), findsOneWidget);
    });

    testWidgets('no favorites → the empty state', (tester) async {
      await real(tester, () => seedSampleLibrary(backend));
      await pumpSection(tester, LibraryStrings.favorites);
      expect(find.text(LibraryStrings.emptyFavorites), findsOneWidget);
    });
  });

  testWidgets('both sections keep their notes when the route is a folder', (
    tester,
  ) async {
    final sample = await real(tester, () async {
      final sample = await seedSampleLibrary(backend);
      await backend.store.library.setFavorite([sample.deepNote.id], true);
      return sample;
    });
    final h = LibraryTestHarness(backend);
    await h.pump(tester, folderId: sample.english.id);
    await tester.pumpAndSettle();
    await tester.tap(navRow(LibraryStrings.favorites));
    await tester.pumpAndSettle();
    expect(tileTitles(tester), ['극한 정리']);
    expect(
      tester.widget<LibraryScreen>(find.byType(LibraryScreen)).folderId,
      sample.english.id,
    );
  });
}
