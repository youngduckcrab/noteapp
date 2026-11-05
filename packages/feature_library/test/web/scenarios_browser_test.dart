// The shared LIBRARY scenarios on dart2js (05-library 8 L20): the same list
// as widget/scenarios_on_fake_test.dart (VM) over CORE's web-safe fake store —
// among them the new note defaults stored in the settings and read back (on
// the web 148.0 is also an int), the custom order, the 200-character copy
// name and NFD title search.
@TestOn('browser')
library;

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
