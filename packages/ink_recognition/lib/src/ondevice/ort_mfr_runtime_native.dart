// lib/src/ondevice/ort_mfr_runtime_native.dart — (internal) MfrRuntime over
// ONNX Runtime (flutter_onnxruntime — native_only_imports, `as ort`).
//
// The plugin runs every call on its own background queue (Android: a
// background task queue of the method channel; iOS: a serial queue), so
// the model never blocks the UI thread; tensors stay native and are passed
// by handle — the encoder output goes back into every decoder step without
// a copy. Android ships the full ONNX Runtime (onnxruntime-android, with
// the int8 operators DynamicQuantizeLinear / MatMulInteger the quantized
// model needs); R8 keeps ai.onnxruntime.** (app/android/app/proguard-rules.pro).
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart' as ort;

import 'mfr_runtime.dart';

final class _OrtHidden implements MfrHidden {
  _OrtHidden(this.value);
  final ort.OrtValue value;
  bool released = false;

  @override
  List<int> get shape => value.shape;
}

final class OrtMfrRuntime implements MfrRuntime {
  OrtMfrRuntime._(this._encoder, this._decoder);

  /// Opens both sessions (CPU, 4 intra-op threads like the reference).
  static Future<OrtMfrRuntime> open({
    required String encoderPath,
    required String decoderPath,
  }) async {
    final runtime = ort.OnnxRuntime();
    final options = ort.OrtSessionOptions(
      intraOpNumThreads: 4,
      interOpNumThreads: 1,
    );
    final encoder = await runtime.createSession(encoderPath, options: options);
    try {
      final decoder = await runtime.createSession(
        decoderPath,
        options: options,
      );
      return OrtMfrRuntime._(encoder, decoder);
    } on Object {
      await encoder.close();
      rethrow;
    }
  }

  final ort.OrtSession _encoder, _decoder;
  bool _closed = false;

  String _input(ort.OrtSession s, String name, int index) =>
      s.inputNames.contains(name) ? name : s.inputNames[index];

  ort.OrtValue _output(Map<String, ort.OrtValue> outputs, String name) =>
      outputs[name] ?? outputs.values.first;

  @override
  Future<MfrHidden> encode(Float32List pixelValues) async {
    _check();
    final input = await ort.OrtValue.fromList(pixelValues, kMfrPixelShape);
    try {
      final outputs = await _encoder.run({
        _input(_encoder, 'pixel_values', 0): input,
      });
      final hidden = _output(outputs, 'last_hidden_state');
      for (final other in outputs.values) {
        if (!identical(other, hidden)) await other.dispose();
      }
      return _OrtHidden(hidden);
    } finally {
      await input.dispose();
    }
  }

  @override
  Future<({Float32List logits, List<int> shape})> decode(
    Int64List ids,
    MfrHidden hidden,
  ) async {
    _check();
    final h = hidden as _OrtHidden;
    final input = await ort.OrtValue.fromList(ids, [1, ids.length]);
    try {
      final outputs = await _decoder.run({
        _input(_decoder, 'input_ids', 0): input,
        _input(_decoder, 'encoder_hidden_states', 1): h.value,
      });
      final logits = _output(outputs, 'logits');
      try {
        final data = await logits.asFlattenedList();
        final values = data is Float32List
            ? data
            : Float32List.fromList([
                for (final v in data) (v as num).toDouble(),
              ]);
        return (logits: values, shape: List<int>.of(logits.shape));
      } finally {
        for (final v in outputs.values) {
          await v.dispose();
        }
      }
    } finally {
      await input.dispose();
    }
  }

  @override
  Future<void> release(MfrHidden hidden) async {
    final h = hidden as _OrtHidden;
    if (h.released) return;
    h.released = true;
    await h.value.dispose();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _encoder.close();
    await _decoder.close();
  }

  void _check() {
    if (_closed) throw StateError('OrtMfrRuntime closed');
  }
}
