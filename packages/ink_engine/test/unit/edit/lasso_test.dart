// T17 (03-ink 6.21, LassoOptions contract 4.7): the lasso path is closed and
// RDP-simplified (simplifyPx / viewScale), degenerate polygons select nothing,
// inside = nonzero winding through a y-band index (= the plain winding number
// on 10 000 random points), and a stroke is selected iff the centerline
// length of its segments whose midpoint is inside reaches `coverage` of its
// length (a dot: its point). Every tool is selectable.
// (m5-7/03-ink 8.2 T37a, 6.14) v2: with LassoOptions.includeObjects (default)
// a page object of any kind is selected iff its frame center is inside
// (nonzero — the figure 8's loops, not a concave notch; a rotated frame's center
// is its rect's center; a shape's frame is its geometry's), however much of the
// frame lies outside; strokes and objects come back in one z order
// (compareOrder); hidden objects are selectable, previews and pending-removed
// objects are not; includeObjects: false → strokes only (null when only
// objects were inside).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/dev_tools.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/edit/lasso_polygon.dart';
import 'package:ink_engine/src/render/sessions.dart' show lassoPolygonOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' show PageObjectFixtures;

import '../../support/pixels.dart';

final _pen = core.StrokeStyle.defaultsFor(core.PenTool.ballpoint);

core.Stroke _line(
  ui.Offset a,
  ui.Offset b, {
  required String id,
  core.StrokeStyle? style,
  int createdAt = 1000,
}) => strokeThrough(segment(a, b), style ?? _pen, id: id, createdAt: createdAt);

/// The plain winding number: every edge, Sunday's crossing test.
int _plainWinding(List<ui.Offset> v, double px, double py) {
  var wn = 0;
  for (var i = 0; i < v.length; i++) {
    final a = v[i], b = v[(i + 1) % v.length];
    final cross = (b.dx - a.dx) * (py - a.dy) - (px - a.dx) * (b.dy - a.dy);
    if (a.dy <= py) {
      if (b.dy > py && cross > 0) wn++;
    } else {
      if (b.dy <= py && cross < 0) wn--;
    }
  }
  return wn;
}

/// A horizontal figure 8 around ([cx], [cy]): x = cx + rx·sin θ,
/// y = cy + ry·sin 2θ — the right loop and the left loop wind opposite ways.
List<ui.Offset> _figureEight(double cx, double cy, double rx, double ry) => [
  for (var k = 0; k < 160; k++)
    ui.Offset(
      cx + rx * math.sin(2 * math.pi * k / 160),
      cy + ry * math.sin(4 * math.pi * k / 160),
    ),
];

List<ui.Offset> _rect(double l, double t, double r, double b) => [
  ui.Offset(l, t),
  ui.Offset(r, t),
  ui.Offset(r, b),
  ui.Offset(l, b),
];

void main() {
  late InkPageController c;

  void show(List<core.Stroke> strokes) =>
      c.updateContent(SyntheticInk.pageContent(strokes: strokes, revision: 2));

  /// Runs a lasso through [path] (page pt) and returns its result.
  InkSelection? lasso(
    List<ui.Offset> path, {
    double viewScale = 1,
    LassoOptions options = const LassoOptions(),
  }) {
    final s = c.beginLasso(path.first, viewScale: viewScale, options: options);
    for (final p in path.skip(1)) {
      s.addPoint(p);
    }
    return s.end();
  }

  setUp(() => c = createTestPageController());
  tearDown(() => c.dispose());

  group('selection rule (L4–L6)', () {
    test('a rectangle selects the strokes inside, in z order', () {
      show([
        _line(
          const ui.Offset(120, 120),
          const ui.Offset(180, 150),
          id: 'b',
          createdAt: 3000,
        ),
        _line(
          const ui.Offset(110, 170),
          const ui.Offset(190, 170),
          id: 'a',
          createdAt: 2000,
        ),
        _line(const ui.Offset(300, 300), const ui.Offset(360, 320), id: 'out'),
        // crosses the lasso: 1/3 inside
        _line(const ui.Offset(170, 230), const ui.Offset(260, 230), id: 'edge'),
      ]);
      final sel = lasso(_rect(100, 100, 200, 200 + 40))!;
      expect(sel.strokeIds.toList(), ['a', 'b']);
      expect(c.selection, same(sel));
      expect(sel.strokes.map((s) => s.id), ['a', 'b']);
    });

    test('coverage 40 % → not selected, 60 % → selected', () {
      // 100 pt, segments of 2 pt (midpoints at odd x)
      final stroke = _line(
        const ui.Offset(100, 300),
        const ui.Offset(200, 300),
        id: 's',
      );
      show([stroke]);
      final forty = LassoPolygon.of(_rect(50, 250, 140, 350));
      final sixty = LassoPolygon.of(_rect(50, 250, 160, 350));
      final ink = InkStroke.of(stroke);
      expect(LassoSelector.coverageOf(ink, forty), closeTo(0.4, 1e-3));
      expect(LassoSelector.coverageOf(ink, sixty), closeTo(0.6, 1e-3));
      expect(LassoSelector.selects(ink, forty, 0.5), isFalse);
      expect(LassoSelector.selects(ink, sixty, 0.5), isTrue);

      expect(lasso(_rect(50, 250, 140, 350)), isNull);
      expect(c.selection, isNull);
      expect(lasso(_rect(50, 250, 160, 350))!.strokeIds, {'s'});
      // the threshold is LassoOptions.coverage
      expect(
        lasso(
          _rect(50, 250, 140, 350),
          options: const LassoOptions(coverage: 0.3),
        )!.strokeIds,
        {'s'},
      );
      expect(
        lasso(
          _rect(50, 250, 160, 350),
          options: const LassoOptions(coverage: 0.7),
        ),
        isNull,
      );
    });

    test('centerline length, not the bounds center', () {
      // an L (20 pt down, 141 pt diagonal): a small lasso around its bounds
      // center (150, 160) holds only 14 pt of it
      final l = strokeThrough(
        [
          ...segment(const ui.Offset(100, 100), const ui.Offset(100, 120)),
          ...segment(
            const ui.Offset(100, 120),
            const ui.Offset(200, 220),
          ).skip(1),
        ],
        _pen,
        id: 'L',
      );
      // a long stroke mostly inside a lasso that misses its bounds center
      final hook = strokeThrough(
        [
          ...segment(const ui.Offset(300, 400), const ui.Offset(400, 400)),
          ...segment(
            const ui.Offset(400, 400),
            const ui.Offset(400, 600),
          ).skip(1),
        ],
        _pen,
        id: 'hook',
      );
      show([l, hook]);
      expect(
        LassoPolygon.of(_rect(140, 150, 160, 170)).contains(150, 160),
        isTrue,
      );
      expect(lasso(_rect(140, 150, 160, 170)), isNull);
      expect(lasso(_rect(390, 390, 420, 610))!.strokeIds, {
        'hook',
      }, reason: 'bounds center (350, 500) is outside, 2/3 of the length in');
    });

    test('figure 8: both loops are inside (nonzero winding)', () {
      show([
        _line(const ui.Offset(370, 400), const ui.Offset(430, 400), id: 'R'),
        _line(const ui.Offset(170, 400), const ui.Offset(230, 400), id: 'L'),
        _line(const ui.Offset(290, 480), const ui.Offset(310, 480), id: 'off'),
      ]);
      final eight = _figureEight(300, 400, 150, 80);
      final polygon = LassoPolygon.of(eight);
      expect(polygon.signedArea.abs(), lessThan(1e-6), reason: 'symmetric');
      expect(polygon.isDegenerate(InkTuning.lassoMinAreaPt2), isFalse);
      expect(polygon.windingNumber(400, 400), -polygon.windingNumber(200, 400));
      expect(polygon.windingNumber(400, 400).abs(), 1);
      expect(lasso(eight)!.strokeIds, {'L', 'R'});
    });

    test('a doubly wound lasso selects like a single one', () {
      show([
        _line(const ui.Offset(120, 150), const ui.Offset(180, 150), id: 'in'),
      ]);
      final twice = [
        ..._rect(100, 100, 200, 200),
        ..._rect(100, 100, 200, 200),
      ];
      final polygon = LassoPolygon.of(twice);
      expect(polygon.windingNumber(150, 150).abs(), 2);
      expect(polygon.absWindingArea(), closeTo(2 * 100 * 100, 1e-6));
      expect(lasso(twice)!.strokeIds, {'in'});
    });

    test('concave polygon: the notch is outside', () {
      // a U: arms x 100–150 and 250–300, bottom y 300–350, notch 150–250 × 100–300
      final u = [
        const ui.Offset(100, 100),
        const ui.Offset(150, 100),
        const ui.Offset(150, 300),
        const ui.Offset(250, 300),
        const ui.Offset(250, 100),
        const ui.Offset(300, 100),
        const ui.Offset(300, 350),
        const ui.Offset(100, 350),
      ];
      show([
        _line(
          const ui.Offset(170, 150),
          const ui.Offset(230, 250),
          id: 'notch',
        ),
        _line(const ui.Offset(110, 120), const ui.Offset(140, 280), id: 'left'),
        _line(
          const ui.Offset(260, 120),
          const ui.Offset(290, 280),
          id: 'right',
        ),
        _line(const ui.Offset(120, 320), const ui.Offset(280, 330), id: 'base'),
      ]);
      expect(lasso(u)!.strokeIds, {'left', 'right', 'base'});
    });

    test('dots: selected iff the point is inside', () {
      final dotIn = strokeThrough(const [ui.Offset(150, 150)], _pen, id: 'in');
      final dotOut = strokeThrough(const [ui.Offset(250, 150)], _pen, id: 'o');
      // zero-length centerline with several points
      final dotSame = strokeThrough(
        const [ui.Offset(160, 160), ui.Offset(160, 160), ui.Offset(160, 160)],
        _pen,
        id: 'same',
      );
      show([dotIn, dotOut, dotSame]);
      expect(lasso(_rect(100, 100, 200, 200))!.strokeIds, {'in', 'same'});
    });

    test('every tool is selectable (no StrokeFilter)', () {
      final strokes = [
        for (final (k, tool) in core.PenTool.values.indexed)
          _line(
            ui.Offset(120, 105.0 + 10 * k),
            ui.Offset(180, 105.0 + 10 * k),
            id: tool.name,
            style: core.StrokeStyle.defaultsFor(tool),
          ),
      ];
      show(strokes);
      expect(lasso(_rect(100, 100, 200, 200))!.strokeIds, {
        for (final t in core.PenTool.values) t.name,
      });
    });

    test('strokes a pending erase hides are not selected', () {
      show([
        _line(const ui.Offset(120, 150), const ui.Offset(180, 150), id: 'a'),
        _line(const ui.Offset(120, 180), const ui.Offset(180, 180), id: 'b'),
      ]);
      final eraser = c.beginErase(
        const InkSample(
          position: ui.Offset(150, 150),
          timeUs: 0,
          kind: InkPointerKind.stylus,
        ),
        spec: const EraserSpec(mode: EraserMode.stroke, radius: 4),
        viewScale: 1,
      );
      expect(eraser.end()!.removedIds, {'a'});
      expect(lasso(_rect(100, 100, 200, 200))!.strokeIds, {'b'});
    });

    test('no content, or nothing selected → null and the selection stays', () {
      expect(lasso(_rect(100, 100, 200, 200)), isNull);
      show([
        _line(const ui.Offset(120, 150), const ui.Offset(180, 150), id: 'a'),
      ]);
      final sel = lasso(_rect(100, 100, 200, 200))!;
      expect(lasso(_rect(300, 300, 400, 400)), isNull);
      expect(c.selection, same(sel));
      expect(c.activeSession, isNull);
    });

    test('non-finite points are ignored', () {
      show([
        _line(const ui.Offset(120, 150), const ui.Offset(180, 150), id: 'a'),
      ]);
      final s = c.beginLasso(const ui.Offset(100, 100), viewScale: 1)
        ..addPoint(const ui.Offset(double.nan, 5))
        ..addPoint(const ui.Offset(200, 100))
        ..addPoint(const ui.Offset(double.infinity, 100))
        ..addPoint(const ui.Offset(200, 200))
        ..addPoint(const ui.Offset(100, 200));
      expect(s.points, hasLength(4));
      expect(s.end()!.strokeIds, {'a'});
    });
  });

  group('objects (v2 — includeObjects, 6.14)', () {
    const pageId = 'p1';
    core.TextBoxObject text(
      String id,
      core.PageRect r, {
      double rotation = 0,
      int createdAt = 1,
    }) => core.TextBoxObject(
      id: id,
      pageId: pageId,
      frame: core.ElementFrame(r, rotation: rotation),
      text: 'x',
      style: const core.TextBoxStyle(),
      createdAt: createdAt,
    );

    void showAll(
      List<core.PageObject> objects, {
      List<core.Stroke> strokes = const [],
    }) => c.updateContent(
      SyntheticInk.pageContentWith(
        strokes: strokes,
        objects: objects,
        revision: 3,
      ),
    );

    test('the frame center decides, not how much of the frame is inside', () {
      showAll([
        // center (150, 150) inside, most of the frame outside
        text('wide', const core.PageRect(20, 140, 280, 160)),
        // 80 % of the frame inside, center (215, 150) outside
        text('mostly', const core.PageRect(130, 130, 300, 170)),
      ]);
      final sel = lasso(_rect(100, 100, 200, 200))!;
      expect(sel.objectIds, {'wide'});
      expect(sel.strokeIds, isEmpty);
    });

    test('every kind, rotated frames and shapes by their frame center', () {
      final objects = <core.PageObject>[
        text('t', const core.PageRect(110, 110, 150, 130)),
        PageObjectFixtures.math(
          pageId: pageId,
          id: 'm',
          rect: const core.PageRect(120, 140, 160, 160),
        ),
        PageObjectFixtures.image(
          pageId: pageId,
          assetId: 'a',
          id: 'i',
          rect: const core.PageRect(100, 160, 190, 190),
        ),
        PageObjectFixtures.unknown(
          pageId: pageId,
          id: 'u',
          rect: const core.PageRect(160, 110, 190, 130),
        ),
        // a line (0,0)→(300,300): frame = its AABB, center (150, 150) — inside
        PageObjectFixtures.shape(
          pageId: pageId,
          kind: core.ShapeKind.line,
          id: 'line',
          rect: const core.PageRect(0, 0, 300, 300),
        ),
        // turned 90°: the long frame stands up, its center (150, 250) stays outside
        text(
          'turned',
          const core.PageRect(100, 245, 200, 255),
          rotation: 1.5708,
        ),
        PageObjectFixtures.shape(
          pageId: pageId,
          kind: core.ShapeKind.ellipse,
          id: 'far',
          rect: const core.PageRect(300, 300, 400, 400),
        ),
      ];
      showAll(objects);
      expect(lasso(_rect(100, 100, 200, 200))!.objectIds, {
        't',
        'm',
        'i',
        'u',
        'line',
      });
    });

    test('nonzero: both loops of a figure 8, not a concave notch', () {
      showAll([
        text('left', const core.PageRect(190, 290, 210, 310)),
        text('right', const core.PageRect(390, 290, 410, 310)),
        text('notch', const core.PageRect(640, 640, 660, 660)),
      ]);
      expect(lasso(_figureEight(300, 300, 150, 100))!.objectIds, {
        'left',
        'right',
      });
      // a U shape whose notch holds the third center
      final u = [
        const ui.Offset(600, 600),
        const ui.Offset(630, 600),
        const ui.Offset(630, 700),
        const ui.Offset(670, 700),
        const ui.Offset(670, 600),
        const ui.Offset(700, 600),
        const ui.Offset(700, 720),
        const ui.Offset(600, 720),
      ];
      expect(lasso(u), isNull);
    });

    test('strokes and objects in one z order; includeObjects: false', () {
      final strokes = [
        _line(
          const ui.Offset(110, 120),
          const ui.Offset(190, 120),
          id: 's-old',
          createdAt: 5,
        ),
        _line(
          const ui.Offset(110, 180),
          const ui.Offset(190, 180),
          id: 's-new',
          createdAt: 50,
        ),
      ];
      final s0 = strokes[0].createdAt, s1 = strokes[1].createdAt;
      showAll([
        text('first', const core.PageRect(120, 140, 140, 160), createdAt: 1),
        text(
          'between',
          const core.PageRect(150, 140, 170, 160),
          createdAt: s0 + 1,
        ),
        text(
          'last',
          const core.PageRect(160, 150, 180, 170),
          createdAt: s1 + 1,
        ),
      ], strokes: strokes);
      final sel = lasso(_rect(100, 100, 200, 200))!;
      expect(sel.allIds.toList(), [
        'first',
        's-old',
        'between',
        's-new',
        'last',
      ]);
      expect(sel.strokeIds, {'s-old', 's-new'});
      expect(sel.objects.map((o) => o.id), ['first', 'between', 'last']);
      final strokesOnly = lasso(
        _rect(100, 100, 200, 200),
        options: const LassoOptions(includeObjects: false),
      )!;
      expect(strokesOnly.allIds.toList(), ['s-old', 's-new']);
      expect(strokesOnly.objectIds, isEmpty);
      // only objects inside and includeObjects: false → nothing
      expect(
        lasso(
          _rect(115, 135, 185, 175),
          options: const LassoOptions(includeObjects: false),
        ),
        isNull,
      );
      expect(lasso(_rect(115, 135, 185, 175))!.objectIds, {
        'first',
        'between',
        'last',
      });
    });

    test(
      'hidden objects are selectable; previews and pending-removed are not',
      () {
        showAll([
          text('hidden', const core.PageRect(110, 110, 130, 130)),
          text('gone', const core.PageRect(150, 150, 170, 170)),
        ]);
        c.setHiddenObjectIds({'hidden'});
        c.setPreviewObjects([
          text('preview', const core.PageRect(160, 110, 180, 130)),
        ]);
        c.select({'gone'}).delete();
        expect(lasso(_rect(100, 100, 200, 200))!.objectIds, {'hidden'});
      },
    );
  });

  group('degenerate polygons (L2) → null', () {
    setUp(
      () => show([
        _line(
          const ui.Offset(100, 100),
          const ui.Offset(100.6, 100.6),
          id: 'a',
        ),
      ]),
    );

    test('fewer than 3 vertices, collinear, tiny area', () {
      expect(lasso(const [ui.Offset(100, 100)]), isNull);
      expect(lasso(const [ui.Offset(90, 90), ui.Offset(110, 110)]), isNull);
      // back and forth on one line: RDP keeps only the turning points, area 0
      expect(
        lasso(const [
          ui.Offset(90, 90),
          ui.Offset(110, 110),
          ui.Offset(95, 95),
          ui.Offset(105, 105),
        ]),
        isNull,
      );
      // a 2 × 3 triangle: 3 pt² < 4 pt²
      expect(
        lasso(const [
          ui.Offset(99, 99),
          ui.Offset(101, 99),
          ui.Offset(99, 102),
        ]),
        isNull,
      );
      expect(c.selection, isNull);
      // a 3 × 3 triangle: 4.5 pt² — not degenerate; the short stroke's
      // midpoint (100.3, 100.3) is inside
      expect(
        lasso(const [
          ui.Offset(99, 99),
          ui.Offset(102, 99),
          ui.Offset(99, 102),
        ])!.strokeIds,
        {'a'},
      );
    });

    test('|area| threshold is LassoOptions.minAreaPt2', () {
      final tri = LassoPolygon.of(const [
        ui.Offset.zero,
        ui.Offset(2, 0),
        ui.Offset(0, 3),
      ]);
      expect(tri.signedArea.abs(), closeTo(3, 1e-9));
      expect(tri.isDegenerate(4), isTrue);
      expect(tri.isDegenerate(3), isFalse);
      expect(tri.isDegenerate(2.9), isFalse);
      expect(
        lasso(const [
          ui.Offset(99, 99),
          ui.Offset(102, 99),
          ui.Offset(99, 102),
        ], options: const LassoOptions(minAreaPt2: 5)),
        isNull,
      );
    });

    test('the area is ∫|winding| dA: a figure 8 adds its loops', () {
      // a symmetric bowtie crossing at (101, 100.5): two 3 pt² triangles
      // wound opposite ways — shoelace area 0, ∫|winding| dA = 6 pt². Each
      // loop alone is under the default 4 pt² (like the 2 × 3 triangle
      // above); the figure 8 is not degenerate. Stroke 'a' is in the left loop.
      const bowtie = [
        ui.Offset(99, 99),
        ui.Offset(103, 102),
        ui.Offset(103, 99),
        ui.Offset(99, 102),
      ];
      final p = LassoPolygon.of(bowtie);
      expect(p.signedArea, closeTo(0, 1e-9), reason: 'symmetric');
      expect(p.absWindingArea(), closeTo(6, 1e-9));
      expect(p.windingNumber(100, 100.5), -p.windingNumber(102, 100.5));
      expect(InkTuning.lassoMinAreaPt2, 4);
      expect(p.isDegenerate(InkTuning.lassoMinAreaPt2), isFalse);
      expect(p.isDegenerate(5.9), isFalse);
      expect(p.isDegenerate(6.1), isTrue);
      expect(lasso(bowtie)!.strokeIds, {'a'});
      expect(
        lasso(bowtie, options: const LassoOptions(minAreaPt2: 6.1)),
        isNull,
      );
    });

    test('closing copy and duplicates are dropped', () {
      final p = LassoPolygon.of(const [
        ui.Offset.zero,
        ui.Offset.zero,
        ui.Offset(10, 0),
        ui.Offset(10, 10),
        ui.Offset(10, 10),
        ui.Offset.zero,
      ]);
      expect(p.vertices, const [
        ui.Offset.zero,
        ui.Offset(10, 0),
        ui.Offset(10, 10),
      ]);
      expect(p.signedArea.abs(), 50);
    });
  });

  group('RDP simplification (L2)', () {
    // a 200 × 200 square whose top edge wobbles by ±0.25 pt every 2 pt
    final wobbly = [
      for (var x = 100.0; x < 300; x += 2)
        ui.Offset(x, 100 + ((x / 2) % 2 == 0 ? 0.25 : -0.25)),
      const ui.Offset(300, 100),
      const ui.Offset(300, 300),
      const ui.Offset(100, 300),
    ];

    test('tolerance = simplifyPx / viewScale pt', () {
      final coarse = LassoPolygon.simplified(wobbly, tolerancePt: 0.75);
      final fine = LassoPolygon.simplified(wobbly, tolerancePt: 0.75 / 4);
      expect(coarse.vertexCount, lessThanOrEqualTo(5));
      expect(fine.vertexCount, greaterThan(50));
      expect(LassoPolygon.of(wobbly).vertexCount, wobbly.length);

      final s1 = c.beginLasso(wobbly.first, viewScale: 1);
      wobbly.skip(1).forEach(s1.addPoint);
      expect(lassoPolygonOf(s1).vertexCount, coarse.vertexCount);
      s1.cancel();
      final s4 = c.beginLasso(wobbly.first, viewScale: 4);
      wobbly.skip(1).forEach(s4.addPoint);
      expect(lassoPolygonOf(s4).vertexCount, fine.vertexCount);
      s4.cancel();
      final px3 = c.beginLasso(
        wobbly.first,
        viewScale: 4,
        options: const LassoOptions(simplifyPx: 3),
      );
      wobbly.skip(1).forEach(px3.addPoint);
      expect(lassoPolygonOf(px3).vertexCount, coarse.vertexCount);
      px3.cancel();
    });

    test('simplified vertices are a subset within the tolerance', () {
      final p = LassoPolygon.simplified(wobbly, tolerancePt: 0.75);
      final kept = p.vertices;
      expect(kept.first, wobbly.first);
      expect(kept.last, wobbly.last);
      for (final v in kept) {
        expect(wobbly, contains(v));
      }
    });
  });

  group('y-band index (L3)', () {
    test('band height = max(8 pt, height / 64)', () {
      final small = LassoPolygon.of(_rect(0, 0, 100, 100));
      expect(small.bandHeight, InkTuning.lassoBandMinPt);
      expect(small.bandCount, 13);
      final tall = LassoPolygon.of(_rect(0, 0, 100, 1280));
      expect(tall.bandHeight, 20);
      expect(tall.bandCount, 64);
      final flat = LassoPolygon.of(const [
        ui.Offset(0, 5),
        ui.Offset(10, 5),
        ui.Offset(20, 5),
      ]);
      expect(flat.bandCount, 1);
      // a band holds only the edges that cross its y range
      for (var b = 1; b < small.bandCount - 1; b++) {
        expect(small.edgesInBand(b), 2, reason: 'band $b');
      }
    });

    test('band winding = plain winding on 10 000 random points', () {
      final rnd = math.Random(1717);
      var points = 0, nonzero = 0;
      for (var poly = 0; poly < 20; poly++) {
        // random polygons: 3–400 vertices, star-like or free (self-crossing)
        final n = 3 + rnd.nextInt(398);
        final cx = 300.0, cy = 400.0;
        final star = poly.isEven;
        final v = <ui.Offset>[
          for (var k = 0; k < n; k++)
            if (star)
              ui.Offset(
                cx +
                    (40 + rnd.nextDouble() * 200) *
                        math.cos(2 * math.pi * k / n),
                cy +
                    (40 + rnd.nextDouble() * 300) *
                        math.sin(2 * math.pi * k / n),
              )
            else
              ui.Offset(rnd.nextDouble() * 595, rnd.nextDouble() * 842),
        ];
        final polygon = LassoPolygon.of(v);
        expect(polygon.vertexCount, n);
        for (var k = 0; k < 500; k++) {
          // a quarter of the points on a vertex's y (band and edge ends)
          final y = k % 4 == 0
              ? v[rnd.nextInt(n)].dy
              : -20 + rnd.nextDouble() * 900;
          final x = -20 + rnd.nextDouble() * 640;
          final expected = _plainWinding(v, x, y);
          expect(polygon.windingNumber(x, y), expected, reason: '($x, $y)');
          expect(polygon.contains(x, y), expected != 0);
          points++;
          if (expected != 0) nonzero++;
        }
      }
      expect(points, 10000);
      expect(nonzero, greaterThan(1000));
    });
  });

  group('∫|w| dA', () {
    double gridAbsWinding(List<ui.Offset> v, ui.Rect r, double cell) {
      var sum = 0.0;
      for (var y = r.top + cell / 2; y < r.bottom; y += cell) {
        for (var x = r.left + cell / 2; x < r.right; x += cell) {
          sum += _plainWinding(v, x, y).abs();
        }
      }
      return sum * cell * cell;
    }

    test('simple polygon = |shoelace|; figure 8 = both loops', () {
      final square = LassoPolygon.of(_rect(10, 10, 30, 40));
      expect(square.absWindingArea(), closeTo(600, 1e-9));
      expect(square.signedArea.abs(), closeTo(600, 1e-9));

      final eight = _figureEight(0, 0, 60, 30);
      final p = LassoPolygon.of(eight);
      final grid = gridAbsWinding(
        eight,
        const ui.Rect.fromLTRB(-61, -31, 61, 31),
        0.25,
      );
      expect(p.absWindingArea(), closeTo(grid, grid * 0.01));
      expect(p.absWindingArea(), greaterThan(1000));
    });

    test('random self-crossing polygons match a fine grid', () {
      final rnd = math.Random(99);
      for (var k = 0; k < 5; k++) {
        final v = [
          for (var i = 0; i < 4 + rnd.nextInt(8); i++)
            ui.Offset(rnd.nextDouble() * 60, rnd.nextDouble() * 60),
        ];
        final area = LassoPolygon.of(v).absWindingArea();
        final grid = gridAbsWinding(
          v,
          const ui.Rect.fromLTWH(0, 0, 60, 60),
          0.2,
        );
        expect(area, closeTo(grid, 25), reason: 'polygon $k');
      }
    });
  });

  group('fast paths (T22): bounds wholly inside / outside', () {
    // A star (alternating radii), a figure 8 and a U.
    final shapes = <String, List<ui.Offset>>{
      'star': [
        for (var i = 0; i < 120; i++)
          const ui.Offset(300, 420) +
              ui.Offset.fromDirection(
                i / 120 * 2 * math.pi,
                i.isEven ? 160.0 : 200.0,
              ),
      ],
      'figure 8': [
        for (var i = 0; i < 80; i++)
          ui.Offset(
            300 + 220 * math.sin(i / 80 * 2 * math.pi),
            420 + 150 * math.sin(i / 80 * 4 * math.pi),
          ),
      ],
      'U': const [
        ui.Offset(100, 200),
        ui.Offset(220, 200),
        ui.Offset(220, 600),
        ui.Offset(380, 600),
        ui.Offset(380, 200),
        ui.Offset(500, 200),
        ui.Offset(500, 720),
        ui.Offset(100, 720),
      ],
    };
    var n = 0;
    final strokes = [
      for (final s in InkDevTools.syntheticStrokes(
        pageId: 'p1',
        pageSize: core.PageSize.a4Portrait,
        count: 1500,
        newId: () => 'fp-${n++}',
        createdAt: 1000,
        seed: 7,
      ))
        InkStroke.of(s),
    ];

    test('classifyRect agrees with the winding number on a 9 × 9 grid', () {
      final rng = math.Random(3);
      for (final MapEntry(key: name, value: v) in shapes.entries) {
        final polygon = LassoPolygon.of(v);
        var decided = 0;
        for (var k = 0; k < 400; k++) {
          final x = rng.nextDouble() * 600, y = rng.nextDouble() * 840;
          final r = ui.Rect.fromLTWH(
            x,
            y,
            rng.nextDouble() * 60,
            rng.nextDouble() * 60,
          );
          final c = polygon.classifyRect(r);
          if (c == LassoPolygon.rectMixed) continue;
          decided++;
          for (var i = 0; i <= 8; i++) {
            for (var j = 0; j <= 8; j++) {
              final px = r.left + r.width * i / 8;
              final py = r.top + r.height * j / 8;
              expect(
                _plainWinding(v, px, py) != 0,
                c == LassoPolygon.rectInside,
                reason: '$name $r ($px, $py)',
              );
            }
          }
        }
        expect(decided, greaterThan(100), reason: name);
      }
    });

    test('selects == coverageOf ≥ coverage for every stroke and coverage', () {
      for (final MapEntry(key: name, value: v) in shapes.entries) {
        final polygon = LassoPolygon.of(v);
        var picked = 0;
        for (final s in strokes) {
          final share = LassoSelector.coverageOf(s, polygon);
          for (final c in [0.0, 0.3, 0.6, 1.0]) {
            final want = share >= c;
            expect(
              LassoSelector.selects(s, polygon, c),
              want,
              reason: '$name ${s.id} share $share coverage $c',
            );
            if (want && c == 0.6) picked++;
          }
        }
        expect(picked, greaterThan(100), reason: name);
      }
    });
  });
}
