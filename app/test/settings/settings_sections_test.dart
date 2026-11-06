// defaultSettingsSections() (docs/plans/01-infra.md 4.5.8 table, 9.1;
// 계약 7.4.11): production order, groups, and the contract widget each
// builder makes. 'app.account' comes with M4. 2nd round S2-9 (J5 —
// docs/plans/m5-7/01-infra.md 6.18): contributed sections after
// 'library.newNote', 'app.features' after 'editor.developer'.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/features/feature_switch_section.dart';
import 'package:noteapp/src/settings/about_section.dart';
import 'package:noteapp/src/settings/settings_sections.dart';
import 'package:noteapp/src/settings/storage_section.dart';

void main() {
  test('production order and ids', () {
    expect(defaultSettingsSections().map((e) => e.id), [
      'app.storage',
      'editor.input',
      'editor.pen',
      'editor.page',
      'library.newNote',
      'editor.developer',
      'app.features',
      'app.about',
    ]);
  });

  test('titles and the 일반 group (4.5.8 table)', () {
    final byId = {for (final e in defaultSettingsSections()) e.id: e};
    expect(
      {for (final e in byId.values) e.id: (e.group, e.title)},
      {
        'app.storage': (null, '저장 공간'),
        'editor.input': (null, '입력'),
        'editor.pen': (null, '펜'),
        'editor.page': ('일반', '페이지 넘김'),
        'library.newNote': ('일반', '새 노트 기본값'),
        'editor.developer': (null, '개발자 표시'),
        'app.features': (null, '기능 켜고 끄기'),
        'app.about': (null, '앱 정보'),
      },
    );
  });

  test('no account section before M4', () {
    expect(
      defaultSettingsSections().where((e) => e.id == 'app.account'),
      isEmpty,
    );
  });

  test('settingsSectionsProvider defaults to defaultSettingsSections()', () {
    final container = ProviderContainer.test();
    expect(
      container.read(settingsSectionsProvider).map((e) => e.id),
      defaultSettingsSections().map((e) => e.id),
    );
  });

  test('2nd round S2-9: contributed sections go after library.newNote, in '
      'contribution order (settingsSectionsProvider reads '
      'shellContributionsProvider)', () {
    SettingsSectionEntry entry(String id) => SettingsSectionEntry(
      id: id,
      title: id,
      builder: (_) => const SizedBox(),
    );
    final container = ProviderContainer.test(
      overrides: [
        shellContributionsProvider.overrideWithValue([
          const ShellContribution(moduleId: 'media'),
          ShellContribution(
            moduleId: 'recognition',
            settingsSections: [entry('recog.settings'), entry('recog.more')],
          ),
        ]),
      ],
    );
    expect(container.read(settingsSectionsProvider).map((e) => e.id), [
      'app.storage',
      'editor.input',
      'editor.pen',
      'editor.page',
      'library.newNote',
      'recog.settings',
      'recog.more',
      'editor.developer',
      'app.features',
      'app.about',
    ]);
    expect(
      () => defaultSettingsSections(contributed: [entry('app.storage')]),
      throwsA(isA<AssertionError>()),
    );
  });

  testWidgets('each builder makes the contract widget', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final context = tester.element(find.byType(SizedBox));
    final built = {
      for (final e in defaultSettingsSections()) e.id: e.builder(context),
    };
    expect(built['app.storage'], isA<StorageSection>());
    expect(built['editor.input'], isA<EditorInputSettingsSection>());
    expect(built['editor.pen'], isA<EditorPenSettingsSection>());
    expect(built['editor.page'], isA<EditorPageSettingsSection>());
    expect(built['library.newNote'], isA<LibrarySettingsSection>());
    expect(built['editor.developer'], isA<EditorDeveloperSettingsSection>());
    expect(built['app.features'], isA<FeatureSwitchSection>());
    expect(built['app.about'], isA<AboutSection>());
  });
}
