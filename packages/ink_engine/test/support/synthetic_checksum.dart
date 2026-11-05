// InkDevTools.syntheticStrokes checksum (03-ink 4.14, 6.26): shared by the VM
// test (test/unit/dev_tools_test.dart) and the browser test
// (test/web/dev_tools_web_test.dart) — the same seed must give the same points
// on both.
import 'package:ink_engine/dev_tools.dart';
import 'package:note_core/note_core.dart' as core;

import 'stroke_scripts.dart' show strokeDataChecksum;

/// The tools the checksum covers (the five M0 pens + one P1 tool).
const List<core.PenTool> syntheticTools = [
  core.PenTool.ballpoint,
  core.PenTool.fountain,
  core.PenTool.highlighter,
  core.PenTool.pencil,
  core.PenTool.marker,
  core.PenTool.brush,
];

/// strokeDataChecksum of every synthetic stroke (A4 portrait, 40 strokes per
/// tool, seed 11; then a 72 pt page where the walk hits the edges), combined
/// with each stroke's createdAt and point count. Arithmetic only.
int syntheticChecksum() {
  const m = 1000000007;
  var sum = 0;
  void add(List<core.Stroke> strokes) {
    for (final s in strokes) {
      sum = (sum * 7 + strokeDataChecksum(s.points.rawData)) % m;
      sum = (sum * 7 + s.createdAt % m) % m;
      sum = (sum * 7 + s.points.length) % m;
    }
  }

  for (final tool in syntheticTools) {
    add(
      InkDevTools.syntheticStrokes(
        pageId: 'p1',
        pageSize: core.PageSize.a4Portrait,
        count: 40,
        newId: core.SequentialIdGenerator(prefix: 'g').newId,
        createdAt: 1700000000000,
        seed: 11,
        tool: tool,
      ),
    );
  }
  add(
    InkDevTools.syntheticStrokes(
      pageId: 'p1',
      pageSize: const core.PageSize(72, 72),
      count: 20,
      newId: core.SequentialIdGenerator(prefix: 'e').newId,
      createdAt: 5,
      seed: 3,
    ),
  );
  return sum;
}

/// syntheticChecksum() recorded on the VM; the browser test expects the same.
const int recordedSyntheticChecksum = 91952586;
