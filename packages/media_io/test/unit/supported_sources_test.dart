// supportedImageSources() per platform (m5-7/06-pdf 4.2.4 — 8.2 T35b): android / iOS →
// photos + camera, other native platforms (desktop Flutter) → none; it looks at the platform
// only, so it works before initializeMediaIo (and FEATURE_MEDIA does not change it — D17).
// The web set (+ clipboard) is web/image_codec_browser_test.dart.
@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/media_io.dart';
import 'package:media_io/src/init.dart';
import 'package:note_core/note_core.dart' as core;

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('without initializeMediaIo', () {
    MediaIoRuntime.debugReset();
    expect(MediaIoRuntime.isInitialized, isFalse);
    expect(supportedImageSources(), isNotNull);
    expect(MediaIoRuntime.isInitialized, isFalse);
  });

  const mobile = {core.ImageImportSource.photos, core.ImageImportSource.camera};
  final expected = <TargetPlatform, Set<core.ImageImportSource>>{
    TargetPlatform.android: mobile,
    TargetPlatform.iOS: mobile,
    TargetPlatform.macOS: const {},
    TargetPlatform.windows: const {},
    TargetPlatform.linux: const {},
    TargetPlatform.fuchsia: const {},
  };
  for (final platform in TargetPlatform.values) {
    test('${platform.name} → ${expected[platform]!.map((s) => s.name)}', () {
      debugDefaultTargetPlatformOverride = platform;
      expect(supportedImageSources(), expected[platform]);
      // no files source on iOS (document picker later — 1.3), never the clipboard off the web
      expect(
        supportedImageSources(),
        isNot(contains(core.ImageImportSource.clipboard)),
      );
    });
  }
}
