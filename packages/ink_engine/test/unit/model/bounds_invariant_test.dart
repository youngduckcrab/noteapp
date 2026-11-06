// T07 (03-ink 8, 6.7 'K-1 불변식', contract 7.3.2 K-1): the rendered outline
// of every stroke built by the real pipeline (buildStroke → newCoreStroke) is
// inside core.Stroke.bounds (tolerance 0.01 pt): outline polygon vertices,
// the smooth and straight fill paths, the vector export path and, for the
// highlighter, the stroked centerline with its square cap corners.
//
// v2 (m5-7/03-ink T27, 6.2 K-1): the brush (pressure gain 0.9, f ≤ 2.2,
// long tapers) and the tape's square caps and square dot. PenProfile.of(tape)
// switches to the tape profile in T31; until then the tape strokes are checked
// with PenProfile.tape's outline over points of widthQ = kNominalWidthQ, the
// only widthQ the tape profile makes (f = 1).
// T29 (6.5 K-1): the dashed pen through the real pipeline — every dash piece
// and dot (default and other patterns, the 4096 cap) — in _tools, its own
// group and the random strokes.
//
// Also run in Chrome by test/web/geometry_on_web_test.dart.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/stroke/stroke_builder.dart';
import 'package:note_core/note_core.dart' as core;

const double _tol = 0.01;

/// MINSTD (web-safe: every product < 2^53, no bit operations).
final class _Rng {
  _Rng(this._state);
  int _state;
  double next() {
    _state = (_state * 48271) % 2147483647;
    return _state / 2147483647;
  }

  int nextInt(int n) => (next() * n).floor().clamp(0, n - 1);
}

var _ids = 0;

core.Stroke _build(
  List<InkSample> samples,
  core.StrokeStyle style, {
  PressureMode mode = PressureMode.auto,
  double viewScale = 1,
}) {
  final f = buildStroke(
    samples,
    style: style,
    viewScale: viewScale,
    mode: mode,
  );
  expect(f, isNotNull);
  _ids++;
  return interop.newCoreStroke(
    f!,
    id: 's-$_ids',
    pageId: 'page-1',
    penDownMillis: 1700000000000,
  );
}

/// A tape stroke as the tape profile builds it: [samples] through the real
/// pipeline, then every widthQ = kNominalWidthQ (f = 1: no pressure, no taper).
core.Stroke _tapeStroke(List<InkSample> samples, core.StrokeStyle style) {
  final f = buildStroke(samples, style: style, viewScale: 1);
  expect(f, isNotNull);
  final data = Float32List.fromList(f!.data);
  for (var i = 2; i < data.length; i += core.StrokePoints.stride) {
    data[i] = core.kNominalWidthQ;
  }
  _ids++;
  return interop.newCoreStroke(
    FinishedStroke(
      style: f.style,
      data: data,
      hasTilt: f.hasTilt,
      hasAzimuth: f.hasAzimuth,
      startTimeUs: f.startTimeUs,
      pressureSource: f.pressureSource,
      meta: const InkStrokeMeta(),
    ),
    id: 't-$_ids',
    pageId: 'page-1',
    penDownMillis: 1700000000000,
  );
}

/// Asserts every rendered extent of [s] is inside s.bounds. [profile] replaces
/// the stroke's profile for the outline (the tape before T31).
void expectInsideBounds(core.Stroke s, String label, {PenProfile? profile}) {
  final ink = InkStroke.of(s);
  final b = ink.bounds;
  void point(double x, double y, String what) {
    final ok =
        x >= b.left - _tol &&
        x <= b.right + _tol &&
        y >= b.top - _tol &&
        y <= b.bottom + _tol;
    if (!ok) fail('$label: $what ($x, $y) outside $b');
  }

  void rect(ui.Rect r, String what) {
    point(r.left, r.top, what);
    point(r.right, r.bottom, what);
  }

  final outline = OutlineGenerator.outlineOf(
    ink.points,
    width: s.style.width,
    profile: profile ?? ink.profile,
    dashPattern: s.style.dashPattern,
  );
  rect(outline.bounds, 'outline bounds');
  final dot = outline.dotCenter;
  if (dot != null) {
    rect(
      ui.Rect.fromCircle(center: dot, radius: outline.dotRadius),
      'dot circle',
    );
  }
  for (final d in outline.dots) {
    rect(
      ui.Rect.fromCircle(center: d, radius: outline.dotRadius),
      'dash dot circle',
    );
  }
  for (final poly in outline.polygons) {
    for (var i = 0; i + 1 < poly.length; i += 2) {
      point(poly[i], poly[i + 1], 'outline vertex ${i ~/ 2}');
    }
  }
  rect(outline.toPath().getBounds(), 'smooth path');
  rect(outline.toPath(smooth: false).getBounds(), 'straight path');
  final vp = outline.toVectorPath();
  if (vp.coords.isNotEmpty) rect(vp.bounds, 'vector path');

  if (ink.profile.renderMethod == InkRenderMethod.strokedPolyline) {
    // stroked centerline: width w, StrokeCap.square, StrokeJoin.round (6.8 O9)
    final line = OutlineGenerator.polyline(ink.points);
    final h = s.style.width / 2;
    final n = line.length ~/ 2;
    ui.Offset p(int i) => ui.Offset(line[2 * i], line[2 * i + 1]);
    final segments = <(ui.Offset, ui.Offset, ui.Offset)>[]; // a, b, unit d
    for (var i = 0; i + 1 < n; i++) {
      final d = p(i + 1) - p(i);
      if (d.distance > 1e-9) segments.add((p(i), p(i + 1), d / d.distance));
    }
    if (segments.isEmpty) {
      // zero-length line: an axis-aligned square of side w
      for (var i = 0; i < n; i++) {
        point(p(i).dx - h, p(i).dy - h, 'square dot');
        point(p(i).dx + h, p(i).dy + h, 'square dot');
      }
    } else {
      for (var k = 0; k < segments.length; k++) {
        final (a, c, d) = segments[k];
        final nrm = ui.Offset(-d.dy, d.dx) * h;
        final ea = k == 0 ? d * -h : ui.Offset.zero; // square start cap
        final ec = k == segments.length - 1 ? d * h : ui.Offset.zero;
        for (final q in [
          a + nrm + ea,
          a - nrm + ea,
          c + nrm + ec,
          c - nrm + ec,
        ]) {
          point(q.dx, q.dy, 'stroke corner');
        }
        // round join disk
        point(a.dx - h, a.dy - h, 'join');
        point(a.dx + h, a.dy + h, 'join');
      }
    }
    // stronger: every centerline point ± h·√2 on both axes
    final e = h * math.sqrt2;
    for (var i = 0; i < n; i++) {
      point(p(i).dx - e, p(i).dy - e, 'cap reach');
      point(p(i).dx + e, p(i).dy + e, 'cap reach');
    }
  }
}

List<InkSample> _samples(
  List<ui.Offset> xy, {
  double? pressure,
  double Function(double u)? pressureAt,
  double tilt = 0,
  double orientation = 0,
  InkPointerKind kind = InkPointerKind.stylus,
  int dtUs = 8333,
}) => [
  for (var i = 0; i < xy.length; i++)
    InkSample(
      position: xy[i],
      timeUs: i * dtUs,
      kind: kind,
      pressure:
          pressureAt?.call(xy.length == 1 ? 0 : i / (xy.length - 1)) ??
          pressure,
      tilt: tilt,
      orientation: orientation,
    ),
];

List<ui.Offset> _sCurve(double scale) => [
  for (var i = 0; i <= 80; i++)
    ui.Offset(
      100 + 3 * scale * i,
      200 + 30 * scale * math.sin(i / 80 * 2 * math.pi),
    ),
];

List<ui.Offset> _backAndForth(double scale) => [
  for (var i = 0; i <= 40; i++) ui.Offset(100 + 2.5 * scale * i, 300),
  for (var i = 39; i >= 0; i--) ui.Offset(100 + 2.5 * scale * i, 300.5),
];

const List<core.PenTool> _tools = [
  core.PenTool.ballpoint,
  core.PenTool.fountain,
  core.PenTool.highlighter,
  core.PenTool.pencil,
  core.PenTool.marker,
  core.PenTool.brush, // m5-7 T27: the brush profile
  core.PenTool.dashed, // m5-7 T29: the dashed profile ([4, 3])
];

void main() {
  for (final tool in _tools) {
    for (final width in [0.1, 1.6, 30.0]) {
      final base = core.StrokeStyle.defaultsFor(tool)
          .copyWith(width: width, pressureSensitivity: 1);
      final scale = math.max(1.0, width / 4);

      test('$tool width $width: max pressure, max tilt, taper', () {
        final maxPressure = _build(
          _samples(_sCurve(scale), pressure: 1),
          base,
          mode: PressureMode.alwaysReal,
        );
        expectInsideBounds(maxPressure, 'max pressure');
        final maxTilt = _build(
          _samples(_sCurve(scale), pressure: 1, tilt: math.pi / 2),
          base,
          mode: PressureMode.alwaysReal,
        );
        expectInsideBounds(maxTilt, 'max tilt');
        if (tool == core.PenTool.pencil) {
          // f 4.48 saturates at kMaxWidthFactor: widthQ 1 (6.7 K4, K6)
          expect(maxTilt.points.maxWidthQ, closeTo(1, 1e-9));
        }
        final taper = _build(
          _samples(
            _sCurve(scale),
            pressureAt: (u) => 0.2 + 0.8 * math.sin(u * math.pi),
            tilt: 0.6,
            orientation: 0.4,
          ),
          base,
        );
        expectInsideBounds(taper, 'taper');
        final simulated = _build(
          _samples(_sCurve(scale), kind: InkPointerKind.touch),
          base,
        );
        expectInsideBounds(simulated, 'simulated pressure');
      });

      test('$tool width $width: dot and 180° back and forth', () {
        final dot = _build(
          _samples([const ui.Offset(50, 50)], pressure: 1),
          base,
          mode: PressureMode.alwaysReal,
        );
        expectInsideBounds(dot, 'dot');
        final tiny = _build(
          _samples([
            const ui.Offset(50, 50),
            const ui.Offset(50.05, 50.02),
            const ui.Offset(50.02, 50.04),
          ], pressure: 0.9),
          base,
        );
        expectInsideBounds(tiny, 'tiny');
        final back = _build(
          _samples(_backAndForth(scale), pressure: 1),
          base,
          mode: PressureMode.alwaysReal,
        );
        expectInsideBounds(back, '180°');
      });
    }
  }

  group('highlighter square caps and straightening', () {
    for (final mode in HighlighterStraightening.values) {
      for (final width in [0.1, 1.6, 30.0]) {
        test('$mode width $width', () {
          final style = core.StrokeStyle.defaultsFor(core.PenTool.highlighter)
              .copyWith(width: width)
              .withHighlighterStraightening(mode);
          for (final xy in [
            // nearly straight, 3° off the axis
            [
              for (var i = 0; i <= 60; i++)
                ui.Offset(
                  40 + 4.0 * i,
                  80 + 4.0 * i * math.tan(3 * math.pi / 180) + (i % 3) * 0.1,
                ),
            ],
            // diagonal: the square cap corners stick out the most
            [
              for (var i = 0; i <= 60; i++)
                ui.Offset(40 + 3.0 * i, 80 + 3.0 * i),
            ],
            _sCurve(math.max(1, width / 4)),
            [const ui.Offset(10, 10)],
          ]) {
            final s = _build(_samples(xy, pressure: 0.7), style);
            expect(s.points.maxWidthQ, closeTo(core.kNominalWidthQ, 1e-9));
            expectInsideBounds(s, '$mode');
          }
        });
      }
    }
  });

  group('dashed pieces and dots (PenProfile.dashed, 6.5)', () {
    final base = core.StrokeStyle.defaultsFor(core.PenTool.dashed);
    for (final pattern in [
      [4.0, 3.0],
      [0.0, 2.0],
      [1.0, 1.0, 0.0, 3.0],
      [50.0, 0.5],
      [0.25, 0.25], // the 4096 cap on the long strokes below at 0.1 pt
    ]) {
      for (final width in [0.1, 1.0, 30.0]) {
        test('$pattern width $width', () {
          final style = base
              .copyWith(width: width)
              .withInkExtras(dashPattern: pattern);
          final scale = math.max(1.0, width / 4);
          for (final (name, xy) in [
            ('S curve', _sCurve(scale)),
            ('180°', _backAndForth(scale)),
            (
              'long',
              [
                for (var i = 0; i <= 400; i++)
                  ui.Offset(20 + 2.0 * scale * i, 400 + 60 * math.sin(i / 40)),
              ],
            ),
            ('dot', [const ui.Offset(30, 30)]),
          ]) {
            final s = _build(_samples(xy, pressure: 0.8), style);
            expect(s.style.profile, same(PenProfile.dashed));
            expect(s.points.maxWidthQ, closeTo(core.kNominalWidthQ, 1e-9));
            expectInsideBounds(s, 'dashed $pattern $name');
          }
        });
      }
    }
  });

  group('tape square caps and square dot (PenProfile.tape)', () {
    final base = core.StrokeStyle.defaultsFor(core.PenTool.tape);
    for (final width in [0.1, 14.0, 60.0]) {
      test('width $width', () {
        final style = base.copyWith(width: width);
        final scale = math.max(1.0, width / 4);
        for (final (name, xy) in [
          (
            'diagonal',
            [
              for (var i = 0; i <= 60; i++)
                ui.Offset(40 + 3.0 * scale * i, 80 + 3.0 * scale * i),
            ],
          ),
          ('S curve', _sCurve(scale)),
          ('180°', _backAndForth(scale)),
          ('dot', [const ui.Offset(30, 30)]),
          (
            'tiny',
            [
              const ui.Offset(50, 50),
              const ui.Offset(50.05, 50.02),
              const ui.Offset(50.02, 50.04),
            ],
          ),
        ]) {
          final s = _tapeStroke(_samples(xy, pressure: 0.8), style);
          expect(s.points.maxWidthQ, closeTo(core.kNominalWidthQ, 1e-9));
          expectInsideBounds(s, 'tape $name', profile: PenProfile.tape);
        }
      });
    }

    test('100 seeded random tape strokes', () {
      final rnd = _Rng(20261106);
      for (var k = 0; k < 100; k++) {
        final width = 0.1 * math.pow(600, rnd.next()).toDouble(); // 0.1 … 60
        final count = 1 + rnd.nextInt(80);
        var p = ui.Offset(50 + 500 * rnd.next(), 50 + 700 * rnd.next());
        var heading = rnd.next() * 2 * math.pi;
        final xy = <ui.Offset>[];
        for (var i = 0; i < count; i++) {
          xy.add(p);
          heading += rnd.next() < 0.08 ? math.pi : (rnd.next() - 0.5) * 1.6;
          final step = rnd.next() < 0.1 ? 0.0 : 8 * rnd.next() * rnd.next();
          p += ui.Offset(math.cos(heading), math.sin(heading)) * step;
        }
        final s = _tapeStroke(
          _samples(xy, pressure: rnd.next()),
          base.copyWith(width: width, smoothing: rnd.next()),
        );
        expectInsideBounds(
          s,
          'tape $k (width $width)',
          profile: PenProfile.tape,
        );
      }
    });
  });

  test('300 seeded random strokes', () {
    final rnd = _Rng(20261105);
    const kinds = InkPointerKind.values;
    const curves = [
      core.PressureCurve.linear,
      core.PressureCurve.soft,
      core.PressureCurve.firm,
    ];
    for (var k = 0; k < 300; k++) {
      final tool = core.PenTool.values[rnd.nextInt(core.PenTool.values.length)];
      final width = 0.1 * math.pow(300, rnd.next()).toDouble(); // 0.1 … 30
      var style = core.StrokeStyle.defaultsFor(tool).copyWith(
        width: width,
        pressureSensitivity: rnd.next(),
        pressureCurve: curves[rnd.nextInt(3)],
        smoothing: rnd.next(),
      );
      if (tool == core.PenTool.highlighter) {
        style = style.withHighlighterStraightening(
          HighlighterStraightening.values[rnd.nextInt(3)],
        );
      }
      final kind = kinds[rnd.nextInt(kinds.length)];
      final count = 1 + rnd.nextInt(120);
      var p = ui.Offset(50 + 500 * rnd.next(), 50 + 700 * rnd.next());
      var heading = rnd.next() * 2 * math.pi;
      var timeUs = 0;
      final samples = <InkSample>[];
      for (var i = 0; i < count; i++) {
        samples.add(
          InkSample(
            position: p,
            timeUs: timeUs,
            kind: kind,
            pressure: rnd.next() < 0.1 ? null : rnd.next(),
            tilt: rnd.next() * math.pi / 2,
            orientation: rnd.next() < 0.5 ? 0 : (rnd.next() - 0.5) * 6,
          ),
        );
        final turn = rnd.next() < 0.08 ? math.pi : (rnd.next() - 0.5) * 1.6;
        heading += turn;
        final step = rnd.next() < 0.1 ? 0.0 : 8 * rnd.next() * rnd.next();
        p += ui.Offset(math.cos(heading), math.sin(heading)) * step;
        timeUs += 2000 + rnd.nextInt(18000);
      }
      final s = _build(
        samples,
        style,
        mode: PressureMode.values[rnd.nextInt(PressureMode.values.length)],
        viewScale: const [0.5, 1.0, 2.0, 4.0][rnd.nextInt(4)],
      );
      expectInsideBounds(s, 'random $k ($tool, width $width)');
    }
  });
}
