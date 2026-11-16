// '화면' settings: 홈 화면 스타일, 필기 화면 스타일 and 밝기
// (docs/plans/m5-7/01-infra.md 14.3, contract 7.4.4 v2.14-ui): defaults,
// persistence as device keys, the stage-1 style migration, live switching
// of the theme, unknown stored values, phone width.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/app/appearance.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/settings/appearance_section.dart';
import 'package:noteapp/src/settings/settings_screen.dart';
import 'package:ui_kit/ui_kit.dart';

import '../support/settings_harness.dart';

void main() {
  test('the keys are device keys under app.appearance.* with the defaults '
      '크래프트 · 시스템 따라', () {
    expect(AppearanceKeys.homeStyle.name, 'app.appearance.homeStyle');
    expect(AppearanceKeys.editorStyle.name, 'app.appearance.editorStyle');
    expect(AppearanceKeys.legacyStyle.name, 'app.appearance.style');
    expect(AppearanceKeys.brightness.name, 'app.appearance.brightness');
    for (final key in [
      AppearanceKeys.homeStyle,
      AppearanceKeys.editorStyle,
      AppearanceKeys.legacyStyle,
      AppearanceKeys.brightness,
    ]) {
      expect(key.scope, SettingScope.device);
    }
    expect(AppearanceKeys.homeStyle.defaultValue, 'craft');
    expect(AppearanceKeys.editorStyle.defaultValue, 'craft');
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
    expect(
      const AppAppearance().effectiveBrightness(Brightness.dark),
      Brightness.dark,
    );
    expect(
      const AppAppearance(brightness: AppBrightnessMode.light)
          .effectiveBrightness(Brightness.dark),
      Brightness.light,
    );
  });

  test('(split) migration: a stored stage-1 style fills both new keys while '
      'they are not stored; a stored new key wins', () {
    AppAppearance from(Map<String, Object?> raw) =>
        AppAppearance.fromSnapshot(SettingsSnapshot(raw));
    expect(from({}), const AppAppearance());
    expect(
      from({'app.appearance.style': 'studio'}),
      const AppAppearance(
        homeStyle: AppStyle.studio,
        editorStyle: AppStyle.studio,
      ),
    );
    expect(
      from({
        'app.appearance.style': 'studio',
        'app.appearance.homeStyle': 'calm',
      }),
      const AppAppearance(
        homeStyle: AppStyle.calm,
        editorStyle: AppStyle.studio,
      ),
    );
    // A stored 'craft' is a choice too: it is not replaced by the old key.
    expect(
      from({
        'app.appearance.style': 'studio',
        'app.appearance.homeStyle': 'craft',
        'app.appearance.editorStyle': 'craft',
      }),
      const AppAppearance(),
    );
    expect(
      from({
        'app.appearance.homeStyle': 'neon',
        'app.appearance.editorStyle': 7,
      }),
      const AppAppearance(),
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
      Theme.of(tester.element(find.byType(AppStyleSection).first));

  testWidgets('the 화면 group is first: 홈 화면 스타일 and 필기 화면 스타일 '
      '(three cards each, with previews and notes), then the brightness '
      'buttons', (tester) async {
    await pumpSettings(tester);
    final group = tester.getTopLeft(find.text('화면'));
    final home = tester.getTopLeft(find.text('홈 화면 스타일'));
    final editor = tester.getTopLeft(find.text('필기 화면 스타일'));
    final brightness = tester.getTopLeft(find.text('밝기'));
    final storage = tester.getTopLeft(find.text('저장 공간'));
    expect(group.dy, lessThan(home.dy));
    expect(home.dy, lessThan(editor.dy));
    expect(editor.dy, lessThan(brightness.dy));
    expect(brightness.dy, lessThan(storage.dy));
    for (final target in StyleTarget.values) {
      for (final style in AppStyle.values) {
        expect(
          find.byKey(AppearanceSectionKeys.styleOf(target, style)),
          findsOneWidget,
        );
      }
    }
    final swatches = tester.widgetList<StylePreviewSwatch>(
      find.byType(StylePreviewSwatch),
    );
    expect(swatches, hasLength(6));
    expect(swatches.where((s) => s.home), hasLength(3));
    for (final label in ['크래프트', '미니멀', '스튜디오']) {
      expect(find.text(label), findsNWidgets(2));
    }
    for (final label in ['시스템 따라', '밝게', '어둡게']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text(AppStrings.homeStyleNote), findsOneWidget);
    expect(find.text('노트를 열었을 때의 도구 막대, 펜, 메뉴에 적용돼요.'), findsOneWidget);
    // The editor note sits under the editor cards.
    expect(
      tester.getTopLeft(find.text(AppStrings.editorStyleNote)).dy,
      greaterThan(
        tester
            .getBottomLeft(
              find.byKey(
                AppearanceSectionKeys.styleOf(
                  StyleTarget.editor,
                  AppStyle.craft,
                ),
              ),
            )
            .dy,
      ),
    );
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

  testWidgets('(review) the notes say what changes now: the toolbar layout '
      'comes later, only the screen outside the paper darkens; the hints do '
      'not depend on brightness', (tester) async {
    await pumpSettings(tester);
    expect(find.byKey(AppearanceSectionKeys.layoutNote), findsOneWidget);
    expect(find.text(AppStrings.styleLayoutNote), findsOneWidget);
    expect(AppStrings.styleLayoutNote, contains('도구 막대 배치는 다음 업데이트'));
    expect(find.text(AppStrings.brightnessPaperNote), findsOneWidget);
    expect(AppStrings.brightnessPaperNote, contains('종이 바깥 화면만'));
    expect(AppStrings.brightnessPaperNote, isNot(contains('페이지 둘레만')));
    for (final hint in [
      AppStrings.styleCraftHint,
      AppStrings.styleCalmHint,
      AppStrings.styleStudioHint,
    ]) {
      // No promise of a layout this stage does not have, and nothing that
      // contradicts a dark preview.
      expect(hint, isNot(contains('도구 막대')));
      expect(hint, isNot(contains('하얗')));
    }
  });

  bool selected(WidgetTester tester, StyleTarget target, AppStyle style) =>
      tester
          .widget<Semantics>(
            find
                .descendant(
                  of: find.byKey(AppearanceSectionKeys.styleOf(target, style)),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .properties
          .selected ??
      false;

  testWidgets('choosing a home style stores homeStyle and the settings '
      'theme changes at once; the editor style is left alone', (tester) async {
    final harness = await pumpSettings(tester);
    await tester.tap(
      find.byKey(
        AppearanceSectionKeys.styleOf(StyleTarget.home, AppStyle.calm),
      ),
    );
    await tester.pumpAndSettle();
    final raw = await tester.runAsync(
      () => harness.store.settings.watchAll().first,
    );
    expect(raw!.raw['app.appearance.homeStyle'], 'calm');
    expect(raw.raw.containsKey('app.appearance.editorStyle'), isFalse);
    final tokens = shownTheme(tester).extension<StyleTokens>()!;
    expect(tokens, styleTokensFor(AppStyle.calm, Brightness.light));
    expect(selected(tester, StyleTarget.home, AppStyle.calm), isTrue);
    expect(selected(tester, StyleTarget.editor, AppStyle.craft), isTrue);
    expect(selected(tester, StyleTarget.editor, AppStyle.calm), isFalse);

    await tester.tap(
      find.byKey(
        AppearanceSectionKeys.styleOf(StyleTarget.home, AppStyle.studio),
      ),
    );
    await tester.pumpAndSettle();
    expect(shownTheme(tester).extension<StyleTokens>()!.style, AppStyle.studio);
  });

  testWidgets('choosing an editor style stores editorStyle; settings keeps '
      'the home style', (tester) async {
    final harness = await pumpSettings(tester);
    await tester.ensureVisible(
      find.byKey(
        AppearanceSectionKeys.styleOf(StyleTarget.editor, AppStyle.studio),
      ),
    );
    await tester.tap(
      find.byKey(
        AppearanceSectionKeys.styleOf(StyleTarget.editor, AppStyle.studio),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      await tester.runAsync(
        () => harness.store.settings.get(AppearanceKeys.editorStyle),
      ),
      'studio',
    );
    expect(selected(tester, StyleTarget.editor, AppStyle.studio), isTrue);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    expect(
      container.read(appAppearanceProvider),
      const AppAppearance(editorStyle: AppStyle.studio),
    );
    expect(shownTheme(tester).extension<StyleTokens>()!.style, AppStyle.craft);
  });

  testWidgets('(split) phone width: each block keeps its three cards in one '
      'row without hints, the chosen style\'s line under it; no overflow', (
    tester,
  ) async {
    final harness = SettingsHarness(build: BuildInfo.local);
    await harness.pump(
      tester,
      SettingsScreen(onClose: () {}),
      followAppearance: true,
      logical: const Size(360, 780),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final target in StyleTarget.values) {
      final tops = {
        for (final style in AppStyle.values)
          tester
              .getTopLeft(
                find.byKey(AppearanceSectionKeys.styleOf(target, style)),
              )
              .dy,
      };
      expect(tops, hasLength(1), reason: '$target cards share a row');
    }
    // Hints are not in the cards; the chosen one (크래프트) shows once per
    // block under the row.
    expect(find.text(AppStrings.styleCalmHint), findsNothing);
    expect(
      find.text('${AppStrings.styleCraft} · ${AppStrings.styleCraftHint}'),
      findsNWidgets(2),
    );
    // (review) The editor block's two notes run as one paragraph on phones;
    // the owner's line stays in it.
    expect(
      find.text('${AppStrings.editorStyleNote} ${AppStrings.styleLayoutNote}'),
      findsOneWidget,
    );
    expect(find.text(AppStrings.styleLayoutNote), findsNothing);
    expect(find.byKey(AppearanceSectionKeys.layoutNote), findsOneWidget);
    expect(
      find.byKey(AppearanceSectionKeys.noteOf(StyleTarget.editor)),
      findsOneWidget,
    );
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

  testWidgets('stored values are read at start (the stage-1 style for both '
      'while the new keys are not stored); unknown values fall back', (
    tester,
  ) async {
    final harness = SettingsHarness(build: BuildInfo.local);
    await tester.runAsync(() async {
      await harness.store.settings.set(AppearanceKeys.legacyStyle, 'studio');
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
        homeStyle: AppStyle.studio,
        editorStyle: AppStyle.studio,
        brightness: AppBrightnessMode.dark,
      ),
    );
    expect(shownTheme(tester).brightness, Brightness.dark);
    expect(selected(tester, StyleTarget.home, AppStyle.studio), isTrue);
    expect(selected(tester, StyleTarget.editor, AppStyle.studio), isTrue);

    // Choosing a home style keeps the editor on the earlier choice.
    await tester.tap(
      find.byKey(
        AppearanceSectionKeys.styleOf(StyleTarget.home, AppStyle.calm),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(appAppearanceProvider),
      const AppAppearance(
        homeStyle: AppStyle.calm,
        editorStyle: AppStyle.studio,
        brightness: AppBrightnessMode.dark,
      ),
    );

    await tester.runAsync(() async {
      await harness.store.settings.set(AppearanceKeys.homeStyle, 'neon');
      await harness.store.settings.set(AppearanceKeys.editorStyle, 'neon');
      await harness.store.settings.set(AppearanceKeys.brightness, 'dim');
    });
    await tester.pumpAndSettle();
    expect(container.read(appAppearanceProvider), const AppAppearance());
  });
}
