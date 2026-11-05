@TestOn('browser')
library;

// PdfrxEngine over pdfrx wasm in Chrome (06-pdf 8 T3): open, render, text, password. Uses
// the assets tool/prepare_web_test.dart copied to test/web/pdfium/ (9.1).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

final PdfrxEngine _engine = PdfrxEngine.shared();
var _docs = 0;

Future<PdfEngineDocument> _open(
  Uint8List bytes, {
  PdfPasswordCallback? onPassword,
}) async {
  final doc = await _engine.open(
    bytes,
    sourceName: 'web:engine-${_docs++}',
    onPassword: onPassword,
  );
  addTearDown(doc.dispose);
  return doc;
}

void main() {
  setUpAll(() async {
    _engine.configure(
      const PdfIoConfig(
        pdfiumWasmModulesUrl: 'pdfium/',
        composeExtensionUrl: 'pdfium/pdf_io_compose_ext.js',
      ),
    );
    await _engine.ensureInitialized();
  });

  test('open: info with rotation', () async {
    final doc = await _open(
      (PdfFixtureBuilder()
            ..addPage(const PdfFixturePage(width: 400, height: 300))
            ..addPage(
              const PdfFixturePage(width: 400, height: 300, rotate: 90),
            ))
          .build(),
    );
    expect(_engine.isInitialized, isTrue);
    expect(doc.info.pageCount, 2);
    expect(doc.info.pages[1].width, closeTo(300, 1e-3));
    expect(doc.info.pages[1].rotationQuarterTurns, 1);
  });

  test('render: whole page and a region', () async {
    final doc = await _open(
      (PdfFixtureBuilder()..addPage(
            const PdfFixturePage(
              width: 400,
              height: 300,
              texts: [PdfFixtureText('HHHH', x: 100, y: 80, size: 40)],
            ),
          ))
          .build(),
    );
    final page = (await doc.render(
      const PdfRenderRequest(pageIndex: 0, scale: 1),
    ))!;
    addTearDown(page.dispose);
    expect(page.width, 400);
    expect(page.height, 300);
    final tile = (await doc.render(
      const PdfRenderRequest(
        pageIndex: 0,
        scale: 2,
        region: PdfPixelRect(192, 96, 128, 64),
      ),
    ))!;
    addTearDown(tile.dispose);
    expect(tile.width, 128);
    expect(tile.height, 64);
    final data = (await tile.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var dark = 0;
    for (var i = 0; i < data.lengthInBytes; i += 4) {
      if (data.getUint8(i) < 100 && data.getUint8(i + 1) < 100) dark++;
    }
    expect(dark, greaterThan(200));
  });

  test('text: char rects in displayed pt, Korean through ToUnicode', () async {
    final doc = await _open(
      (PdfFixtureBuilder()..addPage(
            const PdfFixturePage(
              width: 400,
              height: 300,
              rotate: 90,
              texts: [
                PdfFixtureText('HHHH', x: 100, y: 80, size: 40),
                PdfFixtureText('강의', x: 40, y: 200, mapped: true),
              ],
            ),
          ))
          .build(),
    );
    final text = await doc.loadText(0);
    expect(text.text, contains('HHHH'));
    expect(text.text, contains('강의'));
    expect(text.charRects, hasLength(text.text.length));
    final h = text.charRects[text.text.indexOf('H')];
    expect(h.left, closeTo(100, 6));
    expect(h.bottom, closeTo(80, 3));
  });

  test('password: wrong once, then right; permission-only opens', () async {
    final locked =
        (PdfFixtureBuilder()
              ..addPage(const PdfFixturePage(texts: [PdfFixtureText('Secret')]))
              ..encrypt(userPassword: 'pw'))
            .build();
    final attempts = <int>[];
    final doc = await _open(
      locked,
      onPassword: (r) async {
        attempts.add(r.attempt);
        return r.attempt == 1 ? 'wrong' : 'pw';
      },
    );
    expect(attempts, [1, 2]);
    expect(doc.info.usedPassword, isTrue);
    expect((await doc.loadText(0)).text, contains('Secret'));
    await expectLater(
      _engine.open(
        locked,
        sourceName: 'web:none',
        onPassword: (_) async => null,
      ),
      throwsA(
        isA<PdfIoException>().having(
          (e) => e.code,
          'code',
          PdfErrorCode.passwordCancelled,
        ),
      ),
    );

    final permissionOnly = await _open(
      (PdfFixtureBuilder()
            ..addPage(const PdfFixturePage())
            ..encrypt(userPassword: ''))
          .build(),
      onPassword: (_) async => fail('no password needed'),
    );
    expect(permissionOnly.info.isEncrypted, isTrue);
    expect(permissionOnly.info.usedPassword, isFalse);
  });
}
