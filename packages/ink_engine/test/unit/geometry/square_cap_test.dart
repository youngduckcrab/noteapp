// T27 (m5-7/03-ink 6.7-1, review S-2): square caps. The tape reuses the
// round-1 square caps of the fill outline generator as they are — the
// highlighter's outline (the only round-1 user) is unchanged, checked against a
// checksum recorded with the round-1 generator. The one new shape is the dot
// of a square-capped fill pen (tape): an axis-aligned square of side w (corners
// 0.7071 · w from the point, inside the K-1 inflation 0.75 · w), drawn with
// sharp corners by the smooth path too. (T31) The tape's line-end corners are
// the round-1 square cap corners listed twice, sharp in the smooth path.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/geometry/stroke_outline.dart';

import '../../support/outline_helpers.dart';

/// Quantized polygons + dot of an outline (0.01 pt), arithmetic only.
int _outlineChecksum(StrokeOutline o) {
  const m = 1000000007;
  var sum = 0;
  void add(double v) => sum = (sum * 31 + (v * 100).round() + m) % m;
  final c = o.dotCenter;
  if (c != null) {
    add(c.dx);
    add(c.dy);
    add(o.dotRadius);
  }
  for (final poly in o.polygons) {
    add(poly.length.toDouble());
    for (final v in poly) {
      add(v);
    }
  }
  return sum;
}

/// Highlighter outlines of a few shapes and widths (straight, diagonal, S
/// curve, a corner, a dot).
List<StrokeOutline> _highlighterOutlines() {
  final shapes = <List<ui.Offset>>[
    [const ui.Offset(10, 10), const ui.Offset(110, 10)],
    [for (var i = 0; i <= 30; i++) ui.Offset(20 + 3.0 * i, 40 + 3.0 * i)],
    sampleCurve(
      (u) => ui.Offset(30 + 200 * u, 200 + 30 * math.sin(u * 2 * math.pi)),
      length: 260,
      step: 3,
    ),
    [
      const ui.Offset(50, 300),
      const ui.Offset(150, 300),
      const ui.Offset(60, 320),
    ],
    [const ui.Offset(400, 400)],
  ];
  return [
    for (final width in [0.5, 6.0, 24.0])
      for (final xy in shapes)
        outlineFor(xy, width: width, profile: PenProfile.highlighter),
  ];
}

/// The checksum of _highlighterOutlines() recorded with the round-1 generator
/// (before T27's OutlineSpec).
const int _roundOneHighlighterChecksum = 440172957;

Set<(double, double)> _vertices(Float32List poly) => {
  for (var i = 0; i + 1 < poly.length; i += 2) (poly[i], poly[i + 1]),
};

void main() {
  test('highlighter square caps: the same outlines as round 1', () {
    var sum = 0;
    for (final o in _highlighterOutlines()) {
      sum = (sum * 7 + _outlineChecksum(o)) % 1000000007;
    }
    expect(sum, _roundOneHighlighterChecksum);
  });

  test('highlighter: a straight line is the w-wide box with square ends; a '
      'dot stays the round-1 circle', () {
    final o = outlineFor(
      [const ui.Offset(10, 10), const ui.Offset(110, 10)],
      width: 12,
      profile: PenProfile.highlighter,
    );
    expect(o.isDot, isFalse);
    expect(o.polygons, hasLength(1));
    expect(
      _vertices(o.polygons.single),
      containsAll({(4.0, 4.0), (116.0, 4.0)}),
    );
    expect(o.bounds, const ui.Rect.fromLTRB(4, 4, 116, 16));
    final dot = outlineFor(
      [const ui.Offset(50, 50)],
      width: 12,
      profile: PenProfile.highlighter,
    );
    expect(dot.isDot, isTrue);
    expect(dot.dotRadius, 6);
  });

  test('tape (square caps, constant radius w / 2): the line ends are the '
      'round-1 square caps', () {
    const w = 14.0;
    // widthQ 0.25 = kNominalWidthQ: the tape profile's factor is exactly 1
    final tape = outlineFor(
      [const ui.Offset(10, 10), const ui.Offset(110, 10)],
      width: w,
      profile: PenProfile.tape,
    );
    final highlighter = outlineFor(
      [const ui.Offset(10, 10), const ui.Offset(110, 10)],
      width: w,
      profile: PenProfile.highlighter,
    );
    // (T31) the same vertices; the tape lists its four cap corners twice so the
    // smooth path keeps them sharp (the highlighter outline is unchanged)
    expect(
      _vertices(tape.polygons.single),
      _vertices(highlighter.polygons.single),
    );
    expect(
      tape.polygons.single.length,
      highlighter.polygons.single.length + 4 * 2,
    );
    expect(tape.bounds, const ui.Rect.fromLTRB(3, 3, 117, 17));
    final smooth = tape.toPath();
    for (final corner in const [
      ui.Offset(3.3, 3.3),
      ui.Offset(116.7, 3.3),
      ui.Offset(116.7, 16.7),
      ui.Offset(3.3, 16.7),
    ]) {
      expect(smooth.contains(corner), isTrue, reason: 'sharp corner $corner');
    }
    // diagonal: the corners are r · √2 from the end points
    final diag = outlineFor(
      [ui.Offset.zero, const ui.Offset(30, 40)],
      width: w,
      profile: PenProfile.tape,
    );
    var far = 0.0;
    for (final (x, y) in _vertices(diag.polygons.single)) {
      final d = math.min(
        math.sqrt(x * x + y * y),
        math.sqrt((x - 30) * (x - 30) + (y - 40) * (y - 40)),
      );
      far = math.max(far, d);
    }
    expect(far, closeTo(w / 2 * math.sqrt2, 1e-3));
  });

  test(
    'tape dot: an axis-aligned square of side w, corners 0.7071 · w away',
    () {
      for (final w in [0.4, 14.0, 60.0]) {
        const c = ui.Offset(100, 200);
        final o = outlineFor([c], width: w, profile: PenProfile.tape);
        expect(o.isDot, isFalse, reason: 'a polygon, not the circle');
        expect(o.polygons, hasLength(1));
        final h = w / 2;
        expect(_vertices(o.polygons.single), {
          for (final (x, y) in [
            (c.dx - h, c.dy - h),
            (c.dx + h, c.dy - h),
            (c.dx + h, c.dy + h),
            (c.dx - h, c.dy + h),
          ])
            // Float32 storage
            (Float32List.fromList([x])[0], Float32List.fromList([y])[0]),
        });
        expect(o.bounds.width, closeTo(w, 1e-4));
        expect(o.bounds.height, closeTo(w, 1e-4));
        expect(o.bounds.center.dx, closeTo(c.dx, 1e-4));
        expect(o.bounds.center.dy, closeTo(c.dy, 1e-4));
        expect(polygonArea(o.polygons.single), closeTo(w * w, w * w * 1e-4));
        // corner distance r · √2 = 0.7071 · w ≤ 0.75 · w (the K-1 inflation)
        for (final (x, y) in _vertices(o.polygons.single)) {
          final d = (ui.Offset(x, y) - c).distance;
          expect(d / w, closeTo(math.sqrt2 / 2, 1e-4));
          expect(d, lessThanOrEqualTo(0.75 * w + 1e-6));
        }
        // the smooth path keeps the sharp corners: the full square
        final smooth = o.toPath().getBounds();
        expect(smooth.width, closeTo(w, 1e-3));
        expect(smooth.height, closeTo(w, 1e-3));
        expect(o.toPath().contains(c + ui.Offset(h * 0.95, h * 0.95)), isTrue);
        expect(o.toPath(smooth: false).getBounds().width, closeTo(w, 1e-3));
        final vp = o.toVectorPath();
        expect(vp.bounds.width, closeTo(w, 1e-3));
      }
    },
  );

  test('a zero-length tape line (repeated point) is the same square', () {
    final once = outlineFor(
      [const ui.Offset(5, 5)],
      width: 10,
      profile: PenProfile.tape,
    );
    final repeated = outlineFor(
      [
        const ui.Offset(5, 5),
        const ui.Offset(5, 5),
        const ui.Offset(5.0001, 5),
      ],
      width: 10,
      profile: PenProfile.tape,
    );
    expect(
      _vertices(repeated.polygons.single),
      _vertices(once.polygons.single),
    );
  });

  test('round-cap fill pens keep the round dot', () {
    for (final p in [
      PenProfile.ballpoint,
      PenProfile.brush,
      PenProfile.dashed,
    ]) {
      final o = outlineFor([const ui.Offset(5, 5)], width: 4, profile: p);
      expect(o.isDot, isTrue, reason: '$p');
    }
  });

  test('OutlineSpec.of: method, cap and radius rule of the profile', () {
    expect(
      OutlineSpec.of(PenProfile.tape),
      const OutlineSpec(
        method: InkRenderMethod.filledOutline,
        cap: InkCap.square,
      ),
    );
    expect(OutlineSpec.of(PenProfile.tape).squareDot, isTrue);
    expect(
      OutlineSpec.of(PenProfile.highlighter),
      const OutlineSpec(
        method: InkRenderMethod.strokedPolyline,
        cap: InkCap.square,
        constantRadius: true,
      ),
    );
    expect(OutlineSpec.of(PenProfile.highlighter).squareDot, isFalse);
    expect(OutlineSpec.of(PenProfile.brush).squareDot, isFalse);
    expect(
      OutlineSpec.of(PenProfile.calligraphy).method,
      InkRenderMethod.nibOutline,
    );
  });
}
