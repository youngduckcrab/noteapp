// lib/src/ports/math_recognizer.dart — contract m5-7/00-overview 7.2.11
// (m5-7/05-library 4.2, 4.4.2, 6.11.1). Final since the 2차 foundation step
// R2-B6.
//
// The math engine port and its default: ManualOnlyMathRecognizer is
// mathRecognizerProvider's value without an engine endpoint — the math pad
// then shows LaTeX typing + preview only.
import '../model/failures.dart';
import '../model/math_types.dart';

abstract interface class MathRecognizer {
  String get engineId;

  /// ManualOnlyMathRecognizer: false (LaTeX typing only)
  bool get isAvailable;
  Future<MathResult> recognize(MathInput input, {Future<void>? cancel});
}

/// No math engine: recognize throws [RecognizerUnsupported] (05-library
/// 4.4.2).
final class ManualOnlyMathRecognizer implements MathRecognizer {
  const ManualOnlyMathRecognizer();

  @override
  String get engineId => 'manual';

  @override
  bool get isAvailable => false;

  @override
  Future<MathResult> recognize(MathInput input, {Future<void>? cancel}) async =>
      throw RecognizerUnsupported();
}
