// lib/src/ondevice/on_device_platform.dart — (internal) the on-device math
// engine's platform side, chosen at compile time like the handwriting
// engine (platform_recognizer.dart — contract 7.4.1, a conditional import
// with a stub): the web build never contains ONNX Runtime or dart:io code
// (the web keeps typing LaTeX — ManualOnlyMathRecognizer).
export 'on_device_platform_stub.dart'
    if (dart.library.io) 'on_device_platform_native.dart';
