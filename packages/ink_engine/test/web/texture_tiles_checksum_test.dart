@TestOn('browser')
library;

// (v2.11, C211-01) The texture pens' paper tiles in Chrome are the VM bytes
// (MINSTD streams, box blurs, rank equalization — no bit operations), and
// the geometry noise (two MINSTD tables) gives the VM values.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/src/render/pens/texture/texture_geometry.dart';
import 'package:ink_engine/src/render/pens/texture/texture_tiles.dart';

import '../support/grain_checksum.dart';
import '../support/texture_tile_checksum.dart';

void main() {
  test('tile checksums = the recorded VM values', () {
    expect(byteChecksum(TextureTiles.toothPixels()), recordedToothChecksum);
    expect(byteChecksum(TextureTiles.washPixels()), recordedWashChecksum);
  });

  test('the noise of the texture geometry = the recorded VM values', () {
    var sum = 0.0;
    for (var k = 0; k < 5000; k++) {
      sum += noise01(123456789, k) * (k % 7 + 1);
    }
    expect(sum, recordedNoiseSum);
    expect(noise01(1793750400, 17), recordedNoiseValue);
    expect(strokeSalt(1793750400000), recordedStrokeSalt);
  });
}
