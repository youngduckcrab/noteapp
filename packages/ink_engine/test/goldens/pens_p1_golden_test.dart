@TestOn('vm')
@Tags(['golden'])
library;

// m5-7/03-ink T27 (6.2, 6.3, 9.4): the P1 pens on white paper, built with the
// real stroke pipeline and painted with the page layer painters — one image per
// pen (pens_p1_<pen>.png: an S curve with real pressure above one with
// simulated pressure) and the 'pen preview' sheet (pens_p1_preview.png,
// PenPreviewPainter, S curve and line per pen). T27 has the brush, T29 the
// dashed pen; T31 the tape (pens_p1_tape.png: covered, striped and revealed
// over a written line — the cover layer's three looks — and two preview cells,
// the line striped); T28 and T30 add their pen image and preview cells (the
// preview sheet image is updated then).
// Update with: flutter test --update-goldens test/goldens/pens_p1_golden_test.dart
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/render/layer_painters.dart';
import 'package:ink_engine/src/render/tape_painter.dart';
import 'package:ink_engine/src/stroke/stroke_builder.dart';
import 'package:note_core/note_core.dart' as core;

/// The P1 pens with their own profile so far: tool, golden width, image name.
const List<(core.PenTool, double, String)> _pens = [
  (core.PenTool.brush, 4, 'brush'),
  (core.PenTool.dashed, 2, 'dashed'), // T29: [4, 3] × 2 pt
];

/// The preview sheet rows: the pens above + the tape (T31; its line cell striped).
const List<(core.PenTool, double)> _previewPens = [
  (core.PenTool.brush, 4),
  (core.PenTool.dashed, 2),
  (core.PenTool.tape, 14),
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

/// Three tape rows over a blue written line each: covered, striped, revealed.
class _TapePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(core.PaperColors.white),
    );
    for (var row = 0; row < 3; row++) {
      final ink = InkStroke.of(
        interop.newCoreStroke(
          buildStroke(
            _sCurve(row, real: true),
            style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint)
                .copyWith(colorArgb: 0xFF1E40C8, width: 3),
            viewScale: 1,
          )!,
          id: 'ink-$row',
          pageId: 'p1',
          penDownMillis: 1000,
        ),
      );
      final tape = InkStroke.of(
        interop.newCoreStroke(
          buildStroke(
            [
              for (var i = 0; i <= 40; i++)
                InkSample(
                  position: Offset(60 + 7.0 * i, 40 + _rowHeight * row),
                  timeUs: i * 8333,
                  kind: InkPointerKind.stylus,
                  pressure: 0.5,
                ),
            ],
            style: core.StrokeStyle.defaultsFor(core.PenTool.tape)
                .copyWith(width: 18)
                .withInkExtras(
                  tapeStyle: row == 1 ? InkTapeStyle.striped : null,
                ),
            viewScale: 1,
          )!,
          id: 'tape-$row',
          pageId: 'p1',
          penDownMillis: 1000,
        ),
      );
      paintStrokeLayers(
        canvas,
        [ink],
        paperColorArgb: core.PaperColors.white,
        outlineOf: OutlineGenerator.outline,
      );
      final outline = OutlineGenerator.outline(tape);
      if (row == 2) {
        paintTapeRevealed(canvas, tape, outline, lineWidthPt: 1);
      } else {
        paintTapeCovered(canvas, tape, outline);
      }
    }
  }

  @override
  bool shouldRepaint(_TapePainter oldDelegate) => false;
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

  testWidgets('pens_p1_tape', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = _penImage + const Offset(0, _rowHeight);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          child: CustomPaint(
            size: _penImage + const Offset(0, _rowHeight),
            painter: _TapePainter(),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('images/pens_p1_tape.png'),
    );
  });

  testWidgets('pens_p1_preview', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = Size(
        _previewCell.width,
        _previewCell.height * 2 * _previewPens.length,
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
                  for (final (tool, width) in _previewPens)
                    for (final shape in PenPreviewShape.values)
                      CustomPaint(
                        size: _previewCell,
                        painter: PenPreviewPainter(
                          style: core.StrokeStyle.defaultsFor(tool)
                              .copyWith(width: width)
                              .withInkExtras(
                                tapeStyle:
                                    tool == core.PenTool.tape &&
                                        shape == PenPreviewShape.line
                                    ? InkTapeStyle.striped
                                    : null,
                              ),
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
