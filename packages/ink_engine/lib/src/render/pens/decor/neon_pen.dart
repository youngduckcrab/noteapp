// lib/src/render/pens/decor/neon_pen.dart — INTERNAL (v2.11, C211-01) 네온.
//
// OWNED BY THE DECOR TRACK. The lock app's `drawGlow`: tubes of the same
// centerline from the outside in — a wide faint glow, a narrower glow, the
// colored core and a white wick. Static (no animation) and seedless.
//
// Size: the K-1 reach of a width-w stroke is at least 0.75 · w (decor_kit.dart),
// so the outer glow is 0.75 · w and the lock app's ratios (glow 3.2 · base,
// 2 · base, core 1 · base, wick 0.32 · base — all diameters) give the unit
// b = 0.75 · w / 1.6: core diameter ≈ 0.47 · w, glow diameter 1.5 · w. The
// profile has no pressure response (a neon tube is even), so every layer has a
// constant radius and the live stroke (round strokes of the live centerline)
// is the committed picture. The lock app's outer glow (alpha 0.16) is three
// layers here so its edge fades instead of ending in a ring (lock app: the
// tap's 'two outer glows'); together they are about as strong inside.
//
// Committed / PDF: one round-cap outline per layer (6 pieces). Live: the same
// six layers as round strokes of the live centerline.
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../../geometry/stroke_outline.dart';
import '../../../model/ink_stroke.dart';
import '../pen_renderer.dart';
import 'decor_kit.dart';

const PenRenderer neonPen = _NeonPen();

/// (radius in b, white?, alpha) from the outside in.
const List<(double, bool, double)> _layers = [
  (1.6, false, 0.06),
  (1.4, false, 0.07),
  (1.2, false, 0.08),
  (1.0, false, 0.32),
  (0.5, false, 1.0),
  (0.0, true, 0.8), // the wick: radius [_wick]
];

/// The unit b of a width-[w] neon (see the file comment).
double _unit(double w) => minReach(w) / 1.6;

/// The wick radius: 0.16 b (lock app 0.32 · base diameter), at least 0.2 b on
/// a dot (lock app tap), and never under 0.3 pt while the core allows it —
/// a thinner wick vanishes on thin pens (lock app: '심지만 조금 굵게').
double _wick(double b, {required bool dot}) =>
    math.max(dot ? 0.2 * b : 0.16 * b, math.min(0.4 * b, 0.3));

double _radius(int k, double b, {required bool dot}) {
  final (f, white, _) = _layers[k];
  return white ? _wick(b, dot: dot) : f * b;
}

/// The color of layer [k]: the wick is white; a pale ink (white, light yellow)
/// tints its three outer glows towards the lock app's rim gray so the tube
/// still shows on light paper.
int _layerColor(int k, int color) {
  if (_layers[k].$2) return kWhite;
  if (k > 2) return color;
  final pale = lightInk(color);
  return pale > 0.01 ? mixArgb(color, kRimArgb, 0.6 * pale) : color;
}

final class _NeonPen extends DecorPen {
  const _NeonPen();

  List<DecorShape> _shapes(InkStroke stroke) =>
      decorGeometry('neon', stroke, () {
        final w = stroke.style.width;
        final b = _unit(w);
        final sp = DecorSpine.of(stroke.points);
        final dot = sp.isDot;
        return [
          for (var k = 0; k < _layers.length; k++)
            DecorShape.outline(
              tubeOutline(sp, w, radius: (_) => _radius(k, b, dot: dot)),
            ),
        ];
      }, shapesBytes);

  @override
  List<DecorLayer> layers(
    InkStroke stroke,
    StrokeOutline outline,
    int colorArgb,
  ) {
    final shapes = _shapes(stroke);
    return [
      for (var k = 0; k < _layers.length; k++)
        (
          shape: shapes[k],
          argb: _layerColor(k, colorArgb),
          alpha: _layers[k].$3,
        ),
    ];
  }

  @override
  void paintLive(ui.Canvas canvas, PenLiveFrame frame) {
    final w = frame.style.width;
    final b = _unit(w);
    final sp = DecorSpine.offsets(frame.centerline, 0.25);
    if (sp.isEmpty) return;
    final color = frame.style.colorArgb;
    if (sp.isDot) {
      for (var k = 0; k < _layers.length; k++) {
        canvas.drawCircle(
          ui.Offset(sp.xs[0], sp.ys[0]),
          _radius(k, b, dot: true),
          fillPaint(_layerColor(k, color), _layers[k].$3 * frame.opacity),
        );
      }
      return;
    }
    final path = tubePolyline(sp);
    for (var k = 0; k < _layers.length; k++) {
      canvas.drawPath(
        path,
        tubePaint(
          _radius(k, b, dot: false),
          _layerColor(k, color),
          _layers[k].$3 * frame.opacity,
        ),
      );
    }
  }
}
