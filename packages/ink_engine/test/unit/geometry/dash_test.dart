// m5-7/03-ink T29 (6.5 D1–D5): the dashed pen's outline — the stored
// centerline split by style.dashPattern × width from phase 0, every visible
// interval [a, b] a round-cap piece [a + r, b − r] (visible length b − a) or a
// dot of diameter w, the piece ends InkPoints.lerpAt of the centerline, the
// 4096 cap stretching the whole pattern by one factor, an invalid pattern the
// default [4, 3]. All pieces are one outline (one nonZero path, many contours).
//
// The outline checksum of fixed dashed outlines (test/support/
// outline_checksums.dart) is the recorded VM value — Chrome: the same
// (test/web/determinism_test.dart). Also run in Chrome by
// test/web/geometry_on_web_test.dart.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/dash.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/geometry/stroke_outline.dart';
import 'package:note_core/note_core.dart' as core;

import '../../support/outline_checksums.dart';

var _ids = 0;

/// A dashed stroke through [xy] (widthQ = kNominalWidthQ, the only value the
/// dashed profile makes; t and tilt vary so lerpAt has every channel to check).
InkStroke _dashed(
  List<ui.Offset> xy, {
  double width = 1,
  Object? dash,
  bool setDash = false,
}) {
  final data = Float32List(xy.length * InkPoints.stride);
  for (var i = 0; i < xy.length; i++) {
    final o = i * InkPoints.stride;
    data[o] = xy[i].dx;
    data[o + 1] = xy[i].dy;
    data[o + 2] = core.kNominalWidthQ;
    data[o + 3] = 0.1 + 0.001 * i;
    data[o + 5] = 8.0 * i;
  }
  var style = core.StrokeStyle.defaultsFor(core.PenTool.dashed)
      .copyWith(width: width);
  if (setDash) {
    style = style.copyWith(
      extras: {...style.extras, InkStyleExtras.dash: dash},
    );
  }
  _ids++;
  return InkStroke.of(
    core.Stroke(
      id: 'd-$_ids',
      pageId: 'p',
      style: style,
      points: core.StrokePoints.fromInterleaved(data),
      createdAt: 1,
    ),
  );
}

List<ui.Offset> _line(
  double from,
  double to, {
  double step = 1,
  double y = 50,
}) {
  final n = ((to - from).abs() / step).round();
  return [
    for (var i = 0; i <= n; i++) ui.Offset(from + (to - from) * i / n, y),
  ];
}

/// x extent of every contour, in drawing order.
List<(double, double)> _xExtents(StrokeOutline o) => [
  for (final poly in o.polygons)
    () {
      var lo = double.infinity, hi = double.negativeInfinity;
      for (var i = 0; i < poly.length; i += 2) {
        lo = math.min(lo, poly[i]);
        hi = math.max(hi, poly[i]);
      }
      return (lo, hi);
    }(),
];

void main() {
  test('the dashed pen uses the dashed profile (6.2)', () {
    final s = _dashed(_line(0, 10));
    expect(s.profile, same(PenProfile.dashed));
    expect(s.profile.renderMethod, InkRenderMethod.dashedPolyline);
    expect(s.style.dashPattern, [4, 3]);
  });

  test('[4, 3] × 1 pt: dashes 4 ± 0.05, gaps 3 ± 0.05, phase 0 at the start, '
      'the last one cut at the end', () {
    final s = _dashed(_line(0, 100));
    final o = OutlineGenerator.outline(s);
    expect(o.isDot, isFalse);
    expect(o.dots, isEmpty);
    final xs = _xExtents(o);
    // 100 pt = 14 periods of 7 + 2: 15 dashes, the last [98, 100]
    expect(xs, hasLength(15));
    expect(xs.first.$1, closeTo(0, 0.05), reason: 'phase 0');
    for (var k = 0; k < xs.length - 1; k++) {
      expect(xs[k].$2 - xs[k].$1, closeTo(4, 0.05), reason: 'dash $k');
      expect(xs[k + 1].$1 - xs[k].$2, closeTo(3, 0.05), reason: 'gap $k');
      expect(xs[k].$1, closeTo(7.0 * k, 0.05), reason: 'start $k');
    }
    expect(xs.last.$1, closeTo(98, 0.05));
    expect(xs.last.$2, closeTo(100, 0.05));
    // the straight and the smooth path of the same contours
    final straight = o.toPath(smooth: false).getBounds();
    expect(straight.left, closeTo(0, 0.05));
    expect(straight.right, closeTo(100, 0.05));
    expect(straight.height, closeTo(1, 0.05));
    expect(o.toPath().computeMetrics().length, 15);
  });

  test('the pattern scales with the width: [4, 3] × 2.5 pt', () {
    final s = _dashed(_line(0, 200, step: 2), width: 2.5);
    final xs = _xExtents(OutlineGenerator.outline(s));
    for (var k = 0; k < xs.length - 1; k++) {
      expect(xs[k].$2 - xs[k].$1, closeTo(10, 0.05), reason: 'dash $k');
      expect(xs[k + 1].$1 - xs[k].$2, closeTo(7.5, 0.05), reason: 'gap $k');
    }
  });

  test('phase 0 is the stroke start, whichever way it goes', () {
    final s = _dashed(_line(100, 0));
    final xs = _xExtents(OutlineGenerator.outline(s));
    expect(xs.first.$2, closeTo(100, 0.05));
    expect(xs.first.$2 - xs.first.$1, closeTo(4, 0.05));
  });

  test('[0, 2] → dots of diameter w every 2·w', () {
    final s = _dashed(_line(0, 40), width: 2, dash: [0, 2], setDash: true);
    expect(s.style.dashPattern, [0, 2]);
    final o = OutlineGenerator.outline(s);
    expect(o.polygons, isEmpty);
    expect(o.dots, hasLength(10)); // 0, 4, …, 36 (an `on` starts before 40)
    expect(o.dotRadius * 2, closeTo(2, 1e-6));
    for (var k = 0; k < o.dots.length; k++) {
      expect(o.dots[k].dx, closeTo(4.0 * k, 1e-4));
      expect(o.dots[k].dy, closeTo(50, 1e-4));
    }
    final metrics = o.toPath().computeMetrics().toList();
    expect(metrics, hasLength(10));
    final b = o.toPath().getBounds();
    expect(b.height, closeTo(2, 0.01));
    expect(b.left, closeTo(-1, 0.01));
    // the vector path has the same dots: moveTo + 4 cubics + close each
    final v = o.toVectorPath();
    expect(v.verbs.length, 10 * 6);
    expect(v.bounds.height, closeTo(2, 0.01));
  });

  test('a dash shorter than the width is a dot at its middle; long and short '
      'pieces mix', () {
    // [0.5, 1, 3, 1] × 2 pt: on 1 (< 2r = 2) → dot at 0.5; on 6 → capsule
    final s = _dashed(
      _line(0, 60),
      width: 2,
      dash: [0.5, 1, 3, 1],
      setDash: true,
    );
    final o = OutlineGenerator.outline(s);
    // period 11: dots at 0.5 + 11k, capsules [3, 9] + 11k; the last interval
    // [58, 60] is exactly 2r long → a zero-length piece → a dot at 59
    expect(
      [for (final d in o.dots) d.dx],
      [
        for (final x in [0.5, 11.5, 22.5, 33.5, 44.5, 55.5, 59.0])
          closeTo(x, 1e-4),
      ],
    );
    final xs = _xExtents(o);
    expect(xs, hasLength(5));
    for (var k = 0; k < xs.length; k++) {
      expect(xs[k].$1, closeTo(3 + 11.0 * k, 0.05));
      expect(xs[k].$2, closeTo(9 + 11.0 * k, 0.05));
    }
  });

  test('an invalid pattern → the default [4, 3]', () {
    final reference = OutlineGenerator.outline(_dashed(_line(0, 50)));
    for (final bad in <Object?>[
      [1], // odd
      [1, 2, 3],
      ['a', 2],
      [0.1, 0.1], // sum < 0.5
      List<double>.filled(10, 1), // > 8
      'dash',
      null,
    ]) {
      final s = _dashed(_line(0, 50), dash: bad, setDash: true);
      expect(s.style.dashPattern, [4, 3], reason: '$bad');
      final o = OutlineGenerator.outline(s);
      expect(_xExtents(o), _xExtents(reference), reason: '$bad');
    }
    // an empty or non-positive pattern given to the splitter → solid
    expect(dashIntervals(10, const []), [(start: 0.0, end: 10.0)]);
    expect(dashIntervals(10, const [0, 0]), [(start: 0.0, end: 10.0)]);
  });

  test('more than dashMaxSegments intervals → the pattern stretched by one '
      'factor (D5)', () {
    // 0.1 pt wide, [0, 0.5] → a dot every 0.05 pt: 20,000 dots in 1000 pt
    final s = _dashed(
      _line(0, 1000, step: 2),
      width: 0.1,
      dash: [0, 0.5],
      setDash: true,
    );
    final o = OutlineGenerator.outline(s);
    final n = o.dots.length + o.polygons.length;
    expect(n, lessThanOrEqualTo(InkTuning.dashMaxSegments));
    expect(n, greaterThan(InkTuning.dashMaxSegments - 10));
    // one factor: the dots are evenly spaced
    final step = o.dots[1].dx - o.dots[0].dx;
    expect(step, greaterThan(0.05 * 4));
    for (var k = 1; k < o.dots.length; k++) {
      expect(o.dots[k].dx - o.dots[k - 1].dx, closeTo(step, 1e-3));
    }
    final iv = dashIntervals(1000, const [0.025, 0.025]);
    expect(iv.length, lessThanOrEqualTo(InkTuning.dashMaxSegments));
    final len0 = iv[0].end - iv[0].start, gap0 = iv[1].start - iv[0].end;
    expect(len0, closeTo(gap0, 1e-9), reason: 'the ratio is kept');
  });

  test('piece ends = InkPoints.lerpAt at the arc length, stored points '
      'between (D3)', () {
    final xy = [
      for (var i = 0; i <= 60; i++)
        ui.Offset(20 + 2.3 * i, 80 + 25 * math.sin(i / 60 * math.pi * 1.5)),
    ];
    final s = _dashed(xy, width: 1.5);
    final pts = s.points;
    // arc lengths by a plain scan (independent of the splitter)
    final cum = <double>[0];
    for (var i = 1; i < pts.length; i++) {
      cum.add(
        cum.last +
            math.sqrt(
              math.pow(pts.x(i) - pts.x(i - 1), 2) +
                  math.pow(pts.y(i) - pts.y(i - 1), 2),
            ),
      );
    }
    double indexAt(double s) {
      for (var i = 0; i + 1 < cum.length; i++) {
        if (s <= cum[i + 1]) return i + (s - cum[i]) / (cum[i + 1] - cum[i]);
      }
      return (cum.length - 1).toDouble();
    }

    const r = 0.75; // 2 · 1.5 · 0.25
    final pieces = dashedStrokePieces(pts, const [6, 4.5], radius: r);
    final intervals = dashIntervals(cum.last, const [6, 4.5]);
    expect(pieces, hasLength(intervals.length));
    void same(InkPoints piece, int at, double index, String why) {
      final want = pts.lerpAt(index);
      expect(piece.x(at), closeTo(want.x, 1e-4), reason: why);
      expect(piece.y(at), closeTo(want.y, 1e-4), reason: why);
      expect(piece.widthQ(at), closeTo(want.widthQ, 1e-6), reason: why);
      expect(piece.tilt(at), closeTo(want.tilt, 1e-5), reason: why);
      expect(piece.t(at), closeTo(want.t, 1e-3), reason: why);
    }

    for (var k = 0; k < pieces.length; k++) {
      final iv = intervals[k];
      final piece = pieces[k];
      if (iv.end - iv.start < 2 * r) {
        expect(piece.length, 1);
        same(piece, 0, indexAt((iv.start + iv.end) / 2), 'dot $k');
        continue;
      }
      final a = iv.start + r, b = iv.end - r;
      same(piece, 0, indexAt(a), 'start $k');
      same(piece, piece.length - 1, indexAt(b), 'end $k');
      // between: exactly the stored points with a < s < b
      final inner = [
        for (var i = 0; i < pts.length; i++)
          if (cum[i] > a && cum[i] < b) i,
      ];
      expect(piece.length, inner.length + 2, reason: 'piece $k');
      for (var j = 0; j < inner.length; j++) {
        expect(piece.x(j + 1), pts.x(inner[j]));
        expect(piece.y(j + 1), pts.y(inner[j]));
      }
    }
    expect(fractionalIndexAt(Float64List.fromList(cum), -1), 0);
    expect(fractionalIndexAt(Float64List.fromList(cum), 1e9), pts.length - 1);
  });

  test('one point or a zero-length stroke → the round-1 dot', () {
    for (final xy in [
      [const ui.Offset(10, 10)],
      [const ui.Offset(10, 10), const ui.Offset(10, 10)],
    ]) {
      final o = OutlineGenerator.outline(_dashed(xy, width: 3));
      expect(o.isDot, isTrue);
      expect(o.dotRadius, closeTo(1.5, 1e-6));
      expect(o.dots, isEmpty);
    }
  });

  test('a sharp corner inside a dash splits it (O3) — still one outline', () {
    final xy = [
      ..._line(0, 20),
      for (var i = 1; i <= 20; i++) ui.Offset(20, 50.0 + i),
    ];
    final o = OutlineGenerator.outline(
      _dashed(xy, width: 2, dash: [6, 1], setDash: true),
    );
    // the dash [14, 26] turns the corner at 20: two polygons
    expect(
      o.polygons.length,
      greaterThan(_xExtents(o).where((e) => e.$2 < 14).length + 1),
    );
    for (final poly in o.polygons) {
      expect(OutlineGenerator.signedArea(poly), greaterThan(0));
    }
  });

  test('live: dashIntervalsAfter starts the first `on` at the lead', () {
    expect(
      dashIntervalsAfter(10, const [2, 1], lead: 0),
      dashIntervals(10, const [2, 1]),
    );
    expect(dashIntervalsAfter(10, const [2, 1], lead: 10), isEmpty);
    expect(dashIntervalsAfter(10, const [2, 1], lead: 4), [
      (start: 4.0, end: 6.0),
      (start: 7.0, end: 9.0),
    ]);
    final o = OutlineGenerator.dashed(
      _dashed(_line(0, 10)).points,
      width: 1,
      pattern: const [2, 1],
      lead: 4,
    );
    final xs = _xExtents(o);
    expect(xs, hasLength(2));
    expect(xs[0].$1, closeTo(4, 0.05));
    expect(xs[1].$2, closeTo(9, 0.05));
  });

  test('outline checksum = the recorded VM value (Chrome: the same — '
      'determinism_test)', () {
    expect(foldedChecksum(dashedChecksumOutlines()), recordedDashedChecksum);
  });
}
