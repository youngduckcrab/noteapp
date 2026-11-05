/// Browser [WebPlatform] on `package:web` (docs/plans/01-infra.md 4.5.2,
/// 6.11; contract 00-overview 7.4.3).
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'web_platform.dart';

/// Conditional import: web_platform_stub.dart /
/// web_platform_browser.dart (if dart.library.js_interop).
WebPlatform createWebPlatform() => _BrowserWebPlatform();

/// How long an object URL of [WebPlatform.downloadBytes] stays valid.
const Duration _revokeDelay = Duration(seconds: 30);

final class _BrowserWebPlatform implements WebPlatform {
  @override
  bool get isSupported => true;

  @override
  String? get userAgent {
    try {
      return web.window.navigator.userAgent;
    } on Object {
      return null;
    }
  }

  @override
  bool get isStandalone {
    try {
      if (web.window.matchMedia('(display-mode: standalone)').matches) {
        return true;
      }
      // iPadOS Safari: non-standard navigator.standalone.
      final standalone = (web.window.navigator as JSObject).getProperty<JSAny?>(
        'standalone'.toJS,
      );
      return standalone.isA<JSBoolean>() && (standalone! as JSBoolean).toDart;
    } on Object {
      return false;
    }
  }

  @override
  double? get millisecondsSinceNavigationStart {
    try {
      return web.window.performance.now();
    } on Object {
      return null;
    }
  }

  Uri get _base => Uri.parse(web.document.baseURI);

  @override
  String resolveAppUrl(String relativePath) =>
      _base.resolve(relativePath).toString();

  @override
  Future<String?> fetchTextNoStore(
    String relativePath, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final controller = web.AbortController();
    final resolved = _base.resolve(relativePath);
    final url = resolved.replace(
      queryParameters: {
        ...resolved.queryParameters,
        't': '${DateTime.now().millisecondsSinceEpoch}',
      },
    );
    Future<String?> load() async {
      final response = await web.window
          .fetch(
            url.toString().toJS,
            web.RequestInit(cache: 'no-store', signal: controller.signal),
          )
          .toDart;
      if (!response.ok) return null;
      return (await response.text().toDart).toDart;
    }

    try {
      return await load().timeout(
        timeout,
        onTimeout: () {
          controller.abort();
          return null;
        },
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<bool> downloadBytes(
    Uint8List bytes, {
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) async {
    try {
      final blob = web.Blob(
        <JSAny>[bytes.toJS].toJS,
        web.BlobPropertyBag(type: mimeType),
      );
      final url = web.URL.createObjectURL(blob);
      final anchor = web.HTMLAnchorElement()
        ..href = url
        ..download = fileName
        ..style.display = 'none';
      web.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
      Timer(_revokeDelay, () {
        try {
          web.URL.revokeObjectURL(url);
        } on Object {
          // The page may be gone; nothing to clean up then.
        }
      });
      return true;
    } on Object {
      return false;
    }
  }

  web.ShareData _shareData(List<JSAny> parts, String name, String mimeType) =>
      web.ShareData(
        files: <web.File>[
          web.File(parts.toJS, name, web.FilePropertyBag(type: mimeType)),
        ].toJS,
      );

  bool _hasNavigatorMember(String name) {
    try {
      return (web.window.navigator as JSObject).has(name);
    } on Object {
      return false;
    }
  }

  @override
  bool canShareFiles({String mimeType = 'application/octet-stream'}) {
    if (!_hasNavigatorMember('share') || !_hasNavigatorMember('canShare')) {
      return false;
    }
    try {
      return web.window.navigator.canShare(
        _shareData(const <JSAny>[], 'probe', mimeType),
      );
    } on Object {
      return false;
    }
  }

  @override
  Future<WebShareResult> shareFile(
    Uint8List bytes, {
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) async {
    if (!canShareFiles(mimeType: mimeType)) return WebShareResult.unsupported;
    try {
      await web.window.navigator
          .share(_shareData(<JSAny>[bytes.toJS], fileName, mimeType))
          .toDart;
      return WebShareResult.shared;
    } on Object catch (error) {
      // dart2js rethrows the DOMException itself; its text starts with the
      // exception name.
      return '$error'.contains('AbortError')
          ? WebShareResult.cancelled
          : WebShareResult.failed;
    }
  }

  @override
  Stream<WebVisibility> get visibilityChanges => _visibility.stream;

  /// Lives as long as the page; the DOM listeners are attached on the first
  /// listen and never removed (one pair per page).
  late final StreamController<WebVisibility> _visibility =
      StreamController<WebVisibility>.broadcast(onListen: _attachListeners);

  bool _attached = false;

  void _attachListeners() {
    if (_attached) return;
    _attached = true;
    web.document.addEventListener(
      'visibilitychange',
      ((web.Event _) {
        _visibility.add(
          web.document.visibilityState == 'hidden'
              ? WebVisibility.hidden
              : WebVisibility.visible,
        );
      }).toJS,
    );
    web.window.addEventListener(
      'pagehide',
      ((web.Event _) => _visibility.add(WebVisibility.hidden)).toJS,
    );
  }

  @override
  void reload() => web.window.location.reload();
}
