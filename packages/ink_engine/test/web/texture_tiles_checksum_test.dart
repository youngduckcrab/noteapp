@TestOn('browser')
library;

// (v2.11, C211-01) The texture pens' paper tiles in Chrome are the VM bytes
// (MINSTD streams, box blurs, rank equalization — no bit operations).
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/src/render/pens/texture/texture_tiles.dart';

import '../support/grain_checksum.dart';
import '../support/texture_tile_checksum.dart';

void main() {
  test('tile checksums = the recorded VM values', () {
    expect(byteChecksum(TextureTiles.toothPixels()), recordedToothChecksum);
    expect(byteChecksum(TextureTiles.washPixels()), recordedWashChecksum);
  });
}
