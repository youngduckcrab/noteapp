// V10's PDF part on CORE's REAL store (m5-7/06-pdf 8.3 4-a; 8.2 T29): the real wiring
// (support/real_wiring.dart over note_core/testing_vm.dart openTestNoteStore) imports a PDF,
// pdfSearchIndexerProvider indexes it and searchPages' rects match the 1차 searchNote rects
// (support/search_indexer_core_scenarios.dart). Integration stage only (`ws test --run-skipped
// -t integration --package pdf_io`). pdfium/search_indexer_fake_core_test.dart runs the same
// scenario on CORE's fake store.
@Tags(['integration'])
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/testing_vm.dart' as core_vm;
import 'package:pdf_io/pdf_io.dart';

import '../support/pdfium_env.dart';
import '../support/search_indexer_core_scenarios.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initPdfiumForTests();
    await PdfrxEngine.shared().ensureInitialized();
  });

  searchIndexerCoreScenarios(core_vm.openTestNoteStore, real: true);
}
