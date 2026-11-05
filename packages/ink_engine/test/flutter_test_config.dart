// Test configuration for every test under test/ (03-ink 9.2): on the VM, golden
// comparisons pass when at most 0.5% of the pixels differ (contract 7.4.8). The
// browser variant leaves the comparator alone (Chrome tests use no goldens).
import 'dart:async';

import 'support/golden_tolerance.dart';

/// Golden images may differ in at most this fraction of pixels (0.5%).
const double goldenDiffTolerance = 0.005;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  installTolerantGoldenComparator(goldenDiffTolerance);
  await testMain();
}
