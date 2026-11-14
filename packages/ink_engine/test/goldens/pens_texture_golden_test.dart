@TestOn('vm')
@Tags(['golden'])
library;

// (v2.11, C211-01) The texture pens on white and black paper, built with the
// real stroke pipeline (buildStroke → newCoreStroke) and painted with the page
// layer painters with the grain (⇒ the paper tiles) ready: one row per pen —
// a stylus S curve with a pressure swell (default width) and a light → hard
// line at 2.5× the width. A third image draws the same strokes from their PDF
// vector pieces (the flat look) on white.
// Update with: flutter test --update-goldens test/goldens/pens_texture_golden_test.dart
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/render/layer_painters.dart';
import 'package:ink_engine/src/render/pens/pen_renderer.dart';
import 'package:ink_engine/src/render/stroke_painter.dart';
import 'package:ink_engine/src/stroke/stroke_builder.dart';
import 'package:note_core/note_core.dart' as core;

const Size _size = Size(400, 400);

const List<core.PenTool> _pens = [
  core.PenTool.pencil,
  core.PenTool.brush,
  core.PenTool.crayon,
  core.PenTool.chalk,
  core.PenTool.watercolor,
  core.PenTool.spray,
];

List<InkSample> _samples(int row, {required bool line}) {
  const n = 90;
  final out = <InkSample>[];
  for (var i = 0; i < n; i++) {
    final u = i / (n - 1);
    final y = 36 + 62.0 * row;
    out.add(
      InkSample(
        position: line
            ? Offset(215 + 170 * u, y)
            : Offset(18 + 170 * u, y + 14 * math.sin(u * 2 * math.pi)),
        timeUs: i * 8333,
        kind: InkPointerKind.stylus,
        pressure: line ? 0.15 + 0.8 * u : 0.1 + 0.85 * math.sin(u * math.pi),
      ),
    );
  }
  return out;
}

List<InkStroke> _strokes({required bool dark}) => [
  for (var row = 0; row < _pens.length; row++)
    for (final line in [false, true])
      InkStroke.of(
        interop.newCoreStroke(
          buildStroke(
            _samples(row, line: line),
            style: () {
              final d = core.StrokeStyle.defaultsFor(_pens[row]);
              var s = d.copyWith(width: d.width * (line ? 2.5 : 1));
              if (dark && d.colorArgb == 0xFF1F1F1F) {
                s = s.copyWith(colorArgb: 0xFFEDEDED);
              }
              if (dark && _pens[row] == core.PenTool.pencil) {
                s = s.copyWith(colorArgb: 0xFFCFD8DC);
              }
              return s;
            }(),
            viewScale: 1,
          )!,
          id: 't-$row-$line',
          pageId: 'p1',
          penDownMillis: 1793750400000 + 97 * row + (line ? 1 : 0),
        ),
      ),
];

class _Painter extends CustomPainter {
  _Painter(this.strokes, this.grain, this.paper, {this.vectors = false});
  final List<InkStroke> strokes;
  final PencilGrain grain;
  final int paper;
  final bool vectors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Color(paper));
    if (vectors) {
      for (final s in strokes) {
        final pieces = penRendererOf(s.style.tool).vectorPieces(
          s,
          OutlineGenerator.outline(s),
          opacity: strokeOpacity(s),
          smooth: true,
        );
        for (final p in pieces) {
          canvas.drawPath(
            p.path.toUiPath(),
            Paint()..color = inkColor(p.colorArgb, p.opacity),
          );
        }
      }
      return;
    }
    paintStrokeLayers(
      canvas,
      strokes,
      paperColorArgb: paper,
      outlineOf: OutlineGenerator.outline,
      grain: grain.value,
      marginPt: 1,
    );
  }

  @override
  bool shouldRepaint(_Painter oldDelegate) => true;
}

void main() {
  for (final (name, paper, vectors) in [
    ('texture_pens_white', core.PaperColors.white, false),
    ('texture_pens_black', core.PaperColors.black, false),
    ('texture_pens_vectors', core.PaperColors.white, true),
  ]) {
    testWidgets(name, (tester) async {
      final grain = (await tester.runAsync(() async {
        final g = PencilGrain();
        await g.ready;
        return g;
      }))!;
      addTearDown(grain.dispose);
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = _size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            child: CustomPaint(
              size: _size,
              painter: _Painter(
                _strokes(dark: paper == core.PaperColors.black),
                grain,
                paper,
                vectors: vectors,
              ),
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(RepaintBoundary).first,
        matchesGoldenFile('images/$name.png'),
      );
    });
  }
}
