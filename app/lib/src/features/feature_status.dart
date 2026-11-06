/// Why each feature is on or off at this start — the '기능' line of the about
/// section and the diagnostics copy (docs/plans/m5-7/01-infra.md 6.18, 11 risk
/// 9: a switch left off in the developer menu must be visible).
library;

import '../bootstrap/startup_report.dart';
import 'app_features.dart';

enum AppFeatureState {
  on,

  /// The FEATURE_* compile-time constant is false.
  offInBuild,

  /// The developer menu (AppFeatureKeys) switched it off for this start.
  offInMenu,

  /// The module was enabled but its start failed or timed out.
  startFailed,

  /// mathEngine only: recognition is not running (off or failed).
  offWithRecognition,
}

/// The startup step ids of the feature modules (MediaModule.moduleId,
/// RecognitionModule.moduleId — feature_status_test compares them).
const String mediaStepId = 'media';
const String recognitionStepId = 'recognition';

/// [started] = BootstrapSuccess.features (build ∧ developer menu at this
/// start, appFeaturesProvider); [steps] = StartupReport.steps.
Map<AppFeature, AppFeatureState> appFeatureStatesOf({
  required AppFeatures compileTime,
  required AppFeatures started,
  required List<StartupStep> steps,
}) {
  AppFeatureState module(bool built, bool on, String stepId) {
    if (!built) return AppFeatureState.offInBuild;
    if (!on) return AppFeatureState.offInMenu;
    for (final step in steps) {
      if (step.id != stepId) continue;
      return switch (step.outcome) {
        StartupStepOutcome.ok => AppFeatureState.on,
        // isEnabled false — the only reason a feature module is skipped.
        StartupStepOutcome.skipped => AppFeatureState.offInMenu,
        StartupStepOutcome.failedNonCritical ||
        StartupStepOutcome.timedOut ||
        StartupStepOutcome.failedCritical => AppFeatureState.startFailed,
      };
    }
    return AppFeatureState.on;
  }

  final media = module(compileTime.media, started.media, mediaStepId);
  final recognition = module(
    compileTime.recognition,
    started.recognition,
    recognitionStepId,
  );
  final mathEngine = !compileTime.mathEngine
      ? AppFeatureState.offInBuild
      : !started.mathEngine
      ? AppFeatureState.offInMenu
      : recognition != AppFeatureState.on
      ? AppFeatureState.offWithRecognition
      : AppFeatureState.on;
  return {
    AppFeature.media: media,
    AppFeature.recognition: recognition,
    AppFeature.mathEngine: mathEngine,
  };
}

/// '녹음 켬 · 인식 꺼짐(개발자 메뉴) · 수식 엔진 꺼짐(빌드)'.
String appFeatureStatusLine(Map<AppFeature, AppFeatureState> states) => [
  for (final feature in AppFeature.values)
    '${_featureName(feature)} ${_stateText(states[feature] ?? AppFeatureState.on)}',
].join(' · ');

String _featureName(AppFeature feature) => switch (feature) {
  AppFeature.media => '녹음',
  AppFeature.recognition => '인식',
  AppFeature.mathEngine => '수식 엔진',
};

String _stateText(AppFeatureState state) => switch (state) {
  AppFeatureState.on => '켬',
  AppFeatureState.offInBuild => '꺼짐(빌드)',
  AppFeatureState.offInMenu => '꺼짐(개발자 메뉴)',
  AppFeatureState.startFailed => '시작 실패',
  AppFeatureState.offWithRecognition => '꺼짐(인식 꺼짐)',
};
