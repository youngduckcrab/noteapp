// Golden comparison for test/goldens only (contract 00-overview 7.4.8: a package may allow
// ≤ 0.5 % in test/flutter_test_config.dart). The goldens are made in the Linux container
// and compared in CI (ubuntu); anti-aliasing may differ by a few pixels between machines.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Largest share of differing pixels that still passes (0.5 %).
const double kGoldenTolerance = 0.005;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final current = goldenFileComparator;
  if (current is LocalFileComparator) {
    goldenFileComparator = _TolerantComparator(
      current.basedir.resolve('md_golden_test.dart'),
    );
  }
  await testMain();
}

final class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= kGoldenTolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
