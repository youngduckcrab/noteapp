@Tags(['perf'])
@TestOn('browser')
library;

// Performance in Chrome (m5-7/06-pdf 6.2.10 · 9.5; 8.2 T29 — P-C): the 50-page object note of
// support/perf_objects.dart (per page four text boxes, a photo, a formula and 200 strokes)
// exported through the export service v2 and the compose Worker (pdfium.wasm +
// pdf_io_compose_ext.js from test/web/pdfium/) in at most 15 seconds, with the INK test font
// (setUpAll(useInkTestFonts) — the text box lines are inside its characters, C23-07). perf tag,
// skipped by default (`ws test --package pdf_io --platform chrome --run-skipped -t perf`).
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/testing.dart' as ink;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/compose/compose_backend_browser.dart'
    show BrowserPdfComposeBackend;

import '../support/perf_objects.dart';

const PdfIoConfig _config = PdfIoConfig(
  pdfiumWasmModulesUrl: 'pdfium/',
  composeExtensionUrl: 'pdfium/pdf_io_compose_ext.js',
);

void main() {
  setUpAll(() async {
    await ink.useInkTestFonts();
    PdfrxEngine.shared().configure(_config);
    await PdfrxEngine.shared().ensureInitialized();
  });

  test('50 pages × (4 text boxes, photo, formula, 200 strokes) on the compose Worker ≤ 15 s', () async {
    final backend = BrowserPdfComposeBackend(_config);
    addTearDown(backend.dispose);
    final world = await ObjectsPerfWorld.create(backend);
    await world.export(); // warm-up: the Worker's wasm, the fonts

    final run = await world.export();

    expect(backend.openJobCount, 0);
    await expectObjectsPerfOutput(PdfrxEngine.shared(), run);
    expect(run.elapsed, lessThanOrEqualTo(const Duration(seconds: 15)));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
