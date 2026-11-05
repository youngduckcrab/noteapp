// Performance budget (05-library 6.21, 8 L19): a folder of 1,000 notes is
// shown on the frame after CORE's first stream value, and only the visible
// cells plus about two rows are built (13" landscape, 5 columns → ≤ 35
// NoteTiles), in the grid and in the list. Tiles have their own
// RepaintBoundary and a fixed main-axis extent; scrolling to the end still
// builds a bounded number of tiles. No time is measured.
import 'package:feature_library/feature_library.dart' show LibraryScreen;
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/model/section.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/ui/content/item_list.dart';
import 'package:feature_library/src/ui/content/note_tile.dart';
import 'package:feature_library/src/ui/sidebar/library_sidebar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';

import '../support/fake_library_backend.dart';
import '../support/library_test_harness.dart';
import '../support/test_sizes.dart';

/// 13" landscape: 5 columns; the visible rows plus two rows of cache.
const int kMaxBuiltTiles = 35;

const int kNoteCount = 1000;

/// Built tiles, on screen or in the cache extent.
Finder builtNoteTiles() => find.byType(NoteTile, skipOffstage: false);

Finder builtNoteRows() => find.byType(NoteListRow, skipOffstage: false);

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  /// One folder '큰 폴더' with [kNoteCount] notes, created through CORE one
  /// minute apart ('노트 1000' is the newest).
  Future<Folder> seedBigFolder(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final folder = await backend.seedFolder('큰 폴더');
        for (var i = 1; i <= kNoteCount; i++) {
          await backend.seedNote(
            '노트 ${i.toString().padLeft(4, '0')}',
            folderId: folder.id,
            at: DateTime(2026, 11, 1).add(Duration(minutes: i)),
          );
        }
        backend.clock.current = DateTime(2026, 11, 4, 14, 5);
        return folder;
      }))!;

  testWidgets('1,000 notes: shown on the frame after the first value, '
      '≤ 35 tiles built', (tester) async {
    final folder = await seedBigFolder(tester);
    final h = LibraryTestHarness(backend, size: TestSizes.ipad13Landscape);
    await h.pump(tester, folderId: folder.id);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryScreen)),
    );
    final content = container.listen(
      libraryContentProvider(FolderSection(folder.id)),
      (_, _) {},
    );
    addTearDown(content.close);
    // No time passes: the view settings, then the listing arrive from CORE
    // (each a stream's first value); until then nothing but the shell.
    var frames = 0;
    while (!content.read().hasValue) {
      expect(builtNoteTiles(), findsNothing);
      await tester.pump();
      expect(++frames, lessThanOrEqualTo(3));
    }
    // The next frame: sidebar row and listing, no spinner.
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(LibrarySidebar),
        matching: find.text('큰 폴더'),
      ),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final built = builtNoteTiles().evaluate().length;
    // At least the first screen (two rows of 5 minus the 새 노트 cell).
    expect(built, inInclusiveRange(9, kMaxBuiltTiles));
    expect(find.text('노트 1000'), findsOneWidget); // newest first

    await tester.pumpAndSettle();
    expect(
      builtNoteTiles().evaluate().length,
      lessThanOrEqualTo(kMaxBuiltTiles),
    );

    // Every tile repaints on its own; the grid's rows have a fixed height.
    for (final e in builtNoteTiles().evaluate()) {
      expect(
        find.descendant(
          of: find.byWidget(e.widget, skipOffstage: false),
          matching: find.byType(RepaintBoundary, skipOffstage: false),
          skipOffstage: false,
        ),
        findsWidgets,
      );
    }
    final heights = {
      for (final e in builtNoteTiles().evaluate())
        (e.renderObject! as RenderBox).size.height,
    };
    expect(heights, hasLength(1));
  });

  testWidgets('scrolling to the end keeps the number of built tiles bounded', (
    tester,
  ) async {
    final folder = await seedBigFolder(tester);
    final h = LibraryTestHarness(backend, size: TestSizes.ipad13Landscape);
    await h.pump(tester, folderId: folder.id);
    await tester.pumpAndSettle();
    final grid = find.byType(Scrollable).last;
    final position = tester.state<ScrollableState>(grid).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('노트 0001'), findsOneWidget); // oldest = last (desc)
    expect(
      builtNoteTiles().evaluate().length,
      lessThanOrEqualTo(kMaxBuiltTiles),
    );
    expect(find.text('노트 1000', skipOffstage: false), findsNothing);
  });

  testWidgets('the list view builds only the visible rows plus the cache', (
    tester,
  ) async {
    final folder = await seedBigFolder(tester);
    final h = LibraryTestHarness(backend, size: TestSizes.ipad13Landscape);
    await h.pump(tester, folderId: folder.id);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(LibraryStrings.viewAsList));
    await tester.pumpAndSettle();
    final rows = builtNoteRows().evaluate().length;
    expect(rows, greaterThan(0));
    // About 960 px of list at 64 px a row is 15 rows; plus the cache.
    expect(rows, lessThanOrEqualTo(30));
    final heights = {
      for (final e in builtNoteRows().evaluate())
        (e.renderObject! as RenderBox).size.height,
    };
    expect(heights, hasLength(1));
  });
}
