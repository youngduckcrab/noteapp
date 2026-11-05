// T01 (03-ink 8): the package skeleton. The three entry points compile together on
// the VM, the test configuration installs the tolerant golden comparator (9.2),
// and the shared constants are reachable through the public API.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/dev_tools.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../flutter_test_config.dart' show goldenDiffTolerance;
import '../support/golden_tolerance_native.dart';

void main() {
  test('flutter_test_config installs the 0.5% golden comparator', () {
    final comparator = goldenFileComparator;
    expect(comparator, isA<TolerantGoldenComparator>());
    expect((comparator as TolerantGoldenComparator).tolerance, 0.005);
    expect(goldenDiffTolerance, 0.005);
    // Golden keys still resolve next to the test file.
    expect(comparator.basedir.path, endsWith('/test/unit/'));
  });

  test('public, testing and dev_tools entry points work together', () {
    final page = SyntheticInk.page();
    final ids = core.SequentialIdGenerator(prefix: 'k');
    final strokes = InkDevTools.syntheticStrokes(
      pageId: page.id,
      pageSize: page.size,
      count: 2,
      newId: ids.newId,
      createdAt: 1000,
      seed: 7,
    );
    expect(strokes, hasLength(2));
    final content = InkPageContent.fromCore(
      page: page,
      strokes: strokes,
      revision: 1,
    );
    expect(content.strokes, hasLength(2));
    expect(InkRenderConfig.platformDefault, InkRenderConfig.nativeDefaults);
    expect(InkTuning.liveChunkPoints, 64);
    expect(core.StrokeStyle.minWidth, 0.1);
  });
}
