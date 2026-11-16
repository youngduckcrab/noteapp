// SettingsScreen (docs/plans/01-infra.md 4.5.8, 9.1; 계약 7.4.11): the
// frame puts [group header] + section header + section body in the
// provider's order, the close button calls onClose, the content is at most
// 720 wide and centered, and the production sections lay out without
// overflow in iPad portrait and landscape.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/settings/about_section.dart';
import 'package:noteapp/src/settings/settings_screen.dart';
import 'package:noteapp/src/settings/settings_sections.dart';
import 'package:noteapp/src/settings/storage_section.dart';

import '../support/settings_harness.dart';

/// A section body of [height] showing `body <id>`.
SettingsSectionEntry _entry(String id, {String? group, double height = 80}) =>
    SettingsSectionEntry(
      id: id,
      title: 'title $id',
      group: group,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [SizedBox(height: height, child: Text('body $id'))],
      ),
    );

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

void main() {
  testWidgets('headers and bodies follow the provider order; a group header '
      'is shown once above consecutive entries', (tester) async {
    final harness = SettingsHarness(build: BuildInfo.local);
    var closed = 0;
    await harness.pump(
      tester,
      SettingsScreen(onClose: () => closed++),
      extra: [
        settingsSectionsProvider.overrideWithValue([
          _entry('a.one'),
          _entry('b.two', group: 'G'),
          _entry('b.three', group: 'G'),
          _entry('c.four'),
          _entry('d.five', group: 'G'),
        ]),
      ],
    );

    expect(find.text(AppStrings.settings), findsOneWidget);
    // Two runs of group G → two group headers.
    expect(find.text('G'), findsNWidgets(2));

    final order = [
      find.text('title a.one'),
      find.byKey(const ValueKey<String>('a.one')),
      find.text('G').first,
      find.text('title b.two'),
      find.byKey(const ValueKey<String>('b.two')),
      find.text('title b.three'),
      find.byKey(const ValueKey<String>('b.three')),
      find.text('title c.four'),
      find.byKey(const ValueKey<String>('c.four')),
      find.text('G').last,
      find.text('title d.five'),
      find.byKey(const ValueKey<String>('d.five')),
    ];
    for (final finder in order) {
      expect(finder, findsOneWidget);
    }
    for (var i = 1; i < order.length; i++) {
      expect(
        _top(tester, order[i]),
        greaterThan(_top(tester, order[i - 1])),
        reason: 'item $i below item ${i - 1}',
      );
    }
    // Each keyed body holds its own section.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('c.four')),
        matching: find.text('body c.four'),
      ),
      findsOneWidget,
    );

    // (v2.14-ui) ← 뒤로 (was ✕).
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    await tester.tap(find.byTooltip(AppStrings.back));
    await tester.pump();
    expect(closed, 1);
  });

  testWidgets('content is at most 720 wide and centered (landscape); full '
      'width minus the gutter in a narrow window', (tester) async {
    final harness = SettingsHarness(build: BuildInfo.local);
    await harness.pump(
      tester,
      SettingsScreen(onClose: () {}),
      extra: [
        settingsSectionsProvider.overrideWithValue([_entry('a.one')]),
      ],
      logical: ipadLandscape,
    );
    final body = tester.getRect(find.byKey(const ValueKey<String>('a.one')));
    expect(body.width, SettingsScreen.maxContentWidth);
    expect(body.left, (ipadLandscape.width - 720) / 2);
    expect(body.right, ipadLandscape.width - (ipadLandscape.width - 720) / 2);

    // Portrait (1032 wide) is also wider than 720 → centered too.
    useIpadView(tester);
    await tester.pump();
    final portrait = tester.getRect(
      find.byKey(const ValueKey<String>('a.one')),
    );
    expect(portrait.width, 720);
    expect(portrait.left, (ipadPortrait.width - 720) / 2);

    // Split-screen width (e.g. 500): 16 px gutters.
    tester.view.physicalSize = const Size(1000, 2752);
    await tester.pump();
    final narrow = tester.getRect(find.byKey(const ValueKey<String>('a.one')));
    expect(narrow.left, 16);
    expect(narrow.width, 500 - 32);
  });

  for (final (name, size) in [
    ('portrait', ipadPortrait),
    ('landscape', ipadLandscape),
  ]) {
    testWidgets('production sections lay out without overflow ($name)', (
      tester,
    ) async {
      final harness = SettingsHarness(build: BuildInfo.local);
      await harness.pump(tester, SettingsScreen(onClose: () {}), logical: size);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final ids = defaultSettingsSections().map((e) => e.id).toList();
      final list = find.byType(Scrollable).first;
      for (final id in ids) {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey<String>(id)),
          200,
          scrollable: list,
        );
        expect(find.byKey(ValueKey<String>(id)), findsOneWidget, reason: id);
        expect(tester.takeException(), isNull, reason: id);
      }
      expect(find.byType(AboutSection), findsOneWidget);

      // The 일반 header once, above 페이지 넘김.
      await tester.scrollUntilVisible(
        find.text(AppStrings.groupGeneral),
        -200,
        scrollable: list,
      );
      expect(find.text(AppStrings.groupGeneral), findsOneWidget);

      // Back to the top: the storage section is there again.
      await tester.drag(list, const Offset(0, 5000));
      await tester.pumpAndSettle();
      expect(find.byType(StorageSection), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a section body is built once per entry and keyed by its id', (
    tester,
  ) async {
    final harness = SettingsHarness(build: BuildInfo.local);
    await harness.pump(tester, SettingsScreen(onClose: () {}));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('app.storage')),
        matching: find.byType(StorageSection),
      ),
      findsOneWidget,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    // v2.14-ui: + 화면 스타일, 밝기.
    expect(container.read(settingsSectionsProvider), hasLength(11));
  });
}
