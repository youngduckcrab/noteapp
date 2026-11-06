// The web '파일로 내려받기' body in Chrome (m5-7/06-pdf 6.10.4 — 8.2 T32b): prepare makes a Blob and
// an object URL that serves the same bytes and MIME, save clicks a hidden <a download> with that
// URL and file name synchronously (the click is caught and its default prevented, so no file is
// written) and removes it, revoke makes the URL unreadable and save a no-op; the factory and
// fileDownloadsProvider give the browser body on the web.
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/platform/file_download_browser.dart';
import 'package:media_io/src/platform/file_download_factory.dart'
    as download_factory;
import 'package:media_io/src/providers.dart';
import 'package:web/web.dart' as web;

/// Clicks on <a download> while the test runs: (href, download); the default is prevented.
List<(String, String)> catchDownloadClicks() {
  final clicks = <(String, String)>[];
  final listener = ((web.Event e) {
    final target = e.target;
    if (target != null && target.isA<web.HTMLAnchorElement>()) {
      final a = target as web.HTMLAnchorElement;
      clicks.add((a.href, a.download));
      e.preventDefault();
    }
  }).toJS;
  web.document.addEventListener('click', listener, true.toJS);
  addTearDown(
    () => web.document.removeEventListener('click', listener, true.toJS),
  );
  return clicks;
}

Future<Uint8List> fetchBytes(String url) async {
  final response = await web.window.fetch(url.toJS).toDart;
  final buffer = await response.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

void main() {
  const downloads = BrowserFileDownloads();
  final bytes = Uint8List.fromList(List.generate(1000, (i) => i % 251));

  test('prepare: an object URL with the same bytes and MIME', () async {
    expect(downloads.available, isTrue);
    final p = downloads.prepare(
      bytes,
      mimeType: 'audio/webm',
      fileName: '녹음-20261106-0930.webm',
    )!;
    addTearDown(p.revoke);
    final prepared = p as BrowserPreparedDownload;
    expect(prepared.url, startsWith('blob:'));
    expect(p.fileName, '녹음-20261106-0930.webm');
    final response = await web.window.fetch(prepared.url.toJS).toDart;
    expect(response.headers.get('content-type'), 'audio/webm');
    expect(await fetchBytes(prepared.url), bytes);
  });

  test(
    'save: one synchronous click on a hidden <a download>, removed after',
    () {
      final clicks = catchDownloadClicks();
      final p = downloads.prepare(
        bytes,
        mimeType: 'audio/mp4',
        fileName: 'a.m4a',
      ) as BrowserPreparedDownload;
      addTearDown(p.revoke);
      p.save();
      expect(clicks, [(p.url, 'a.m4a')]); // before save() returned
      expect(web.document.querySelectorAll('a[download]').length, 0);
    },
  );

  test('revoke: the URL no longer reads, save does nothing, a second revoke is a no-op', () async {
    final clicks = catchDownloadClicks();
    final p = downloads.prepare(
      bytes,
      mimeType: 'audio/webm',
      fileName: 'b.webm',
    ) as BrowserPreparedDownload;
    p.revoke();
    expect(p.revoked, isTrue);
    p.revoke();
    p.save();
    expect(clicks, isEmpty);
    await expectLater(fetchBytes(p.url), throwsA(anything));
  });

  test(
    'the factory and fileDownloadsProvider give the browser body on the web',
    () {
      expect(
        download_factory.createPlatformFileDownloads(),
        isA<BrowserFileDownloads>(),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(fileDownloadsProvider),
        isA<BrowserFileDownloads>(),
      );
    },
  );
}
