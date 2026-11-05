// Performance (06-pdf 8 T18, 6.1 V8, 6.11.1): exporting a 500-page PDF note with 200
// strokes of 50 cubic Béziers on every page (100 000 strokes) through the native compose
// backend (FFI on the pdfrx worker isolate, real PDFium) takes at most 30 seconds, and the
// output has the 500 pages, the original text and the ink.
//
// Wall-clock bound on purpose: perf tag, skipped by default
// (`flutter test --run-skipped -t perf test/perf/compose_500_native_test.dart`). Building
// the fixture and checking the output are not timed.
@Tags(['perf'])
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/compose/compose_backend_native.dart'
    show NativePdfComposeBackend, debugNativeComposeJobCount;

import '../support/pdfium_env.dart';
import '../support/perf_compose.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initPdfiumForTests();
    await PdfrxEngine.shared().ensureInitialized();
  });

  test(
    '500 pages × 200 strokes (50 cubics each) on the native backend ≤ 30 s',
    () async {
      final backend = NativePdfComposeBackend();
      addTearDown(backend.dispose);
      final world = await PerfComposeWorld.create(backend);

      final run = await world.export();

      expect(backend.openJobCount, 0);
      expect(await debugNativeComposeJobCount(), 0);
      await expectPerfOutput(PdfrxEngine.shared(), run.result);
      expect(run.elapsed, lessThanOrEqualTo(const Duration(seconds: 30)));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
