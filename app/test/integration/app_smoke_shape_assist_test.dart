@Tags(['integration'])
library;

// V5b auto shape app smoke (docs/plans/m5-7/01-infra.md 9.1 'V5b', 8.3 H3;
// contract v2.2 C22-07 — P-B: INK T39, EDITOR E2-15 and LIBRARY L2-06 are
// all merged, so this counts toward completion). The same injection
// arguments as V5 v2 (test/support/smoke_v2_fakes.dart): RecognitionModule's
// GeometricShapeFitter() is the real judge. The pen follows
// SyntheticShapes.rectanglePath and holds still past InkTuning.shapeHoldMs
// (INK 03-ink 6.18: the timer armed at the anchor fires the hold even with
// still pointer events) → one rectangle ShapeObject, no stroke, one undo
// step → undo → redo → close → reopen keeps it (the reopened session has no
// undo — C15-04). Narrowing tests if it fails: INK hold_detector_test (T39),
// EDITOR shape_assist_smoke_test (E2-21b), LIBRARY shape_assist_flow_test
// (L2-I3). V6 (Chrome) runs the V5 flow only.
//
// Skipped by default (app/dart_test.yaml); run with
// `ws test --run-skipped -t integration --package noteapp`.

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/modules/core_module.dart';

import '../fakes/fake_native_paths.dart';
import '../support/smoke_v2_fakes.dart';
import '../support/smoke_v2_scenario.dart';

void main() {
  testWidgets('V5b: real modules → new note → a rectangle path held still → '
      'one rectangle, no stroke, one undo step → undo → redo → reopen', (
    tester,
  ) async {
    final fakes = SmokeV2Fakes();
    final app = await bootSmokeV2App(
      tester,
      fakes,
      CoreModule(
        nativePaths: noNativePaths,
        configFor: (_) => const NoteStoreConfig(inMemory: true),
      ),
    );
    expectContractOverridesV2(app, fakes);
    expect(
      app.container.read(ink.inkShapeFitterProvider),
      isA<GeometricShapeFitter>(),
    );

    // V15 on the screen, all on (feature_switch_test checks all off).
    await createNote(tester, app.store);
    expect(await editorSwitchRows(tester), {
      '녹음 버튼': true,
      '이미지 삽입': true,
      '인식 메뉴': true,
      '자동 도형 보정': true,
    });
    await leaveEditor(tester, 'the switch rows');

    final steps = <String>[];
    await runShapeAssistScenario(tester, app, trace: steps.add);

    expect(app.errorLog.totalCount, 0, reason: '${app.errorLog} $steps');
    await app.shutdown(tester);
  });
}
