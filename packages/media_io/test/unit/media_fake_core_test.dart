// The T40 scenarios (m5-7/06-pdf 8.2 T40) on CORE's fake store — the same bodies as
// test/integration/media_real_core_test.dart (real CORE, integration step 4-d), so the recorder
// flow against the store contract is checked in every run: record → stop → asset + row, M-1
// enforced by the store, a draft kept across a reopen → recovered, the empty-chunk keep-alive,
// a purged note → nothing left, audioBytesOf.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import '../support/media_core_scenarios.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mediaCoreScenarios(FakeCoreStores.new);
}
