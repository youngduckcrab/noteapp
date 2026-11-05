// Breadcrumb bar (05-library 6.6, 8 L10): 4 / 3 / 2 places by size class,
// the hidden part in the '…' menu, ancestor crumbs open their folder, the
// current one is bold and not a button, 200 px per crumb, renames show up.
import 'package:feature_library/feature_library.dart' show LibraryScreen;
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/ui/top_bar/breadcrumb_bar.dart';
import 'package:feature_library/src/ui/top_bar/library_top_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_library_backend.dart';
import '../support/fixtures.dart';
import '../support/library_test_harness.dart';
import '../support/test_sizes.dart';

/// The texts of the breadcrumb, in order ('…' for the hidden part).
List<String> crumbs(WidgetTester tester) {
  final bar = find.byType(BreadcrumbBar);
  final out = <String>[];
  for (final e
      in find
          .descendant(
            of: bar,
            matching: find.byWidgetPredicate(
              (w) => w is Text || (w is Icon && w.icon == Icons.more_horiz),
            ),
          )
          .evaluate()) {
    final w = e.widget;
    out.add(w is Text ? w.data! : LibraryStrings.ellipsis);
  }
  return out;
}

Finder crumbButton(String label) => find.descendant(
  of: find.byType(BreadcrumbBar),
  matching: find.widgetWithText(TextButton, label),
);

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  Future<(SampleLibrary, LibraryTestHarness)> pumpAt(
    WidgetTester tester,
    Size size, {
    String? Function(SampleLibrary s)? folder,
  }) async {
    final sample = (await tester.runAsync(() => seedSampleLibrary(backend)))!;
    final h = LibraryTestHarness(backend, size: size);
    await h.pump(tester, folderId: folder?.call(sample));
    await tester.pumpAndSettle();
    return (sample, h);
  }

  testWidgets('home: one current crumb, not a button', (tester) async {
    await pumpAt(tester, TestSizes.ipad13Landscape);
    expect(crumbs(tester), ['홈']);
    expect(crumbButton('홈'), findsNothing);
    final text = tester.widget<Text>(
      find.descendant(of: find.byType(BreadcrumbBar), matching: find.text('홈')),
    );
    expect(text.style?.fontWeight, FontWeight.w700);
  });

  testWidgets('expanded keeps 4: 홈 › … › 극한 › 연습 문제; … opens the rest', (
    tester,
  ) async {
    final (sample, h) = await pumpAt(
      tester,
      TestSizes.ipad13Landscape,
      folder: (s) => s.deepest.id,
    );
    expect(crumbs(tester), ['홈', '…', '극한', '연습 문제']);
    expect(crumbButton('연습 문제'), findsNothing); // current

    await tester.tap(find.byTooltip(LibraryStrings.hiddenPath));
    await tester.pumpAndSettle();
    final items = find.byType(MenuItemButton);
    expect(
      [
        for (final e in items.evaluate())
          ((e.widget as MenuItemButton).child! as ConstrainedBox).child!,
      ].map((w) => (w as Text).data),
      ['수학', '미적분'],
    );
    await tester.tap(find.widgetWithText(MenuItemButton, '미적분'));
    await tester.pumpAndSettle();
    expect(h.log.entries, ['folder:${sample.nested[0].id}']);
    expect(crumbs(tester), ['홈', '수학', '미적분']);
  });

  testWidgets('medium keeps 3: 홈 › … › 연습 문제', (tester) async {
    await pumpAt(tester, TestSizes.ipad13Portrait, folder: (s) => s.deepest.id);
    expect(crumbs(tester), ['홈', '…', '연습 문제']);
  });

  testWidgets('compact keeps 2: … › 연습 문제; 홈 is in the menu', (tester) async {
    final (_, h) = await pumpAt(
      tester,
      TestSizes.compact,
      folder: (s) => s.deepest.id,
    );
    expect(crumbs(tester), ['…', '연습 문제']);
    await tester.tap(find.byTooltip(LibraryStrings.hiddenPath));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNWidgets(4));
    await tester.tap(find.widgetWithText(MenuItemButton, '홈'));
    await tester.pumpAndSettle();
    expect(h.log.entries, ['folder:home']);
    expect(crumbs(tester), ['홈']);
  });

  testWidgets('an ancestor crumb opens its folder', (tester) async {
    final (sample, h) = await pumpAt(
      tester,
      TestSizes.ipad13Landscape,
      folder: (s) => s.nested[1].id, // 극한: 4 places, nothing hidden
    );
    expect(crumbs(tester), ['홈', '수학', '미적분', '극한']);
    expect(find.byTooltip(LibraryStrings.hiddenPath), findsNothing);

    await tester.tap(crumbButton('수학'));
    await tester.pumpAndSettle();
    expect(h.log.entries, ['folder:${sample.math.id}']);
    await tester.tap(crumbButton('홈'));
    await tester.pumpAndSettle();
    expect(h.log.entries.last, 'folder:home');
  });

  testWidgets('a long name is cut at 200', (tester) async {
    final long = '아주 긴 폴더 이름' * 10;
    late final String id;
    await tester.runAsync(() async {
      id = (await backend.seedFolder(long)).id;
    });
    final h = LibraryTestHarness(backend);
    await h.pump(tester, folderId: id);
    await tester.pumpAndSettle();
    final text = find.descendant(
      of: find.byType(BreadcrumbBar),
      matching: find.text(long),
    );
    expect(text, findsOneWidget);
    expect(tester.getSize(text).width, lessThanOrEqualTo(200));
  });

  testWidgets('a rename elsewhere shows up', (tester) async {
    final (sample, _) = await pumpAt(
      tester,
      TestSizes.ipad13Landscape,
      folder: (s) => s.nested[0].id,
    );
    expect(crumbs(tester), ['홈', '수학', '미적분']);
    await tester.runAsync(
      () => backend.remoteChange(
        (store) => store.library.renameFolder(sample.math.id, '수학 Ⅰ'),
      ),
    );
    await tester.pumpAndSettle();
    expect(crumbs(tester), ['홈', '수학 Ⅰ', '미적분']);
  });

  testWidgets('other sections show their title instead', (tester) async {
    await pumpAt(tester, TestSizes.ipad13Landscape, folder: (s) => s.math.id);
    expect(find.byType(BreadcrumbBar), findsOneWidget);
    ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)))
        .read(
          librarySectionProvider(
            tester.widget<LibraryScreen>(find.byType(LibraryScreen)).folderId,
          ).notifier,
        )
        .showFavorites();
    await tester.pumpAndSettle();
    expect(find.byType(BreadcrumbBar), findsNothing);
    expect(
      find.descendant(
        of: find.byType(LibraryTopBar),
        matching: find.text(LibraryStrings.favorites),
      ),
      findsOneWidget,
    );
  });
}
