// lib/src/ondevice/on_device_platform_native.dart — (internal) the native
// side of on_device_platform.dart: the model manager (app support
// directory, package:http) and the recognizer over ONNX Runtime on Android
// and iOS; the desktops (development only) have no engine (null), like the
// handwriting engine (6.7.1 — defaultTargetPlatform, never dart:io
// Platform).
import 'dart:io' show File;
import 'dart:isolate';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:http/http.dart' as http;

import '../ports/math_recognizer.dart';
import 'math_model_manager.dart';
import 'math_model_manifest.dart';
import 'math_model_storage_native.dart';
import 'mfr_raster.dart';
import 'mfr_tokenizer.dart';
import 'on_device_math_recognizer.dart';
import 'ort_mfr_runtime_native.dart';

/// Android / iOS: a manager over `<app support>/models`; else null.
MathModelManager? createPlatformMathModelManager() {
  final platform = defaultTargetPlatform;
  if (platform != TargetPlatform.android && platform != TargetPlatform.iOS) {
    return null;
  }
  return MathModelManager(
    storage: FileMathModelStorage(),
    createClient: http.Client.new,
  );
}

/// The engine over an installed model: ONNX Runtime sessions (opened on the
/// first call), the tokenizer file, preprocessing in a background isolate.
MathRecognizer createOnDeviceMathRecognizer(MathModelInstall install) =>
    OnDeviceMathRecognizer(
      openRuntime: () => OrtMfrRuntime.open(
        encoderPath: install.path(kMathModelEncoderFile),
        decoderPath: install.path(kMathModelDecoderFile),
      ),
      loadTokenizer: () async => MfrTokenizer.fromJson(
        await File(install.path(kMathModelTokenizerFile)).readAsString(),
      ),
      preprocess: (traces) => Isolate.run(() => mfrPixelValues(traces)),
    );
