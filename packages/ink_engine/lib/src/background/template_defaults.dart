// lib/src/background/template_defaults.dart — INTERNAL (not exported): the
// page template defaults of 03-ink 6.16 — THE single source of the default
// template numbers (contract 7.2.5; CORE keeps no table). Units pt, W / H =
// page width / height. test/unit/background/template_defaults_test.dart checks
// every value against the 6.16 table.
//
// A null PageTemplate field or a missing / wrongly typed extras key falls back
// to the value here (that key only); unknown keys are ignored.
import 'dart:math' as math;

import 'package:note_core/note_core.dart' as core;

abstract final class TemplateDefaults {
  // --- spacing (per kind) ----------------------------------------------------
  static const double linedSpacing = 24;
  static const double gridSpacing = 14.1732; // 5 mm
  static const double dottedSpacing = 14.1732;
  static const double cornellSpacing = 24;
  static const double musicSpacing = 7; // staff line gap
  static const double plannerSpacing = 20;

  // --- widths ------------------------------------------------------------------
  static const double lineWidth = 0.5;
  static const double musicLineWidth = 0.6;

  /// dotted: lineWidth is the dot DIAMETER
  static const double dotDiameter = 1.5;

  /// structure lines = structureWidthFactor × lineWidth (1.0 by default)
  static const double structureWidthFactor = 2;
  static const double marginLineWidth = 0.75;

  // --- colors (lineColorArgb == null → by paper luminance) --------------------
  static const int lightLine = 0xFFB7C4D6;
  static const int lightDot = 0xFF9AA5B4;
  static const int lightStructure = 0xFF8FA3BF; // also staff lines
  static const int lightMargin = 0x99E57373;
  static const int darkLine = 0x4DFFFFFF;
  static const int darkDot = 0x66FFFFFF;
  static const int darkStructure = 0x80FFFFFF; // also staff lines
  static const int darkMargin = 0x99EF9A9A;

  // --- extras ------------------------------------------------------------------
  static const double linedMarginTop = 72;
  static const double linedMarginLeft = 72;
  static const bool linedShowMarginLine = true;

  static const double cornellHeaderHeight = 72;
  static const double cornellCueColumnMax = 180;
  static const double cornellCueColumnFraction = 0.3; // of W
  static const double cornellSummaryMax = 144;
  static const double cornellSummaryFraction = 0.2; // of H

  static const double musicMarginTop = 54;
  static const double musicMarginLeft = 36;
  static const double musicStaffGap = 36;
  static const int musicStaffLines = 5;

  static const String plannerLayout = 'weekly';
  static const double plannerMarginTop = 36;
  static const double plannerMarginLeft = 36;
  static const double plannerHeaderHeight = 56;

  /// planner: the title line sits this far below a cell's top; ruled lines stop
  /// this far above a cell's bottom.
  static const double plannerTitleOffset = 20;
  static const double plannerCellBottomGap = 4;

  /// Default spacing of [kind].
  static double spacingOf(core.PageTemplateKind kind) => switch (kind) {
    core.PageTemplateKind.lined => linedSpacing,
    core.PageTemplateKind.grid => gridSpacing,
    core.PageTemplateKind.dotted => dottedSpacing,
    core.PageTemplateKind.cornell => cornellSpacing,
    core.PageTemplateKind.music => musicSpacing,
    core.PageTemplateKind.planner => plannerSpacing,
  };

  /// Default lineWidth of [kind] (dotted: the dot diameter).
  static double lineWidthOf(core.PageTemplateKind kind) => switch (kind) {
    core.PageTemplateKind.music => musicLineWidth,
    core.PageTemplateKind.dotted => dotDiameter,
    _ => lineWidth,
  };

  static double cornellCueColumnWidth(double pageWidth) =>
      math.min(cornellCueColumnMax, cornellCueColumnFraction * pageWidth);

  static double cornellSummaryHeight(double pageHeight) =>
      math.min(cornellSummaryMax, cornellSummaryFraction * pageHeight);
}

/// The resolved parameters of one template on one page (6.16 rules applied).
final class ResolvedTemplate {
  ResolvedTemplate(this.template, {required int paperColorArgb})
    : spacing = _positive(
        template.spacing,
        TemplateDefaults.spacingOf(template.kind),
      ),
      lineWidth = _positive(
        template.lineWidth,
        TemplateDefaults.lineWidthOf(template.kind),
      ),
      darkPaper = core.PaperColors.isDark(paperColorArgb);

  final core.PageTemplate template;
  final double spacing;

  /// lineWidth (dotted: dot diameter)
  final double lineWidth;
  final bool darkPaper;

  double get structureWidth =>
      TemplateDefaults.structureWidthFactor * lineWidth;

  int get lineColor =>
      template.lineColorArgb ??
      (darkPaper ? TemplateDefaults.darkLine : TemplateDefaults.lightLine);
  int get dotColor =>
      template.lineColorArgb ??
      (darkPaper ? TemplateDefaults.darkDot : TemplateDefaults.lightDot);
  int get structureColor =>
      template.lineColorArgb ??
      (darkPaper
          ? TemplateDefaults.darkStructure
          : TemplateDefaults.lightStructure);

  /// Staff lines use the structure color.
  int get staffColor => structureColor;

  /// The margin line keeps the automatic color even with lineColorArgb.
  int get marginColor =>
      darkPaper ? TemplateDefaults.darkMargin : TemplateDefaults.lightMargin;

  /// A numeric extras value; missing, non-numeric or non-finite → [fallback].
  double number(String key, double fallback) {
    final v = template.extras[key];
    if (v is num && v.isFinite) return v.toDouble();
    return fallback;
  }

  /// A bool extras value; missing or not a bool → [fallback].
  bool flag(String key, bool fallback) {
    final v = template.extras[key];
    return v is bool ? v : fallback;
  }

  /// A string extras value; missing or not a string → [fallback].
  String text(String key, String fallback) {
    final v = template.extras[key];
    return v is String ? v : fallback;
  }

  static double _positive(double? v, double fallback) =>
      v != null && v.isFinite && v > 0 ? v : fallback;
}
