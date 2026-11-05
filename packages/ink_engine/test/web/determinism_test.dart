@TestOn('browser')
library;

// T06 (03-ink 8, 6.26): the stroke pipeline is deterministic across platforms —
// the FinishedStroke.data checksum of the fixed sample script in Chrome equals
// the value recorded on the VM (test/unit/stroke/stroke_builder_test.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/src/stroke/stroke_builder.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/stroke_scripts.dart';

void main() {
  test('script checksum = the recorded VM value', () {
    expect(scriptChecksum(), recordedScriptChecksum);
  });

  test('buildStroke is repeatable', () {
    final samples = scriptedStroke();
    final style = core.StrokeStyle.defaultsFor(core.PenTool.fountain);
    final a = buildStroke(samples, style: style, viewScale: 1)!;
    final b = buildStroke(samples, style: style, viewScale: 1)!;
    expect(b.data, a.data);
  });
}
