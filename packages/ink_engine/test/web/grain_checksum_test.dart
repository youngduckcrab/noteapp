@TestOn('browser')
library;

// T08 (03-ink 8, 6.11, 9.1): the pencil grain bytes in Chrome are the VM bytes
// (arithmetic MINSTD, no bit operations) and decode into the texture.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';

import '../support/grain_checksum.dart';

void main() {
  test('grain checksum = the recorded VM value', () {
    expect(byteChecksum(PencilGrain.generatePixels()), recordedGrainChecksum);
  });
}
