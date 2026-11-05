@TestOn('vm')
@Tags(['golden'])
library;

// T20 (03-ink 4.9, 9.2): PenPreviewPainter's S curve for the five pens on
// white paper (pencil with the grain ready), built with the real pipeline.
// Update with: flutter test --update-goldens test/goldens/pen_preview_golden_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:note_core/note_core.dart' as core;

const _row = Size(360, 64);

const _pens = <(core.PenTool, double)>[
  (core.PenTool.ballpoint, 3),
  (core.PenTool.fountain, 5),
  (core.PenTool.highlighter, 16),
  (core.PenTool.pencil, 5),
  (core.PenTool.marker, 6),
];

void main() {
  testWidgets('pen_preview', (tester) async {
    // made and decoded in the real zone (see pens_golden_test)
    final grain = (await tester.runAsync(() async {
      final g = PencilGrain();
      await g.ready;
      return g;
    }))!;
    addTearDown(grain.dispose);
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = Size(_row.width, _row.height * _pens.length);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            child: ColoredBox(
              color: const Color(core.PaperColors.white),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (tool, width) in _pens)
                    CustomPaint(
                      size: _row,
                      painter: PenPreviewPainter(
                        style: core.StrokeStyle.defaultsFor(tool)
                            .copyWith(width: width),
                        pencilGrain: grain,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('pen_preview.png'),
    );
  });
}
