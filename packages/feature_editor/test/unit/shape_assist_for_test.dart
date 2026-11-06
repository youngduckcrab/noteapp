// m5-7/04-editor 8.2 E2-15, 6.10: the pen-down decision of the auto shape
// assist — the whole table: 10 pen types × the setting (on / off) × the
// fitter (INK's NoShapeFitter / FakeInkShapeFitter) → holdToSnap / off.
import 'package:feature_editor/src/state/settings/editor_settings.dart';
import 'package:feature_editor/src/tools/shape_assist_for.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:note_core/note_core.dart' as core;

/// The pens that get the assist (12.2 Q4 — not the highlighter, the laser,
/// the tape).
const _assist = {
  core.PenTool.ballpoint,
  core.PenTool.fountain,
  core.PenTool.pencil,
  core.PenTool.marker,
  core.PenTool.brush,
  core.PenTool.calligraphy,
  core.PenTool.dashed,
};

void main() {
  final fitters = <String, ink.InkShapeFitter>{
    'NoShapeFitter': const ink.NoShapeFitter(),
    'FakeInkShapeFitter': ink_testing.FakeInkShapeFitter(),
  };

  test('10 pens × setting × fitter: holdToSnap only with the setting on, a '
      'fitter wired and an assist pen', () {
    expect(core.PenTool.values, hasLength(10));
    var rows = 0;
    var snapping = 0;
    for (final pen in core.PenTool.values) {
      for (final on in [true, false]) {
        for (final MapEntry(key: name, value: fitter) in fitters.entries) {
          final expected =
              on && name == 'FakeInkShapeFitter' && _assist.contains(pen)
              ? ink.ShapeAssist.holdToSnap
              : ink.ShapeAssist.off;
          expect(
            shapeAssistFor(EditorSettings(shapeAssist: on), pen, fitter),
            expected,
            reason: '$pen, setting $on, $name',
          );
          rows++;
          if (expected == ink.ShapeAssist.holdToSnap) snapping++;
        }
      }
    }
    expect(rows, 40);
    expect(snapping, 7); // the 7 assist pens, setting on, a fitter
  });

  test(
    'the default setting is on (U14): an assist pen snaps with a fitter',
    () {
      expect(const EditorSettings().shapeAssist, isTrue);
      expect(
        shapeAssistFor(
          const EditorSettings(),
          core.PenTool.ballpoint,
          ink_testing.FakeInkShapeFitter(),
        ),
        ink.ShapeAssist.holdToSnap,
      );
    },
  );

  test('shapeAssistPen = the 7 pens; shapeFitterAvailable = not '
      'NoShapeFitter', () {
    expect({
      for (final p in core.PenTool.values)
        if (shapeAssistPen(p)) p,
    }, _assist);
    expect(shapeFitterAvailable(const ink.NoShapeFitter()), isFalse);
    expect(shapeFitterAvailable(ink_testing.FakeInkShapeFitter()), isTrue);
  });
}
