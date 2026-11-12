// lib/src/ondevice/mfr_runtime.dart — (internal) the on-device math
// engine's model port and its greedy decoder (pure Dart).
//
// The model (TrOCR-style VisionEncoderDecoder, ONNX, no KV cache):
// - encoder: pixel_values float32 [1, 3, 384, 384] → last_hidden_state
//   float32 [1, 578, 384], run once per formula;
// - decoder: input_ids int64 [1, t] + encoder_hidden_states → logits
//   float32 [1, t, 1868], fed the WHOLE sequence each step; the next id is
//   the argmax of the last position. Start <s> = 1, stop at </s> = 2, at
//   most [kMfrMaxNewTokens] new ids.
// [MfrRuntime] is what ort_mfr_runtime_native.dart implements over
// flutter_onnxruntime (sessions and tensors stay native; the encoder output
// is passed back by handle); tests use a fake.
import 'dart:math' as math;
import 'dart:typed_data';

import 'mfr_raster.dart' show kMfrImageSize;

const int kMfrStartId = 1;
const int kMfrEndId = 2;
const int kMfrVocabSize = 1868;
const int kMfrMaxNewTokens = 200;

/// The encoder's output shape.
const List<int> kMfrHiddenShape = [1, 578, 384];

/// The encoder's input shape.
const List<int> kMfrPixelShape = [1, 3, kMfrImageSize, kMfrImageSize];

/// The encoder's output, kept by the runtime (a native tensor in the app).
abstract interface class MfrHidden {
  List<int> get shape;
}

abstract interface class MfrRuntime {
  /// pixel_values ([kMfrPixelShape], NCHW) → last_hidden_state.
  Future<MfrHidden> encode(Float32List pixelValues);

  /// The logits [1, ids.length, vocab] of input_ids [1, ids.length].
  Future<({Float32List logits, List<int> shape})> decode(
    Int64List ids,
    MfrHidden hidden,
  );

  /// Frees [hidden] (idempotent).
  Future<void> release(MfrHidden hidden);

  /// Closes the sessions; later calls fail.
  Future<void> close();
}

/// The model answered with an unexpected tensor (a wrong or damaged model
/// file).
final class MfrShapeError implements Exception {
  MfrShapeError(this.message);
  final String message;

  @override
  String toString() => 'MfrShapeError($message)';
}

/// The decoder stopped because the caller cancelled.
final class MfrCancelled implements Exception {
  const MfrCancelled();

  @override
  String toString() => 'MfrCancelled';
}

/// The ids (with the start id, and the end id when the model gave it) and
/// the geometric mean of the chosen tokens' softmax probabilities.
typedef MfrDecoded = ({List<int> ids, double confidence, bool ended});

/// Encoder once + greedy decoder loop. [cancelled] is asked before every
/// model call (→ [MfrCancelled]); the encoder output is always released.
Future<MfrDecoded> runMfrGreedy(
  MfrRuntime runtime,
  Float32List pixelValues, {
  bool Function()? cancelled,
  int maxNewTokens = kMfrMaxNewTokens,
}) async {
  bool stop() => cancelled?.call() ?? false;
  if (pixelValues.length != kMfrPixelShape.reduce((a, b) => a * b)) {
    throw ArgumentError.value(
      pixelValues.length,
      'pixelValues',
      'expected ${kMfrPixelShape.join('×')} values',
    );
  }
  if (stop()) throw const MfrCancelled();
  final hidden = await runtime.encode(pixelValues);
  try {
    if (hidden.shape.length != 3 ||
        hidden.shape[0] != 1 ||
        hidden.shape[2] != kMfrHiddenShape[2]) {
      throw MfrShapeError('encoder output ${hidden.shape}');
    }
    final ids = <int>[kMfrStartId];
    var logProb = 0.0;
    var ended = false;
    for (var step = 0; step < maxNewTokens; step++) {
      if (stop()) throw const MfrCancelled();
      final (:logits, :shape) = await runtime.decode(
        Int64List.fromList(ids),
        hidden,
      );
      if (shape.length != 3 ||
          shape[0] != 1 ||
          shape[1] != ids.length ||
          shape[2] != kMfrVocabSize ||
          logits.length != shape[1] * shape[2]) {
        throw MfrShapeError('decoder logits $shape for ${ids.length} ids');
      }
      final vocab = shape[2];
      final offset = (shape[1] - 1) * vocab;
      var best = 0;
      var bestValue = -double.infinity;
      for (var v = 0; v < vocab; v++) {
        final x = logits[offset + v];
        if (x > bestValue) {
          bestValue = x;
          best = v;
        }
      }
      var sum = 0.0;
      for (var v = 0; v < vocab; v++) {
        sum += math.exp(logits[offset + v] - bestValue);
      }
      logProb += -math.log(sum); // log softmax of the argmax
      ids.add(best);
      if (best == kMfrEndId) {
        ended = true;
        break;
      }
    }
    final steps = ids.length - 1;
    return (
      ids: List<int>.unmodifiable(ids),
      confidence: steps == 0 ? 0.0 : math.exp(logProb / steps),
      ended: ended,
    );
  } finally {
    await runtime.release(hidden);
  }
}
