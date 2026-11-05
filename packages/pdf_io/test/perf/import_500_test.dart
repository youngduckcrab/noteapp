// Performance (06-pdf 8 T18, 6.3): opening a 500-page PDF and reading its information on
// the real PDFium (VM) takes at most 2 seconds — the engine alone (open + every page size)
// and the import session the sheet shows (file read, %PDF- check, open, info, title).
//
// Wall-clock bound on purpose: perf tag, skipped by default
// (`flutter test --run-skipped -t perf test/perf/import_500_test.dart`). The fixture is built
// in the test (PdfFixtureBuilder, no file committed) and is not timed.
@Tags(['perf'])
@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

import '../support/pdfium_env.dart';
import '../support/render_doubles.dart';

const int _pages = 500;
const Duration _limit = Duration(seconds: 2);

/// 500 pages: mostly A4 portrait with a line of text, every 10th page US Letter landscape
/// (a /Rotate 90 page), every 25th page A3 — so the info has more than one size.
Uint8List _fixture() =>
    (PdfFixtureBuilder()..addPages(_pages, (i) {
          final texts = [PdfFixtureText('Lecture page ${i + 1}')];
          if (i % 25 == 24) {
            return PdfFixturePage(width: 841.89, height: 1190.55, texts: texts);
          }
          if (i % 10 == 9) {
            return PdfFixturePage(
              width: 612,
              height: 792,
              rotate: 90,
              texts: texts,
            );
          }
          return PdfFixturePage(texts: texts);
        }))
        .build();

void _report(String what, Duration elapsed, int bytes) => debugPrint(
  'perf $what: ${elapsed.inMilliseconds} ms '
  '($_pages pages, ${(bytes / 1024).round()} KiB)',
);

void _expectInfo(PdfDocumentInfo info) {
  expect(info.pageCount, _pages);
  expect(info.pages[0].width, closeTo(595.28, 0.01));
  expect(info.pages[9].width, closeTo(792, 0.01)); // rotated Letter
  expect(info.pages[9].rotationQuarterTurns, 1);
  expect(info.pages[24].height, closeTo(1190.55, 0.01)); // A3
  expect(info.pages.last.index, _pages - 1);
  expect(info.isEncrypted, isFalse);
}

void main() {
  late Uint8List bytes;

  setUpAll(() async {
    await initPdfiumForTests();
    await PdfrxEngine.shared().ensureInitialized();
    bytes = _fixture();
    // Warm-up (first open loads PDFium code paths); not part of the measurement.
    final warm = await PdfrxEngine.shared().open(
      (PdfFixtureBuilder()..addPage(const PdfFixturePage())).build(),
      sourceName: 'warm-up',
    );
    await warm.dispose();
  });

  test('engine: open + page information of 500 pages ≤ 2 s', () async {
    final watch = Stopwatch()..start();
    final document = await PdfrxEngine.shared().open(
      Uint8List.fromList(bytes),
      sourceName: 'perf-500',
      fileName: 'lecture-500.pdf',
    );
    final info = document.info;
    var area = 0.0; // touch every page's size
    for (final page in info.pages) {
      area += page.width * page.height;
    }
    watch.stop();
    addTearDown(document.dispose);

    _report('engine open+info', watch.elapsed, bytes.length);
    expect(area, greaterThan(0));
    _expectInfo(info);
    expect(watch.elapsed, lessThanOrEqualTo(_limit));
  });

  test(
    'import session: read + check + open + info of 500 pages ≤ 2 s',
    () async {
      final service = DefaultPdfImportService(
        engine: PdfrxEngine.shared(),
        gateway: FakePdfNoteGateway(),
        pool: RecordingDocumentPool(),
        renderer: SolidThumbnailRenderer(),
        config: const PdfIoConfig(),
      );
      final watch = Stopwatch()..start();
      final session = await service.open(
        PickedPdfFile.fromBytes('강의 자료 500.pdf', Uint8List.fromList(bytes)),
      );
      final info = session.info;
      final title = session.suggestedTitle;
      watch.stop();
      addTearDown(session.dispose);

      _report('import session open', watch.elapsed, bytes.length);
      _expectInfo(info);
      expect(title, '강의 자료 500');
      expect(session.byteLength, bytes.length);
      expect(watch.elapsed, lessThanOrEqualTo(_limit));
    },
  );
}
