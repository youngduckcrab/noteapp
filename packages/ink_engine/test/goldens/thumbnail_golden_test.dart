@TestOn('vm')
@Tags(['golden'])
library;

// T20 (03-ink 6.17, 9.2): the page panel thumbnail of a lined A4 page with
// handwriting, a highlighter and a fountain pen stroke — background from the
// template builder (isThumbnail), strokes rasterized once. 280 px wide, the
// A4 height 396.0004 px is captured as 396 rows (9.2: opaque).
// Update with: flutter test --update-goldens test/goldens/thumbnail_golden_test.dart
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/dev_tools.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/golden_frame.dart';
import '../support/pixels.dart';
import '../support/thumbnails.dart';

const double _width = 280;

void main() {
  testWidgets('thumbnail', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(280, 400);
    addTearDown(tester.view.reset);
    var n = 0;
    final strokes = [
      ...InkDevTools.syntheticStrokes(
        pageId: 'p1',
        pageSize: core.PageSize.a4Portrait,
        count: 120,
        newId: () => 'h${n++}',
        createdAt: 1000,
        seed: 5,
      ),
      strokeThrough(
        segment(const ui.Offset(60, 200), const ui.Offset(520, 210)),
        core.StrokeStyle.defaultsFor(core.PenTool.highlighter),
        id: 'hl',
        createdAt: 5000,
      ),
      strokeThrough(
        segment(const ui.Offset(80, 700), const ui.Offset(500, 620)),
        core.StrokeStyle.defaultsFor(core.PenTool.fountain)
            .copyWith(width: 6, colorArgb: 0xFF1E4FD8),
        id: 'fp',
        createdAt: 5001,
      ),
    ];
    const a4 = core.PageSize.a4Portrait;
    await tester.pumpWidget(
      goldenFrame(
        Size(_width, _width * a4.height / a4.width),
        InkPageThumbnail(
          content: SyntheticInk.pageContent(
            strokes: strokes,
            background: const core.TemplateBackground(
              template: core.PageTemplate(kind: core.PageTemplateKind.lined),
            ),
          ),
          width: _width,
          backgroundBuilders: const [TemplateBackgroundLayerBuilder()],
        ),
      ),
    );
    await settleThumbnails(tester);
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('images/thumbnail.png'),
    );
  });
}
