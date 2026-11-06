// lib/src/testing/test_hooks.dart — media_io's internal test hooks (m5-7/06-pdf 4.3.2,
// 6.18). installFakeMediaPlatforms (testing.dart, VM only) sets them; the native engine,
// the play cache and the foreground service read them (PDF T31b, T32, P-B) instead of
// path_provider and FlutterForegroundTask. Not exported; never set in the app.
import 'package:flutter/foundation.dart';

abstract final class MediaTestHooks {
  /// A directory that replaces path_provider's support / cache directories (recordings and
  /// the native play cache go under it). null = path_provider.
  static String? directory;

  /// true = the Android foreground service is a no-op (no FlutterForegroundTask calls).
  static bool noForegroundService = false;

  /// Tests only: back to the app values.
  @visibleForTesting
  static void reset() {
    directory = null;
    noForegroundService = false;
  }
}
