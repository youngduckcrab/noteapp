@TestOn('browser')
library;

// Browser output sink (06-pdf 4.10, 6.12; 8 T16): the download anchor (download attribute,
// Blob URL of the bytes, removed after the click, URL revoked later), desktop Chrome offers
// no share, two results → neither download nor new tab, navigator.canShare gets every file,
// navigator.share outcomes (AbortError / NotAllowedError / other), window.open → a Blob URL
// and a blocked popup → needsUserGesture. A fake navigator / opener stands for the parts
// headless Chrome cannot do.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/output/output_sink_browser.dart'
    show BrowserPdfOutputSink;
import 'package:web/web.dart' as web;

PdfExportResult _result(String name, List<int> bytes) => PdfExportResult(
  bytes: Uint8List.fromList(bytes),
  fileName: name,
  pageCount: 1,
  elapsed: Duration.zero,
);

/// A navigator with canShare / share only: records what it gets; share settles with
/// [shareError] (null → resolves).
final class _FakeNavigator {
  bool canShare = true;
  JSAny? shareError;
  final List<web.ShareData> canShareCalls = [];
  final List<web.ShareData> shareCalls = [];

  web.Navigator get navigator {
    final object = JSObject();
    object['canShare'] = ((web.ShareData data) {
      canShareCalls.add(data);
      return canShare.toJS;
    }).toJS;
    object['share'] = ((web.ShareData data) {
      shareCalls.add(data);
      final error = shareError;
      return JSPromise<JSAny?>(
        ((JSFunction resolve, JSFunction reject) {
          if (error == null) {
            resolve.callAsFunction();
          } else {
            reject.callAsFunction(null, error);
          }
        }).toJS,
      );
    }).toJS;
    return object as web.Navigator;
  }
}

List<web.File> _files(web.ShareData data) => data.files.toDart;

Future<Uint8List> _fetchBytes(String url) async {
  final response = await web.window.fetch(url.toJS).toDart;
  final buffer = await response.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

Future<bool> _fetchFails(String url) async {
  try {
    await web.window.fetch(url.toJS).toDart;
    return false;
  } on Object {
    return true;
  }
}

void main() {
  final a = _result('a.pdf', [0x25, 0x50, 0x44, 0x46, 0x2d, 0x61]);
  final b = _result('b.pdf', [0x25, 0x50, 0x44, 0x46, 0x2d, 0x62, 0x62]);

  test('createPlatformOutputSink is the browser sink', () {
    expect(createPlatformOutputSink(), isA<BrowserPdfOutputSink>());
  });

  test('download: a hidden <a download> with a Blob URL of the bytes, removed '
      'after the click; the URL is revoked later', () async {
    final clicks = <(String, String)>[];
    final listener = ((web.Event event) {
      final target = event.target;
      if (target != null && target.isA<web.HTMLAnchorElement>()) {
        final anchor = target as web.HTMLAnchorElement;
        clicks.add((anchor.download, anchor.href));
        event.preventDefault(); // no real download in the test browser
      }
    }).toJS;
    web.document.addEventListener('click', listener, true.toJS);
    addTearDown(
      () => web.document.removeEventListener('click', listener, true.toJS),
    );

    final sink = BrowserPdfOutputSink(revokeDelay: Duration.zero);
    final outcome = await sink.deliver([a], PdfOutputAction.download);
    expect(outcome, PdfOutputOutcome.done);
    final (download, href) = clicks.single;
    expect(download, 'a.pdf');
    expect(href, startsWith('blob:'));
    expect(web.document.querySelectorAll('a[download]').length, 0);

    // A second sink keeps its URL long enough to read it back.
    final keep = BrowserPdfOutputSink();
    await keep.deliver([b], PdfOutputAction.download);
    final kept = clicks.last.$2;
    expect(await _fetchBytes(kept), b.bytes);
    final response = await web.window.fetch(kept.toJS).toDart;
    expect(response.headers.get('content-type'), 'application/pdf');

    // revokeDelay zero: the first URL stops working (polled — no wall-clock bound).
    var revoked = false;
    for (var i = 0; i < 200 && !revoked; i++) {
      revoked = await _fetchFails(href);
      if (!revoked) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
    expect(revoked, isTrue);
  });

  test('desktop Chrome: no file share; one result → download + new tab, '
      'two → nothing', () {
    final sink = BrowserPdfOutputSink();
    expect(sink.availableActions([a]), {
      PdfOutputAction.download,
      PdfOutputAction.openInNewTab,
    });
    expect(sink.availableActions([a, b]), isEmpty);
    expect(sink.availableActions(const []), isEmpty);
    expect(() => sink.deliver([a], PdfOutputAction.share), throwsArgumentError);
    expect(
      () => sink.deliver([a, b], PdfOutputAction.download),
      throwsArgumentError,
    );
    expect(
      () => sink.deliver([a, b], PdfOutputAction.openInNewTab),
      throwsArgumentError,
    );
  });

  test(
    'canShare gets every result as a PDF File; two results → share only',
    () {
      final fake = _FakeNavigator();
      final sink = BrowserPdfOutputSink(navigator: fake.navigator);
      expect(sink.availableActions([a, b]), {PdfOutputAction.share});
      final files = _files(fake.canShareCalls.single);
      expect([for (final f in files) f.name], ['a.pdf', 'b.pdf']);
      expect(
        [for (final f in files) f.type],
        ['application/pdf', 'application/pdf'],
      );
      expect([for (final f in files) f.size], [6, 7]);
      expect(fake.canShareCalls.single.title, 'PDF 2개');

      expect(sink.availableActions([a]), {
        PdfOutputAction.share,
        PdfOutputAction.download,
        PdfOutputAction.openInNewTab,
      });
      expect(fake.canShareCalls.last.title, 'a.pdf');
      // The File is made once per result.
      expect(
        _files(fake.canShareCalls.last).single,
        same(_files(fake.canShareCalls.first).first),
      );

      fake.canShare = false;
      expect(sink.availableActions([a, b]), isEmpty);
      expect(
        () => sink.deliver([a, b], PdfOutputAction.share),
        throwsArgumentError,
      );
    },
  );

  test('share is called before deliver returns; its outcomes', () async {
    final fake = _FakeNavigator();
    final sink = BrowserPdfOutputSink(navigator: fake.navigator);

    final done = sink.deliver([a, b], PdfOutputAction.share);
    // Synchronously: the tap's user activation is still there (6.12).
    expect(fake.shareCalls, hasLength(1));
    expect(
      [for (final f in _files(fake.shareCalls.single)) f.name],
      ['a.pdf', 'b.pdf'],
    );
    expect(fake.shareCalls.single.title, 'PDF 2개');
    expect(await done, PdfOutputOutcome.done);

    fake.shareError = web.DOMException('closed', 'AbortError');
    expect(
      await sink.deliver([a], PdfOutputAction.share),
      PdfOutputOutcome.dismissedByUser,
    );
    expect(fake.shareCalls.last.title, 'a.pdf');
    fake.shareError = web.DOMException('no activation', 'NotAllowedError');
    expect(
      await sink.deliver([a], PdfOutputAction.share),
      PdfOutputOutcome.needsUserGesture,
    );
    fake.shareError = web.DOMException('bad data', 'DataError');
    expect(
      await sink.deliver([a], PdfOutputAction.share),
      PdfOutputOutcome.failed,
    );
    fake.shareError = 'not an exception'.toJS;
    expect(
      await sink.deliver([a], PdfOutputAction.share),
      PdfOutputOutcome.failed,
    );
  });

  test(
    'openInNewTab: window.open gets a Blob URL; blocked → needsUserGesture',
    () async {
      final opened = <String>[];
      web.Window? answer;
      final sink = BrowserPdfOutputSink(
        openWindow: (url) {
          opened.add(url);
          return answer;
        },
      );
      expect(
        await sink.deliver([a], PdfOutputAction.openInNewTab),
        PdfOutputOutcome.needsUserGesture,
      );
      answer = web.window;
      expect(
        await sink.deliver([a], PdfOutputAction.openInNewTab),
        PdfOutputOutcome.done,
      );
      expect(opened, hasLength(2));
      expect(opened.last, startsWith('blob:'));
      expect(await _fetchBytes(opened.last), a.bytes);
    },
  );
}
