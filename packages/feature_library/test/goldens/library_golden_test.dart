// Goldens of the library screen (05-library 8 L19, 9.1; contract 7.4.8):
// 13" landscape grid, 13" portrait grid (drawer closed), 13" landscape list,
// the trash, (v2, L2-04) 13" landscape search results with the '노트 내용'
// group (source badges, page labels, snippets, '더 보기'). Test font (Ahem
// boxes) — layout only. Dates come from the fixed
// TestClock (seedSampleLibrary leaves it at 2026-11-04 14:05); covers are the
// placeholder (no renderer). Generated in the Linux container, compared in CI
// (ubuntu); flutter_test_config.dart in this directory allows ≤ 0.5 %.
// Update: `flutter test --update-goldens --tags golden`, in its own commit.
@Tags(['golden'])
@TestOn('vm')
library;

import 'package:feature_library/feature_library.dart';
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/ui/content/content_hits_view.dart';
import 'package:feature_library/src/ui/content/item_list.dart';
import 'package:feature_library/src/ui/top_bar/library_search_field.dart';
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

  /// The sample library with a favorite (아이디어), a color cover (일기) and
  /// a decorated folder (영어), so the goldens show ★, a color card and a
  /// folder color / icon.
  Future<SampleLibrary> seed(WidgetTester tester) => real(tester, () async {
    final sample = await seedSampleLibrary(backend);
    final now = backend.clock.current;
    final library = backend.store.library;
    await library.setFavorite([sample.homeNotes[2].id], true);
    await library.setCover(
      sample.homeNotes[3].id,
      ColorCover(CoverPalette.colors[0]),
    );
    await library.setFolderAppearance(
      sample.english.id,
      colorArgb: FolderPalette.colors[3],
      icon: FolderIcons.keys[5],
    );
    backend.clock.current = now;
    return sample;
  });

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    await LibraryTestHarness(backend, size: size).pump(tester);
    await tester.pumpAndSettle();
  }

  Finder screen() => find.byType(LibraryScreen);

  testWidgets('13" landscape grid', (tester) async {
    await seed(tester);
    await pumpAt(tester, TestSizes.ipad13Landscape);
    await expectLater(screen(), matchesGoldenFile('library_13_landscape.png'));
  });

  testWidgets('13" portrait grid, drawer closed', (tester) async {
    await seed(tester);
    await pumpAt(tester, TestSizes.ipad13Portrait);
    expect(find.byType(Drawer), findsNothing);
    await expectLater(screen(), matchesGoldenFile('library_13_portrait.png'));
  });

  testWidgets('13" landscape list', (tester) async {
    await seed(tester);
    await pumpAt(tester, TestSizes.ipad13Landscape);
    await tester.tap(find.byTooltip(LibraryStrings.viewAsList));
    await tester.pumpAndSettle();
    expect(find.byType(NoteListRow), findsNWidgets(4));
    await expectLater(
      screen(),
      matchesGoldenFile('library_13_landscape_list.png'),
    );
  });

  testWidgets('trash', (tester) async {
    final sample = await seed(tester);
    await real(tester, () async {
      final now = backend.clock.current;
      Future<void> trash(LibraryItemRef ref, int daysAgo) =>
          backend.seedTrashed([ref], at: now.subtract(Duration(days: daysAgo)));
      await trash(NoteRef(sample.homeNotes[2].id), 30); // 오늘 삭제
      await trash(FolderRef(sample.math.id), 27); // 3일 남음
      await trash(FolderRef(sample.english.id), 10); // 20일 남음
      await trash(NoteRef(sample.homeNotes[0].id), 0); // 30일 남음
    });
    await pumpAt(tester, TestSizes.ipad13Landscape);
    ProviderScope.containerOf(tester.element(screen()))
        .read(librarySectionProvider(null).notifier)
        .showTrash();
    await tester.pumpAndSettle();
    expect(find.text(LibraryStrings.trashNotice), findsOneWidget);
    await expectLater(screen(), matchesGoldenFile('library_trash.png'));
  });

  testWidgets('13" landscape search with the 노트 내용 group', (tester) async {
    await real(tester, () async {
      await seedContentHits(backend);
      await seedTextBoxNote(backend, '주간 회의', const [
        '회의 1',
        '회의 2',
        '회의 3',
        '회의 4',
      ]);
    });
    await pumpAt(tester, TestSizes.ipad13Landscape);
    await tester.enterText(
      find.descendant(
        of: find.byType(LibrarySearchField),
        matching: find.byType(TextField),
      ),
      '회의',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byType(SourceBadge), findsWidgets);
    expect(find.byType(ContentMoreRow), findsOneWidget);
    await expectLater(
      screen(),
      matchesGoldenFile('library_search_content.png'),
    );
  });
}
