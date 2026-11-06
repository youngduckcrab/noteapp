@TestOn('vm')
@Tags(['golden'])
library;

// m5-7/03-ink T27 (6.2, 6.3, 9.4): the P1 pens on white paper, built with the
// real stroke pipeline and painted with the page layer painters — one image per
// pen (pens_p1_<pen>.png: an S curve with real pressure above one with
// simulated pressure) and the 'pen preview' sheet (pens_p1_preview.png,
// PenPreviewPainter, S curve and line per pen). T27 has the brush, T29 the
// dashed pen; T28, T30 and T31 add their pen image and preview cells (the
// preview sheet image is updated then).
// Update with: flutter test --update-goldens test/goldens/pens_p1_golden_test.dart
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/render/layer_painters.dart';
import 'package:ink_engine/src/stroke/stroke_builder.dart';
import 'package:note_core/note_core.dart' as core;

/// The P1 pens with their own profile so far: tool, golden width, image name.
const List<(core.PenTool, double, String)> _pens = [
  (core.PenTool.brush, 4, 'brush'),
  (core.PenTool.dashed, 2, 'dashed'), // T29: [4, 3] × 2 pt
];

const double _rowHeight = 70;
const Size _penImage = Size(400, 10 + _rowHeight * 2);
const Size _previewCell = Size(360, 64);

/// An S curve for row [row]; stylus samples with a pressure swell (real) or
/// touch samples with a speed swell (simulated pressure).
List<InkSample> _sCurve(int row, {required bool real}) {
  const n = 160;
  final out = <InkSample>[];
  var timeUs = 0;
  for (var i = 0; i < n; i++) {
    final u = i / (n - 1);
    out.add(
      InkSample(
        position: Offset(
          30 + 340 * u,
          40 + _rowHeight * row + 20 * math.sin(u * 2 * math.pi),
        ),
        timeUs: timeUs,
        kind: real ? InkPointerKind.stylus : InkPointerKind.touch,
        pressure: real ? 0.1 + 0.85 * math.sin(u * math.pi) : null,
        tilt: real ? 0.3 + 0.8 * u : 0,
      ),
    );
    timeUs += real
        ? 8333
        : (4000 + 24000 * (1 - math.sin(u * math.pi))).round();
  }
  return out;
}

/// Row 0 = real pressure, row 1 = simulated pressure.
List<InkStroke> _strokes(core.PenTool tool, double width) => [
  for (final real in [true, false])
    InkStroke.of(
      interop.newCoreStroke(
        buildStroke(
          _sCurve(real ? 0 : 1, real: real),
          style: core.StrokeStyle.defaultsFor(tool).copyWith(width: width),
          viewScale: 1,
        )!,
        id: 'p1-${tool.name}-$real',
        pageId: 'p1',
        penDownMillis: 1000,
      ),
    ),
];

class _PensPainter extends CustomPainter {
  _PensPainter(this.strokes);
  final List<InkStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(core.PaperColors.white),
    );
    paintStrokeLayers(
      canvas,
      strokes,
      paperColorArgb: core.PaperColors.white,
      outlineOf: OutlineGenerator.outline,
      marginPt: 1,
    );
  }

  @override
  bool shouldRepaint(_PensPainter oldDelegate) => true;
}

void main() {
  for (final (tool, width, name) in _pens) {
    testWidgets('pens_p1_$name', (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = _penImage;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            child: CustomPaint(
              size: _penImage,
              painter: _PensPainter(_strokes(tool, width)),
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(RepaintBoundary).first,
        matchesGoldenFile('images/pens_p1_$name.png'),
      );
    });
  }

  testWidgets('pens_p1_preview', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = Size(
        _previewCell.width,
        _previewCell.height * 2 * _pens.length,
      );
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
                  for (final (tool, width, _) in _pens)
                    for (final shape in PenPreviewShape.values)
                      CustomPaint(
                        size: _previewCell,
                        painter: PenPreviewPainter(
                          style: core.StrokeStyle.defaultsFor(tool)
                              .copyWith(width: width),
                          shape: shape,
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
      matchesGoldenFile('images/pens_p1_preview.png'),
    );
  });
}
