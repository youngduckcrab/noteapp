// lib/src/render/pens/decor/jelly_pen.dart — INTERNAL (v2.11, C211-01) 젤리.
//
// OWNED BY THE DECOR TRACK. The lock app's jelly (BrushRender JELLY): a plump
// body in the pen color with a thin white gloss line (0.3 · base wide, alpha
// 0.45) laid 0.22 · base towards the light. Added here for a rounder, jelly-like
// tube: a narrow, faint lighter sheen between the center and the gloss (the
// gloss line carries the look; a wide band made outlined bubble letters), and for pale inks
// (white, yellow) a faint rim outside and a faint shade on the far side, so a
// pale jelly still shows on light paper (lock app: the tap's pale-ink shade).
//
// The body is the stroke's own outline (pressure, like the ballpoint), so the
// live stroke draws exactly the same body; the bands are constant-radius
// tubes of the shifted centerline (sizes from the width, inside the thinnest
// body the profile makes: factor ≥ 0.8 → radius ≥ 0.4 · w). The light side is
// chosen once per stroke (DecorSpine.lightSide). A dot is the lock app's tap:
// a round drop a little larger than the line with a short gloss arc.
//
// Committed / PDF: rim, body, light band, shade, gloss (≤ 5 pieces).
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../../geometry/stroke_outline.dart';
import '../../../model/ink_stroke.dart';
import '../../stroke_painter.dart';
import '../pen_renderer.dart';
import 'decor_kit.dart';

const PenRenderer jellyPen = _JellyPen();

// sizes in multiples of the width
const double _rimOut = 0.07;
const double _bandShift = 0.15, _bandRadius = 0.2, _bandTrim = 0.25;

/// how much lighter the band is than the ink (a soft sheen, not a second
/// tube: a wide light band read as hollow bubble letters)
const double _bandLight = 0.22;
const double _glossShift = 0.22, _glossRadius = 0.15, _glossTrim = 0.35;
const double _shadeShift = 0.24, _shadeRadius = 0.12;

// alphas
const double _rimAlpha = 0.45, _bandAlpha = 0.2, _glossAlpha = 0.45;
const double _shadeAlpha = 0.10;

// the dot (lock app tap): radius, gloss arc radius and angles (deg, screen)
const double _dotRadius = 0.62, _dotArc = 0.36;
const double _arcFrom = 195, _arcTo = 265;

final class _Geom {
  _Geom(this.rim, this.body, this.band, this.shade, this.gloss);
  final DecorShape? rim;

  /// a dot's drop; null for a line (its body is the L1 outline itself — the
  /// geometry cache keeps no second copy of it)
  final DecorShape? body;
  final DecorShape band, shade, gloss;

  int get bytes => shapesBytes([rim, body, band, shade, gloss]);
}

_Geom _build(InkStroke stroke) {
  final w = stroke.style.width;
  final reach = reachOf(stroke);
  final sp = DecorSpine.of(stroke.points);
  if (sp.isDot) {
    final c = ui.Offset(sp.xs[0], sp.ys[0]);
    final r = math.min(reach - _rimOut * w, _dotRadius * w);
    DecorShape circle(ui.Offset o, double radius) =>
        DecorShape.vector((VecBuilder()..circle(o.dx, o.dy, radius)).build());
    final arc = DecorSpine.offsets([
      for (var k = 0; k <= 12; k++)
        c +
            ui.Offset.fromDirection(
              (_arcFrom + (_arcTo - _arcFrom) * k / 12) * math.pi / 180,
              _dotArc * w * r / (_dotRadius * w),
            ),
    ], 0.25);
    return _Geom(
      circle(c, r + _rimOut * w),
      circle(c, r),
      circle(c + ui.Offset(-0.06 * w, -0.08 * w), 0.6 * r),
      circle(c + ui.Offset(0.1 * w, 0.12 * w), 0),
      DecorShape.outline(
        tubeOutline(
          arc,
          w,
          radius: (_) => _glossRadius * w * r / (_dotRadius * w),
          within: reach - _dotArc * w * r / (_dotRadius * w),
        ),
      ),
    );
  }
  final side = sp.lightSide(w);
  final (b0, b1) = trimmed(sp.length, _bandTrim * w);
  final (g0, g1) = trimmed(sp.length, _glossTrim * w);
  return _Geom(
    DecorShape.outline(
      tubeOutline(
        sp,
        w,
        radius: (q) => math.min(reach, 2 * w * q + _rimOut * w),
      ),
    ),
    null,
    DecorShape.outline(
      tubeOutline(
        sp,
        w,
        radius: (_) => _bandRadius * w,
        t0: b0,
        t1: b1,
        shift: side * _bandShift * w,
        within: reach,
      ),
    ),
    DecorShape.outline(
      tubeOutline(
        sp,
        w,
        radius: (_) => _shadeRadius * w,
        t0: b0,
        t1: b1,
        shift: -side * _shadeShift * w,
        within: reach,
      ),
    ),
    DecorShape.outline(
      tubeOutline(
        sp,
        w,
        radius: (_) => _glossRadius * w,
        t0: g0,
        t1: g1,
        shift: side * _glossShift * w,
        within: reach,
      ),
    ),
  );
}

final class _JellyPen extends DecorPen {
  const _JellyPen();

  @override
  List<DecorLayer> layers(
    InkStroke stroke,
    StrokeOutline outline,
    int colorArgb,
  ) {
    final g = decorGeometry(
      'jelly',
      stroke,
      () => _build(stroke),
      (g) => g.bytes,
    );
    final pale = lightInk(colorArgb);
    return [
      if (pale > 0.01) (shape: g.rim!, argb: kRimArgb, alpha: _rimAlpha * pale),
      (shape: g.body ?? DecorShape.outline(outline), argb: colorArgb, alpha: 1),
      (shape: g.band, argb: lighten(colorArgb, _bandLight), alpha: _bandAlpha),
      if (pale > 0.01)
        (shape: g.shade, argb: kBlack, alpha: _shadeAlpha * pale),
      (shape: g.gloss, argb: kWhite, alpha: _glossAlpha),
    ];
  }

  @override
  void paintLive(ui.Canvas canvas, PenLiveFrame frame) {
    final w = frame.style.width;
    final color = frame.style.colorArgb;
    final pale = lightInk(color);
    final o = frame.opacity;
    if (pale > 0.01) {
      // the rim: a 2 · rimOut stroke of the body outline (its inner half is
      // under the body)
      final rim = ui.Paint()
        ..isAntiAlias = true
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2 * _rimOut * w
        ..strokeJoin = ui.StrokeJoin.round
        ..color = inkColor(kRimArgb, _rimAlpha * pale * o);
      for (final p in frame.paths) {
        canvas.drawPath(p, rim);
      }
    }
    paintFillPaths(
      canvas,
      frame.paths,
      profile: frame.profile,
      colorArgb: color,
      opacity: o,
      bounds: frame.bounds,
    );
    final sp = DecorSpine.offsets(frame.centerline, 0.25);
    if (sp.isDot) return; // the drop look comes with the pen lift
    final side = sp.lightSide(w);
    final (b0, b1) = trimmed(sp.length, _bandTrim * w);
    final (g0, g1) = trimmed(sp.length, _glossTrim * w);
    canvas.drawPath(
      tubePolyline(sp, t0: b0, t1: b1, shift: side * _bandShift * w),
      tubePaint(_bandRadius * w, lighten(color, _bandLight), _bandAlpha * o),
    );
    if (pale > 0.01) {
      canvas.drawPath(
        tubePolyline(sp, t0: b0, t1: b1, shift: -side * _shadeShift * w),
        tubePaint(_shadeRadius * w, kBlack, _shadeAlpha * pale * o),
      );
    }
    canvas.drawPath(
      tubePolyline(sp, t0: g0, t1: g1, shift: side * _glossShift * w),
      tubePaint(_glossRadius * w, kWhite, _glossAlpha * o),
    );
  }
}
