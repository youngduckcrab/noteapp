/// Section list of the settings screen (docs/plans/01-infra.md 4.5.8,
/// 계약 7.4.11).
library;

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show developerModeProvider;

import '../app/strings.dart';
import '../bootstrap/app_module.dart' show ShellContribution;
import '../features/feature_switch_section.dart';
import 'about_section.dart';
import 'appearance_section.dart';
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
/// | app.homeStyle | 화면 | 홈 화면 스타일 |
/// | app.editorStyle | 화면 | 필기 화면 스타일 |
/// | app.brightness | 화면 | 밝기 |
/// | app.hoverNames | 화면 | 도구 이름 (UI stage 2) |
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
///
/// (v2.14-ui, UI stage 1) 'editor.developer', 'app.features' and 'app.v1Copy'
/// are developer-only: left out unless [developerMode] (settings › 정보 ›
/// the 빌드 row 7 times, the developer overlay, `?dev=1` — developer_mode.dart).
List<SettingsSectionEntry> defaultSettingsSections({
  List<SettingsSectionEntry> contributed = const [],
  bool developerMode = false,
}) {
  final sections = _sections(contributed, developerMode: developerMode);
  assert(
    sections.map((s) => s.id).toSet().length == sections.length,
    'settings section ids are not unique: ${sections.map((s) => s.id)}',
  );
  return sections;
}

List<SettingsSectionEntry> _sections(
  List<SettingsSectionEntry> contributed, {
  required bool developerMode,
}) => [
  // v2.14-ui (01-infra 14.3): the '화면' group comes first.
  SettingsSectionEntry(
    id: 'app.homeStyle',
    group: AppStrings.groupScreen,
    title: AppStrings.sectionHomeStyle,
    builder: (context) => const AppStyleSection(target: StyleTarget.home),
  ),
  SettingsSectionEntry(
    id: 'app.editorStyle',
    group: AppStrings.groupScreen,
    title: AppStrings.sectionEditorStyle,
    builder: (context) => const AppStyleSection(target: StyleTarget.editor),
  ),
  SettingsSectionEntry(
    id: 'app.brightness',
    group: AppStrings.groupScreen,
    title: AppStrings.sectionBrightness,
    builder: (context) => const AppBrightnessSection(),
  ),
  SettingsSectionEntry(
    id: 'app.hoverNames',
    group: AppStrings.groupScreen,
    title: AppStrings.sectionHoverNames,
    builder: (context) => const AppHoverNamesSection(),
  ),
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
  if (developerMode) ...[
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
  ],
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
    developerMode: ref.watch(developerModeProvider),
  ),
  name: 'settingsSectionsProvider',
);
