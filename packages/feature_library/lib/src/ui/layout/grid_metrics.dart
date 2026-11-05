// lib/src/ui/layout/grid_metrics.dart — 05-library 6.2 (grid columns).
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

import 'library_metrics.dart';
import 'size_class.dart';

/// Width of the content pane: the screen width minus the pinned sidebar and
/// its divider (281) in the expanded class while the sidebar is shown.
double libraryContentWidth(
  double screenWidth, {
  required LibrarySizeClass sizeClass,
  required bool sidebarVisible,
}) => sizeClass == LibrarySizeClass.expanded && sidebarVisible
    ? screenWidth - LibraryMetrics.sidebarWidth - LibraryMetrics.dividerWidth
    : screenWidth;

@immutable
final class GridMetrics {
  const GridMetrics({
    required this.columns,
    required this.tileWidth,
    required this.coverHeight,
    required this.tileHeight,
    required this.padding,
    required this.gap,
  });

  /// [contentWidth] = width of the content pane (sidebar already removed).
  ///   compact: padding 16, gap 12, min tile 140; otherwise 24, 20, 168.
  ///   inner = contentWidth - 2 * padding
  ///   columns = max(2, floor((inner + gap) / (minTile + gap)))
  ///   tileWidth = (inner - (columns - 1) * gap) / columns
  ///   coverHeight = tileWidth / (3/4); footer = 8 + 56 * min(textScale, 1.3)
  factory GridMetrics.forWidth(
    double contentWidth, {
    required LibrarySizeClass sizeClass,
    double textScale = 1.0,
  }) {
    final compact = sizeClass == LibrarySizeClass.compact;
    final padding = compact
        ? LibraryMetrics.gridPaddingCompact
        : LibraryMetrics.gridPaddingRegular;
    final gap = compact
        ? LibraryMetrics.gridGapCompact
        : LibraryMetrics.gridGapRegular;
    final minTile = compact
        ? LibraryMetrics.minTileWidthCompact
        : LibraryMetrics.minTileWidthRegular;
    final inner = math.max(0.0, contentWidth - 2 * padding);
    final columns = math.max(
      LibraryMetrics.minColumns,
      ((inner + gap) / (minTile + gap)).floor(),
    );
    final tileWidth = math.max(0.0, (inner - (columns - 1) * gap) / columns);
    final coverHeight = tileWidth / LibraryMetrics.coverAspect;
    final scale = math.min(textScale, LibraryMetrics.maxTileTextScale);
    final footer =
        8 + (LibraryMetrics.tileFooterBase - 8) * math.max(scale, 0.0);
    return GridMetrics(
      columns: columns,
      tileWidth: tileWidth,
      coverHeight: coverHeight,
      tileHeight: coverHeight + footer,
      padding: padding,
      gap: gap,
    );
  }

  final int columns;

  /// == cover width.
  final double tileWidth;

  /// tileWidth / coverAspect.
  final double coverHeight;

  /// coverHeight + footer.
  final double tileHeight;

  /// Left / right / top / bottom of the grid.
  final double padding;

  /// Between tiles, both axes.
  final double gap;

  @override
  bool operator ==(Object other) =>
      other is GridMetrics &&
      other.columns == columns &&
      other.tileWidth == tileWidth &&
      other.coverHeight == coverHeight &&
      other.tileHeight == tileHeight &&
      other.padding == padding &&
      other.gap == gap;

  @override
  int get hashCode =>
      Object.hash(columns, tileWidth, coverHeight, tileHeight, padding, gap);

  @override
  String toString() =>
      'GridMetrics($columns × ${tileWidth.toStringAsFixed(2)}, '
      'tile height ${tileHeight.toStringAsFixed(2)}, padding $padding, '
      'gap $gap)';
}
