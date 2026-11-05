// Edge auto scroll during a drag (05-library 6.10.4, 8 L15): near the bottom
// edge of the content grid / list or the sidebar tree, one pump of 100 ms
// moves the offset; above the region it scrolls back up at full speed; the
// middle does not scroll; the end of the drag stops it.
import 'package:feature_library/feature_library.dart';
import 'package:feature_library/src/model/view_prefs.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/ui/content/item_grid.dart';
import 'package:feature_library/src/ui/content/item_list.dart';
import 'package:feature_library/src/ui/content/note_tile.dart';
import 'package:feature_library/src/ui/sidebar/sidebar_folder_tree.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_library_backend.dart';
import '../support/library_test_harness.dart';

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  Future<void> seedNotes(WidgetTester tester, int n) async {
    await tester.runAsync(() async {
      for (var i = 1; i <= n; i++) {
        await backend.seedNote('노트 ${i.toString().padLeft(2, '0')}');
      }
    });
  }

  Future<void> pumpHome(WidgetTester tester) async {
    await LibraryTestHarness(backend).pump(tester);
    await tester.pumpAndSettle();
  }

  double offsetIn(WidgetTester tester, Finder region) => tester
      .state<ScrollableState>(
        find.descendant(of: region, matching: find.byType(Scrollable)).first,
      )
      .position
      .pixels;

  Future<TestGesture> startDrag(WidgetTester tester, Finder source) async {
    final g = await tester.startGesture(
      tester.getCenter(source),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 450));
    await g.moveBy(const Offset(0, 20));
    await tester.pump();
    return g;
  }

  testWidgets('content grid: the bottom edge scrolls down, above the grid '
      'scrolls up, the end of the drag stops', (tester) async {
    await seedNotes(tester, 60);
    await pumpHome(tester);
    final grid = find.byType(ItemGrid);
    final rect = tester.getRect(grid);
    expect(offsetIn(tester, grid), 0);

    final g = await startDrag(tester, find.byType(NoteTile).first);
    // The middle: nothing.
    await g.moveTo(rect.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(offsetIn(tester, grid), 0);

    // 10 px from the bottom edge: v = 1200 × 46 / 56 ≈ 986 px/s.
    await g.moveTo(Offset(rect.center.dx, rect.bottom - 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final down = offsetIn(tester, grid);
    expect(down, greaterThan(90));
    expect(down, lessThan(110));
    await tester.pump(const Duration(milliseconds: 100));
    expect(offsetIn(tester, grid), greaterThan(down));

    // Above the grid (the top bar): full speed up.
    final before = offsetIn(tester, grid);
    await g.moveTo(Offset(rect.center.dx, rect.top - 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(offsetIn(tester, grid), closeTo(before - 120, 1));

    await g.up();
    await tester.pump();
    final stopped = offsetIn(tester, grid);
    await tester.pump(const Duration(milliseconds: 200));
    expect(offsetIn(tester, grid), stopped);
    await tester.pumpAndSettle();
  });

  testWidgets('content list view scrolls the same way', (tester) async {
    await seedNotes(tester, 40);
    await pumpHome(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryScreen)),
    );
    await container
        .read(libraryPrefsProvider.notifier)
        .setViewMode(LibraryViewMode.list);
    await tester.pumpAndSettle();
    final list = find.byType(ItemList);
    final rect = tester.getRect(list);
    final g = await startDrag(tester, find.byType(NoteListRow).first);
    await g.moveTo(Offset(rect.center.dx, rect.bottom - 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(offsetIn(tester, list), greaterThan(100));
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('sidebar tree: the bottom edge scrolls the tree only', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (var i = 1; i <= 40; i++) {
        await backend.seedFolder('폴더 ${i.toString().padLeft(2, '0')}');
      }
      await backend.seedNote('메모');
    });
    await pumpHome(tester);
    final tree = find.byType(SidebarFolderTree);
    final grid = find.byType(ItemGrid);
    final rect = tester.getRect(tree);
    expect(offsetIn(tester, tree), 0);
    await tester.scrollUntilVisible(
      find.text('메모'),
      300,
      scrollable: find
          .descendant(of: grid, matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
    final gridOffset = offsetIn(tester, grid);

    final g = await startDrag(tester, find.text('메모'));
    await g.moveTo(Offset(rect.center.dx, rect.bottom - 5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(offsetIn(tester, tree), greaterThan(80));
    expect(offsetIn(tester, grid), gridOffset);
    await g.up();
    await tester.pumpAndSettle();
  });
}
