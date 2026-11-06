// lib/src/lines/line_tuning.dart — (internal) every constant of the line
// grouping (m5-7/05-library 6.5 table; values confirmed by the E-L5 run,
// 7.3). Changing a value is a 6.5 change: run unit/group_into_lines_test.dart
// (V9) with it. gapFactor is not here — it is the contract argument of
// groupIntoLines (default 1.2; callers may pass 1.5, 6.5 '알려진 한계').
import 'package:meta/meta.dart';

@immutable
final class LineTuning {
  const LineTuning({
    this.glyphInflateX = 0.5,
    this.glyphInflateY = 0.1,
    this.smallBoxRatio = 0.35,
    this.minVerticalOverlap = 0.5,
    this.tailBoxes = 2,
    this.smallAttachBand = 0.6,
    this.minStrokeHeight = 1,
    this.minGlyphHeight = 4,
  });

  /// Stroke boxes are widened by these × the median stroke-box height before
  /// overlapping strokes are joined into glyph boxes (6.5 step 2 — narrow
  /// vertically so glyphs of neighbouring lines stay apart).
  final double glyphInflateX, glyphInflateY;

  /// A glyph box lower than this × the glyph height is a 'small box' (dots,
  /// commas, strokes of a mark — 6.5 steps 3 and 5).
  final double smallBoxRatio;

  /// Vertical overlap (÷ the smaller height) that still joins a big box to a
  /// line (6.5 step 4).
  final double minVerticalOverlap;

  /// Last big boxes of a line a new box is compared with (a slanted line
  /// still chains — 6.5 step 4).
  final int tailBoxes;

  /// Vertical slack (× the glyph height) of a line band for small boxes
  /// (6.5 step 5).
  final double smallAttachBand;

  /// Floor of the median stroke-box height (pt).
  final double minStrokeHeight;

  /// Floor of the glyph height H (pt).
  final double minGlyphHeight;
}

/// The 6.5 values (E-L5 confirmed).
const LineTuning kLineTuning = LineTuning();
