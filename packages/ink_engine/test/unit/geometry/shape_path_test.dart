// m5-7/03-ink T33 (6.5 D2–D5, 6.9): the shared dash splitter and the shape
// geometry — polyline / ellipse paths, arrow heads (apex, both sides exactly
// L, the line ends at the base midpoint, zero-length segments skipped, no
// head when every segment is zero), ellipse dash sampling 32..256, dashed
// [4, 3] and dotted [0, 2] pieces, the 4096 cap, and the vector outline whose
// line and head contours share one orientation (S-10).
//
// Also run in Chrome by test/web/object_bounds_web_test.dart.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/src/geometry/dash.dart';
import 'package:ink_engine/src/object/shape_path.dart';
import 'package:ink_engine/src/tuning.dart';
import 'package:note_core/note_core.dart' as core;

core.ShapeObject _shape(
  core.ShapeGeometry geometry, {
  core.ShapeKind kind = core.ShapeKind.line,
  double width = 2,
  core.LineDash dash = core.LineDash.solid,
  core.ArrowHeads heads = core.ArrowHeads.none,
  int? fill,
}) => core.ShapeObject(
  id: 'sh',
  pageId: 'p1',
  shapeKind: kind,
  geometry: geometry,
  style: core.ShapeStyle(
    strokeColorArgb: 0xFF000000,
    strokeWidth: width,
    dash: dash,
    arrowHeads: heads,
    fillColorArgb: fill,
  ),
  createdAt: 1,
);

core.PolylineGeometry _poly(
  List<(double, double)> pts, {
  bool closed = false,
}) => core.PolylineGeometry([
  for (final (x, y) in pts) core.PagePoint(x, y),
], closed: closed);

Matcher _near(ui.Offset o, {double tol = 1e-6}) => isA<ui.Offset>().having(
  (p) => (p - o).distance,
  'distance to $o',
  lessThan(tol),
);

void main() {
  group('dash intervals (6.5 D2, D5)', () {
    test('[4, 3] × 1 pt: phase 0, on 4, off 3, cut at the end', () {
      final iv = dashIntervals(20, const [4, 3]);
      expect(iv.first.start, 0, reason: 'starts with a dash');
      expect(
        [for (final i in iv) (i.start, i.end)],
        [(0.0, 4.0), (7.0, 11.0), (14.0, 18.0)],
      );
      final cut = dashIntervals(16, const [4, 3]);
      expect(cut.last.end, 16, reason: 'the last dash is cut by the end');
    });

    test('[0, 2]: zero-length intervals every 2 pt', () {
      final iv = dashIntervals(10, const [0, 2]);
      expect([for (final i in iv) i.start], [0, 2, 4, 6, 8]);
      expect(iv.every((i) => i.end == i.start), isTrue);
    });

    test('invalid patterns draw solid; a zero-length path is one dot', () {
      for (final p in const [
        <double>[],
        [-1.0, 2.0],
        [0.0, 0.0],
        [double.nan, 1.0],
      ]) {
        expect(
          [for (final i in dashIntervals(10, p)) (i.start, i.end)],
          [(0.0, 10.0)],
          reason: '$p',
        );
      }
      expect(dashIntervals(0, const [4, 3]).single.end, 0);
      // an odd pattern repeats: [2] = [2, 2]
      expect(
        [
          for (final i in dashIntervals(9, const [2])) i.start,
        ],
        [0, 4, 8],
      );
    });

    test('more than dashMaxSegments → the pattern is stretched to fit', () {
      final iv = dashIntervals(1e6, const [0.1, 0.1]);
      expect(iv.length, lessThanOrEqualTo(InkTuning.dashMaxSegments));
      expect(iv.length, greaterThan(InkTuning.dashMaxSegments * 0.9));
      final on = iv[1].end - iv[1].start, off = iv[2].start - iv[1].end;
      expect(
        on,
        closeTo(off, 1e-6),
        reason: 'one factor for the whole pattern',
      );
      expect(
        dashIntervals(100, const [1, 1], maxSegments: 10).length,
        lessThanOrEqualTo(10),
      );
    });

    test('pieces: capsule ends at a + r, b − r on the segments; dots', () {
      final line = PolylineMeasure(const [
        ui.Offset.zero,
        ui.Offset(10, 0),
        ui.Offset(10, 10),
      ]);
      expect(line.length, 20);
      final pieces = dashPieces(line, const [4, 3], radius: 0.5);
      // [0, 4] → [0.5, 3.5]; [7, 11] → [7.5, 10.5] across the corner
      expect(pieces.first, [
        _near(const ui.Offset(0.5, 0)),
        _near(const ui.Offset(3.5, 0)),
      ]);
      expect(pieces[1], [
        _near(const ui.Offset(7.5, 0)),
        _near(const ui.Offset(10, 0)),
        _near(const ui.Offset(10, 0.5)),
      ]);
      // visible length of a capsule with its round caps = on
      for (final p in pieces.take(2)) {
        final m = PolylineMeasure(p);
        expect(m.length + 2 * 0.5, closeTo(4, 0.05));
      }
      final dots = dashPieces(line, const [0, 2], radius: 0.5);
      expect(dots.every((p) => p.length == 1), isTrue);
      expect(dots[3].single, _near(const ui.Offset(6, 0)));
      expect(dots[6].single, _near(const ui.Offset(10, 2)));
      expect(line.at(15), _near(const ui.Offset(10, 5)));
    });

    test('ellipse dash sampling: clamp(⌈perimeter / 2⌉, 32, 256)', () {
      expect(ellipseDashSegments(1, 1), 32);
      expect(ellipseDashSegments(1000, 1000), 256);
      expect(ellipseDashSegments(50, 50), (math.pi * 100 / 2).ceil());
    });
  });

  group('shape paths (6.9.1)', () {
    test('polyline: open as given, closed back to the first point', () {
      final open = shapeGeometryOf(
        _shape(_poly([(10, 10), (50, 10), (50, 40)])),
      );
      expect(open.centerline, hasLength(3));
      expect(open.closed, isFalse);
      expect(open.fill, isNull);
      final rect = shapeGeometryOf(
        _shape(
          core.ShapeGeometry.rectangle(const core.PageRect(10, 20, 110, 70)),
          kind: core.ShapeKind.rectangle,
          fill: 0xFFFF0000,
        ),
      );
      expect(rect.closed, isTrue);
      expect(rect.centerline.first, rect.centerline.last);
      expect(rect.centerline, hasLength(5));
      expect(rect.fill!.getBounds(), const ui.Rect.fromLTRB(10, 20, 110, 70));
      expect(
        rect.strokePath!.getBounds(),
        const ui.Rect.fromLTRB(10, 20, 110, 70),
      );
      // an open polyline is never filled
      final openFilled = shapeGeometryOf(
        _shape(_poly([(0, 0), (10, 10)]), fill: 0xFFFF0000),
      );
      expect(openFilled.fill, isNull);
    });

    test('ellipse: the exact oval, rotated about its center', () {
      final e = shapeGeometryOf(
        _shape(
          core.ShapeGeometry.ellipse(const core.PageRect(0, 0, 100, 40)),
          kind: core.ShapeKind.ellipse,
          fill: 0xFF00FF00,
        ),
      );
      expect(e.oval, isNotNull);
      final b = e.strokePath!.getBounds();
      expect(b.left, closeTo(0, 1e-3));
      expect(b.right, closeTo(100, 1e-3));
      expect(b.height, closeTo(40, 1e-3));
      expect(e.fill, isNotNull);
      final turned = shapeGeometryOf(
        _shape(
          core.ShapeGeometry.ellipse(
            const core.PageRect(0, 0, 100, 40),
            rotation: math.pi / 2,
          ),
          kind: core.ShapeKind.ellipse,
        ),
      );
      final t = turned.strokePath!.getBounds();
      expect(t.width, closeTo(40, 1e-3));
      expect(t.height, closeTo(100, 1e-3));
      expect(t.center.dx, closeTo(50, 1e-3));
      expect(t.center.dy, closeTo(20, 1e-3));
    });

    test('dashed / dotted ellipse: a sampled closed centerline', () {
      final e = shapeGeometryOf(
        _shape(
          core.ShapeGeometry.ellipse(const core.PageRect(0, 0, 100, 100)),
          kind: core.ShapeKind.ellipse,
          dash: core.LineDash.dashed,
          width: 2,
        ),
      );
      expect(e.oval, isNull);
      expect(e.centerline, hasLength(ellipseDashSegments(50, 50) + 1));
      expect(e.centerline.first, _near(e.centerline.last));
      for (final p in e.centerline) {
        expect((p - const ui.Offset(50, 50)).distance, closeTo(50, 1e-9));
      }
      expect(e.capsules, isNotEmpty);
      final dotted = shapeGeometryOf(
        _shape(
          core.ShapeGeometry.ellipse(const core.PageRect(0, 0, 100, 100)),
          kind: core.ShapeKind.ellipse,
          dash: core.LineDash.dotted,
          width: 2,
        ),
      );
      expect(dotted.capsules, isEmpty);
      // dots every 2·w along the sampled perimeter
      expect(
        dotted.dots.length,
        closeTo(PolylineMeasure(dotted.centerline).length / 4, 1),
      );
    });

    test('dashed rectangle: [4, 3] × w capsules from the first corner', () {
      final g = shapeGeometryOf(
        _shape(
          core.ShapeGeometry.rectangle(const core.PageRect(0, 0, 70, 70)),
          kind: core.ShapeKind.rectangle,
          dash: core.LineDash.dashed,
          width: 2,
        ),
      );
      // period 14 pt; capsule centerline = 8 − 2 = 6 pt (visible 8 with the caps)
      expect(g.capsules.first.first, _near(const ui.Offset(1, 0)));
      expect(g.capsules.first.last, _near(const ui.Offset(7, 0)));
      expect(g.capsules[1].first, _near(const ui.Offset(15, 0)));
      expect(g.capsules.length, (280 / 14).ceil());
    });
  });

  group('arrow heads (6.9.3)', () {
    const alpha = InkTuning.arrowHeadHalfAngleDeg * math.pi / 180;

    test('end: apex E, both sides exactly L, line to the base midpoint', () {
      final o = _shape(
        _poly([(0, 0), (100, 0)]),
        kind: core.ShapeKind.arrow,
        width: 4,
        heads: core.ArrowHeads.end,
      );
      final l = o.style.arrowHeadLength;
      expect(l, 12, reason: 'CORE max(6, 3·w)');
      final g = shapeGeometryOf(o);
      final head = g.heads.single;
      const e = ui.Offset(100, 0);
      expect(head[0], e);
      expect((head[1] - e).distance, closeTo(l, 1e-9));
      expect((head[2] - e).distance, closeTo(l, 1e-9));
      final base = ui.Offset.lerp(head[1], head[2], 0.5)!;
      expect(base, _near(ui.Offset(100 - l * math.cos(alpha), 0)));
      expect(g.centerline.last, _near(base), reason: 'the line stops at B');
      expect(g.centerline.first, ui.Offset.zero);
    });

    test('both: heads at both ends; the line between the base midpoints', () {
      final o = _shape(
        _poly([(0, 0), (0, 100)]),
        width: 2,
        heads: core.ArrowHeads.both,
      );
      final g = shapeGeometryOf(o);
      expect(g.heads, hasLength(2));
      final back = o.style.arrowHeadLength * math.cos(alpha);
      expect(g.centerline.first, _near(ui.Offset(0, back)));
      expect(g.centerline.last, _near(ui.Offset(0, 100 - back)));
      expect(g.heads[1][0], ui.Offset.zero);
    });

    test('zero-length segments are skipped; all zero → no head', () {
      final g = shapeGeometryOf(
        _shape(
          _poly([(0, 0), (50, 0), (50, 0), (50, 0)]),
          heads: core.ArrowHeads.end,
        ),
      );
      final head = g.heads.single;
      expect(head[0], const ui.Offset(50, 0));
      expect(head[1].dx, lessThan(50), reason: 'direction of (0,0)→(50,0)');
      expect(head[1].dy, closeTo(-head[2].dy, 1e-9));
      final none = shapeGeometryOf(
        _shape(_poly([(5, 5), (5, 5)]), heads: core.ArrowHeads.end),
      );
      expect(none.heads, isEmpty);
    });

    test('heads only on line / arrow kinds and open polylines', () {
      final tri = shapeGeometryOf(
        _shape(
          core.ShapeGeometry.triangle(const core.PageRect(0, 0, 50, 50)),
          kind: core.ShapeKind.triangle,
          heads: core.ArrowHeads.end,
        ),
      );
      expect(tri.heads, isEmpty);
      final short = shapeGeometryOf(
        _shape(_poly([(0, 0), (5, 0)]), width: 4, heads: core.ArrowHeads.both),
      );
      expect(short.heads, hasLength(2));
      expect(short.centerline, isEmpty, reason: 'the heads cover the line');
    });
  });

  group('vector outline (6.9.5, S-10)', () {
    test('line outline and head contours have the same orientation', () {
      for (final heads in [core.ArrowHeads.end, core.ArrowHeads.both]) {
        for (final pts in [
          [(0.0, 0.0), (100.0, 0.0)],
          [(100.0, 50.0), (0.0, 0.0)],
          [(0.0, 0.0), (40.0, 40.0), (80.0, 0.0)],
        ]) {
          final out = shapeOutlineOf(
            _shape(_poly(pts), kind: core.ShapeKind.arrow, heads: heads),
          );
          expect(out.stroke.length, greaterThanOrEqualTo(2));
          for (final poly in out.stroke) {
            expect(shoelaceArea(poly), greaterThan(0), reason: '$pts $heads');
          }
        }
      }
    });

    test('fill polygons and dash pieces, all positive', () {
      final out = shapeOutlineOf(
        _shape(
          core.ShapeGeometry.ellipse(const core.PageRect(0, 0, 80, 40)),
          kind: core.ShapeKind.ellipse,
          dash: core.LineDash.dashed,
          fill: 0xFF0000FF,
        ),
      );
      expect(out.fill, hasLength(1));
      expect(out.stroke.length, greaterThan(5));
      for (final p in [...out.fill, ...out.stroke]) {
        expect(shoelaceArea(p), greaterThan(0));
      }
      final dotted = shapeOutlineOf(
        _shape(_poly([(0, 0), (40, 0)]), dash: core.LineDash.dotted, width: 2),
      );
      expect(dotted.stroke, hasLength(10), reason: 'a dot every 4 pt');
    });
  });
}
