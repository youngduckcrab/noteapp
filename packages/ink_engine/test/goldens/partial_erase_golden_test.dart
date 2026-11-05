@TestOn('vm')
@Tags(['golden'])
library;

// T16 (03-ink 6.20, 9.2): the five pens (real pipeline, S curves) after one
// partial-eraser gesture with two passes — a straight vertical one and a
// wavy one — painted with the page layer painters. The cut ends are round
// (pens) and flat (highlighter), and only the ink inside the eraser is gone.
// The eraser path is drawn as a thin grey line for reference.
// Update with:
// flutter test --update-goldens test/goldens/partial_erase_golden_test.dart
import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/render/layer_painters.dart';
import 'package:ink_engine/src/stroke/stroke_builder.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

const Size _size = Size(400, 360);
const double _radius = 6;

const List<(core.PenTool, double)> _pens = [
  (core.PenTool.ballpoint, 3),
  (core.PenTool.fountain, 4),
  (core.PenTool.highlighter, 16),
  (core.PenTool.pencil, 4),
  (core.PenTool.marker, 6),
];

List<InkSample> _sCurve(int row) {
  const n = 160;
  return [
    for (var i = 0; i < n; i++)
      InkSample(
        position: Offset(
          30 + 340 * (i / (n - 1)),
          40 + 70 * row + 20 * math.sin(i / (n - 1) * 2 * math.pi),
        ),
        timeUs: i * 8333,
        kind: InkPointerKind.stylus,
        pressure: 0.1 + 0.85 * math.sin(i / (n - 1) * math.pi),
        tilt: 0.4,
      ),
  ];
}

List<core.Stroke> _strokes() => [
  for (var row = 0; row < _pens.length; row++)
    interop.newCoreStroke(
      buildStroke(
        _sCurve(row),
        style: core.StrokeStyle.defaultsFor(_pens[row].$1)
            .copyWith(width: _pens[row].$2),
        viewScale: 1,
      )!,
      id: 'g-$row',
      pageId: 'p1',
      penDownMillis: 1000 + row,
    ),
];

/// Down at x 120, then a wavy pass back up around x 260.
List<Offset> _eraserPath() => [
  for (var y = 10.0; y <= 350; y += 30) Offset(120, y),
  for (var y = 350.0; y >= 10; y -= 10) Offset(260 + 18 * math.sin(y / 25), y),
];

class _ResultPainter extends CustomPainter {
  _ResultPainter(this.strokes, this.path);
  final List<InkStroke> strokes;
  final List<Offset> path;

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
    canvas.drawPoints(
      PointMode.polygon,
      path,
      Paint()
        ..color = const Color(0xFFB0B0B0)
        ..strokeWidth = 0.75,
    );
  }

  @override
  bool shouldRepaint(_ResultPainter oldDelegate) => true;
}

void main() {
  testWidgets('partial_erase', (tester) async {
    final controller = createTestPageController();
    addTearDown(controller.dispose);
    final originals = _strokes();
    controller.updateContent(SyntheticInk.pageContent(strokes: originals));
    final path = _eraserPath();
    InkSample at(int i) => InkSample(
      position: path[i],
      timeUs: i * 8333,
      kind: InkPointerKind.stylus,
    );
    final session = controller.beginErase(
      at(0),
      spec: const EraserSpec(mode: EraserMode.partial, radius: _radius),
      viewScale: 1,
    );
    for (var i = 1; i < path.length; i++) {
      session.addSample(at(i));
    }
    final edit = session.end()!;
    expect(edit.removedIds, hasLength(5));
    // every row is cut by both passes → 3 pieces each
    expect(edit.added, hasLength(15));
    final result = [
      for (final s in originals)
        if (!edit.removedIds.contains(s.id)) s,
      ...edit.added,
    ]..sort(core.Stroke.compareOrder);

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = _size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          child: CustomPaint(
            size: _size,
            painter: _ResultPainter([
              for (final s in result) InkStroke.of(s),
            ], path),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('images/partial_erase.png'),
    );
  });
}
