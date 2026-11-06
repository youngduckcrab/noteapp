// lib/src/ui/recognition_sheets.dart — (internal) m5-7/05-library 6.13–6.16.
//
// The sheets an action opens, behind one seam so unit/recognition_actions_test
// can check the dispatch and the run rules (6.3, 6.16) without the sheets.
// recognitionSelectionActions() / recognitionInsertActions() always use
// DefaultRecognitionSheets; the tests build the lists with a recording fake
// (buildSelectionActions(sheets:) — internal).
//
// Each method is called SYNCHRONOUSLY from the run, right after the run
// captured its scope (ActionRun), and opens its sheet before its first await
// (the sheet shows '인식 중…' while it works — 6.13.1).
//
// The sheets landed with their tasks — the LaTeX editor (recog.editMath)
// L2-13, the math pad (direct input L2-14, handwriting L2-17a), recog.toMath
// L2-17b and the conversion sheet (recog.toText / recog.copyText with
// strokes) L2-15. A sheet that throws is reported once by the run's guard and
// shown as '실행하지 못했어요' (6.16, 6.22).
import 'package:note_core/note_core.dart' as core;

import '../actions/action_scope.dart';
import 'conversion_sheet.dart';
import 'latex_editor_sheet.dart';
import 'math_pad_sheet.dart';

abstract interface class RecognitionSheets {
  /// recog.toText ([copy] false — primary '텍스트 상자로') / recog.copyText
  /// with strokes ([copy] true — primary '복사'); [inputs] = the recognition
  /// input strokes of the selection, z order (6.13).
  Future<void> conversion(
    ActionRun run, {
    required List<core.Stroke> inputs,
    required bool copy,
  });

  /// recog.toMath — strokes → formula → LaTeX editor ('수식으로 바꾸기', 6.15.3).
  Future<void> toMath(ActionRun run, {required List<core.Stroke> inputs});

  /// recog.editMath — the LaTeX editor on [math] (6.15.1).
  Future<void> latexEditor(ActionRun run, core.MathObject math);

  /// recog.mathPad — the math input pad (6.14).
  Future<void> mathPad(ActionRun run);
}

final class DefaultRecognitionSheets implements RecognitionSheets {
  const DefaultRecognitionSheets();

  @override
  Future<void> conversion(
    ActionRun run, {
    required List<core.Stroke> inputs,
    required bool copy,
  }) => openConversion(run, inputs: inputs, copy: copy);

  @override
  Future<void> toMath(ActionRun run, {required List<core.Stroke> inputs}) =>
      openToMath(run, inputs: inputs);

  @override
  Future<void> latexEditor(ActionRun run, core.MathObject math) =>
      openLatexEditor(run, math);

  @override
  Future<void> mathPad(ActionRun run) => openMathPad(run);
}
