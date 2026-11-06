// Performance (m5-7/06-pdf 6.2.10 · 9.5; 8.2 T29 — P-C): exporting the 50-page object note
// (support/perf_objects.dart — per page four text boxes, a photo, a formula and 200 strokes)
// through the export service v2 and the native compose backend (FFI on the pdfrx worker
// isolate, real PDFium, real NoteSans) takes at most 6 seconds; the output has the 50 pages,
// the text boxes as text and the ledger stays within 16 MiB. The 1차 500-page target is
// perf/compose_500_native_test (unchanged — no objects).
//
// Wall-clock bound on purpose: perf tag, skipped by default
// (`flutter test --run-skipped -t perf test/perf/compose_objects_perf_test.dart`). Building the
// note and checking the output are not timed.
@Tags(['perf'])
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/compose/compose_backend_native.dart'
    show NativePdfComposeBackend, debugNativeComposeJobCount;

import '../support/pdfium_env.dart';
import '../support/perf_objects.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initPdfiumForTests();
    await PdfrxEngine.shared().ensureInitialized();
  });

  test('50 pages × (4 text boxes, photo, formula, 200 strokes) on the native backend ≤ 6 s', () async {
    final backend = NativePdfComposeBackend();
    addTearDown(backend.dispose);
    final world = await ObjectsPerfWorld.create(backend);
    await world.export(); // warm-up: fonts, the worker, the formula port

    final run = await world.export();

    expect(backend.openJobCount, 0);
    expect(await debugNativeComposeJobCount(), 0);
    await expectObjectsPerfOutput(PdfrxEngine.shared(), run);
    expect(run.elapsed, lessThanOrEqualTo(const Duration(seconds: 6)));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
