// appFeatureStatesOf / appFeatureStatusLine (docs/plans/m5-7/01-infra.md
// 6.18, 11 risk 9): why each feature is on or off at this start — build,
// developer menu, failed start; the math engine also follows recognition.
import 'package:flutter_test/flutter_test.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/features/app_features.dart';
import 'package:noteapp/src/features/feature_status.dart';
import 'package:noteapp/src/modules/media_module.dart';
import 'package:noteapp/src/modules/recognition_module.dart';

StartupStep _step(String id, StartupStepOutcome outcome) =>
    StartupStep(id: id, elapsed: Duration.zero, outcome: outcome);

void main() {
  test('step ids are the module ids', () {
    expect(mediaStepId, MediaModule.moduleId);
    expect(recognitionStepId, RecognitionModule.moduleId);
  });

  test('all on (steps ok, or no step at all)', () {
    for (final steps in [
      [
        _step('media', StartupStepOutcome.ok),
        _step('recognition', StartupStepOutcome.ok),
      ],
      const <StartupStep>[],
    ]) {
      final states = appFeatureStatesOf(
        compileTime: AppFeatures.all,
        started: AppFeatures.all,
        steps: steps,
      );
      expect(states.values.toSet(), {AppFeatureState.on});
      expect(appFeatureStatusLine(states), '녹음 켬 · 인식 켬 · 수식 엔진 켬');
    }
  });

  test('build off wins over the menu', () {
    const build = AppFeatures(media: false, mathEngine: false);
    final states = appFeatureStatesOf(
      compileTime: build,
      started: build.and(const AppFeatures(media: false, mathEngine: false)),
      steps: [
        _step('media', StartupStepOutcome.skipped),
        _step('recognition', StartupStepOutcome.ok),
      ],
    );
    expect(states, {
      AppFeature.media: AppFeatureState.offInBuild,
      AppFeature.recognition: AppFeatureState.on,
      AppFeature.mathEngine: AppFeatureState.offInBuild,
    });
    expect(appFeatureStatusLine(states), '녹음 꺼짐(빌드) · 인식 켬 · 수식 엔진 꺼짐(빌드)');
  });

  test('menu off → 꺼짐(개발자 메뉴); the math engine follows recognition', () {
    final states = appFeatureStatesOf(
      compileTime: AppFeatures.all,
      started: const AppFeatures(recognition: false),
      steps: [
        _step('media', StartupStepOutcome.ok),
        _step('recognition', StartupStepOutcome.skipped),
      ],
    );
    expect(states, {
      AppFeature.media: AppFeatureState.on,
      AppFeature.recognition: AppFeatureState.offInMenu,
      AppFeature.mathEngine: AppFeatureState.offWithRecognition,
    });
    expect(
      appFeatureStatusLine(states),
      '녹음 켬 · 인식 꺼짐(개발자 메뉴) · 수식 엔진 꺼짐(인식 꺼짐)',
    );
  });

  test('the plan example: media on, recognition menu, math engine build', () {
    const build = AppFeatures(mathEngine: false);
    final states = appFeatureStatesOf(
      compileTime: build,
      started: build.and(const AppFeatures(recognition: false)),
      steps: [_step('recognition', StartupStepOutcome.skipped)],
    );
    expect(appFeatureStatusLine(states), '녹음 켬 · 인식 꺼짐(개발자 메뉴) · 수식 엔진 꺼짐(빌드)');
  });

  test('failed or timed-out start → 시작 실패', () {
    for (final outcome in [
      StartupStepOutcome.failedNonCritical,
      StartupStepOutcome.timedOut,
      StartupStepOutcome.failedCritical,
    ]) {
      final states = appFeatureStatesOf(
        compileTime: AppFeatures.all,
        started: AppFeatures.all,
        steps: [_step('media', outcome), _step('recognition', outcome)],
      );
      expect(states, {
        AppFeature.media: AppFeatureState.startFailed,
        AppFeature.recognition: AppFeatureState.startFailed,
        AppFeature.mathEngine: AppFeatureState.offWithRecognition,
      }, reason: outcome.name);
      expect(
        appFeatureStatusLine(states),
        '녹음 시작 실패 · 인식 시작 실패 · 수식 엔진 꺼짐(인식 꺼짐)',
      );
    }
  });

  test('only the math engine off in the menu', () {
    final states = appFeatureStatesOf(
      compileTime: AppFeatures.all,
      started: const AppFeatures(mathEngine: false),
      steps: [_step('recognition', StartupStepOutcome.ok)],
    );
    expect(states[AppFeature.mathEngine], AppFeatureState.offInMenu);
    expect(states[AppFeature.recognition], AppFeatureState.on);
  });

  test('other steps (core, pdf) do not count', () {
    final states = appFeatureStatesOf(
      compileTime: AppFeatures.all,
      started: AppFeatures.all,
      steps: [
        _step('core', StartupStepOutcome.failedCritical),
        _step('pdf', StartupStepOutcome.timedOut),
      ],
    );
    expect(states.values.toSet(), {AppFeatureState.on});
  });
}
