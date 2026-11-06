// lib/src/engines/platform_recognizer_stub.dart — (internal) the web side of
// platform_recognizer.dart (dart2js / dart2wasm, no dart:io): handwriting
// recognition is not available (G-1, 6.7.1).
import '../ports/handwriting_recognizer.dart';

/// The web: always [UnsupportedHandwritingRecognizer].
HandwritingRecognizer createPlatformHandwritingRecognizer() =>
    const UnsupportedHandwritingRecognizer();
