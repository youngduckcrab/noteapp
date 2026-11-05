// B4 eraser move, B5 partial eraser, B6 lasso, B7 spatial index build
// (03-ink 9.1, T22). Run: flutter test benchmark/.
@Tags(['bench'])
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/edit/partial_eraser.dart';
import 'package:ink_engine/src/edit/spatial_index.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/render/sessions.dart' show lassoPolygonOf;
import 'package:ink_engine/testing.dart';

import 'support/bench.dart';
import 'support/workloads.dart';

InkSample _at(ui.Offset p, int i) => InkSample(
  position: p,
  timeUs: i * 4167,
  kind: InkPointerKind.stylus,
  pressure: 0.5,
);

void main() {
  test('B4 eraser move (index query + exact contact), 10 000 strokes', () {
    final c = createTestPageController();
    c.updateContent(pageOf(mixedPage(10000)));
    const spec = EraserSpec(mode: EraserMode.stroke, radius: 8);
    // A scrub over the page: one continuous zig-zag, 2–4 pt per 240 Hz sample.
    final path = [
      for (var i = 0; i < 400; i++)
        ui.Offset(300 + 240 * math.sin(i * 0.0157), 150 + i * 1.4),
    ];
    final rounds = <double>[];
    var touched = 0;
    for (var round = 0; round < 6; round++) {
      // the first beginErase builds the spatial index (B7)
      final session = c.beginErase(
        _at(path.first, 0),
        spec: spec,
        viewScale: 1,
      );
      final s = measureSteps(
        path.length - 1,
        (i) => session.addSample(_at(path[i + 1], i + 1)),
      );
      touched = session.touchedStrokeIds.length;
      session.cancel();
      if (round >= 2) rounds.addAll(s.samples);
    }
    c.dispose();
    expect(touched, greaterThan(50));
    report(
      'B4',
      'eraser move, 10 000 strokes (radius 8 pt)',
      BenchStats(rounds),
      criteria: {'mean_ms': 0.3},
      extra: {'touched_per_scrub': touched},
    );
  });

  test('B5 partial eraser: 50 touched strokes, cut + pieces + fragments', () {
    // 50 lines of writing (150 points each, x 60 → 540) stacked 12 pt apart;
    // one eraser move straight down through all of them.
    final strokes = [
      for (var i = 0; i < 50; i++)
        strokeAlong(
          [
            for (var k = 0; k < 150; k++)
              ui.Offset(
                60 + k * 480 / 149,
                100 + 12.0 * i + 3 * math.sin(k * 0.4 + i),
              ),
          ],
          id: 'line-$i',
          createdAt: 1000 + i,
        ),
    ];
    const x = 301.0, top = ui.Offset(x, 90), bottom = ui.Offset(x, 712);

    // 9.1 B5 as defined: the cut intervals (P2–P4) of the 50 touched strokes,
    // their kept pieces (P5/P6) and the CORE fragments
    // (StrokePoints.fromInterleaved, P7).
    final ink = [for (final s in strokes) InkStroke.of(s)];
    var fragments = 0;
    final core = measure(
      () {
        final eraser = PartialEraser(6);
        fragments = 0;
        for (final s in ink) {
          if (!eraser.addCapsule(s, top, bottom)) continue;
          var k = 0;
          for (final data in eraser.piecesOf(s.id)) {
            interop.fragmentOf(s.source, data, id: '${s.id}-${k++}');
            fragments++;
          }
        }
      },
      warmup: 30,
      runs: 60,
    );
    expect(fragments, 100); // two pieces per line
    report(
      'B5',
      'partial eraser: cuts + pieces + fragments, 50 strokes × 150 pt',
      core,
      criteria: {'median_ms': 2},
      extra: {'fragments': fragments},
    );

    // The whole gesture through the controller, for reference: begin, one
    // move through all 50 lines (also builds the P8 preview pieces drawn
    // while erasing), end (InkEdit with the fragments).
    final c = createTestPageController();
    c.updateContent(pageOf(strokes));
    const spec = EraserSpec(mode: EraserMode.partial, radius: 6);
    InkEdit? edit;
    final gesture = measure(
      () {
        final session = c.beginErase(_at(top, 0), spec: spec, viewScale: 1);
        session.addSample(_at(bottom, 1));
        edit = session.end();
      },
      setUp: () {
        if (edit != null) c.discardEdit(edit!);
      },
      warmup: 10,
      runs: 40,
    );
    expect(edit!.removedIds, hasLength(50));
    expect(edit!.added, hasLength(100));
    c.dispose();
    report(
      'B5',
      'partial eraser gesture incl. previews (reference)',
      gesture,
      criteria: const {},
    );
  });

  test('B6 lasso: 10 000 strokes, 400-vertex polygon (30% of the page)', () {
    final c = createTestPageController();
    c.updateContent(pageOf(mixedPage(10000)));
    // A star: radii 205 / 235 pt alternating (RDP keeps every vertex).
    const center = ui.Offset(297.6, 420.9);
    final vertices = [
      for (var i = 0; i < 400; i++)
        center +
            ui.Offset.fromDirection(
              i / 400 * 2 * math.pi,
              i.isEven ? 205.0 : 235.0,
            ),
    ];
    var polygonVertices = 0, selected = 0;
    double area = 0;
    late LassoSession session;
    final stats = measure(
      () => selected = session.end()?.strokeIds.length ?? 0,
      setUp: () {
        session = c.beginLasso(vertices.first, viewScale: 1);
        vertices.skip(1).forEach(session.addPoint);
        final polygon = lassoPolygonOf(session);
        polygonVertices = polygon.vertexCount;
        area = polygon.absWindingArea();
      },
      warmup: 3,
      runs: 15,
    );
    final pageArea = a4.width * a4.height;
    expect(polygonVertices, 400);
    expect(area / pageArea, closeTo(0.3, 0.03));
    expect(selected, greaterThan(1000));
    c.dispose();
    report(
      'B6',
      'lasso 400 vertices, 10 000 strokes',
      stats,
      criteria: {'median_ms': 25},
      extra: {'selected': selected, 'page_share': area / pageArea},
    );
  });

  test('B7 spatial index build: 10 000 strokes', () {
    final strokes = [for (final s in mixedPage(10000)) InkStroke.of(s)];
    for (final s in strokes) {
      s.bounds; // computed by the first paint already
    }
    final size = ui.Size(a4.width, a4.height);
    late StrokeSpatialIndex index;
    final stats = measure(
      () => index = StrokeSpatialIndex.of(size, strokes),
      warmup: 5,
      runs: 30,
    );
    expect(index.length, 10000);
    report(
      'B7',
      'spatial index build 10 000 strokes',
      stats,
      criteria: {'median_ms': 15},
    );
  });
}
