/// What the app runs on (docs/plans/01-infra.md 4.5.1).
library;

import 'package:flutter/foundation.dart';

import '../app/strings.dart';
import '../web/web_platform.dart';

enum WebRenderer { notWeb, canvasKit, skwasm }

@immutable
final class RuntimeInfo {
  const RuntimeInfo({
    required this.isWeb,
    required this.renderer,
    required this.isStandalone,
    this.userAgent,
  });

  /// isWeb = kIsWeb; renderer = kIsWasm ? skwasm : canvasKit (web only);
  /// isStandalone/userAgent from [web].
  factory RuntimeInfo.detect(WebPlatform web) => RuntimeInfo(
    isWeb: kIsWeb,
    renderer: !kIsWeb
        ? WebRenderer.notWeb
        : kIsWasm
        ? WebRenderer.skwasm
        : WebRenderer.canvasKit,
    isStandalone: web.isStandalone,
    userAgent: web.userAgent,
  );

  final bool isWeb;
  final WebRenderer renderer;

  /// True when launched from the iPad home screen (display-mode: standalone).
  final bool isStandalone;
  final String? userAgent;

  /// e.g. `CanvasKit (dart2js)`, `skwasm (wasm)`, `네이티브`.
  String get rendererLabel => switch (renderer) {
    WebRenderer.canvasKit => 'CanvasKit (dart2js)',
    WebRenderer.skwasm => 'skwasm (wasm)',
    WebRenderer.notWeb => AppStrings.rendererNative,
  };
}
