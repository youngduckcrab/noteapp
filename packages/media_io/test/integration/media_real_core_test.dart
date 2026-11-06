// T40 on CORE's REAL store (m5-7/06-pdf 8.2 T40 — judged at integration step 4-d:
// `ws test --run-skipped -t integration --package media_io`). The scenarios are in
// test/support/media_core_scenarios.dart (openTestNoteStore on a file, a fake engine); until
// CORE T30/T31 they skip themselves at run time. test/unit/media_fake_core_test.dart runs the
// same bodies on CORE's fake store in every run.
@Tags(['integration'])
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import '../support/media_core_scenarios.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mediaCoreScenarios(FileCoreStores.new, real: true);
}
