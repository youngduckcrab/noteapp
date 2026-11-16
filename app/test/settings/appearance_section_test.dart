// '화면' settings: 화면 스타일 and 밝기 (docs/plans/m5-7/01-infra.md 14.3,
// contract 7.4.4 v2.14-ui): defaults, persistence as device keys, live
// switching of the theme, unknown stored values.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/app/appearance.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/settings/appearance_section.dart';
import 'package:noteapp/src/settings/settings_screen.dart';
import 'package:ui_kit/ui_kit.dart';

import '../support/settings_harness.dart';

void main() {
  test('the keys are device keys under app.appearance.* with the defaults '
      '크래프트 · 시스템 따라', () {
    expect(AppearanceKeys.style.name, 'app.appearance.style');
    expect(AppearanceKeys.brightness.name, 'app.appearance.brightness');
    expect(AppearanceKeys.style.scope, SettingScope.device);
    expect(AppearanceKeys.brightness.scope, SettingScope.device);
    expect(AppearanceKeys.style.defaultValue, 'craft');
    expect(AppearanceKeys.brightness.defaultValue, 'system');
    expect(const AppAppearance().themeMode, ThemeMode.system);
    expect(
      const AppAppearance(brightness: AppBrightnessMode.dark).themeMode,
      ThemeMode.dark,
    );
    expect(
      const AppAppearance(brightness: AppBrightnessMode.light).themeMode,
      ThemeMode.light,
    );
  });

  Future<SettingsHarness> pumpSettings(WidgetTester tester) async {
    final harness = SettingsHarness(build: BuildInfo.local);
    await harness.pump(
      tester,
      SettingsScreen(onClose: () {}),
      followAppearance: true,
    );
    await tester.pumpAndSettle();
    return harness;
  }

  ThemeData shownTheme(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(AppStyleSection)));

  testWidgets('the 화면 group is first: three style cards with previews and '
      'the brightness buttons', (tester) async {
    await pumpSettings(tester);
    final group = tester.getTopLeft(find.text('화면'));
    final storage = tester.getTopLeft(find.text('저장 공간'));
    expect(group.dy, lessThan(storage.dy));
    for (final style in AppStyle.values) {
      expect(find.byKey(AppearanceSectionKeys.styleOf(style)), findsOneWidget);
    }
    expect(find.byType(StylePreviewSwatch), findsNWidgets(3));
    for (final label in ['크래프트', '미니멀', '스튜디오', '시스템 따라', '밝게', '어둡게']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      tester
          .widget<SegmentedButton<AppBrightnessMode>>(
            find.byKey(AppearanceSectionKeys.brightness),
          )
          .selected,
      {AppBrightnessMode.system},
    );
    // Default: 크래프트 light (the test view's platform brightness is light).
    expect(shownTheme(tester).extension<StyleTokens>()!.style, AppStyle.craft);
    expect(shownTheme(tester).brightness, Brightness.light);
  });

  testWidgets('choosing a style stores its wire name and the theme changes '
      'at once', (tester) async {
    final harness = await pumpSettings(tester);
    await tester.tap(find.byKey(AppearanceSectionKeys.styleOf(AppStyle.calm)));
    await tester.pumpAndSettle();
    final stored = await tester.runAsync(
      () => harness.store.settings.get(AppearanceKeys.style),
    );
    expect(stored, 'calm');
    final tokens = shownTheme(tester).extension<StyleTokens>()!;
    expect(tokens, styleTokensFor(AppStyle.calm, Brightness.light));
    expect(
      tester
          .widget<Semantics>(
            find
                .descendant(
                  of: find.byKey(AppearanceSectionKeys.styleOf(AppStyle.calm)),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .properties
          .selected,
      isTrue,
    );

    await tester.tap(
      find.byKey(AppearanceSectionKeys.styleOf(AppStyle.studio)),
    );
    await tester.pumpAndSettle();
    expect(shownTheme(tester).extension<StyleTokens>()!.style, AppStyle.studio);
  });

  testWidgets('어둡게 / 밝게 / 시스템 따라 switch the brightness live and are '
      'stored', (tester) async {
    final harness = await pumpSettings(tester);
    await tester.tap(find.text('어둡게'));
    await tester.pumpAndSettle();
    expect(shownTheme(tester).brightness, Brightness.dark);
    expect(
      shownTheme(tester).extension<StyleTokens>(),
      styleTokensFor(AppStyle.craft, Brightness.dark),
    );
    expect(
      await tester.runAsync(
        () => harness.store.settings.get(AppearanceKeys.brightness),
      ),
      'dark',
    );
    // The preview swatches follow the brightness.
    final swatches = tester
        .widgetList<StylePreviewSwatch>(find.byType(StylePreviewSwatch))
        .map((s) => s.tokens.brightness);
    expect(swatches, everyElement(Brightness.dark));

    await tester.tap(find.text('밝게'));
    await tester.pumpAndSettle();
    expect(shownTheme(tester).brightness, Brightness.light);

    // 시스템 따라 with a dark platform → dark.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.tap(find.text('시스템 따라'));
    await tester.pumpAndSettle();
    expect(shownTheme(tester).brightness, Brightness.dark);
    expect(
      await tester.runAsync(
        () => harness.store.settings.get(AppearanceKeys.brightness),
      ),
      'system',
    );
  });

  testWidgets('stored values are read at start; unknown values fall back', (
    tester,
  ) async {
    final harness = SettingsHarness(build: BuildInfo.local);
    await tester.runAsync(() async {
      await harness.store.settings.set(AppearanceKeys.style, 'studio');
      await harness.store.settings.set(AppearanceKeys.brightness, 'dark');
    });
    final container = await harness.pump(
      tester,
      SettingsScreen(onClose: () {}),
      followAppearance: true,
    );
    await tester.pumpAndSettle();
    expect(
      container.read(appAppearanceProvider),
      const AppAppearance(
        style: AppStyle.studio,
        brightness: AppBrightnessMode.dark,
      ),
    );
    expect(shownTheme(tester).brightness, Brightness.dark);

    await tester.runAsync(() async {
      await harness.store.settings.set(AppearanceKeys.style, 'neon');
      await harness.store.settings.set(AppearanceKeys.brightness, 'dim');
    });
    await tester.pumpAndSettle();
    expect(container.read(appAppearanceProvider), const AppAppearance());
  });
}
