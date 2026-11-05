@TestOn('browser')
library;

// pdfrx wasm in Chrome with the assets tool/prepare_web_test.dart copied to test/web/pdfium/
// (06-pdf 8 T2, 9.1, V11): open, render and text of PdfFixtureBuilder output, incl. the
// Korean ToUnicode text and the RC4 password path.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/testing.dart';
import 'package:pdfrx/pdfrx.dart' as rx;

var _docs = 0;

void main() {
  setUpAll(() async {
    rx.Pdfrx.pdfiumWasmModulesUrl = 'pdfium/';
    await rx.pdfrxFlutterInitialize();
  });

  test('open, render, text', () async {
    final bytes =
        (PdfFixtureBuilder()
              ..addPage(
                const PdfFixturePage(
                  width: 400,
                  height: 300,
                  texts: [
                    PdfFixtureText('Hello web', x: 40, y: 100, size: 40),
                    PdfFixtureText('강의 자료', x: 40, y: 200, mapped: true),
                  ],
                ),
              )
              ..addPage(const PdfFixturePage(rotate: 90)))
            .build();
    final doc = await rx.PdfDocument.openData(
      bytes,
      sourceName: 'mem:web-smoke-${_docs++}',
    );
    addTearDown(doc.dispose);
    expect(doc.pages, hasLength(2));
    expect(doc.pages[0].width, closeTo(400, 1e-3));
    expect(doc.pages[1].width, closeTo(841.8898, 1e-3));

    final text = await doc.pages[0].loadStructuredText();
    expect(text.fullText, contains('Hello web'));
    expect(text.fullText, contains('강의'));

    final image = (await doc.pages[0].render(fullWidth: 400, fullHeight: 300))!;
    addTearDown(image.dispose);
    expect(image.width, 400);
    expect(image.height, 300);
    var dark = 0;
    for (var x = 40; x < 240; x++) {
      final i = (90 * image.width + x) * 4;
      if (image.pixels[i] < 128 && image.pixels[i + 1] < 128) dark++;
    }
    expect(dark, greaterThan(10), reason: 'glyph pixels above the baseline');
    final corner = (5 * image.width + 395) * 4;
    expect(image.pixels.sublist(corner, corner + 3), [255, 255, 255]);
  });

  test('user password through the provider', () async {
    final bytes =
        (PdfFixtureBuilder()
              ..addPage(const PdfFixturePage(texts: [PdfFixtureText('Secret')]))
              ..encrypt(userPassword: 'pw'))
            .build();
    var calls = 0;
    final doc = await rx.PdfDocument.openData(
      bytes,
      sourceName: 'mem:web-smoke-${_docs++}',
      passwordProvider: () {
        calls++;
        return calls == 1 ? 'wrong' : 'pw';
      },
    );
    addTearDown(doc.dispose);
    expect(calls, 2);
    expect(
      (await doc.pages.single.loadStructuredText()).fullText,
      contains('Secret'),
    );
  });
}
