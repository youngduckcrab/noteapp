// (UI stage 2, 05-library 20) The library's top bar and sidebar draw the
// ui_kit line icons; menus take their glyph from the same table.
import 'package:feature_library/src/ui/sidebar/library_sidebar.dart';
import 'package:feature_library/src/ui/top_bar/library_top_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../support/fake_library_backend.dart';
import '../support/library_test_harness.dart';

Finder _lineIcon(Finder within, AppIconKind kind) => find.descendant(
  of: within,
  matching: find.byWidgetPredicate((w) => w is AppIcon && w.kind == kind),
);

void main() {
  late FakeLibraryBackend backend;
  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  testWidgets('sidebar: 모든 노트 · 최근 · 즐겨찾기 · 휴지통 · 설정 are line icons', (
    tester,
  ) async {
    await tester.runAsync(() => backend.seedNote('물리 2주차'));
    await LibraryTestHarness(backend)
        .pump(tester, theme: buildStyleTheme(AppStyle.craft, Brightness.light));
    await tester.pumpAndSettle();
    final sidebar = find.byType(LibrarySidebar);
    for (final kind in [
      AppIconKind.home,
      AppIconKind.recent,
      AppIconKind.favorite,
      AppIconKind.trash,
      AppIconKind.settings,
    ]) {
      expect(_lineIcon(sidebar, kind), findsOneWidget, reason: kind.name);
    }
    final bar = find.byType(LibraryTopBar);
    for (final kind in [
      AppIconKind.sidebar,
      AppIconKind.sort,
      AppIconKind.select,
      AppIconKind.add,
    ]) {
      expect(_lineIcon(bar, kind), findsWidgets, reason: kind.name);
    }
  });
}
