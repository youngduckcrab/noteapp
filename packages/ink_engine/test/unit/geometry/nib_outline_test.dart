// m5-7/03-ink T28 (6.4 N1–N7): the calligraphy outline — the elliptic nib (major
// radius a = 2 · width · widthQ, minor b = nibAspect · a, major axis at nibAngleDeg
// clockwise on the screen) swept along the centerline. The support point formula:
// at 0° a horizontal stroke is 2b wide and a vertical one 2a (± 0.01 pt), a stroke
// at any direction is 2 · h(n) wide (h = the ellipse's support function of the
// side normal); aspect 1 is the round-1 fill outline (area < 1 %); a dot is the
// nib ellipse; a sharp corner splits the polygon; turning the points by ψ with the
// angle + ψ turns the outline (0°, 45°, 90°, 135°); the real pipeline reads the
// style's nib (OutlineGenerator.outline), and the live chunks are nib outlines
// (6.4 'live'). The outline checksum recorded here is also checked in Chrome
// (test/web/geometry_on_web_test.dart).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/geometry/stroke_outline.dart';
import 'package:ink_engine/src/input/pressure_detector.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/render/sessions.dart';
import 'package:ink_engine/src/stroke/stroke_builder.dart';
import 'package:note_core/note_core.dart' as core;

import '../../support/outline_helpers.dart';

StrokeOutline _nib(
  List<ui.Offset> xy, {
  double width = 4,
  double widthQ = 0.25,
  double angleDeg = 0,
  double aspect = 0.25,
}) => OutlineGenerator.nib(
  pointsOf(xy, widthQ: widthQ),
  width: width,
  angleDeg: angleDeg,
  aspect: aspect,
);

/// A straight line of [length] pt from [from] in the direction [deg] (clockwise
/// on the screen), a point every 2 pt.
List<ui.Offset> _line(ui.Offset from, double deg, {double length = 100}) {
  final r = deg * math.pi / 180;
  final d = ui.Offset(math.cos(r), math.sin(r));
  return sampleCurve((u) => from + d * (length * u), length: length, step: 2);
}

ui.Rect _vertexBounds(StrokeOutline o) {
  var l = double.infinity, t = double.infinity;
  var r = double.negativeInfinity, b = double.negativeInfinity;
  for (final p in o.polygons) {
    for (var i = 0; i + 1 < p.length; i += 2) {
      l = math.min(l, p[i]);
      r = math.max(r, p[i]);
      t = math.min(t, p[i + 1]);
      b = math.max(b, p[i + 1]);
    }
  }
  return ui.Rect.fromLTRB(l, t, r, b);
}

double _area(StrokeOutline o) {
  var a = 0.0;
  for (final p in o.polygons) {
    a += polygonArea(p);
  }
  return a;
}

/// The support function of the nib ellipse (major [a] along [deg], minor [b]) for
/// the unit normal [n]: the half width of a straight stroke across [n].
double _support(double a, double b, double deg, ui.Offset n) {
  final r = deg * math.pi / 180;
  final un = math.cos(r) * n.dx + math.sin(r) * n.dy;
  final vn = -math.sin(r) * n.dx + math.cos(r) * n.dy;
  return math.sqrt(a * a * un * un + b * b * vn * vn);
}

/// Distance from (px, py) to the closed polygon [poly]'s edges.
double _toPolygon(Float32List poly, double px, double py) {
  final m = poly.length ~/ 2;
  final xy = [
    for (var i = 0; i <= m; i++)
      ui.Offset(poly[2 * (i % m)], poly[2 * (i % m) + 1]),
  ];
  return distanceToPolyline(xy, px, py);
}

/// The largest distance from a vertex of [a] to the edges of [b] (both ways).
double _hausdorff(StrokeOutline a, StrokeOutline b) {
  double oneWay(StrokeOutline x, StrokeOutline y) {
    var worst = 0.0;
    for (final p in x.polygons) {
      for (var i = 0; i + 1 < p.length; i += 2) {
        var best = double.infinity;
        for (final q in y.polygons) {
          best = math.min(best, _toPolygon(q, p[i], p[i + 1]));
        }
        worst = math.max(worst, best);
      }
    }
    return worst;
  }

  return math.max(oneWay(a, b), oneWay(b, a));
}

StrokeOutline _rotated(StrokeOutline o, ui.Offset c, double deg) {
  final r = deg * math.pi / 180;
  final cs = math.cos(r), sn = math.sin(r);
  return StrokeOutline(
    polygons: [
      for (final p in o.polygons)
        Float32List.fromList([
          for (var i = 0; i + 1 < p.length; i += 2) ...[
            c.dx + (p[i] - c.dx) * cs - (p[i + 1] - c.dy) * sn,
            c.dy + (p[i] - c.dx) * sn + (p[i + 1] - c.dy) * cs,
          ],
        ]),
    ],
    bounds: ui.Rect.zero,
  );
}

List<ui.Offset> _rotatedPoints(List<ui.Offset> xy, ui.Offset c, double deg) {
  final r = deg * math.pi / 180;
  final cs = math.cos(r), sn = math.sin(r);
  return [
    for (final p in xy)
      ui.Offset(
        c.dx + (p.dx - c.dx) * cs - (p.dy - c.dy) * sn,
        c.dy + (p.dx - c.dx) * sn + (p.dy - c.dy) * cs,
      ),
  ];
}

List<ui.Offset> _sCurve({ui.Offset origin = const ui.Offset(60, 120)}) =>
    sampleCurve(
      (u) => origin + ui.Offset(200 * u, 40 * math.sin(u * 2 * math.pi)),
      length: 260,
      step: 2,
    );

/// Quantized polygons of an outline (0.01 pt), arithmetic only (web-safe).
int _outlineChecksum(StrokeOutline o) {
  const m = 1000000007;
  var sum = 0;
  void add(double v) => sum = (sum * 31 + (v * 100).round() + m) % m;
  for (final poly in o.polygons) {
    add(poly.length.toDouble());
    for (final v in poly) {
      add(v);
    }
  }
  return sum;
}

/// Nib outlines of a few shapes, angles, aspects and widths.
List<StrokeOutline> _checksumOutlines() => [
  for (final (angle, aspect) in [(0.0, 0.25), (45.0, 0.1), (135.0, 0.6)])
    for (final width in [0.5, 2.5, 18.0])
      for (final xy in [
        _line(const ui.Offset(20, 30), 0),
        _line(const ui.Offset(20, 30), 60),
        _sCurve(),
        [
          const ui.Offset(50, 300),
          const ui.Offset(150, 300),
          const ui.Offset(60, 320),
        ],
        [const ui.Offset(400, 400)],
      ])
        _nib(xy, width: width, angleDeg: angle, aspect: aspect),
];

/// The checksum of _checksumOutlines() recorded on the VM (T28).
const int _recordedNibChecksum = 168632678;

void main() {
  group('the support point formula (N4)', () {
    // width 4, widthQ 0.25 → a = 2; aspect 0.25 → b = 0.5
    test('0°: a horizontal stroke is 2b wide, a vertical one 2a', () {
      final h = _vertexBounds(_nib(_line(const ui.Offset(10, 50), 0)));
      expect(h.height, closeTo(1.0, 0.01), reason: '2b');
      // the cap tip is between two of its 9 vertices: a · (1 − cos(π / 18)) short
      expect(h.width, closeTo(100 + 2 * 2, 0.07), reason: 'length + 2a');
      final v = _vertexBounds(_nib(_line(const ui.Offset(50, 10), 90)));
      expect(v.width, closeTo(4.0, 0.01), reason: '2a');
      expect(v.height, closeTo(100 + 2 * 0.5, 0.02), reason: 'length + 2b');
    });

    test('90°: the other way round; aspect 1 → 2a both ways', () {
      final h = _vertexBounds(
        _nib(_line(const ui.Offset(10, 50), 0), angleDeg: 90),
      );
      expect(h.height, closeTo(4.0, 0.01));
      final v = _vertexBounds(
        _nib(_line(const ui.Offset(50, 10), 90), angleDeg: 90),
      );
      expect(v.width, closeTo(1.0, 0.01));
      for (final deg in [0.0, 90.0]) {
        final o = _nib(
          _line(const ui.Offset(10, 50), deg),
          angleDeg: 30,
          aspect: 1,
        );
        final b = _vertexBounds(o);
        expect(deg == 0 ? b.height : b.width, closeTo(4.0, 0.01));
      }
    });

    test('any direction: the half width is the support function h(n)', () {
      const c = ui.Offset(200, 200);
      for (final nibDeg in [0.0, 30.0, 45.0, 100.0, 170.0]) {
        for (final aspect in [0.1, 0.25, 0.7]) {
          for (final dir in [0.0, 15.0, 45.0, 80.0, 120.0, 200.0, 300.0]) {
            final xy = _line(c, dir, length: 60);
            final o = _nib(xy, angleDeg: nibDeg, aspect: aspect);
            final r = dir * math.pi / 180;
            final d = ui.Offset(math.cos(r), math.sin(r));
            final n = ui.Offset(-d.dy, d.dx);
            // the extent across the line: the side points L, R (the caps stay
            // inside ± h; O8 may drop a side end within its b / 4 tolerance)
            var left = double.negativeInfinity;
            var right = double.infinity;
            for (final p in o.polygons) {
              for (var i = 0; i + 1 < p.length; i += 2) {
                final q = ui.Offset(p[i], p[i + 1]) - c;
                final across = q.dx * n.dx + q.dy * n.dy;
                left = math.max(left, across);
                right = math.min(right, across);
              }
            }
            final h = _support(2, 2 * aspect, nibDeg, n);
            final label = 'nib $nibDeg aspect $aspect direction $dir';
            expect(left, closeTo(h, 0.015), reason: label);
            expect(right, closeTo(-h, 0.015), reason: label);
          }
        }
      }
    });

    test('the radius follows widthQ: a = 2 · width · widthQ (minRadiusPt)', () {
      final o = _nib(_line(const ui.Offset(50, 10), 90), width: 3, widthQ: 0.5);
      expect(_vertexBounds(o).width, closeTo(2 * (2 * 3 * 0.5), 0.01));
      final thin = _nib(
        _line(const ui.Offset(50, 10), 90),
        width: 0.001,
        widthQ: 0.25,
      );
      expect(
        _vertexBounds(thin).width,
        closeTo(2 * InkTuning.minRadiusPt, 0.002),
      );
    });
  });

  group('aspect 1 = the round-1 fill outline', () {
    for (final (name, xy, widthQ) in [
      ('S curve', _sCurve(), 0.25),
      ('S curve, wide', _sCurve(), 0.6),
      (
        'corner',
        [
          const ui.Offset(50, 300),
          const ui.Offset(150, 300),
          const ui.Offset(60, 320),
        ],
        0.25,
      ),
      (
        'spiral',
        [
          for (var i = 0; i <= 120; i++)
            ui.Offset(
              300 + (5 + i * 0.4) * math.cos(i / 8),
              300 + (5 + i * 0.4) * math.sin(i / 8),
            ),
        ],
        0.4,
      ),
    ]) {
      test('$name: area difference < 1 %, the same polygons', () {
        for (final angle in [0.0, 45.0, 120.0]) {
          final nib = _nib(
            xy,
            width: 6,
            widthQ: widthQ,
            angleDeg: angle,
            aspect: 1,
          );
          final round = outlineFor(xy, width: 6, widthQ: widthQ);
          expect(nib.polygons.length, round.polygons.length);
          final an = _area(nib), ar = _area(round);
          expect((an - ar).abs() / ar, lessThan(0.01), reason: '$angle°');
          expect(_hausdorff(nib, round), lessThan(0.05), reason: '$angle°');
        }
      });
    }
  });

  group('dots and corners (N1, N3)', () {
    test('a dot is the nib ellipse (2 × the O6 segment count)', () {
      for (final (angle, aspect, width) in [
        (0.0, 0.25, 4.0),
        (45.0, 0.1, 10.0),
        (135.0, 1.0, 1.0),
      ]) {
        const c = ui.Offset(80, 90);
        for (final xy in [
          [c],
          [c, c, c],
          [c, c + const ui.Offset(0.0004, 0.0003)],
        ]) {
          final o = _nib(xy, width: width, angleDeg: angle, aspect: aspect);
          final a = 2 * width * 0.25, b = aspect * a;
          expect(o.isDot, isFalse, reason: 'a polygon, not a circle');
          expect(o.polygons, hasLength(1));
          final poly = o.polygons.single;
          final segments =
              2 *
              (math.pi * a / InkTuning.capChordPt).ceil().clamp(
                4,
                InkTuning.maxCapSegments,
              );
          expect(poly.length ~/ 2, segments);
          expect(polygonArea(poly), greaterThan(0));
          final r = angle * math.pi / 180;
          for (var i = 0; i + 1 < poly.length; i += 2) {
            final q = ui.Offset(poly[i], poly[i + 1]) - c;
            final u = q.dx * math.cos(r) + q.dy * math.sin(r);
            final v = -q.dx * math.sin(r) + q.dy * math.cos(r);
            expect(
              (u / a) * (u / a) + (v / b) * (v / b),
              closeTo(1, 1e-3),
              reason: 'on the ellipse ($angle°, $aspect)',
            );
          }
          expect(o.bounds, _vertexBounds(o));
        }
      }
    });

    test('a sharp corner splits the polygon; a gentle bend does not', () {
      final sharp = _nib([
        const ui.Offset(50, 300),
        const ui.Offset(150, 300),
        const ui.Offset(60, 320),
      ], angleDeg: 45);
      expect(sharp.polygons, hasLength(2));
      final gentle = _nib([
        const ui.Offset(50, 300),
        const ui.Offset(150, 300),
        const ui.Offset(250, 330),
      ], angleDeg: 45);
      expect(gentle.polygons, hasLength(1));
      for (final o in [sharp, gentle]) {
        for (final p in o.polygons) {
          expect(polygonArea(p), greaterThan(0), reason: 'O7 orientation');
        }
      }
    });

    test('the caps are half ellipses on the forward and back sides', () {
      // 0°, horizontal: the ends reach ± a past the end points along x
      final o = _nib(_line(const ui.Offset(10, 50), 0), angleDeg: 0);
      final b = _vertexBounds(o);
      // 9 cap segments: the tip a · (1 − cos(π / 18)) = 0.03 short at most
      expect(b.left, closeTo(10 - 2, 0.035));
      expect(b.right, closeTo(110 + 2, 0.035));
      // 90°, horizontal: the ends reach ± b past the end points
      final o90 = _nib(_line(const ui.Offset(10, 50), 0), angleDeg: 90);
      final b90 = _vertexBounds(o90);
      expect(b90.left, closeTo(10 - 0.5, 0.01));
      expect(b90.right, closeTo(110 + 0.5, 0.01));
    });

    test('every coordinate is finite; NaN points and an aspect out of range '
        'are tolerated', () {
      final o = OutlineGenerator.nib(
        pointsOf([
          const ui.Offset(10, 10),
          const ui.Offset(double.nan, 20),
          const ui.Offset(40, 30),
        ]),
        width: 2,
        angleDeg: double.infinity,
        aspect: double.nan,
      );
      expect(outlineIsFinite(o), isTrue);
      final clamped = _nib(_line(const ui.Offset(10, 50), 0), aspect: 0.01);
      expect(
        _vertexBounds(clamped).height,
        closeTo(2 * 0.2, 0.01),
        reason: 'aspect clamped to 0.1',
      );
    });
  });

  group('rotation symmetry (0°, 45°, 90°, 135°)', () {
    const c = ui.Offset(200, 220);
    for (final angle in [0.0, 45.0, 90.0, 135.0]) {
      for (final turn in [45.0, 90.0, 30.0]) {
        test('nib $angle° turned by $turn°', () {
          for (final xy in [
            _sCurve(origin: const ui.Offset(100, 200)),
            [
              const ui.Offset(150, 200),
              const ui.Offset(250, 200),
              const ui.Offset(160, 230),
            ],
            [const ui.Offset(180, 210)],
          ]) {
            final o = _nib(xy, width: 5, angleDeg: angle, aspect: 0.3);
            final turned = _nib(
              _rotatedPoints(xy, c, turn),
              width: 5,
              angleDeg: angle + turn,
              aspect: 0.3,
            );
            final expected = _rotated(o, c, turn);
            expect(turned.polygons.length, expected.polygons.length);
            expect(
              (_area(turned) - _area(expected)).abs() / _area(expected),
              lessThan(1e-3),
            );
            expect(_hausdorff(turned, expected), lessThan(0.035));
          }
        });
      }
    }

    test('a reversed stroke covers the same area (the nib is symmetric)', () {
      for (final angle in [0.0, 45.0, 90.0, 135.0]) {
        final xy = _sCurve();
        final a = _area(_nib(xy, angleDeg: angle));
        final b = _area(_nib(xy.reversed.toList(), angleDeg: angle));
        expect((a - b).abs() / a, lessThan(0.005), reason: '$angle°');
      }
    });
  });

  group('the pen (PenProfile.calligraphy, style extras)', () {
    test('OutlineSpec carries the nib for nibOutline only', () {
      final spec = OutlineSpec.of(
        PenProfile.calligraphy,
        nibAngleDeg: 30,
        nibAspect: 0.5,
      );
      expect(spec.method, InkRenderMethod.nibOutline);
      expect((spec.nibAngleDeg, spec.nibAspect), (30, 0.5));
      final other = OutlineSpec.of(
        PenProfile.ballpoint,
        nibAngleDeg: 30,
        nibAspect: 0.5,
      );
      expect(other, OutlineSpec.of(PenProfile.ballpoint));
      final style = core.StrokeStyle.defaultsFor(core.PenTool.calligraphy)
          .withInkExtras(nibAngleDeg: 200, nibAspect: 0.05);
      final fromStyle = OutlineSpec.ofStyle(style);
      expect(fromStyle.nibAngleDeg, closeTo(20, 1e-9), reason: 'mod 180');
      expect(fromStyle.nibAspect, 0.1, reason: 'clamped');
    });

    core.Stroke build(List<ui.Offset> xy, core.StrokeStyle style) =>
        interop.newCoreStroke(
          buildStroke(
            [
              for (var i = 0; i < xy.length; i++)
                InkSample(
                  position: xy[i],
                  timeUs: i * 8333,
                  kind: InkPointerKind.stylus,
                  pressure: 0.5,
                ),
            ],
            style: style,
            viewScale: 1,
          )!,
          id: 'c',
          pageId: 'p',
          penDownMillis: 0,
        );

    test('the real pipeline: OutlineGenerator.outline reads the style nib', () {
      final base = core.StrokeStyle.defaultsFor(core.PenTool.calligraphy)
          .copyWith(width: 8);
      expect(base.profile, same(PenProfile.calligraphy));
      for (final (angle, horizontalThin) in [(0.0, true), (90.0, false)]) {
        final style = base.withInkExtras(nibAngleDeg: angle);
        final h = InkStroke.of(build(_line(const ui.Offset(20, 40), 0), style));
        final v = InkStroke.of(
          build(_line(const ui.Offset(40, 20), 90), style),
        );
        expect(h.profile, same(PenProfile.calligraphy));
        final hb = OutlineGenerator.outline(h).bounds;
        final vb = OutlineGenerator.outline(v).bounds;
        final a = h.maxRadius;
        expect(a, greaterThan(2));
        if (horizontalThin) {
          expect(hb.height, closeTo(2 * 0.25 * a, 0.05));
          expect(vb.width, closeTo(2 * a, 0.05));
        } else {
          expect(hb.height, closeTo(2 * a, 0.05));
          expect(vb.width, closeTo(2 * 0.25 * a, 0.05));
        }
        // the default nib: 45°
        final d = InkStroke.of(build(_line(const ui.Offset(20, 40), 0), base));
        expect(
          OutlineGenerator.outline(d).bounds.height,
          closeTo(2 * _support(a, 0.25 * a, 45, const ui.Offset(0, 1)), 0.05),
        );
      }
    });

    test(
      'live: the frozen chunks and the tail are nib outlines (6.4 live)',
      () {
        final style = core.StrokeStyle.defaultsFor(core.PenTool.calligraphy)
            .copyWith(width: 8)
            .withInkExtras(nibAngleDeg: 0);
        final b = StrokeBuilder(
          style: style,
          viewScale: 1,
          pressure: PressureDetector(
            kind: InkPointerKind.stylus,
            mode: PressureMode.auto,
            prior: PressureCapability.supported,
          ),
        );
        for (var i = 0; i < 200; i++) {
          b.add(
            InkSample(
              position: ui.Offset(20 + 2.0 * i, 60),
              timeUs: i * 8333,
              kind: InkPointerKind.stylus,
              pressure: 0.5,
            ),
          );
        }
        final chunks = liveFrozenChunks(b.live);
        expect(chunks, isNotEmpty);
        final finished = b.finish()!;
        final a = InkStroke.of(
          interop.newCoreStroke(
            finished,
            id: 'c',
            pageId: 'p',
            penDownMillis: 0,
          ),
        ).maxRadius;
        for (final path in [...chunks, b.live.tailPath]) {
          final h = path.getBounds().height;
          if (h == 0) continue;
          expect(h, lessThan(2 * 0.25 * a + 0.1), reason: 'thin: 2b, not 2a');
          expect(h, greaterThan(2 * 0.25 * a * 0.8));
        }
      },
    );
  });

  test('outline checksum = the recorded VM value (Chrome: the same)', () {
    var sum = 0;
    for (final o in _checksumOutlines()) {
      sum = (sum * 7 + _outlineChecksum(o)) % 1000000007;
    }
    expect(sum, _recordedNibChecksum);
  });
}
