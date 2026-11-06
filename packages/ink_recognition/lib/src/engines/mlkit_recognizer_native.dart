// lib/src/engines/mlkit_recognizer_native.dart — (internal) the native side
// of platform_recognizer.dart (m5-7/05-library 6.7.1, 6.7.2). The ONLY file
// that may import ML Kit (native_only_imports, `as mlkit` — R4).
//
// L2-07: the choice by platform (defaultTargetPlatform, never dart:io
// Platform — 7.4.1). L2-08 adds MlKitHandwritingRecognizer here and returns
// it on Android / iOS; until then those platforms get the unsupported engine
// too (the conversion sheet shows the 'unsupported' sentence, no indexer).
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

import '../ports/handwriting_recognizer.dart';

/// Whether [platform] has an ML Kit handwriting engine (Android, iOS); the
/// desktops (development only) do not (6.7.1).
bool platformHasMlKit(TargetPlatform platform) =>
    platform == TargetPlatform.android || platform == TargetPlatform.iOS;

/// Native: ML Kit on Android / iOS (from L2-08), the unsupported engine on
/// the desktops.
HandwritingRecognizer createPlatformHandwritingRecognizer() {
  if (platformHasMlKit(defaultTargetPlatform)) {
    // The ML Kit adapter arrives with L2-08; until then no engine here either.
    return const UnsupportedHandwritingRecognizer();
  }
  return const UnsupportedHandwritingRecognizer();
}
