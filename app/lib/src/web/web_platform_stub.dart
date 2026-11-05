/// VM / native [WebPlatform]: every call is a no-op
/// (docs/plans/01-infra.md 4.5.2).
library;

import 'dart:typed_data';

import 'web_platform.dart';

/// Conditional import: web_platform_stub.dart /
/// web_platform_browser.dart (if dart.library.js_interop).
WebPlatform createWebPlatform() => const _StubWebPlatform();

final class _StubWebPlatform implements WebPlatform {
  const _StubWebPlatform();

  @override
  bool get isSupported => false;

  @override
  String? get userAgent => null;

  @override
  bool get isStandalone => false;

  @override
  double? get millisecondsSinceNavigationStart => null;

  @override
  String resolveAppUrl(String relativePath) => relativePath;

  @override
  Future<String?> fetchTextNoStore(
    String relativePath, {
    Duration timeout = const Duration(seconds: 5),
  }) async => null;

  @override
  Future<bool> downloadBytes(
    Uint8List bytes, {
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) async => false;

  @override
  bool canShareFiles({String mimeType = 'application/octet-stream'}) => false;

  @override
  Future<WebShareResult> shareFile(
    Uint8List bytes, {
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) async => WebShareResult.unsupported;

  @override
  Stream<WebVisibility> get visibilityChanges => const Stream.empty();

  @override
  void reload() {}
}
