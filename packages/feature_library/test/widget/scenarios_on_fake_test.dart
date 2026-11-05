// Shared LIBRARY scenarios on CORE's fake store (05-library 5.7, 8 L0). The
// same list runs on real CORE in integration/core_contract_test.dart (L21,
// needsFaults == false only).
import 'package:flutter_test/flutter_test.dart';

import '../shared/library_scenarios.dart';
import '../support/fake_library_backend.dart';
import '../support/library_test_harness.dart';

void main() {
  for (final scenario in libraryScenarios) {
    testWidgets(scenario.name, (tester) async {
      final backend = FakeLibraryBackend();
      addTearDown(backend.dispose);
      await scenario.body(tester, LibraryTestHarness(backend));
    });
  }
}
