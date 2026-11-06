// lib/src/render/pen_preview.dart — 03-ink 4.9 (INK T20).
//
// A sample stroke for a style, built with the real pipeline (buildStroke →
// newCoreStroke → InkStroke) from a fixed synthetic stylus script — an S
// curve or a straight line with a real-pressure swell, 120 Hz — fitted to the
// painter size in logical px (1 pt = 1 px, so the width is the size at 100 %)
// and painted like the page layers: the highlighter as a group on the paper
// (6.10), fill pens by their outline (6.8), the pencil with the grain once the
// PencilGrain is ready (6.11 — the painter listens to it: repaint).
// Built strokes are kept in a small LRU by (style, shape, size).
//
// (m5-7/03-ink 6.2 'pen preview v2', T27) The painter branches on the
// profile's render method and calls the same paint function as the page
// layers (preview = real stroke shape). The dashed branch draws the dashed
// outline (T29 — OutlineGenerator.outline gives the dash pieces), the nib
// branch the calligraphy outline of style.nibAngleDeg / nibAspect (T28 — the
// same fill as the page layers), the tape the covered shape with its stripes
// (T31 — the cover layer's covered look), the laser a still picture (T30 —
// the trail's glow + core in InkTuning.laserArgb at full opacity, no fade and
// no repaint).
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart' show internal;
import 'package:note_core/note_core.dart' as core;

import '../geometry/outline_generator.dart';
import '../geometry/stroke_outline.dart';
import '../input/ink_sample.dart';
import '../input/pressure_capability.dart';
import '../interop/core_interop.dart' as interop;
import '../model/ink_layer.dart';
import '../model/ink_stroke.dart';
import '../pen/pen_profile.dart';
import '../stroke/stroke_builder.dart';
import 'highlighter_compositor.dart';
import 'laser_trail.dart';
import 'pencil_grain.dart';
import 'stroke_painter.dart';
import 'tape_painter.dart';

enum PenPreviewShape { sCurve, line }

/// Draws a sample stroke for a style (F-04 size preview, preset bar icons). Built with the
/// real stroke pipeline from a fixed synthetic sample script (real-pressure S curve).
/// (v1.1) pencilGrain is the PencilGrain itself (ref.watch(pencilGrainProvider)), not its
/// ui.Image; the painter repaints on it (repaint: pencilGrain).
class PenPreviewPainter extends CustomPainter {
  PenPreviewPainter({
    required this.style,
    this.shape = PenPreviewShape.sCurve,
    this.paperColorArgb = core.PaperColors.white,
    this.pencilGrain,
  }) : super(repaint: pencilGrain);
  final core.StrokeStyle style;
  final PenPreviewShape shape;
  final int paperColorArgb;

  /// repaints when the grain becomes ready
  final PencilGrain? pencilGrain;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    final sample = penPreviewStrokeOf(style, shape, size);
    if (sample == null) return;
    final stroke = sample.stroke;
    switch (stroke.profile.renderMethod) {
      case InkRenderMethod.strokedPolyline:
        paintHighlighterGroups(
          canvas,
          groupHighlighters([stroke]),
          paperColorArgb: paperColorArgb,
          marginPt: 1,
        );
      case InkRenderMethod.filledOutline when stroke.layer == InkLayer.cover:
        // (T31) the tape: the covered shape (+ stripes), never the revealed border
        paintTapeCovered(
          canvas,
          stroke,
          sample.outline ?? OutlineGenerator.outline(stroke),
        );
      case InkRenderMethod.transientTrail:
        // (T30) the still laser: glow + core along the centerline, laserArgb
        final p = stroke.points;
        paintLaserStill(canvas, [
          for (var i = 0; i < p.length; i++) Offset(p.x(i), p.y(i)),
        ], stroke.style.width);
      case InkRenderMethod.filledOutline:
      case InkRenderMethod.nibOutline:
      case InkRenderMethod.dashedPolyline:
        paintFillStroke(
          canvas,
          stroke,
          sample.outline ?? OutlineGenerator.outline(stroke),
          grain: stroke.profile.textured ? pencilGrain?.value : null,
        );
    }
  }

  /// style / shape / paperColorArgb differ by value, or pencilGrain is another object.
  @override
  bool shouldRepaint(PenPreviewPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.shape != shape ||
      oldDelegate.paperColorArgb != paperColorArgb ||
      !identical(oldDelegate.pencilGrain, pencilGrain);
}

/// INTERNAL: a built preview stroke and its outline (null for the highlighter).
@internal
typedef PenPreviewStroke = ({InkStroke stroke, StrokeOutline? outline});

final LinkedHashMap<
  (core.StrokeStyle, PenPreviewShape, Size),
  PenPreviewStroke?
>
_cache = LinkedHashMap();
const int _cacheSize = 32;

/// INTERNAL: the preview stroke of [style] in [size] (cached; null when the
/// pipeline draws nothing).
@internal
PenPreviewStroke? penPreviewStrokeOf(
  core.StrokeStyle style,
  PenPreviewShape shape,
  Size size,
) {
  final key = (style, shape, size);
  if (_cache.containsKey(key)) {
    final hit = _cache.remove(key);
    _cache[key] = hit;
    return hit;
  }
  final built = _build(style, shape, size);
  _cache[key] = built;
  while (_cache.length > _cacheSize) {
    _cache.remove(_cache.keys.first);
  }
  return built;
}

/// The synthetic stylus script: 96 samples at 120 Hz along the shape, raw
/// pressure 0.25 → 0.9 → 0.25 (sine swell), a little tilt.
@internal
List<InkSample> penPreviewScript(
  core.StrokeStyle style,
  PenPreviewShape shape,
  Size size,
) {
  const n = 96;
  // room for the widest point (width × kMaxWidthFactor) and the fringe
  final margin = math.min(
    style.width * core.kMaxWidthFactor / 2 + 2,
    size.shortestSide / 2,
  );
  final x0 = margin;
  final span = math.max(0.0, size.width - 2 * margin);
  final mid = size.height / 2;
  final amplitude = shape == PenPreviewShape.sCurve
      ? math.max(0.0, size.height / 2 - margin) * 0.7
      : 0.0;
  return [
    for (var i = 0; i < n; i++)
      () {
        final u = i / (n - 1);
        return InkSample(
          position: Offset(
            x0 + span * u,
            mid - amplitude * math.sin(u * 2 * math.pi),
          ),
          timeUs: (i * 1000000 / 120).round(),
          kind: InkPointerKind.stylus,
          pressure: 0.25 + 0.65 * math.sin(u * math.pi),
          tilt: 0.4,
        );
      }(),
  ];
}

PenPreviewStroke? _build(
  core.StrokeStyle style,
  PenPreviewShape shape,
  Size size,
) {
  final finished = buildStroke(
    penPreviewScript(style, shape, size),
    style: style,
    viewScale: 1,
    prior: PressureCapability.supported,
  );
  if (finished == null) return null;
  final stroke = InkStroke.of(
    interop.newCoreStroke(
      finished,
      id: 'pv-pen',
      pageId: 'pv-pen',
      penDownMillis: 0,
    ),
  );
  return (
    stroke: stroke,
    outline: stroke.profile.renderMethod == InkRenderMethod.strokedPolyline
        ? null
        : OutlineGenerator.outline(stroke),
  );
}
