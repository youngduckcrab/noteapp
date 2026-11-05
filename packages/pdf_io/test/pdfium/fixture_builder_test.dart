// PdfFixtureBuilder against real PDFium (06-pdf 8 T2): every feature opens with the expected
// size, rotation, text, Korean text and password requirement.
@Tags(['pdfium'])
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/testing.dart';
import 'package:pdfrx/pdfrx.dart' as rx;

import '../support/pdfium_env.dart';

var _docs = 0;

Future<rx.PdfDocument> _open(
  Uint8List bytes, {
  rx.PdfPasswordProvider? passwordProvider,
}) => rx.PdfDocument.openData(
  bytes,
  sourceName: 'mem:fixture-${_docs++}',
  passwordProvider: passwordProvider,
);

/// BGRA pixel at (x, y) of a rendered image.
List<int> _rgb(rx.PdfImage image, int x, int y) {
  final i = (y * image.width + x) * 4;
  return [image.pixels[i + 2], image.pixels[i + 1], image.pixels[i]];
}

void main() {
  setUpAll(initPdfiumForTests);

  test('default page: A4 size, one shared font, text extracted', () async {
    final bytes =
        (PdfFixtureBuilder()..addPage(
              const PdfFixturePage(texts: [PdfFixtureText('Hello lecture')]),
            ))
            .build();
    final doc = await _open(bytes);
    addTearDown(doc.dispose);
    expect(doc.pages, hasLength(1));
    final page = doc.pages.single;
    expect(page.width, closeTo(595.2756, 1e-3));
    expect(page.height, closeTo(841.8898, 1e-3));
    expect(page.rotation, rx.PdfPageRotation.none);
    expect(doc.isEncrypted, isFalse);
    final text = await page.loadStructuredText();
    expect(text.fullText, contains('Hello lecture'));
  });

  test('text sits at its display position (rotation 0)', () async {
    final bytes =
        (PdfFixtureBuilder()..addPage(
              const PdfFixturePage(
                width: 400,
                height: 300,
                texts: [PdfFixtureText('H', x: 100, y: 80, size: 40)],
              ),
            ))
            .build();
    final doc = await _open(bytes);
    addTearDown(doc.dispose);
    final text = await doc.pages.single.loadStructuredText();
    final rect = text.charRects.first;
    // PDFium boxes are in PDF space (y up): baseline y = 300 − 80 = 220, cap height ≈ 29 pt.
    expect(rect.left, closeTo(100, 6));
    expect(rect.bottom, closeTo(220, 3));
    expect(rect.top, greaterThan(240));
    expect(rect.top, lessThan(260));
  });

  test('rotation 90 swaps the displayed size, text still extracted', () async {
    final bytes =
        (PdfFixtureBuilder()
              ..addPage(
                const PdfFixturePage(
                  width: 400,
                  height: 300,
                  rotate: 90,
                  texts: [PdfFixtureText('Turned page', x: 40, y: 60)],
                ),
              )
              ..addPage(
                const PdfFixturePage(width: 400, height: 300, rotate: 180),
              )
              ..addPage(
                const PdfFixturePage(width: 400, height: 300, rotate: 270),
              ))
            .build();
    final doc = await _open(bytes);
    addTearDown(doc.dispose);
    final turned = doc.pages[0];
    expect(turned.rotation, rx.PdfPageRotation.clockwise90);
    expect(turned.width, closeTo(300, 1e-3));
    expect(turned.height, closeTo(400, 1e-3));
    expect(doc.pages[1].rotation, rx.PdfPageRotation.clockwise180);
    expect(doc.pages[1].width, closeTo(400, 1e-3));
    expect(doc.pages[2].rotation, rx.PdfPageRotation.clockwise270);
    expect(doc.pages[2].width, closeTo(300, 1e-3));
    expect(
      (await turned.loadStructuredText()).fullText,
      contains('Turned page'),
    );
  });

  test(
    'text on a rotated page is drawn upright at its display position',
    () async {
      // A filled box would be easier, but text is what the fixture places with D⁻¹.
      final bytes =
          (PdfFixtureBuilder()..addPage(
                const PdfFixturePage(
                  width: 400,
                  height: 300,
                  rotate: 90,
                  texts: [PdfFixtureText('IIIIIIII', x: 40, y: 100, size: 60)],
                ),
              ))
              .build();
      final doc = await _open(bytes);
      addTearDown(doc.dispose);
      final page = doc.pages.single;
      final image = (await page.render(
        fullWidth: page.width,
        fullHeight: page.height,
      ))!;
      addTearDown(image.dispose);
      expect(image.width, 300);
      expect(image.height, 400);
      // Upright 'I' strokes: dark just above the baseline at display (x≈50, y≈90),
      // paper below the baseline and far right of the text.
      bool dark(int x, int y) => _rgb(image, x, y).every((c) => c < 128);
      var darkAbove = 0;
      for (var x = 40; x < 140; x++) {
        if (dark(x, 85)) darkAbove++;
      }
      expect(darkAbove, greaterThan(10));
      var darkBelow = 0;
      for (var x = 40; x < 140; x++) {
        if (dark(x, 110)) darkBelow++;
      }
      expect(darkBelow, 0);
    },
  );

  test('MediaBox and CropBox: the displayed size is the CropBox', () async {
    final bytes =
        (PdfFixtureBuilder()
              ..addPage(
                const PdfFixturePage(
                  mediaBox: [0, 0, 612, 792],
                  cropBox: [36, 72, 576, 756],
                  texts: [PdfFixtureText('Cropped', x: 20, y: 40)],
                ),
              )
              ..addPage(
                const PdfFixturePage(
                  mediaBox: [-100, -50, 512, 742],
                  cropBox: [0, 0, 400, 600],
                  rotate: 270,
                ),
              ))
            .build();
    final doc = await _open(bytes);
    addTearDown(doc.dispose);
    expect(doc.pages[0].width, closeTo(540, 1e-3));
    expect(doc.pages[0].height, closeTo(684, 1e-3));
    expect(
      (await doc.pages[0].loadStructuredText()).fullText,
      contains('Cropped'),
    );
    expect(doc.pages[1].width, closeTo(600, 1e-3));
    expect(doc.pages[1].height, closeTo(400, 1e-3));
  });

  test("mapped text: '강의 자료' and NFD jamo through ToUnicode", () async {
    final bytes =
        (PdfFixtureBuilder()..addPage(
              const PdfFixturePage(
                texts: [
                  PdfFixtureText('강의 자료', mapped: true),
                  PdfFixtureText('가', y: 200, mapped: true),
                  PdfFixtureText('Latin too', y: 300),
                ],
              ),
            ))
            .build();
    final doc = await _open(bytes);
    addTearDown(doc.dispose);
    final text = await doc.pages.single.loadStructuredText();
    expect(text.fullText, contains('강의'));
    expect(text.fullText, contains('강의 자료'));
    // Decomposed jamo come out decomposed (V12) — pdf_io normalizes them (6.10.1).
    expect(text.fullText, contains('가'));
    expect(text.fullText, contains('Latin too'));
    // One char box per UTF-16 code unit (V12).
    final index = text.fullText.indexOf('강의');
    final first = text.charRects[index];
    expect(first.right, greaterThan(first.left));
  });

  test('raw content is appended verbatim', () async {
    final bytes =
        (PdfFixtureBuilder()..addPage(
              const PdfFixturePage(
                width: 200,
                height: 100,
                rawContent: '0 0 1 rg 20 20 40 30 re f\n',
              ),
            ))
            .build();
    final doc = await _open(bytes);
    addTearDown(doc.dispose);
    final image = (await doc.pages.single.render())!;
    addTearDown(image.dispose);
    // User space (20..60, 20..50) = display x 20..60, y 50..80.
    expect(_rgb(image, 40, 65), [0, 0, 255]);
    expect(_rgb(image, 100, 65), [255, 255, 255]);
    expect(_rgb(image, 40, 30), [255, 255, 255]);
  });

  test('user password: needs it, wrong one asked again, then opens', () async {
    final bytes =
        (PdfFixtureBuilder()
              ..addPage(
                const PdfFixturePage(texts: [PdfFixtureText('Secret text')]),
              )
              ..encrypt(userPassword: 'pw1234'))
            .build();
    await expectLater(
      _open(bytes, passwordProvider: () => null),
      throwsA(isA<rx.PdfPasswordException>()),
    );
    var calls = 0;
    final doc = await _open(
      bytes,
      passwordProvider: () {
        calls++;
        return calls == 1 ? 'wrong' : 'pw1234';
      },
    );
    addTearDown(doc.dispose);
    expect(calls, 2);
    expect(doc.isEncrypted, isTrue);
    expect(
      (await doc.pages.single.loadStructuredText()).fullText,
      contains('Secret text'),
    );
  });

  test('permission-only encryption opens without asking', () async {
    final bytes =
        (PdfFixtureBuilder()
              ..addPage(
                const PdfFixturePage(
                  texts: [PdfFixtureText('강의', mapped: true)],
                ),
              )
              ..encrypt(userPassword: '', ownerPassword: 'owner'))
            .build();
    var calls = 0;
    final doc = await _open(
      bytes,
      passwordProvider: () {
        calls++;
        return null;
      },
    );
    addTearDown(doc.dispose);
    expect(calls, 0);
    expect(doc.isEncrypted, isTrue);
    expect(
      (await doc.pages.single.loadStructuredText()).fullText,
      contains('강의'),
    );
  });

  test(
    'many pages share the font: 50 pages open with their own text',
    () async {
      final bytes =
          (PdfFixtureBuilder()..addPages(
                50,
                (i) => PdfFixturePage(texts: [PdfFixtureText('Page ${i + 1}')]),
              ))
              .build();
      final doc = await _open(bytes);
      addTearDown(doc.dispose);
      expect(doc.pages, hasLength(50));
      expect(
        (await doc.pages[41].loadStructuredText()).fullText,
        contains('Page 42'),
      );
    },
  );
}
