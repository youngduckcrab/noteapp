/// Section list of the settings screen (docs/plans/01-infra.md 4.5.8,
/// 계약 7.4.11).
library;

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/strings.dart';
import '../bootstrap/app_module.dart' show ShellContribution;
import '../features/feature_switch_section.dart';
import 'about_section.dart';
import 'storage_section.dart';
import 'v1_copy_section.dart';

@immutable
final class SettingsSectionEntry {
  const SettingsSectionEntry({
    required this.id,
    required this.title,
    required this.builder,
    this.group,
  });

  /// Stable id `<area>.<name>` (e.g. 'editor.input'); widget key and tests.
  final String id;

  /// Section header (Korean).
  final String title;

  /// Optional group header shown once above consecutive entries ('일반').
  final String? group;

  /// Column-only section body (no Scaffold, no scrolling).
  final WidgetBuilder builder;
}

/// Overridden in the root overrides with BootstrapSuccess.contributions
/// (docs/plans/m5-7/01-infra.md 4.6.7).
final shellContributionsProvider = Provider<List<ShellContribution>>(
  (ref) => const [],
  name: 'shellContributionsProvider',
);

/// Production order (table below; 2nd round S2-9). [contributed] entries go
/// after 'library.newNote' in contribution order (e.g. 'recog.settings' —
/// '인식', only when the recognition module started); 'app.features' after
/// 'editor.developer', 'app.v1Copy' after 'app.features'. Ids stay unique
/// (assert). M4 prepends the 'app.account' entry.
///
/// | id | group | title |
/// |---|---|---|
/// | app.storage | — | 저장 공간 |
/// | editor.input | — | 입력 |
/// | editor.pen | — | 펜 |
/// | editor.page | 일반 | 페이지 넘김 |
/// | library.newNote | 일반 | 새 노트 기본값 |
/// | (contributed) | — | (e.g. 인식) |
/// | editor.developer | — | 개발자 표시 |
/// | app.features | — | 기능 켜고 끄기 |
/// | app.v1Copy | — | 이전 판 DB 사본 |
/// | app.about | — | 앱 정보 |
List<SettingsSectionEntry> defaultSettingsSections({
  List<SettingsSectionEntry> contributed = const [],
}) {
  final sections = _sections(contributed);
  assert(
    sections.map((s) => s.id).toSet().length == sections.length,
    'settings section ids are not unique: ${sections.map((s) => s.id)}',
  );
  return sections;
}

List<SettingsSectionEntry> _sections(List<SettingsSectionEntry> contributed) =>
    [
      SettingsSectionEntry(
        id: 'app.storage',
        title: AppStrings.sectionStorage,
        builder: (context) => const StorageSection(),
      ),
      SettingsSectionEntry(
        id: 'editor.input',
        title: AppStrings.sectionInput,
        builder: (context) => const EditorInputSettingsSection(),
      ),
      SettingsSectionEntry(
        id: 'editor.pen',
        title: AppStrings.sectionPen,
        builder: (context) => const EditorPenSettingsSection(),
      ),
      SettingsSectionEntry(
        id: 'editor.page',
        group: AppStrings.groupGeneral,
        title: AppStrings.sectionPageFlip,
        builder: (context) => const EditorPageSettingsSection(),
      ),
      SettingsSectionEntry(
        id: 'library.newNote',
        group: AppStrings.groupGeneral,
        title: AppStrings.sectionNewNote,
        builder: (context) => const LibrarySettingsSection(),
      ),
      ...contributed,
      SettingsSectionEntry(
        id: 'editor.developer',
        title: AppStrings.sectionDeveloper,
        builder: (context) => const EditorDeveloperSettingsSection(),
      ),
      SettingsSectionEntry(
        id: 'app.features',
        title: AppStrings.sectionFeatures,
        builder: (context) => const FeatureSwitchSection(),
      ),
      SettingsSectionEntry(
        id: 'app.v1Copy',
        title: AppStrings.sectionV1Copy,
        builder: (context) => const V1CopySection(),
      ),
      SettingsSectionEntry(
        id: 'app.about',
        title: AppStrings.sectionAbout,
        builder: (context) => const AboutSection(),
      ),
    ];

final settingsSectionsProvider = Provider<List<SettingsSectionEntry>>(
  (ref) => defaultSettingsSections(
    contributed: [
      for (final contribution in ref.watch(shellContributionsProvider))
        ...contribution.settingsSections,
    ],
  ),
  name: 'settingsSectionsProvider',
);
