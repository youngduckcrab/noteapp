// T07 (03-ink 8, 6.8 O1–O9): the fill outline of a stroke.
//
// Also run in Chrome by test/web/geometry_on_web_test.dart.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/model/ink_points.dart';
import 'package:ink_engine/src/pen/pen_profile.dart';
import 'package:ink_engine/src/tuning.dart';

import '../../support/outline_helpers.dart';

void main() {
  group('straight line, constant width', () {
    for (final (width, widthQ) in [
      (4.0, 0.25),
      (1.6, 0.25),
      (30.0, 0.25),
      (0.1, 1.0),
      (2.0, 0.8),
    ]) {
      final r = 2 * width * widthQ;
      test('area ≈ L·2r + π·r² ±1% (width $width, widthQ $widthQ)', () {
        const length = 100.0;
        final xy = sampleCurve(
          (u) => ui.Offset(20 + length * u, 40 + 0.3 * length * u),
          length: length * math.sqrt(1 + 0.09),
        );
        final o = outlineFor(xy, width: width, widthQ: widthQ);
        expect(o.isDot, isFalse);
        expect(o.polygons, hasLength(1));
        final l = length * math.sqrt(1 + 0.09);
        final expected = l * 2 * r + math.pi * r * r;
        var area = 0.0;
        for (final p in o.polygons) {
          area += polygonArea(p);
        }
        expect((area - expected).abs() / expected, lessThan(0.01));
      });
    }

    test('the straight sides are simplified (O8)', () {
      final xy = sampleCurve((u) => ui.Offset(10 + 100 * u, 10), length: 100);
      final raw = outlineFor(
        xy,
        options: const OutlineOptions(simplifyTolerance: 0),
      );
      final simple = outlineFor(xy);
      expect(raw.vertexCount, greaterThan(2 * xy.length));
      expect(simple.vertexCount, lessThan(40));
      expect(simple.bounds.left, closeTo(raw.bounds.left, 1e-4));
      expect(simple.bounds.right, closeTo(raw.bounds.right, 1e-4));
      expect(simple.bounds.top, closeTo(raw.bounds.top, 1e-4));
      expect(simple.bounds.bottom, closeTo(raw.bounds.bottom, 1e-4));
    });
  });

  group('dot (O1)', () {
    test('one point → a circle of radius r', () {
      final o = outlineFor([const ui.Offset(50, 60)], width: 2, widthQ: 0.5);
      expect(o.isDot, isTrue);
      expect(o.polygons, isEmpty);
      expect(o.dotCenter, const ui.Offset(50, 60));
      expect(o.dotRadius, closeTo(2, 1e-9));
      expect(o.bounds, ui.Rect.fromCircle(center: o.dotCenter!, radius: 2));
      final path = o.toPath().getBounds();
      expect(path.left, closeTo(48, 1e-3));
      expect(path.right, closeTo(52, 1e-3));
      expect(o.vertexCount, 1);
    });

    test('repeated points and a length below 1e-3 are a dot too', () {
      final same = outlineFor(List.filled(5, const ui.Offset(3, 4)));
      expect(same.isDot, isTrue);
      final tiny = outlineFor([
        const ui.Offset(3, 4),
        const ui.Offset(3.0002, 4),
        const ui.Offset(3.0004, 4.0002),
      ]);
      expect(tiny.isDot, isTrue);
      expect(tiny.dotCenter, const ui.Offset(3, 4));
    });
  });

  group('sharp corners (O3) and orientation (O7)', () {
    List<ui.Offset> turn(double degrees) {
      final a = degrees * math.pi / 180;
      return [
        for (var i = 0; i <= 40; i++) ui.Offset(20.0 + i, 50),
        for (var i = 1; i <= 40; i++)
          ui.Offset(60 + i * math.cos(a), 50 + i * math.sin(a)),
      ];
    }

    test('180° back and forth → ≥ 2 polygons, all the same direction', () {
      final xy = [
        for (var i = 0; i <= 100; i++) ui.Offset(10.0 + i, 50),
        for (var i = 99; i >= 0; i--) ui.Offset(10.0 + i, 50),
      ];
      final o = outlineFor(xy);
      expect(o.polygons.length, greaterThanOrEqualTo(2));
      for (final p in o.polygons) {
        expect(polygonArea(p), greaterThan(0));
      }
    });

    test('a turn sharper than ~100° splits, a gentler one does not', () {
      expect(outlineFor(turn(90)).polygons, hasLength(1));
      expect(outlineFor(turn(95)).polygons, hasLength(1));
      expect(outlineFor(turn(105)).polygons, hasLength(2));
      expect(outlineFor(turn(150)).polygons, hasLength(2));
      for (final o in [outlineFor(turn(105)), outlineFor(turn(150))]) {
        for (final p in o.polygons) {
          expect(polygonArea(p), greaterThan(0));
        }
        // the corner itself is covered
        expect(o.toPath().contains(const ui.Offset(60, 50)), isTrue);
      }
    });

    test('random curves: every polygon has a positive shoelace area', () {
      final rnd = math.Random(7);
      for (var k = 0; k < 40; k++) {
        var p = const ui.Offset(100, 100);
        var heading = rnd.nextDouble() * 2 * math.pi;
        final xy = <ui.Offset>[p];
        for (var i = 0; i < 60; i++) {
          heading += (rnd.nextDouble() - 0.5) * 2.4;
          p += ui.Offset(math.cos(heading), math.sin(heading)) * 1.5;
          xy.add(p);
        }
        final o = outlineFor(xy, width: 1 + 6 * rnd.nextDouble());
        for (final poly in o.polygons) {
          expect(polygonArea(poly), greaterThan(0));
        }
      }
    });
  });

  group('distance to the centerline', () {
    for (final width in [4.0, 16.0]) {
      test('every vertex is r ±2% from the centerline (width $width)', () {
        final r = 2 * width * 0.25;
        final xy = sampleCurve(
          (u) => ui.Offset(
            100 + 60 * math.cos(u * 2 * math.pi / 3),
            100 + 60 * math.sin(u * 2 * math.pi / 3),
          ),
          length: 60 * 2 * math.pi / 3,
        );
        final o = outlineFor(xy, width: width);
        for (final poly in o.polygons) {
          for (var i = 0; i + 1 < poly.length; i += 2) {
            final d = distanceToPolyline(xy, poly[i], poly[i + 1]);
            expect(d, closeTo(r, 0.02 * r), reason: 'vertex ${i ~/ 2}');
          }
        }
      });
    }

    test('O5: a curve tighter than the radius keeps the centerline filled', () {
      // arc radius 2 with r = 4: the inner side runs backwards
      final xy = sampleCurve(
        (u) => ui.Offset(
          50 + 2 * math.cos(u * math.pi),
          50 + 2 * math.sin(u * math.pi),
        ),
        length: 2 * math.pi,
        step: 0.2,
      );
      final o = outlineFor(xy, width: 8, widthQ: 0.25);
      final path = o.toPath();
      for (final p in xy) {
        expect(windingNumber(o.polygons, p.dx, p.dy), isNot(0));
        expect(path.contains(p), isTrue);
      }
      expect(windingNumber(o.polygons, 50, 50), isNot(0));
      // fewer vertices on the inner side than points
      final raw = outlineFor(
        xy,
        width: 8,
        options: const OutlineOptions(simplifyTolerance: 0),
      );
      expect(raw.vertexCount, lessThan(2 * xy.length));
    });
  });

  test(
    'a loop overlapping itself fills the overlap, not the hole (nonzero)',
    () {
      final xy = <ui.Offset>[
        for (var i = 0; i <= 50; i++) ui.Offset(i.toDouble(), 50),
        ...sampleCurve(
          (u) => ui.Offset(
            50 + 20 * math.sin(u * 2 * math.pi),
            30 + 20 * math.cos(u * 2 * math.pi),
          ),
          length: 40 * math.pi,
        ).skip(1),
        for (var i = 1; i <= 50; i++) ui.Offset(50.0 + i, 50),
      ];
      final o = outlineFor(xy);
      expect(o.polygons, hasLength(1));
      expect(windingNumber(o.polygons, 47, 50).abs(), 2); // tail + loop
      expect(windingNumber(o.polygons, 50, 10).abs(), 1); // loop top
      expect(windingNumber(o.polygons, 50, 30), 0); // the hole
      final path = o.toPath();
      expect(path.contains(const ui.Offset(47, 50.5)), isTrue);
      expect(path.contains(const ui.Offset(50, 30)), isFalse);
    },
  );

  group('caps (O6)', () {
    test('segment count = clamp(⌈π·r / 0.75⌉, 4, 16)', () {
      const noSimplify = OutlineOptions(simplifyTolerance: 0);
      int vertices(double width, double widthQ) => outlineFor(
        [const ui.Offset(10, 10), const ui.Offset(60, 10)],
        width: width,
        widthQ: widthQ,
        options: noSimplify,
      ).vertexCount;
      // 2 points: 2 side vertices per side + (segments − 1) per cap
      expect(vertices(0.1, 0.001), 4 + 2 * 3); // r = minRadiusPt → 4
      expect(vertices(2, 0.25), 4 + 2 * 4); // r = 1: ⌈4.19⌉ = 5
      expect(vertices(30, 0.25), 4 + 2 * 15); // r = 15 → 16
    });

    test('round caps reach r beyond the ends', () {
      final o = outlineFor([
        const ui.Offset(10, 10),
        const ui.Offset(60, 10),
      ], width: 4);
      // r = 2, 9 segments: the vertex nearest the tip is at r · cos(π / 18)
      final tip = 2 * (1 - math.cos(math.pi / 18));
      expect(o.bounds.left, closeTo(8 + tip, 1e-4));
      expect(o.bounds.right, closeTo(62 - tip, 1e-4));
      expect(o.bounds.top, closeTo(8, 1e-4));
      expect(o.bounds.bottom, closeTo(12, 1e-4));
    });
  });

  group('highlighter (O9)', () {
    test('constant radius width / 2, square caps at r·√2', () {
      final o = outlineFor(
        [
          const ui.Offset(10, 10),
          const ui.Offset(35, 10),
          const ui.Offset(60, 10),
        ],
        width: 8,
        widthQ: 0.9,
        profile: PenProfile.highlighter,
      );
      expect(o.bounds, const ui.Rect.fromLTRB(6, 6, 64, 14));
      final corners = <double>[];
      for (final p in o.polygons) {
        for (var i = 0; i + 1 < p.length; i += 2) {
          corners.add(
            math.min(
              (ui.Offset(p[i], p[i + 1]) - const ui.Offset(10, 10)).distance,
              (ui.Offset(p[i], p[i + 1]) - const ui.Offset(60, 10)).distance,
            ),
          );
        }
      }
      expect(corners.reduce(math.max), closeTo(4 * math.sqrt2, 1e-4));
    });

    test('polyline = centerline x,y pairs', () {
      final pts = pointsOf([const ui.Offset(1, 2), const ui.Offset(3, 4)]);
      expect(OutlineGenerator.polyline(pts), [1, 2, 3, 4]);
    });
  });

  group('no NaN', () {
    test('duplicates, zero length, minimum width, widthQ 0', () {
      final cases = <List<ui.Offset>>[
        [
          const ui.Offset(5, 5),
          const ui.Offset(5, 5),
          const ui.Offset(5, 5),
          const ui.Offset(9, 5),
          const ui.Offset(9, 5),
          const ui.Offset(9, 9),
          const ui.Offset(9, 9),
        ],
        [const ui.Offset(5, 5), const ui.Offset(5, 5)],
        [
          for (var i = 0; i < 30; i++) ui.Offset(5 + i * 2e-6, 5 + i * 1e-6),
          const ui.Offset(5.01, 5),
        ],
        [for (var i = 0; i < 50; i++) ui.Offset(5 + 0.01 * i, 5)],
      ];
      for (final xy in cases) {
        for (final (width, widthQ) in [(0.1, 0.001), (1.6, 0.0), (30.0, 1.0)]) {
          final o = outlineFor(xy, width: width, widthQ: widthQ);
          expect(outlineIsFinite(o), isTrue, reason: '$xy $width $widthQ');
          expect(o.toPath().getBounds().isFinite, isTrue);
          final vp = o.toVectorPath();
          for (final c in vp.coords) {
            expect(c.isFinite, isTrue);
          }
        }
      }
      final minimal = outlineFor(
        [ui.Offset.zero, const ui.Offset(10, 0)],
        width: 0.1,
        widthQ: 0.001,
      );
      expect(minimal.bounds.top, closeTo(-InkTuning.minRadiusPt, 1e-6));
      expect(polygonArea(minimal.polygons.single), greaterThan(0));
    });

    test('non-finite raw values are read as 0', () {
      final raw = pointsOf([const ui.Offset(1, 1), const ui.Offset(4, 1)]).raw;
      raw[2] = double.nan;
      final o = OutlineGenerator.outlineOf(
        InkPoints.fromRaw(raw),
        width: 2,
        profile: PenProfile.fountain,
      );
      expect(outlineIsFinite(o), isTrue);
    });
  });
}
