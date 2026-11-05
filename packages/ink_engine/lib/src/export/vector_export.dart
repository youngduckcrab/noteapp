// lib/src/export/vector_export.dart — 03-ink 4.11 (contract 7.2.16, approved).
//
// Foundation step B3 (03-ink 4.15): both functions return empty InkPageVectors.
// The export of 6.24 (outline paths, highlighter groups) comes with INK T21.
import 'dart:ui' show Rect;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../geometry/vector_path.dart';
import '../model/ink_stroke.dart';
import '../pen/pen_profile.dart';
import '../render/ink_page_content.dart';
import '../tuning.dart';

enum InkBlendMode { normal, multiply }

@immutable
final class InkExportOptions {
  const InkExportOptions({
    this.smooth = true,
    this.pencilOpacityFactor = InkTuning.exportPencilOpacityFactor,
    this.paperColorArgb = core.PaperColors.white,
  });
  final bool smooth;

  /// grain cannot be vector → flat color, slightly lighter
  final double pencilOpacityFactor;

  /// decides highlighter blend (6.10)
  final int paperColorArgb;

  @override
  bool operator ==(Object other) =>
      other is InkExportOptions &&
      other.smooth == smooth &&
      other.pencilOpacityFactor == pencilOpacityFactor &&
      other.paperColorArgb == paperColorArgb;

  @override
  int get hashCode => Object.hash(smooth, pencilOpacityFactor, paperColorArgb);
}

/// One filled ink stroke (z-ordered).
final class InkFillShape {
  InkFillShape._({
    required this.strokeId,
    required this.tool,
    required this.path,
    required this.colorArgb,
    required this.opacity,
  });
  final String strokeId;
  final core.PenTool tool;

  /// nonzero fill
  final InkVectorPath path;
  final int colorArgb;
  final double opacity;
}

/// One highlighter stroke inside a group.
final class InkHighlighterLine {
  InkHighlighterLine._({
    required this.strokeId,
    required this.centerline,
    required this.width,
    required this.cap,
  });
  final String strokeId;

  /// stroke it
  final InkVectorPath centerline;
  final double width;
  final InkCap cap;
}

/// Same color + opacity highlighters. Paint all lines of a group as ONE stroked path
/// with [opacity] and [blend] so overlaps do not darken (6.24).
final class InkHighlighterGroup {
  InkHighlighterGroup._({
    required this.colorArgb,
    required this.opacity,
    required this.blend,
    required this.lines,
  });
  final int colorArgb;
  final double opacity;
  final InkBlendMode blend;
  final List<InkHighlighterLine> lines;
}

final class InkPageVectors {
  InkPageVectors._({
    required this.highlighterGroups,
    required this.inkShapes,
    required this.bounds,
  });

  static final InkPageVectors _empty = InkPageVectors._(
    highlighterGroups: const [],
    inkShapes: const [],
    bounds: Rect.zero,
  );

  /// draw first (below ink)
  final List<InkHighlighterGroup> highlighterGroups;

  /// then these, in order
  final List<InkFillShape> inkShapes;
  final Rect bounds;
  bool get isEmpty => highlighterGroups.isEmpty && inkShapes.isEmpty;
}

abstract final class InkVectorExport {
  static InkPageVectors exportStrokes(
    List<InkStroke> strokes, {
    InkExportOptions options = const InkExportOptions(),
  }) => InkPageVectors._empty;

  /// options == null → InkExportOptions(paperColorArgb: content.background.paperColorArgb).
  static InkPageVectors exportPage(
    InkPageContent content, {
    InkExportOptions? options,
  }) => exportStrokes(
    content.strokes,
    options:
        options ??
        InkExportOptions(paperColorArgb: content.background.paperColorArgb),
  );
}
