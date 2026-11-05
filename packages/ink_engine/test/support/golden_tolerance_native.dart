// VM: a LocalFileComparator that accepts small anti-aliasing differences
// (03-ink 9.2, contract 7.4.8: diffPercent <= 0.5%).
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replaces the default local golden comparator with [TolerantGoldenComparator].
void installTolerantGoldenComparator(double tolerance) {
  final current = goldenFileComparator;
  if (current is LocalFileComparator) {
    // LocalFileComparator only uses the test file URI to find its directory.
    goldenFileComparator = TolerantGoldenComparator(
      current.basedir.resolve('golden_test.dart'),
      tolerance: tolerance,
    );
  }
}

/// Passes a golden comparison when the fraction of differing pixels is at
/// most [tolerance] (0..1).
class TolerantGoldenComparator extends LocalFileComparator {
  TolerantGoldenComparator(super.testFile, {required this.tolerance});

  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
