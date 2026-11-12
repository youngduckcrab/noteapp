@Tags(['integration'])
library;

// Contract V15 (docs/plans/m5-7/01-infra.md 6.6, 8.2 J19, 9.1
// feature_switch_test; contract V15 v2.1, 7.3.3 '기능 스위치'): FEATURE_MEDIA
// =false turns off recording only, FEATURE_RECOGNITION=false the
// recognition menus, settings and indexer together with automatic shape
// correction, FEATURE_MATH_ENGINE=false the math engine only; image insert
// and image page stay in every combination.
//
// The switches go in the two ways a build gets them:
// - injected: the eight combinations as AppBootstrapper.features plus
//   modulesFor(features:) — what productionModules() does with the
//   --dart-define constants (a switched-off module is not even made);
// - --dart-define: AppFeatures.compileTime — all on in a plain test run; H5
//   runs this file with `--dart-define FEATURE_MEDIA=false --dart-define
//   FEATURE_RECOGNITION=false --dart-define FEATURE_MATH_ENGINE=false`.
// Each start is compared row by row (test/support/smoke_v2_fakes.dart
// featureRows — provider values; the screens follow them, H5 compares the
// widgets), and the start with everything off passes the 1st round V5 flow.
// Skipped by default (app/dart_test.yaml); run with
// `ws test --run-skipped -t integration --package noteapp`.

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/features/app_features.dart';
import 'package:noteapp/src/modules/core_module.dart';

import '../fakes/fake_native_paths.dart';
import '../support/smoke_scenario.dart';
import '../support/smoke_v2_fakes.dart';
import '../support/smoke_v2_scenario.dart';

CoreModule _memoryCore() => CoreModule(
  nativePaths: noNativePaths,
  configFor: (_) => const NoteStoreConfig(inMemory: true),
);

/// The eight combinations, all on first.
final List<AppFeatures> _combinations = [
  for (final media in [true, false])
    for (final recognition in [true, false])
      for (final mathEngine in [true, false])
        AppFeatures(
          media: media,
          recognition: recognition,
          mathEngine: mathEngine,
        ),
];

/// The three fields as given (AppFeatures.toString folds mathEngine into
/// recognition, so two combinations print alike).
String _label(AppFeatures f) =>
    'media ${f.media} · recognition ${f.recognition} · '
    'mathEngine ${f.mathEngine}';

/// The rows a combination may change (the V15 sentence).
Set<String> _rowsOff(AppFeatures f) => {
  if (!f.media) '녹음',
  if (!f.recognition) ...{'인식 메뉴', '수식 엔진', '자동 도형 보정'},
  if (f.recognition && !f.mathEngine) '수식 엔진',
};

void main() {
  test('the expected rows differ from all-on exactly by the V15 sentence; '
      'the image rows never differ', () {
    final allOn = expectedFeatureRows(AppFeatures.all);
    expect(allOn.keys, [
      '녹음',
      '인식 메뉴',
      '수식 엔진',
      '자동 도형 보정',
      '이미지 삽입',
      '이미지 페이지',
    ]);
    expect(_combinations, hasLength(8));
    expect(_combinations.toSet(), hasLength(8));
    for (final f in _combinations) {
      final rows = expectedFeatureRows(f);
      expect(differingRows(rows, allOn), _rowsOff(f), reason: _label(f));
      expect(rows['이미지 삽입'], allOn['이미지 삽입'], reason: _label(f));
      expect(rows['이미지 페이지'], allOn['이미지 페이지'], reason: _label(f));
    }
  });

  group('injected switches', () {
    for (final features in _combinations) {
      testWidgets('${_label(features)}: the modules of the switches only, '
          'the rows of the V15 sentence', (tester) async {
        final fakes = SmokeV2Fakes();
        final app = await bootSmokeV2App(
          tester,
          fakes,
          _memoryCore(),
          features: features,
        );
        expectContractOverridesV2(app, fakes, features: features);
        expect(featureRows(app, fakes), expectedFeatureRows(features));
        expect(app.errorLog.totalCount, 0, reason: '${app.errorLog}');
        await app.shutdown(tester);
      });
    }
  });

  testWidgets('everything off: the 1st round V5 flow still passes', (
    tester,
  ) async {
    const off = AppFeatures(
      media: false,
      recognition: false,
      mathEngine: false,
    );
    final fakes = SmokeV2Fakes();
    final app = await bootSmokeV2App(
      tester,
      fakes,
      _memoryCore(),
      features: off,
    );
    expectContractOverridesV2(app, fakes, features: off);
    expect(featureRows(app, fakes), expectedFeatureRows(off));
    await runSmokeScenario(tester, app, banner: findsOneWidget);
    // H5: the same difference on the editor screen — the mic button, the
    // recognition menu item and the auto shape toggle go; image insert stays
    // (V5b checks the all-on screen).
    await createNote(tester, app.store);
    expect(await editorSwitchRows(tester), {
      '녹음 버튼': false,
      '이미지 삽입': true,
      '인식 메뉴': false,
      '자동 도형 보정': false,
    });
    await leaveEditor(tester, 'the switch rows');
    expect(app.errorLog.totalCount, 0, reason: '${app.errorLog}');
    await app.shutdown(tester);
  });

  testWidgets('--dart-define: AppFeatures.compileTime '
      '(${_label(AppFeatures.compileTime)}) — its rows, and the 1st round V5 '
      'flow', (tester) async {
    const features = AppFeatures.compileTime;
    final fakes = SmokeV2Fakes();
    final app = await bootSmokeV2App(
      tester,
      fakes,
      _memoryCore(),
      features: features,
    );
    expectContractOverridesV2(app, fakes, features: features);
    expect(featureRows(app, fakes), expectedFeatureRows(features));
    await runSmokeScenario(tester, app, banner: findsOneWidget);
    expect(app.errorLog.totalCount, 0, reason: '${app.errorLog}');
    await app.shutdown(tester);
  });
}
