// PdfrxEngine on real PDFium (06-pdf 4.3, 8 T3): info, rotated sizes, render regions and
// cancel, password retries and limit, permission-only PDFs, char rects in displayed pt,
// re-encoding without security, '%PDF-' check.
@Tags(['pdfium'])
@TestOn('vm')
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

import '../support/pdfium_env.dart';

final PdfrxEngine _engine = PdfrxEngine.shared();
var _docs = 0;

Future<PdfEngineDocument> _open(
  Uint8List bytes, {
  PdfPasswordCallback? onPassword,
  int maxPasswordAttempts = 5,
}) async {
  final doc = await _engine.open(
    bytes,
    sourceName: 'test:engine-${_docs++}',
    fileName: 'fixture.pdf',
    onPassword: onPassword,
    maxPasswordAttempts: maxPasswordAttempts,
  );
  addTearDown(doc.dispose);
  return doc;
}

Matcher _code(PdfErrorCode code) =>
    isA<PdfIoException>().having((e) => e.code, 'code', code);

/// Number of dark pixels (all channels < 100) in [image] inside [x0, x1) × [y0, y1).
Future<int> _dark(
  ui.Image image, {
  int x0 = 0,
  int y0 = 0,
  int? x1,
  int? y1,
}) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  var count = 0;
  for (var y = y0; y < (y1 ?? image.height); y++) {
    for (var x = x0; x < (x1 ?? image.width); x++) {
      final i = (y * image.width + x) * 4;
      if (data.getUint8(i) < 100 &&
          data.getUint8(i + 1) < 100 &&
          data.getUint8(i + 2) < 100) {
        count++;
      }
    }
  }
  return count;
}

Uint8List _textPage({int rotate = 0}) =>
    (PdfFixtureBuilder()..addPage(
          PdfFixturePage(
            width: 400,
            height: 300,
            rotate: rotate,
            texts: const [PdfFixtureText('HHHH', x: 100, y: 80, size: 40)],
          ),
        ))
        .build();

void main() {
  setUpAll(() async {
    await initPdfiumForTests();
    await _engine.ensureInitialized();
  });

  test('ensureInitialized is idempotent', () async {
    expect(_engine.isInitialized, isTrue);
    await _engine.ensureInitialized();
    expect(identical(PdfrxEngine.shared(), _engine), isTrue);
  });

  test('info: page sizes, rotation swaps the displayed size', () async {
    final doc = await _open(
      (PdfFixtureBuilder()
            ..addPage(const PdfFixturePage())
            ..addPage(const PdfFixturePage(width: 400, height: 300, rotate: 90))
            ..addPage(
              const PdfFixturePage(
                mediaBox: [0, 0, 612, 792],
                cropBox: [36, 72, 576, 756],
                rotate: 270,
              ),
            ))
          .build(),
    );
    final info = doc.info;
    expect(info.pageCount, 3);
    expect(info.isEncrypted, isFalse);
    expect(info.usedPassword, isFalse);
    expect(doc.sourceName, startsWith('test:engine-'));
    expect(info.pages[0].index, 0);
    expect(info.pages[0].width, closeTo(595.2756, 1e-3));
    expect(info.pages[0].rotationQuarterTurns, 0);
    expect(info.pages[1].width, closeTo(300, 1e-3));
    expect(info.pages[1].height, closeTo(400, 1e-3));
    expect(info.pages[1].rotationQuarterTurns, 1);
    expect(info.pages[2].width, closeTo(684, 1e-3));
    expect(info.pages[2].height, closeTo(540, 1e-3));
    expect(info.pages[2].rotationQuarterTurns, 3);
  });

  test("bytes without '%PDF-' → notPdf, broken PDF → corrupt", () async {
    await expectLater(
      _engine.open(Uint8List.fromList('hello'.codeUnits), sourceName: 'x'),
      throwsA(_code(PdfErrorCode.notPdf)),
    );
    final late = Uint8List(2000)..setAll(1500, '%PDF-1.4'.codeUnits);
    await expectLater(
      _engine.open(late, sourceName: 'x'),
      throwsA(_code(PdfErrorCode.notPdf)),
    );
    final broken = Uint8List.fromList(
      '%PDF-1.4\n garbage, no objects'.codeUnits,
    );
    await expectLater(
      _engine.open(broken, sourceName: 'x-broken'),
      throwsA(_code(PdfErrorCode.corrupt)),
    );
  });

  test('render: whole page at scale 2, glyphs where the text is', () async {
    final doc = await _open(_textPage());
    final image = (await doc.render(
      const PdfRenderRequest(pageIndex: 0, scale: 2),
    ))!;
    addTearDown(image.dispose);
    expect(image.width, 800);
    expect(image.height, 600);
    // Text box: x 100.., baseline y 80, cap height ≈ 29 → pixels (200.., 102..160).
    expect(
      await _dark(image, x0: 200, y0: 100, x1: 400, y1: 160),
      greaterThan(500),
    );
    expect(await _dark(image, y0: 200), 0);
  });

  test('render: a region is a tile of the full page', () async {
    final doc = await _open(_textPage());
    final textTile = (await doc.render(
      const PdfRenderRequest(
        pageIndex: 0,
        scale: 2,
        region: PdfPixelRect(192, 96, 128, 64),
      ),
    ))!;
    addTearDown(textTile.dispose);
    expect(textTile.width, 128);
    expect(textTile.height, 64);
    expect(await _dark(textTile), greaterThan(200));

    final emptyTile = (await doc.render(
      const PdfRenderRequest(
        pageIndex: 0,
        scale: 2,
        region: PdfPixelRect(512, 384, 128, 128),
      ),
    ))!;
    addTearDown(emptyTile.dispose);
    expect(await _dark(emptyTile), 0);
  });

  test('render: background color, cancel before and during → null', () async {
    final doc = await _open(_textPage());
    final blue = (await doc.render(
      const PdfRenderRequest(
        pageIndex: 0,
        scale: 0.5,
        region: PdfPixelRect(0, 0, 8, 8),
        backgroundArgb: 0xFF0000FF,
      ),
    ))!;
    addTearDown(blue.dispose);
    final px = (await blue.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    expect([px.getUint8(0), px.getUint8(1), px.getUint8(2)], [0, 0, 255]);

    final before = PdfRenderCancelToken()..cancel();
    expect(
      await doc.render(
        const PdfRenderRequest(pageIndex: 0, scale: 2),
        cancelToken: before,
      ),
      isNull,
    );
    final during = PdfRenderCancelToken();
    final pending = doc.render(
      const PdfRenderRequest(pageIndex: 0, scale: 4),
      cancelToken: during,
    );
    during.cancel();
    expect(await pending, isNull);
  });

  test('user password: wrong once, then right', () async {
    final bytes =
        (PdfFixtureBuilder()
              ..addPage(const PdfFixturePage(texts: [PdfFixtureText('Secret')]))
              ..encrypt(userPassword: 'pw1234'))
            .build();
    final requests = <PdfPasswordRequest>[];
    final doc = await _open(
      bytes,
      onPassword: (r) async {
        requests.add(r);
        return r.attempt == 1 ? 'wrong' : 'pw1234';
      },
    );
    expect(requests.map((r) => r.attempt), [1, 2]);
    expect(requests.first.fileName, 'fixture.pdf');
    expect(doc.info.isEncrypted, isTrue);
    expect(doc.info.usedPassword, isTrue);
    expect((await doc.loadText(0)).text, contains('Secret'));
  });

  test(
    'more than maxPasswordAttempts wrong answers → passwordCancelled',
    () async {
      final bytes =
          (PdfFixtureBuilder()
                ..addPage(const PdfFixturePage())
                ..encrypt(userPassword: 'pw1234'))
              .build();
      var calls = 0;
      await expectLater(
        _engine.open(
          bytes,
          sourceName: 'test:attempts',
          onPassword: (_) async {
            calls++;
            return 'wrong';
          },
        ),
        throwsA(_code(PdfErrorCode.passwordCancelled)),
      );
      expect(calls, 5);
      await expectLater(
        _engine.open(
          bytes,
          sourceName: 'test:give-up',
          onPassword: (_) async => null,
        ),
        throwsA(_code(PdfErrorCode.passwordCancelled)),
      );
      await expectLater(
        _engine.open(bytes, sourceName: 'test:no-callback'),
        throwsA(_code(PdfErrorCode.passwordCancelled)),
      );
    },
  );

  test('permission password: opens without the callback', () async {
    final bytes =
        (PdfFixtureBuilder()
              ..addPage(
                const PdfFixturePage(texts: [PdfFixtureText('Open text')]),
              )
              ..encrypt(userPassword: ''))
            .build();
    var calls = 0;
    final doc = await _open(
      bytes,
      onPassword: (_) async {
        calls++;
        return null;
      },
    );
    expect(calls, 0);
    expect(doc.info.isEncrypted, isTrue);
    expect(doc.info.usedPassword, isFalse);
    expect((await doc.loadText(0)).text, contains('Open text'));
  });

  for (final rotate in [0, 90]) {
    test('charRects in displayed pt, y down (rotation $rotate)', () async {
      final doc = await _open(_textPage(rotate: rotate));
      final text = await doc.loadText(0);
      expect(text.pageIndex, 0);
      expect(text.text, contains('HHHH'));
      expect(text.charRects, hasLength(text.text.length));
      final first = text.charRects[text.text.indexOf('H')];
      // 'H' at display (100, 80), size 40: x 100..~129, cap top ≈ 80 − 29.
      expect(first.left, closeTo(100, 6));
      expect(first.bottom, closeTo(80, 3));
      expect(first.top, inInclusiveRange(45, 60));
      expect(first.width, inInclusiveRange(20, 35));
      final last = text.charRects[text.text.lastIndexOf('H')];
      expect(last.left, greaterThan(first.left + 60));
      expect(last.bottom, closeTo(80, 3));
    });
  }

  test('mapped Korean text: one rect per code unit', () async {
    final doc = await _open(
      (PdfFixtureBuilder()..addPage(
            const PdfFixturePage(
              texts: [PdfFixtureText('강의 자료', x: 72, y: 100, mapped: true)],
            ),
          ))
          .build(),
    );
    final text = await doc.loadText(0);
    final at = text.text.indexOf('강의');
    expect(at, greaterThanOrEqualTo(0));
    expect(text.charRects, hasLength(text.text.length));
    final rect = text.charRects[at];
    expect(rect.left, closeTo(72, 6));
    expect(rect.bottom, closeTo(100, 4));
  });

  test('encodeWithoutSecurity: the copy opens without a password', () async {
    final bytes =
        (PdfFixtureBuilder()
              ..addPage(
                const PdfFixturePage(texts: [PdfFixtureText('Kept text')]),
              )
              ..encrypt(userPassword: 'pw'))
            .build();
    final doc = await _open(bytes, onPassword: (_) async => 'pw');
    final plain = await doc.encodeWithoutSecurity();
    var asked = 0;
    final reopened = await _open(
      plain,
      onPassword: (_) async {
        asked++;
        return null;
      },
    );
    expect(asked, 0);
    expect(reopened.info.isEncrypted, isFalse);
    expect((await reopened.loadText(0)).text, contains('Kept text'));
  });

  test('dispose is idempotent; a disposed document renders nothing', () async {
    final doc = await _engine.open(_textPage(), sourceName: 'test:dispose');
    expect(doc.isDisposed, isFalse);
    await doc.dispose();
    await doc.dispose();
    expect(doc.isDisposed, isTrue);
    expect(
      await doc.render(const PdfRenderRequest(pageIndex: 0, scale: 1)),
      isNull,
    );
    expect(() => doc.loadText(0), throwsStateError);
  });
}
