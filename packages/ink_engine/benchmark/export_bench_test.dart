// B9 vector export, B10 thumbnail render (03-ink 9.1, T22).
// Run: flutter test benchmark/.
@Tags(['bench'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import 'support/bench.dart';
import 'support/workloads.dart';

void main() {
  test('B9 vector export: 2000 strokes', () {
    final strokes = [for (final s in mixedPage(2000)) InkStroke.of(s)];
    late InkPageVectors vectors;
    final stats = measure(
      () => vectors = InkVectorExport.exportStrokes(strokes),
      warmup: 3,
      runs: 12,
    );
    final lines = vectors.highlighterGroups.fold(
      0,
      (n, g) => n + g.lines.length,
    );
    expect(vectors.inkShapes.length + lines, 2000);
    report(
      'B9',
      'vector export 2000 strokes (80% ballpoint, 10% fountain, '
          '10% highlighter)',
      stats,
      criteria: {'median_ms': 300},
      extra: {'fill_shapes': vectors.inkShapes.length, 'lines': lines},
    );
  });

  test('B10 thumbnail: 3000 strokes, 512 px PNG (yields included)', () async {
    final page = SyntheticInk.page(
      background: const core.TemplateBackground(
        template: core.PageTemplate(kind: core.PageTemplateKind.lined),
      ),
    );
    final strokes = mixedPage(3000);
    final renderer = InkPageThumbnailRenderer(
      backgroundBuilders: const [TemplateBackgroundLayerBuilder()],
    );
    core.PageThumbnail? thumb;
    final stats = await measureAsync(
      () async => thumb = await renderer.render(
        core.PageContent(page: page, strokes: strokes, revision: 1),
      ),
      warmup: 2,
      runs: 8,
    );
    expect(thumb, isNotNull);
    expect(thumb!.width, lessThanOrEqualTo(512));
    expect(thumb!.height, 512);
    expect(thumb!.bytes.sublist(1, 4), 'PNG'.codeUnits);
    report(
      'B10',
      'thumbnail 3000 strokes, 512 px PNG',
      stats,
      criteria: {'median_ms': 600},
      extra: {'png_bytes': thumb!.bytes.length},
    );
  });
}
