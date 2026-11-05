// Accessibility guidelines (05-library 6.20, 8 L19; contract 7.4.8): every
// main state of the screen meets iOSTapTargetGuideline (44 × 44),
// labeledTapTargetGuideline and textContrastGuideline, on 13" landscape and
// portrait: the grid and the list, a folder with its breadcrumb, the trash,
// search results with the clear button, the 새로 만들기 menu with 'PDF
// 가져오기' (준비 중), an item menu, selection mode, the storage banner with
// [닫기], the new note / new folder dialogs, and the drawer (portrait).
import 'package:feature_library/feature_library.dart';
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/ui/banners/storage_warning_banner.dart';
import 'package:feature_library/src/ui/dialogs/new_folder_dialog.dart';
import 'package:feature_library/src/ui/dialogs/new_note_dialog.dart';
import 'package:feature_library/src/ui/top_bar/library_search_field.dart';
import 'package:feature_library/src/ui/top_bar/selection_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';

import '../support/fake_library_backend.dart';
import '../support/fixtures.dart';
import '../support/library_test_harness.dart';
import '../support/test_sizes.dart';

/// The three guidelines of 6.20 on what is on screen now.
Future<void> expectGuidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

final Finder searchInput = find.descendant(
  of: find.byType(LibrarySearchField),
  matching: find.byType(TextField),
);

void main() {
  for (final (name, size) in const [
    ('13" landscape', TestSizes.ipad13Landscape),
    ('13" portrait', TestSizes.ipad13Portrait),
  ]) {
    group(name, () {
      late FakeLibraryBackend backend;

      setUp(() => backend = FakeLibraryBackend());
      tearDown(() => backend.dispose());

      Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
          (await tester.runAsync(body)) as T;

      /// The sample library with ★ (아이디어) and a color cover (일기).
      Future<SampleLibrary> seed(WidgetTester tester) => real(tester, () async {
        final sample = await seedSampleLibrary(backend);
        final now = backend.clock.current;
        await backend.store.library.setFavorite([sample.homeNotes[2].id], true);
        await backend.store.library.setCover(
          sample.homeNotes[3].id,
          ColorCover(CoverPalette.colors[0]),
        );
        backend.clock.current = now;
        return sample;
      });

      Future<void> pumpAt(WidgetTester tester, {FolderId? folderId}) async {
        await LibraryTestHarness(
          backend,
          size: size,
        ).pump(tester, folderId: folderId);
        await tester.pumpAndSettle();
      }

      /// A test that builds a state with [body], then checks the guidelines
      /// (semantics on for the whole test).
      void check(
        String description,
        Future<void> Function(WidgetTester) body,
      ) => testWidgets(description, (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await body(tester);
          await expectGuidelines(tester);
        } finally {
          semantics.dispose();
        }
      });

      Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      check('home grid', (tester) async {
        await seed(tester);
        await pumpAt(tester);
      });

      check('home list', (tester) async {
        await seed(tester);
        await pumpAt(tester);
        await tapAndSettle(tester, find.byTooltip(LibraryStrings.viewAsList));
      });

      check('a deep folder with its breadcrumb', (tester) async {
        final sample = await seed(tester);
        await pumpAt(tester, folderId: sample.deepest.id);
        expect(find.text('극한 정리'), findsWidgets);
      });

      check('an empty folder', (tester) async {
        final sample = await seed(tester);
        await pumpAt(tester, folderId: sample.english.id);
        expect(find.text(LibraryStrings.newFolder), findsWidgets);
      });

      check('trash with items', (tester) async {
        final sample = await seed(tester);
        await real(tester, () async {
          final now = backend.clock.current;
          await backend.seedTrashed([NoteRef(sample.homeNotes[0].id)], at: now);
          await backend.seedTrashed([
            FolderRef(sample.math.id),
          ], at: now.subtract(const Duration(days: 28)));
        });
        await pumpAt(tester);
        ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)))
            .read(librarySectionProvider(null).notifier)
            .showTrash();
        await tester.pumpAndSettle();
        expect(find.text(LibraryStrings.trashNotice), findsOneWidget);
      });

      check('search results with the clear button', (tester) async {
        await seed(tester);
        await pumpAt(tester);
        if (searchInput.evaluate().isEmpty) {
          await tapAndSettle(tester, find.byTooltip(LibraryStrings.search));
        }
        await tester.enterText(searchInput, '수');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(find.byTooltip(LibraryStrings.clearSearch), findsOneWidget);
      });

      check("the 새로 만들기 menu ('PDF 가져오기' 준비 중)", (tester) async {
        await seed(tester);
        await pumpAt(tester);
        await tapAndSettle(tester, find.text(LibraryStrings.newMenu));
        expect(find.text(LibraryStrings.importPdf), findsOneWidget);
        expect(find.text(LibraryStrings.comingSoon), findsOneWidget);
      });

      check('an item menu', (tester) async {
        await seed(tester);
        await pumpAt(tester);
        await tapAndSettle(
          tester,
          find.byTooltip(LibraryStrings.itemMenu('회의록')),
        );
        expect(find.byType(MenuItemButton), findsWidgets);
      });

      check('selection mode', (tester) async {
        await seed(tester);
        await pumpAt(tester);
        await tapAndSettle(
          tester,
          find.widgetWithText(TextButton, LibraryStrings.select),
        );
        await tapAndSettle(tester, find.text('회의록').first);
        expect(
          find.descendant(
            of: find.byType(SelectionBar),
            matching: find.text(LibraryStrings.selectedCount(1)),
          ),
          findsOneWidget,
        );
      });

      check('the storage banner with [닫기]', (tester) async {
        await backend.dispose();
        backend = FakeLibraryBackend(
          storageInfo: const StorageInfo(backend: StorageBackend.webInMemory),
        );
        await seed(tester);
        await pumpAt(tester);
        expect(
          find.descendant(
            of: find.byType(StorageWarningBanner),
            matching: find.widgetWithText(TextButton, LibraryStrings.close),
          ),
          findsOneWidget,
        );
      });

      check('the new note dialog', (tester) async {
        await seed(tester);
        await pumpAt(tester);
        await tapAndSettle(tester, find.text(LibraryStrings.newMenu));
        await tapAndSettle(
          tester,
          find.widgetWithText(MenuItemButton, LibraryStrings.newNote),
        );
        expect(find.byType(NewNoteDialog), findsOneWidget);
      });

      check('the new folder dialog', (tester) async {
        await seed(tester);
        await pumpAt(tester);
        await tapAndSettle(tester, find.text(LibraryStrings.newMenu));
        await tapAndSettle(
          tester,
          find.widgetWithText(MenuItemButton, LibraryStrings.newFolder),
        );
        expect(find.byType(NewFolderDialog), findsOneWidget);
      });

      if (size == TestSizes.ipad13Portrait) {
        check('the drawer', (tester) async {
          await seed(tester);
          await pumpAt(tester);
          await tapAndSettle(tester, find.byTooltip(LibraryStrings.openMenu));
          expect(find.byType(Drawer), findsOneWidget);
        });
      }
    });
  }
}
