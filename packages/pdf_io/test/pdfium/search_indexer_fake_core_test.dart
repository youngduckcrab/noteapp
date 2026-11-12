// V10's PDF part on CORE's fake store (m5-7/06-pdf 8.2 T29): the scenario of
// integration/search_indexer_core_test.dart (support/search_indexer_core_scenarios.dart — real
// wiring, real PDFium, pdfSearchIndexerProvider, searchPages rects = 1차 searchNote rects) over
// note_core/testing.dart createFakeNoteStore (its memory search index judges and merges as the
// real one — CP-14), so the flow is checked in every run, not only at the integration stage.
@Tags(['pdfium'])
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';

import '../support/pdfium_env.dart';
import '../support/search_indexer_core_scenarios.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initPdfiumForTests();
    await PdfrxEngine.shared().ensureInitialized();
  });

  searchIndexerCoreScenarios(
    () async => core_testing.createFakeNoteStore(),
    real: false,
  );
}
