/// Browser-only APIs of the app shell behind one interface
/// (docs/plans/01-infra.md 4.5.2, contract 00-overview 7.4.3).
///
/// Storage persistence (`navigator.storage.persist()` / `estimate()`) is not
/// here: only CORE calls it (contract 7.2.12); the shell shows CORE's
/// `StorageInfo`.
library;

import 'dart:typed_data';

export 'web_platform_stub.dart'
    if (dart.library.js_interop) 'web_platform_browser.dart'
    show createWebPlatform;

/// Page visibility reported by [WebPlatform.visibilityChanges].
enum WebVisibility { visible, hidden }

/// Outcome of [WebPlatform.shareFile].
enum WebShareResult { shared, cancelled, unsupported, failed }

/// Browser-only APIs behind an interface. The VM/native implementation is a
/// no-op so that every caller works in `flutter test` and on native builds.
abstract interface class WebPlatform {
  bool get isSupported;
  String? get userAgent;

  /// matchMedia('(display-mode: standalone)') || navigator.standalone.
  bool get isStandalone;

  /// performance.now(), i.e. ms since navigation start. Null if unsupported.
  double? get millisecondsSinceNavigationStart;

  /// Absolute URL of [relativePath] resolved against `document.baseURI`
  /// (honours `<base href>`; dart2js `Uri.base` is `location.href`, which is a
  /// deep path such as `/notes/<id>` under the path URL strategy).
  /// 계약 7.2.12 · 7.4.3 (v1.1): production passes ONLY these absolute URLs to
  /// CORE WebStorageConfig; CORE keeps Uri.base.resolve(path), which returns an
  /// absolute URL unchanged. Non-web: returns [relativePath] unchanged.
  String resolveAppUrl(String relativePath);

  /// GET [relativePath] (resolved by fetch() against document.baseURI) with
  /// `cache: 'no-store'` and a `?t=<epochMs>` query.
  /// Returns null on non-2xx, network error or after [timeout].
  Future<String?> fetchTextNoStore(
    String relativePath, {
    Duration timeout = const Duration(seconds: 5),
  });

  /// Starts a browser download of [bytes]: Blob + `<a download=fileName>` click,
  /// object URL revoked after 30 s (Safari needs the delay).
  /// Returns false when unsupported (non-web) or when the browser threw.
  /// Never throws. NOTE (미확인, 11절): an iPadOS home-screen app may ignore
  /// `<a download>`; [shareFile] is the second path. Call from a tap handler.
  Future<bool> downloadBytes(
    Uint8List bytes, {
    required String fileName,
    String mimeType = 'application/octet-stream',
  });

  /// navigator.canShare({files: [File([], 'probe', {type: mimeType})]}).
  /// False off-web, when navigator.share / canShare is missing, or when it
  /// throws. Never throws.
  bool canShareFiles({String mimeType = 'application/octet-stream'});

  /// navigator.share({files: [File([bytes], fileName, {type: mimeType})]})
  /// (Safari 15+ — 미확인). Must be called directly from a tap handler (user
  /// activation). AbortError → cancelled; missing API → unsupported; any
  /// other error → failed. Never throws.
  Future<WebShareResult> shareFile(
    Uint8List bytes, {
    required String fileName,
    String mimeType = 'application/octet-stream',
  });

  /// document 'visibilitychange' (+ 'pagehide' mapped to hidden).
  /// Single broadcast stream, listener attached lazily once.
  Stream<WebVisibility> get visibilityChanges;

  /// window.location.reload().
  void reload();
}
