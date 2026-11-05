@TestOn('vm')
library;

// T08 (03-ink 8, 6.11): the pencil grain texture — alpha mean 0.75…0.85,
// at least 40 different values, deterministic MINSTD bytes (checksum shared
// with Chrome), no bit operations in the generator.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';

import '../../support/grain_checksum.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('alpha mean 0.75…0.85, ≥ 40 distinct values, white RGB', () {
    final px = PencilGrain.generatePixels();
    const n = InkTuning.grainSize * InkTuning.grainSize;
    expect(px.length, n * 4);
    var sum = 0;
    final values = <int>{};
    for (var i = 0; i < n; i++) {
      expect(px[4 * i], 255);
      expect(px[4 * i + 1], 255);
      expect(px[4 * i + 2], 255);
      final a = px[4 * i + 3];
      sum += a;
      values.add(a);
    }
    final mean = sum / n / 255;
    expect(mean, inInclusiveRange(0.75, 0.85));
    expect(values.length, greaterThanOrEqualTo(40));
    // alpha = round(255 · (0.62 + 0.38 · v)), v ∈ [0, 1)
    expect(values.reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(158));
  });

  test('deterministic: same seed → same bytes = the recorded checksum', () {
    final a = PencilGrain.generatePixels();
    final b = PencilGrain.generatePixels();
    expect(b, a);
    expect(byteChecksum(a), recordedGrainChecksum);
    final other = PencilGrain.generatePixels(seed: InkTuning.grainSeed + 1);
    expect(byteChecksum(other), isNot(recordedGrainChecksum));
  });

  test('MINSTD seed range and arithmetic-only source (7.4.3)', () {
    expect(InkTuning.grainSeed, inInclusiveRange(1, 2147483646));
    final source = File('lib/src/render/pencil_grain.dart').readAsStringSync();
    // strip comments and string literals, then look for bit operators
    final code = source
        .replaceAll(RegExp(r'//[^\n]*'), '')
        .replaceAll(RegExp(r"'[^'\n]*'"), "''")
        .replaceAll('&&', ' ')
        .replaceAll('||', ' ')
        .replaceAll('~/', ' ');
    for (final op in ['<<', '>>', '&', '|', '^', '~']) {
      expect(code.contains(op), isFalse, reason: 'bit operator $op');
    }
  });

  test('the texture becomes a 256×256 image once', () async {
    final grain = PencilGrain();
    addTearDown(grain.dispose);
    final image = await grain.ready;
    expect(image.width, InkTuning.grainSize);
    expect(image.height, InkTuning.grainSize);
    expect(grain.value, same(image));
    expect(await grain.ready, same(image));
  });
}
