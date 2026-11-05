// Import with the real PdfrxEngine (06-pdf 6.3–6.5, 8 T5) + FakePdfNoteGateway: page sizes of
// a mixed / rotated PDF, user-password PDFs stored as a decrypted copy, permission-password
// PDFs stored byte for byte.
@Tags(['pdfium'])
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

import '../support/pdfium_env.dart';
import '../support/render_doubles.dart';

final PdfrxEngine _engine = PdfrxEngine.shared();

final class _Import {
  final FakePdfNoteGateway gateway = FakePdfNoteGateway();
  final RecordingDocumentPool pool = RecordingDocumentPool();
  late final DefaultPdfImportService service = DefaultPdfImportService(
    engine: _engine,
    gateway: gateway,
    pool: pool,
    renderer: SolidThumbnailRenderer(),
    config: const PdfIoConfig(),
  );

  /// Closes what the pool adopted (the real pool does that in T7).
  Future<void> close() async {
    for (final (_, document) in pool.adopted) {
      await document.dispose();
    }
  }
}

Future<PdfImportResult> _import(
  _Import im,
  Uint8List bytes, {
  PdfPasswordCallback? onPassword,
}) async {
  final session = await im.service.open(
    PickedPdfFile.fromBytes('fixture.pdf', bytes),
    onPassword: onPassword,
  );
  try {
    return await session.commit(const PdfImportAsNewNote());
  } finally {
    await session.dispose();
  }
}

void main() {
  setUpAll(() async {
    await initPdfiumForTests();
    await _engine.ensureInitialized();
  });

  test('mixed sizes and a rotated page → note page sizes (6.5)', () async {
    final bytes =
        (PdfFixtureBuilder()
              ..addPage(const PdfFixturePage()) // A4
              ..addPage(
                const PdfFixturePage(width: 612, height: 792, rotate: 90),
              )
              ..addPage(const PdfFixturePage(width: 50, height: 50)))
            .build();
    final im = _Import();
    addTearDown(im.close);
    final result = await _import(im, bytes);
    final pages = await im.gateway.pagesOf(result.noteId);
    expect(
      [for (final p in pages) p.size],
      const [
        core.PageSize(595.276, 841.89),
        core.PageSize(792, 612), // /Rotate 90 swaps the displayed size
        core.PageSize(72, 72), // short side < 72 → scaled up uniformly
      ],
    );
    expect(
      [
        for (final p in pages)
          (p.background as core.PdfBackground).pdfPageIndex,
      ],
      [0, 1, 2],
    );
    expect(result.sourcePageCount, 3);
    expect(result.storedDecryptedCopy, isFalse);
    expect(await im.gateway.readAssetBytes(result.assetId), bytes);
    // The real engine document went to the pool, still open.
    final (id, document) = im.pool.adopted.single;
    expect(id, result.assetId);
    expect(document.isDisposed, isFalse);
    expect(document.info.pageCount, 3);
  });

  test(
    'user password → decrypted copy that opens without a password',
    () async {
      final bytes =
          (PdfFixtureBuilder()
                ..addPage(
                  const PdfFixturePage(
                    texts: [PdfFixtureText('Secret page', x: 72, y: 100)],
                  ),
                )
                ..encrypt(userPassword: 'pw1234'))
              .build();
      final im = _Import();
      addTearDown(im.close);
      final attempts = <int>[];
      final result = await _import(
        im,
        bytes,
        onPassword: (request) async {
          attempts.add(request.attempt);
          return request.attempt == 1 ? 'wrong' : 'pw1234';
        },
      );
      expect(attempts, [1, 2]);
      expect(result.storedDecryptedCopy, isTrue);
      expect(im.pool.adopted, isEmpty); // closed; the pool opens the copy later
      final stored = (await im.gateway.readAssetBytes(result.assetId))!;
      expect(stored, isNot(equals(bytes)));
      var asked = 0;
      final reopened = await _engine.open(
        stored,
        sourceName: 'test:import-decrypted',
        onPassword: (_) async {
          asked++;
          return null;
        },
      );
      addTearDown(reopened.dispose);
      expect(asked, 0);
      expect(reopened.info.usedPassword, isFalse);
      expect(reopened.info.isEncrypted, isFalse);
      final text = await reopened.loadText(0);
      expect(text.text, contains('Secret page'));
    },
  );

  test('permission password only → no prompt, original bytes stored', () async {
    final bytes =
        (PdfFixtureBuilder()
              ..addPage(const PdfFixturePage())
              ..encrypt(userPassword: ''))
            .build();
    final im = _Import();
    addTearDown(im.close);
    var asked = 0;
    final result = await _import(
      im,
      bytes,
      onPassword: (_) async {
        asked++;
        return null;
      },
    );
    expect(asked, 0);
    expect(result.storedDecryptedCopy, isFalse);
    expect(await im.gateway.readAssetBytes(result.assetId), bytes);
    expect(im.pool.adopted.single.$2.info.isEncrypted, isTrue);
  });
}
