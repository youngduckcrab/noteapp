@TestOn('browser')
@Tags(['perf'])
library;

// Performance in Chrome (06-pdf 8 T18, 6.1 V8, 6.11.1, 6.11.6): exporting a 500-page PDF
// note with 200 strokes of 50 cubic Béziers on every page (100 000 strokes) through the web
// compose backend (the compose Worker with its own pdfium.wasm) takes at most 40 seconds,
// and the output — reopened with pdfrx wasm — has the 500 pages, the original text and the
// ink.
//
// Wall-clock bound on purpose: perf tag, skipped by default. Run after the web test
// preparation (tool/prepare_web_test.dart copies the PDFium files to test/web/pdfium/):
// `flutter test --platform chrome --run-skipped -t perf test/web/perf_compose_500_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/compose/compose_backend_browser.dart'
    show BrowserPdfComposeBackend;

import '../support/perf_compose.dart';

const PdfIoConfig _config = PdfIoConfig(
  pdfiumWasmModulesUrl: 'pdfium/',
  composeExtensionUrl: 'pdfium/pdf_io_compose_ext.js',
);

void main() {
  final engine = PdfrxEngine.shared();

  setUpAll(() async {
    engine.configure(_config);
    await engine.ensureInitialized();
  });

  test(
    '500 pages × 200 strokes (50 cubics each) on the web backend ≤ 40 s',
    () async {
      final backend = BrowserPdfComposeBackend(_config);
      addTearDown(backend.dispose);
      final world = await PerfComposeWorld.create(backend);

      final run = await world.export();

      expect(backend.openJobCount, 0);
      expect(await backend.debugWorkerJobCount(), 0);
      await expectPerfOutput(engine, run.result);
      expect(run.elapsed, lessThanOrEqualTo(const Duration(seconds: 40)));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
