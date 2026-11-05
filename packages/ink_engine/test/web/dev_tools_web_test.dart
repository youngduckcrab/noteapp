@TestOn('browser')
library;

// T12 (03-ink 8, 4.14, 6.26): InkDevTools.syntheticStrokes gives the same
// points in Chrome as on the VM — the checksum equals the value recorded by
// test/unit/dev_tools_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/dev_tools.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/synthetic_checksum.dart';

void main() {
  test('synthetic stroke checksum = the recorded VM value', () {
    expect(syntheticChecksum(), recordedSyntheticChecksum);
  });

  test('every point stays on the page in Chrome too', () {
    final strokes = InkDevTools.syntheticStrokes(
      pageId: 'p1',
      pageSize: const core.PageSize(72, 72),
      count: 200,
      newId: core.SequentialIdGenerator(prefix: 'w').newId,
      createdAt: 0,
      seed: 21,
    );
    for (final s in strokes) {
      final b = s.points.pointBounds;
      expect(b.left >= 0 && b.top >= 0, isTrue);
      expect(b.right <= 72 && b.bottom <= 72, isTrue);
    }
  });
}
