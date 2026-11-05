// lib/src/input/predictor.dart — interface only in this scope (native later, 6.27).
import 'ink_sample.dart';

abstract interface class InkPredictor {
  /// Predicted samples to draw after [history] (never stored). Must be cheap (< 0.1 ms).
  List<InkSample> predict(List<InkSample> history, {required int nowUs});
}

final class NoopPredictor implements InkPredictor {
  const NoopPredictor();

  @override
  List<InkSample> predict(List<InkSample> history, {required int nowUs}) =>
      const [];
}
