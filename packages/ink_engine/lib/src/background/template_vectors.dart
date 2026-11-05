// lib/src/background/template_vectors.dart — TemplateVectorItem / TemplateLine /
// TemplateDot (INK 4.10), contract 7.2.16.
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import 'template_defaults.dart';

sealed class TemplateVectorItem {
  const TemplateVectorItem();
}

@immutable
final class TemplateLine extends TemplateVectorItem {
  const TemplateLine(
    this.p0,
    this.p1, {
    required this.width,
    required this.colorArgb,
  });
  final Offset p0;
  final Offset p1;
  final double width;
  final int colorArgb;

  @override
  bool operator ==(Object other) =>
      other is TemplateLine &&
      other.p0 == p0 &&
      other.p1 == p1 &&
      other.width == width &&
      other.colorArgb == colorArgb;

  @override
  int get hashCode => Object.hash(p0, p1, width, colorArgb);
}

@immutable
final class TemplateDot extends TemplateVectorItem {
  const TemplateDot(
    this.center, {
    required this.radius,
    required this.colorArgb,
  });
  final Offset center;
  final double radius;
  final int colorArgb;

  @override
  bool operator ==(Object other) =>
      other is TemplateDot &&
      other.center == center &&
      other.radius == radius &&
      other.colorArgb == colorArgb;

  @override
  int get hashCode => Object.hash(center, radius, colorArgb);
}

abstract final class TemplateVectors {
  /// Lines / dots (no paper fill) in page pt, y down. Used by the painter and PDF export.
  ///
  /// 6.16: null parameters → the 6.16 defaults (template_defaults.dart),
  /// lineColorArgb == null → colors by paper luminance. Every line is cut to
  /// the page rectangle, dots only when inside the page (radius included).
  /// With [clip], only items that meet it (lines cut to it). Original widths
  /// (no screen minimum — the painter applies 1 device px).
  static List<TemplateVectorItem> build(
    core.PageTemplate template, {
    required Size pageSize,
    required int paperColorArgb,
    Rect? clip,
  }) {
    final w = pageSize.width, h = pageSize.height;
    if (!(w > 0 && h > 0 && w.isFinite && h.isFinite)) return const [];
    var bounds = Rect.fromLTWH(0, 0, w, h);
    if (clip != null) {
      bounds = bounds.intersect(clip); // negative size when they do not meet
      if (bounds.width < 0 || bounds.height < 0) return const [];
    }
    final out = _Items(pageSize, bounds);
    final r = ResolvedTemplate(template, paperColorArgb: paperColorArgb);
    switch (template.kind) {
      case core.PageTemplateKind.lined:
        _lined(out, r, w, h);
      case core.PageTemplateKind.grid:
        _grid(out, r, w, h);
      case core.PageTemplateKind.dotted:
        _dotted(out, r, w, h);
      case core.PageTemplateKind.cornell:
        _cornell(out, r, w, h);
      case core.PageTemplateKind.music:
        _music(out, r, w, h);
      case core.PageTemplateKind.planner:
        _planner(out, r, w, h);
    }
    return List.unmodifiable(out.items);
  }

  static const double _eps = 1e-9;

  /// Lined: ruled lines y = marginTop + k·spacing (y ≤ H − spacing), full
  /// width; margin line x = marginLeft, full height.
  static void _lined(_Items out, ResolvedTemplate r, double w, double h) {
    final top = r.number(
      core.TemplateExtrasKeys.marginTop,
      TemplateDefaults.linedMarginTop,
    );
    final left = r.number(
      core.TemplateExtrasKeys.marginLeft,
      TemplateDefaults.linedMarginLeft,
    );
    for (var k = 0; ; k++) {
      final y = top + k * r.spacing;
      if (y > h - r.spacing + _eps) break;
      out.line(Offset(0, y), Offset(w, y), r.lineWidth, r.lineColor);
    }
    if (r.flag(
      core.TemplateExtrasKeys.showMarginLine,
      TemplateDefaults.linedShowMarginLine,
    )) {
      out.line(
        Offset(left, 0),
        Offset(left, h),
        TemplateDefaults.marginLineWidth,
        r.marginColor,
      );
    }
  }

  /// Grid / dotted alignment: the first line at (side mod spacing) / 2.
  static List<double> _centered(double side, double spacing) {
    final start = (side % spacing) / 2;
    return [
      for (var k = 0; start + k * spacing <= side + _eps; k++)
        start + k * spacing,
    ];
  }

  static void _grid(_Items out, ResolvedTemplate r, double w, double h) {
    for (final y in _centered(h, r.spacing)) {
      out.line(Offset(0, y), Offset(w, y), r.lineWidth, r.lineColor);
    }
    for (final x in _centered(w, r.spacing)) {
      out.line(Offset(x, 0), Offset(x, h), r.lineWidth, r.lineColor);
    }
  }

  static void _dotted(_Items out, ResolvedTemplate r, double w, double h) {
    final xs = _centered(w, r.spacing);
    for (final y in _centered(h, r.spacing)) {
      for (final x in xs) {
        out.dot(Offset(x, y), r.lineWidth / 2, r.dotColor);
      }
    }
  }

  /// Cornell: header / summary bands and the cue column are structure lines;
  /// ruled lines y = headerHeight + k·spacing (k ≥ 1, y ≤ H − summary −
  /// spacing / 2), full width.
  static void _cornell(_Items out, ResolvedTemplate r, double w, double h) {
    final header = r.number(
      core.TemplateExtrasKeys.headerHeight,
      TemplateDefaults.cornellHeaderHeight,
    );
    final cue = r.number(
      core.TemplateExtrasKeys.cueColumnWidth,
      TemplateDefaults.cornellCueColumnWidth(w),
    );
    final summary = r.number(
      core.TemplateExtrasKeys.summaryHeight,
      TemplateDefaults.cornellSummaryHeight(h),
    );
    final summaryTop = h - summary;
    for (var k = 1; ; k++) {
      final y = header + k * r.spacing;
      if (y > summaryTop - r.spacing / 2 + _eps) break;
      out.line(Offset(0, y), Offset(w, y), r.lineWidth, r.lineColor);
    }
    final sw = r.structureWidth, sc = r.structureColor;
    out
      ..line(Offset(0, header), Offset(w, header), sw, sc)
      ..line(Offset(0, summaryTop), Offset(w, summaryTop), sw, sc)
      ..line(Offset(cue, header), Offset(cue, summaryTop), sw, sc);
  }

  /// Music: n staves of 5 lines (gap = spacing), n = ⌊(H − 2·marginTop +
  /// staffGap) / (4·spacing + staffGap)⌋, the block centred vertically, lines
  /// from marginLeft to W − marginLeft in the staff color, width lineWidth.
  static void _music(_Items out, ResolvedTemplate r, double w, double h) {
    final top = r.number(
      core.TemplateExtrasKeys.marginTop,
      TemplateDefaults.musicMarginTop,
    );
    final left = r.number(
      core.TemplateExtrasKeys.marginLeft,
      TemplateDefaults.musicMarginLeft,
    );
    final gap = r.number(
      core.TemplateExtrasKeys.staffGap,
      TemplateDefaults.musicStaffGap,
    );
    const lines = TemplateDefaults.musicStaffLines;
    final staff = (lines - 1) * r.spacing;
    final pitch = staff + gap;
    if (!(pitch > 0) || !(w - 2 * left > 0)) return;
    final n = ((h - 2 * top + gap) / pitch + _eps).floor();
    if (n < 1) return;
    final y0 = (h - (n * staff + (n - 1) * gap)) / 2;
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < lines; j++) {
        final y = y0 + i * pitch + j * r.spacing;
        out.line(
          Offset(left, y),
          Offset(w - left, y),
          r.lineWidth,
          r.staffColor,
        );
      }
    }
  }

  /// Planner (weekly; an unknown layout is weekly too): a header band
  /// marginTop … marginTop + headerHeight whose bottom is a structure line;
  /// the body below it down to H − marginTop, marginLeft from both sides, is
  /// 8 cells (portrait 2 × 4, landscape 4 × 2) with structure-line borders.
  /// Each cell: a title line 20 pt below its top, then ruled lines every
  /// spacing down to 4 pt above its bottom. No text.
  static void _planner(_Items out, ResolvedTemplate r, double w, double h) {
    final top = r.number(
      core.TemplateExtrasKeys.marginTop,
      TemplateDefaults.plannerMarginTop,
    );
    final left = r.number(
      core.TemplateExtrasKeys.marginLeft,
      TemplateDefaults.plannerMarginLeft,
    );
    final header = r.number(
      core.TemplateExtrasKeys.headerHeight,
      TemplateDefaults.plannerHeaderHeight,
    );
    // 'weekly' is the only layout (03-ink 6.16): the `layout` extra is not
    // read — any value draws the weekly page.
    final bodyTop = top + header, bodyBottom = h - top;
    final bodyLeft = left, bodyRight = w - left;
    if (!(bodyBottom - bodyTop > 0) || !(bodyRight - bodyLeft > 0)) return;
    final portrait = w <= h;
    final cols = portrait ? 2 : 4, rows = portrait ? 4 : 2;
    final cw = (bodyRight - bodyLeft) / cols,
        ch = (bodyBottom - bodyTop) / rows;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final x0 = bodyLeft + col * cw, x1 = x0 + cw;
        final cellTop = bodyTop + row * ch, cellBottom = cellTop + ch;
        for (var k = 0; ; k++) {
          final y =
              cellTop + TemplateDefaults.plannerTitleOffset + k * r.spacing;
          if (y > cellBottom - TemplateDefaults.plannerCellBottomGap + _eps) {
            break;
          }
          out.line(Offset(x0, y), Offset(x1, y), r.lineWidth, r.lineColor);
        }
      }
    }
    final sw = r.structureWidth, sc = r.structureColor;
    for (var row = 0; row <= rows; row++) {
      final y = bodyTop + row * ch;
      out.line(Offset(bodyLeft, y), Offset(bodyRight, y), sw, sc);
    }
    for (var col = 0; col <= cols; col++) {
      final x = bodyLeft + col * cw;
      out.line(Offset(x, bodyTop), Offset(x, bodyBottom), sw, sc);
    }
  }
}

/// Collects items, cutting lines to [bounds] (page ∩ clip) and keeping dots
/// that lie inside the page and meet [bounds].
final class _Items {
  _Items(this.pageSize, this.bounds);

  final Size pageSize;
  final Rect bounds;
  final List<TemplateVectorItem> items = [];

  void line(Offset p0, Offset p1, double width, int colorArgb) {
    final cut = clipSegment(p0, p1, bounds);
    if (cut == null) return;
    items.add(TemplateLine(cut.$1, cut.$2, width: width, colorArgb: colorArgb));
  }

  void dot(Offset c, double radius, int colorArgb) {
    if (c.dx - radius < 0 ||
        c.dy - radius < 0 ||
        c.dx + radius > pageSize.width ||
        c.dy + radius > pageSize.height) {
      return;
    }
    if (c.dx + radius < bounds.left ||
        c.dx - radius > bounds.right ||
        c.dy + radius < bounds.top ||
        c.dy - radius > bounds.bottom) {
      return;
    }
    items.add(TemplateDot(c, radius: radius, colorArgb: colorArgb));
  }
}

/// Liang–Barsky: the part of p0–p1 inside [r] (edges included), or null.
@visibleForTesting
(Offset, Offset)? clipSegment(Offset p0, Offset p1, Rect r) {
  final dx = p1.dx - p0.dx, dy = p1.dy - p0.dy;
  // axis-aligned (every template line): exact clamping, no rounding
  if (dy == 0 || dx == 0) {
    final x0 = math.max(math.min(p0.dx, p1.dx), r.left);
    final x1 = math.min(math.max(p0.dx, p1.dx), r.right);
    final y0 = math.max(math.min(p0.dy, p1.dy), r.top);
    final y1 = math.min(math.max(p0.dy, p1.dy), r.bottom);
    if (x0 > x1 || y0 > y1) return null;
    final forward = dx >= 0 && dy >= 0;
    final a = Offset(x0, y0), b = Offset(x1, y1);
    return forward ? (a, b) : (b, a);
  }
  var t0 = 0.0, t1 = 1.0;
  final p = [-dx, dx, -dy, dy];
  final q = [p0.dx - r.left, r.right - p0.dx, p0.dy - r.top, r.bottom - p0.dy];
  for (var i = 0; i < 4; i++) {
    if (p[i] == 0) {
      if (q[i] < 0) return null;
      continue;
    }
    final t = q[i] / p[i];
    if (p[i] < 0) {
      if (t > t1) return null;
      if (t > t0) t0 = t;
    } else {
      if (t < t0) return null;
      if (t < t1) t1 = t;
    }
  }
  return (
    t0 == 0 ? p0 : Offset(p0.dx + t0 * dx, p0.dy + t0 * dy),
    t1 == 1 ? p1 : Offset(p0.dx + t1 * dx, p0.dy + t1 * dy),
  );
}
