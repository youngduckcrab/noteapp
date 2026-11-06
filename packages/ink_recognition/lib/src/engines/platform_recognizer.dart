// lib/src/engines/platform_recognizer.dart — (internal) the platform
// handwriting engine, chosen at compile time (m5-7/05-library 3.4, 6.7.1;
// contract 7.4.1 — conditional import with a stub): the web build never
// contains ML Kit code. createPlatformHandwritingRecognizer() is read only by
// recognitionOverrides() (4.4.8).
export 'platform_recognizer_stub.dart'
    if (dart.library.io) 'mlkit_recognizer_native.dart';
