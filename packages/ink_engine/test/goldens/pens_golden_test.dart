@TestOn('vm')
@Tags(['golden'])
library;

// T08 (03-ink 8, 6.8–6.11, 9.2): the five pens on white paper, built with the
// real stroke pipeline (buildStroke → newCoreStroke) and painted with the page
// layer painters (highlighter group under the ink, pencil grain) — one image
// with real pressure (stylus S curves), one with simulated pressure (touch).
// Update with: flutter test --update-goldens test/goldens/pens_golden_test.dart
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/render/layer_painters.dart';
import 'package:ink_engine/src/stroke/stroke_builder.dart';
import 'package:note_core/note_core.dart' as core;

const Size _size = Size(400, 360);

const List<(core.PenTool, double)> _pens = [
  (core.PenTool.ballpoint, 3),
  (core.PenTool.fountain, 4),
  (core.PenTool.highlighter, 16),
  (core.PenTool.pencil, 4),
  (core.PenTool.marker, 6),
];

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
          40 + 70 * row + 20 * math.sin(u * 2 * math.pi),
        ),
        timeUs: timeUs,
        kind: real ? InkPointerKind.stylus : InkPointerKind.touch,
        pressure: real ? 0.1 + 0.85 * math.sin(u * math.pi) : null,
        tilt: real ? 0.3 + 0.8 * u : 0,
      ),
    );
    // touch: slow at the ends, fast in the middle (simulated pressure varies)
    timeUs += real
        ? 8333
        : (4000 + 24000 * (1 - math.sin(u * math.pi))).round();
  }
  return out;
}

List<InkStroke> _strokes({required bool real}) => [
  for (var row = 0; row < _pens.length; row++)
    InkStroke.of(
      interop.newCoreStroke(
        buildStroke(
          _sCurve(row, real: real),
          style: core.StrokeStyle.defaultsFor(_pens[row].$1)
              .copyWith(width: _pens[row].$2),
          viewScale: 1,
        )!,
        id: 'g-$row',
        pageId: 'p1',
        penDownMillis: 1000 + row,
      ),
    ),
];

class _PensPainter extends CustomPainter {
  _PensPainter(this.strokes, this.grain);
  final List<InkStroke> strokes;
  final PencilGrain grain;

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
      grain: grain.value,
      marginPt: 1,
    );
  }

  @override
  bool shouldRepaint(_PensPainter oldDelegate) => true;
}

void main() {
  for (final real in [true, false]) {
    final name = real ? 'pens_real_pressure' : 'pens_simulated_pressure';
    testWidgets(name, (tester) async {
      // created and decoded in the real zone: a Completer made in the fake
      // async zone of testWidgets would only complete on a pump
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
              painter: _PensPainter(_strokes(real: real), grain),
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(RepaintBoundary).first,
        matchesGoldenFile('$name.png'),
      );
    });
  }
}
