// Folder missing view (05-library 6.4, 8 L10): a route folder that is in the
// trash → [휴지통 보기] [홈으로]; gone → [홈으로]; another device trashing /
// purging / restoring the shown folder switches the view (remoteChange).
import 'package:feature_library/feature_library.dart' show LibraryScreen;
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/model/section.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/ui/content/folder_missing_view.dart';
import 'package:feature_library/src/ui/content/note_tile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

import '../support/fake_library_backend.dart';
import '../support/fixtures.dart';
import '../support/library_test_harness.dart';

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  Future<SampleLibrary> seed(WidgetTester tester) async =>
      (await tester.runAsync(() => seedSampleLibrary(backend)))!;

  Future<LibraryTestHarness> pumpAt(WidgetTester tester, String id) async {
    final h = LibraryTestHarness(backend);
    await h.pump(tester, folderId: id);
    await tester.pumpAndSettle();
    return h;
  }

  testWidgets('a trashed route folder: 휴지통 보기 and 홈으로', (tester) async {
    final sample = await seed(tester);
    await tester.runAsync(
      () => backend.seedTrashed([
        FolderRef(sample.math.id),
      ], at: DateTime(2026, 11, 3)),
    );
    final h = await pumpAt(tester, sample.math.id);
    expect(find.text(LibraryStrings.folderInTrash), findsOneWidget);
    expect(find.byType(NoteTile), findsNothing);

    await tester.tap(find.text(LibraryStrings.showTrash));
    await tester.pumpAndSettle();
    expect(
      containerOf(tester).read(librarySectionProvider(sample.math.id)),
      const TrashSection(),
    );
    expect(h.log.entries, isEmpty);

    containerOf(tester)
        .read(librarySectionProvider(sample.math.id).notifier)
        .showRouteFolder();
    await tester.pumpAndSettle();
    await tester.tap(find.text(LibraryStrings.goHome));
    await tester.pumpAndSettle();
    expect(h.log.entries, ['folder:home']);
    expect(find.byType(FolderMissingView), findsNothing);
  });

  testWidgets('a folder inside a trashed one is shown as trashed', (
    tester,
  ) async {
    final sample = await seed(tester);
    await tester.runAsync(
      () => backend.seedTrashed([
        FolderRef(sample.math.id),
      ], at: DateTime(2026, 11, 3)),
    );
    await pumpAt(tester, sample.deepest.id);
    expect(find.text(LibraryStrings.folderInTrash), findsOneWidget);
  });

  testWidgets('an unknown id: 폴더를 찾을 수 없어요 and 홈으로 only', (tester) async {
    await seed(tester);
    final h = await pumpAt(tester, 'no-such-folder');
    expect(find.text(LibraryStrings.folderNotFound), findsOneWidget);
    expect(find.text(LibraryStrings.showTrash), findsNothing);
    await tester.tap(find.text(LibraryStrings.goHome));
    await tester.pumpAndSettle();
    expect(h.log.entries, ['folder:home']);
    expect(find.text(LibraryStrings.emptyHome), findsNothing);
    expect(find.byType(NoteTile), findsNWidgets(4));
  });

  testWidgets('another device trashes, restores, then purges the folder', (
    tester,
  ) async {
    final sample = await seed(tester);
    await pumpAt(tester, sample.nested[2].id); // 연습 문제: one note
    expect(find.widgetWithText(NoteTile, '극한 정리'), findsOneWidget);

    await tester.runAsync(
      () => backend.remoteChange(
        (store) => store.library.trashItems([FolderRef(sample.nested[2].id)]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(LibraryStrings.folderInTrash), findsOneWidget);

    await tester.runAsync(
      () => backend.remoteChange(
        (store) => store.trash.restore([FolderRef(sample.nested[2].id)]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FolderMissingView), findsNothing);
    expect(find.widgetWithText(NoteTile, '극한 정리'), findsOneWidget);

    await tester.runAsync(
      () => backend.remoteChange((store) async {
        await store.library.trashItems([FolderRef(sample.nested[2].id)]);
        await store.trash.purge([FolderRef(sample.nested[2].id)]);
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text(LibraryStrings.folderNotFound), findsOneWidget);
    expect(backend.calls, isEmpty); // nothing went through the wrappers
  });
}
