// defaultSettingsSections() (docs/plans/01-infra.md 4.5.8 table, 9.1;
// 계약 7.4.11): production order, groups, and the contract widget each
// builder makes. 'app.account' comes with M4. 2nd round S2-9 (J5 —
// docs/plans/m5-7/01-infra.md 6.18): contributed sections after
// 'library.newNote', 'app.features' after 'editor.developer'; (J14b)
// 'app.v1Copy' ('이전 판 DB 사본') between 'app.features' and 'app.about'.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show developerModeProvider;
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/features/feature_switch_section.dart';
import 'package:noteapp/src/settings/about_section.dart';
import 'package:noteapp/src/settings/settings_sections.dart';
import 'package:noteapp/src/settings/storage_section.dart';
import 'package:noteapp/src/settings/v1_copy_section.dart';

void main() {
  test('production order and ids (developer mode)', () {
    expect(defaultSettingsSections(developerMode: true).map((e) => e.id), [
      // v2.14-ui: the '화면' group first.
      'app.style',
      'app.brightness',
      'app.storage',
      'editor.input',
      'editor.pen',
      'editor.page',
      'library.newNote',
      'editor.developer',
      'app.features',
      'app.v1Copy',
      'app.about',
    ]);
  });

  test('titles, the 화면 and 일반 groups (4.5.8 table, v2.14-ui)', () {
    final byId = {
      for (final e in defaultSettingsSections(developerMode: true)) e.id: e,
    };
    expect(
      {for (final e in byId.values) e.id: (e.group, e.title)},
      {
        'app.style': ('화면', '화면 스타일'),
        'app.brightness': ('화면', '밝기'),
        'app.storage': (null, '저장 공간'),
        'editor.input': (null, '입력'),
        'editor.pen': (null, '펜'),
        'editor.page': ('일반', '페이지 넘김'),
        'library.newNote': ('일반', '새 노트 기본값'),
        'editor.developer': (null, '개발자 표시'),
        'app.features': (null, '기능 켜고 끄기'),
        'app.v1Copy': (null, '이전 판 DB 사본'),
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

  test('(v2.14-ui) outside developer mode: no 개발자 표시 · 기능 켜고 끄기 · '
      '이전 판 DB 사본', () {
    expect(defaultSettingsSections().map((e) => e.id), [
      'app.style',
      'app.brightness',
      'app.storage',
      'editor.input',
      'editor.pen',
      'editor.page',
      'library.newNote',
      'app.about',
    ]);
  });

  test('settingsSectionsProvider defaults to defaultSettingsSections() and '
      'follows developerModeProvider', () {
    final container = ProviderContainer.test();
    expect(
      container.read(settingsSectionsProvider).map((e) => e.id),
      defaultSettingsSections().map((e) => e.id),
    );
    final dev = ProviderContainer.test(
      overrides: [developerModeProvider.overrideWithValue(true)],
    );
    expect(
      dev.read(settingsSectionsProvider).map((e) => e.id),
      defaultSettingsSections(developerMode: true).map((e) => e.id),
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
        developerModeProvider.overrideWithValue(true),
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
      'app.style',
      'app.brightness',
      'app.storage',
      'editor.input',
      'editor.pen',
      'editor.page',
      'library.newNote',
      'recog.settings',
      'recog.more',
      'editor.developer',
      'app.features',
      'app.v1Copy',
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
      for (final e in defaultSettingsSections(developerMode: true))
        e.id: e.builder(context),
    };
    expect(built['app.storage'], isA<StorageSection>());
    expect(built['editor.input'], isA<EditorInputSettingsSection>());
    expect(built['editor.pen'], isA<EditorPenSettingsSection>());
    expect(built['editor.page'], isA<EditorPageSettingsSection>());
    expect(built['library.newNote'], isA<LibrarySettingsSection>());
    expect(built['editor.developer'], isA<EditorDeveloperSettingsSection>());
    expect(built['app.features'], isA<FeatureSwitchSection>());
    expect(built['app.v1Copy'], isA<V1CopySection>());
    expect(built['app.about'], isA<AboutSection>());
  });
}
