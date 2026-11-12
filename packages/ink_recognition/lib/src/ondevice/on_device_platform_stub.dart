// lib/src/ondevice/on_device_platform_stub.dart — (internal) the web side of
// on_device_platform.dart: no on-device math engine.
import '../ports/math_recognizer.dart';
import 'math_model_manager.dart';

/// The web: null (no model manager, no settings row).
MathModelManager? createPlatformMathModelManager() => null;

/// Never called on the web (no manager → never ready).
MathRecognizer createOnDeviceMathRecognizer(MathModelInstall install) =>
    const ManualOnlyMathRecognizer();
