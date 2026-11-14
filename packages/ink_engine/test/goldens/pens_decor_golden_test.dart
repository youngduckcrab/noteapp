@TestOn('vm')
@Tags(['golden'])
library;

// (v2.11, C211-01) The decoration pens (render/pens/decor/), built with the
// real stroke pipeline and painted with the page layer painters — one image per
// pen (decor_<pen>.png: on white paper an S curve with real pressure, one with
// simulated pressure and a row of dots; then the same S curve and dots in a
// second color on the dark paper) and the pen preview sheet
// (decor_preview.png, PenPreviewPainter: S curve | line per pen).
// Update with: flutter test --update-goldens test/goldens/pens_decor_golden_test.dart
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/render/layer_painters.dart';
import 'package:ink_engine/src/stroke/stroke_builder.dart';
import 'package:note_core/note_core.dart' as core;

/// tool, golden width, image name, second color (dark paper row)
const List<(core.PenTool, double, String, int)> _pens = [
  (core.PenTool.neon, 6, 'neon', 0xFF00E5FF),
  (core.PenTool.jelly, 6, 'jelly', 0xFFFFF59D),
  (core.PenTool.rainbow, 5, 'rainbow', 0xFF2F80ED),
  (core.PenTool.glitter, 7, 'glitter', 0xFFFFFFFF),
];

const double _rowHeight = 70;
const Size _penImage = Size(400, _rowHeight * 4);
const Size _previewCell = Size(200, 64);

List<InkSample> _sCurve(double y0, {required bool real}) {
  const n = 160;
  final out = <InkSample>[];
  var timeUs = 0;
  for (var i = 0; i < n; i++) {
    final u = i / (n - 1);
    out.add(
      InkSample(
        position: Offset(30 + 280 * u, y0 + 20 * math.sin(u * 2 * math.pi)),
        timeUs: timeUs,
        kind: real ? InkPointerKind.stylus : InkPointerKind.touch,
        pressure: real ? 0.1 + 0.85 * math.sin(u * math.pi) : null,
      ),
    );
    timeUs += real
        ? 8333
        : (4000 + 24000 * (1 - math.sin(u * math.pi))).round();
  }
  return out;
}

var _ids = 0;

InkStroke _stroke(List<InkSample> samples, core.StrokeStyle style) =>
    InkStroke.of(
      interop.newCoreStroke(
        buildStroke(samples, style: style, viewScale: 1)!,
        id: 'decor-${_ids++}',
        pageId: 'p1',
        penDownMillis: 1000 + _ids,
      ),
    );

/// An S curve and three dots at row [row].
List<InkStroke> _row(
  core.StrokeStyle style,
  int row, {
  required bool real,
  bool dots = true,
}) {
  final y = _rowHeight * row + _rowHeight / 2;
  return [
    _stroke(_sCurve(y, real: real), style),
    if (dots)
      for (var k = 0; k < 3; k++)
        _stroke([
          InkSample(
            position: Offset(335 + 20.0 * k, y),
            timeUs: 0,
            kind: InkPointerKind.stylus,
            pressure: 0.5,
          ),
        ], style),
  ];
}

class _PenPainter extends CustomPainter {
  _PenPainter(this.tool, this.width, this.second);
  final core.PenTool tool;
  final double width;
  final int second;

  @override
  void paint(Canvas canvas, Size size) {
    _ids = 0;
    final style = core.StrokeStyle.defaultsFor(tool).copyWith(width: width);
    canvas
      ..drawRect(
        Rect.fromLTWH(0, 0, size.width, _rowHeight * 2),
        Paint()..color = const Color(core.PaperColors.white),
      )
      ..drawRect(
        Rect.fromLTWH(0, _rowHeight * 2, size.width, _rowHeight * 2),
        Paint()..color = const Color(core.PaperColors.black),
      );
    void paintOn(int paper, List<InkStroke> strokes) => paintStrokeLayers(
      canvas,
      strokes,
      paperColorArgb: paper,
      outlineOf: OutlineGenerator.outline,
      marginPt: 1,
    );
    paintOn(core.PaperColors.white, [
      ..._row(style, 0, real: true),
      ..._row(style, 1, real: false, dots: false),
    ]);
    paintOn(core.PaperColors.black, [
      ..._row(style, 2, real: true),
      ..._row(style.copyWith(colorArgb: second), 3, real: true),
    ]);
  }

  @override
  bool shouldRepaint(_PenPainter oldDelegate) => true;
}

void main() {
  for (final (tool, width, name, second) in _pens) {
    testWidgets('decor_$name', (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = _penImage;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            child: CustomPaint(
              size: _penImage,
              painter: _PenPainter(tool, width, second),
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(RepaintBoundary).first,
        matchesGoldenFile('images/decor_$name.png'),
      );
    });
  }

  testWidgets('decor_preview', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = Size(
        _previewCell.width * PenPreviewShape.values.length,
        _previewCell.height * _pens.length,
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
                  for (final (tool, _, _, _) in _pens)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final shape in PenPreviewShape.values)
                          CustomPaint(
                            size: _previewCell,
                            painter: PenPreviewPainter(
                              style: core.StrokeStyle.defaultsFor(tool),
                              shape: shape,
                            ),
                          ),
                      ],
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
      matchesGoldenFile('images/decor_preview.png'),
    );
  });
}
