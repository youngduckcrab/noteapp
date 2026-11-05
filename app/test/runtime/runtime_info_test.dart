// RuntimeInfo (docs/plans/01-infra.md 4.5.1 and 9.1) on the VM, with the
// fake web platform and with the real VM stub of createWebPlatform().

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:noteapp/src/web/web_platform.dart';

import '../fakes/fake_web_platform.dart';

void main() {
  test('VM: notWeb renderer; standalone and userAgent from the platform', () {
    final info = RuntimeInfo.detect(
      FakeWebPlatform(isStandalone: true, userAgent: 'iPad Safari'),
    );
    expect(info.isWeb, isFalse);
    expect(info.renderer, WebRenderer.notWeb);
    expect(info.rendererLabel, AppStrings.rendererNative);
    expect(info.isStandalone, isTrue);
    expect(info.userAgent, 'iPad Safari');
  });

  test('VM stub of createWebPlatform is a no-op', () async {
    final web = createWebPlatform();
    expect(web.isSupported, isFalse);
    expect(web.userAgent, isNull);
    expect(web.isStandalone, isFalse);
    expect(web.millisecondsSinceNavigationStart, isNull);
    expect(web.resolveAppUrl('sqlite3.wasm'), 'sqlite3.wasm');
    expect(await web.fetchTextNoStore('build_info.json'), isNull);
    expect(await web.downloadBytes(Uint8List(1), fileName: 'a.json'), isFalse);
    expect(web.canShareFiles(), isFalse);
    expect(
      await web.shareFile(Uint8List(1), fileName: 'a.json'),
      WebShareResult.unsupported,
    );
    expect(await web.visibilityChanges.isEmpty, isTrue);
    web.reload(); // no-op, does not throw

    final info = RuntimeInfo.detect(web);
    expect(info.isStandalone, isFalse);
    expect(info.userAgent, isNull);
    expect(info.renderer, WebRenderer.notWeb);
  });

  test('renderer labels', () {
    String label(WebRenderer r) => RuntimeInfo(
      isWeb: r != WebRenderer.notWeb,
      renderer: r,
      isStandalone: false,
    ).rendererLabel;
    expect(label(WebRenderer.canvasKit), 'CanvasKit (dart2js)');
    expect(label(WebRenderer.skwasm), 'skwasm (wasm)');
    expect(label(WebRenderer.notWeb), '네이티브');
  });
}
