// lib/src/ui/pen/width_mapping.dart — 04-editor 6.9.4.
import 'dart:math' as math;

import 'package:note_core/note_core.dart' as core;

/// Non-linear slider: fine control at small widths.
/// width(t) = snap(0.1 + 29.9 * t^2), t in [0, 1]
/// t(width) = sqrt((width - 0.1) / 29.9)
/// e.g. t=0.2 → 1.3 pt, t=0.5 → 7.6 pt, t=0.26 → 2.1 pt.
abstract final class WidthMapping {
  static const double min = core.StrokeStyle.minWidth; // 0.1
  static const double max = core.StrokeStyle.maxWidth; // 30.0
  static const double step = 0.1;

  static double widthAt(double t) {
    final tc = t.isNaN ? 0.0 : t.clamp(0.0, 1.0);
    return snap(min + (max - min) * tc * tc);
  }

  static double positionOf(double width) {
    final w = width.isNaN ? min : width.clamp(min, max);
    return math.sqrt((w - min) / (max - min)).clamp(0.0, 1.0);
  }

  /// Clamp to [min, max] and round to 0.1.
  static double snap(double width) {
    if (width.isNaN) return min;
    final rounded = (width.clamp(min, max) * 10).round() / 10;
    return rounded.clamp(min, max);
  }
}
