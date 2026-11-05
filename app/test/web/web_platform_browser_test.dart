@TestOn('browser')
library;

// WebPlatform in a real browser (docs/plans/01-infra.md 4.5.2 and 9.1):
// `ws test --platform chrome` runs this file with dart2js.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noteapp/src/web/web_platform.dart';
import 'package:web/web.dart' as html;

void main() {
  late WebPlatform web;
  setUp(() => web = createWebPlatform());

  test('is the browser implementation', () {
    expect(web.isSupported, isTrue);
    expect(web.userAgent, isNotEmpty);
    expect(web.millisecondsSinceNavigationStart, greaterThan(0));
  });

  test('resolveAppUrl is absolute against document.baseURI', () {
    final url = web.resolveAppUrl('sqlite3.wasm');
    expect(Uri.parse(url).isAbsolute, isTrue);
    expect(url, endsWith('/sqlite3.wasm'));
    expect(Uri.parse(url).scheme, startsWith('http'));
  });

  test('fetchTextNoStore returns null for a 404', () async {
    expect(await web.fetchTextNoStore('no_such_file_for_ws_test.json'), isNull);
  });

  test('a fetch that does not answer in time returns null', () async {
    expect(
      await web.fetchTextNoStore(
        'no_such_file_for_ws_test.json',
        timeout: Duration.zero,
      ),
      isNull,
    );
  });

  test('visibilityChanges maps pagehide and visibilitychange; listeners '
      'can be cancelled', () async {
    final stream = web.visibilityChanges;
    expect(stream.isBroadcast, isTrue);
    final events = <WebVisibility>[];
    final first = stream.listen(events.add);
    final second = stream.listen((_) {});
    html.window.dispatchEvent(html.Event('pagehide'));
    html.document.dispatchEvent(html.Event('visibilitychange'));
    await pumpEventQueue();
    expect(events, [
      WebVisibility.hidden,
      html.document.visibilityState == 'hidden'
          ? WebVisibility.hidden
          : WebVisibility.visible,
    ]);
    await first.cancel();
    await second.cancel();
    // Listening again after every listener left still works, and the DOM
    // listeners are not attached twice (one event per dispatch).
    final again = <WebVisibility>[];
    final third = web.visibilityChanges.listen(again.add);
    html.window.dispatchEvent(html.Event('pagehide'));
    await pumpEventQueue();
    expect(again, [WebVisibility.hidden]);
    await third.cancel();
  });

  test('not started from the home screen in a test browser', () {
    expect(web.isStandalone, isFalse);
  });

  test('downloadBytes does not throw and reports success', () async {
    final ok = await web.downloadBytes(
      Uint8List.fromList([1, 2, 3]),
      fileName: 'ws_test.json',
      mimeType: 'application/json',
    );
    expect(ok, isTrue);
  });

  test('canShareFiles is a bool; without file sharing shareFile is '
      'unsupported', () async {
    final can = web.canShareFiles(mimeType: 'application/json');
    expect(can, isA<bool>());
    if (!can) {
      expect(
        await web.shareFile(
          Uint8List.fromList([1]),
          fileName: 'ws_test.json',
          mimeType: 'application/json',
        ),
        WebShareResult.unsupported,
      );
    }
  });
}
