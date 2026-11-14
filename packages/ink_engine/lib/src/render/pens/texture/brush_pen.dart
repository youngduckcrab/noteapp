// lib/src/render/pens/texture/brush_pen.dart — INTERNAL (v2.11, C211-01).
//
// OWNED BY THE TEXTURE TRACK. 붓펜 — refined modestly with the lock app's
// `inkBrush`, keeping the T27 profile (pressure, tapers) and outline:
//   * dry brush (비백): as the ink runs out along the stroke (long strokes, light
//     fast parts and the last widths before the lift), 4–12 bristle tracks open
//     one after another as thin gaps along the stroke, each with its own place,
//     width and strength — cut out of the body as reversed polygons (nonzero),
//     so the screen and the PDF have exactly the same holes.
// Strokes shorter than about three widths never dry (a short bar must not
// fork), and the dryness grows in over 3–8 widths of length. The lock app's ink
// bleed fringe was dropped in review: without its wash texture it read as a
// gray drop shadow around every letter. No paper texture (the brush profile is
// not textured): one vector piece, the same on screen, in thumbnails and in the
// PDF. Track order, places and widths are hashed from the stroke's createdAt.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../geometry/stroke_outline.dart';
import '../../../model/ink_stroke.dart';
import '../pen_renderer.dart';
import 'texture_geometry.dart';
import 'texture_pen.dart';
import 'texture_tiles.dart';

const PenRenderer brushPen = _BrushPen();

const int _tracksMin = 4;
const int _tracksMax = 12;

/// radius one bristle track covers (pt)
const double _trackPt = 0.65;

final class _Geom {
  _Geom(this.holes);

  /// dry-brush gaps: negative polygons cut out of the outline (nonzero)
  final List<Float32List> holes;
}

// the gaps are long streaks: a spine three times as coarse as the other pens.
_Geom _geom(InkStroke stroke) =>
    textureGeometry(stroke, _build, (g) => polygonsBytes(g.holes), spacing: 3);

final _Geom _none = _Geom(const []);

_Geom _build(Spine sp) {
  final w = sp.width;
  final n = sp.n;
  // short strokes stay wet: the dryness grows in over 3–8 widths of length
  final long = smoothstep(3 * w, 8 * w, sp.length);
  if (sp.isDot || long <= 0) return _none;
  // ink used up: from the length so far, so the start never changes while drawing
  final dry = Float64List(n);
  for (var i = 0; i < n; i++) {
    dry[i] =
        (long *
                (math.max(0, (sp.s[i] / w - 10) / 60) +
                    0.6 * math.max(0, 0.55 - sp.p[i]) +
                    0.55 * smoothstep(3 * w, 0, sp.length - sp.s[i]) +
                    0.2 * wobble(sp.s[i] / w * 0.11, sp.seed + 17)))
            .clamp(0.0, 1.0);
  }
  // dry-brush tracks
  final mid = sp.r;
  var widest = 0.0;
  for (var i = 0; i < n; i++) {
    widest = math.max(widest, mid[i]);
  }
  final tracks = (widest / _trackPt).round().clamp(_tracksMin, _tracksMax);
  final holes = <Float32List>[];
  final wl = Float64List(n), wr = Float64List(n);
  final salt = sp.seed;
  for (var k = 0; k < tracks; k++) {
    // the order in which the tracks dry: a hashed rank
    final nk = noise01(salt, 11 * k + 3);
    var rank = 0;
    for (var m = 0; m < tracks; m++) {
      final nm = noise01(salt, 11 * m + 3);
      if (nm < nk || (nm == nk && m < k)) rank++;
    }
    final pitch = 1.72 / tracks;
    final frac =
        -0.86 + 1.72 * (k + 0.5 + 0.7 * (noise01(salt, 7 * k) - 0.5)) / tracks;
    final on = 0.3 + 0.55 * rank / tracks + 0.08 * noise01(salt, 19 * k);
    final wk = pitch * (0.35 + 0.45 * noise01(salt, 5 * k + 9));
    final freq = 0.2 + 0.4 * noise01(salt, 17 * k + 2);
    var most = 0.0;
    for (var i = 0; i < n; i++) {
      final open = smoothstep(on, on + 0.3, dry[i]);
      if (open <= 0) {
        wl[i] = 0;
        wr[i] = 0;
        continue;
      }
      final u = sp.s[i] / w;
      var width =
          mid[i] *
          wk *
          open *
          (1.75 * valueNoise(u * freq, salt + 131 * k) - 0.35).clamp(0.0, 1.0);
      // thin tracks fade out instead of becoming hairlines
      if (width < 0.18) width *= width / 0.18;
      wl[i] = width * (0.2 + 0.6 * valueNoise(u * 1.9, salt + 137 * k));
      wr[i] = width * (0.2 + 0.6 * valueNoise(u * 1.9, salt + 139 * k));
      most = math.max(most, wl[i]);
    }
    if (most < 0.05) continue;
    for (final p in offsetBands(
      sp,
      frac,
      mid,
      wl,
      wr,
      maxOffset: (i) => 0.8 * mid[i],
    )) {
      holes.add(negative(decimate(p)));
    }
  }
  return holes.isEmpty ? _none : _Geom(holes);
}

final class _BrushPen extends TexturePen {
  const _BrushPen();

  @override
  bool get layered => false;

  @override
  void paintTextured(
    Canvas canvas,
    InkStroke stroke,
    StrokeOutline outline,
    int argb,
    TextureTiles tiles,
  ) {
    for (final l in flatLayers(stroke, outline, argb)) {
      canvas.drawPath(l.outline.toPath(), solidPaint(argb, l.alpha));
    }
  }

  @override
  List<FlatLayer> flatLayers(
    InkStroke stroke,
    StrokeOutline outline,
    int argb,
  ) {
    final g = _geom(stroke);
    return [
      (
        outline: g.holes.isEmpty ? outline : withHoles(outline, g.holes),
        alpha: 1,
        argb: null,
      ),
    ];
  }
}
