// lib/src/render/tile_math.dart — 06-pdf 6.7.1, 6.7.2 (PDF T8). Internal (not exported).
//
// Pure calculations of the page background renderer: scale buckets, the preview scale, the
// tile grid with its 1 px overlap, the tiles a visible rectangle needs (25% prefetch margin,
// at most 64) and the whole per-page plan (thumbnail mode or preview + tiles). Web-safe
// numbers only (contract 7.4.3): doubles and small ints, no bit operations.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../engine/page_info.dart';
import '../model/page_size_policy.dart';
import '../tuning.dart';
import 'render_service.dart' show PdfBackgroundParams;

/// The paper color with alpha forced to 0xFF, without bit operations (contract 7.4.3).
/// Render backgrounds and the painted paper are always opaque (6.8 ①).
int opaquePaperArgb(int argb) => 0xFF000000 + argb % 0x1000000;

/// Image kinds of the render cache; each has its own byte budget (6.7.4).
enum PdfRenderKind { preview, tile, thumbnail }

/// Render queue classes, highest priority first (6.7.3). Within a class: request order.
enum PdfRenderClass {
  visiblePreview,
  visibleTile,
  thumbnail,
  prefetchTile;

  /// pdfrx priority hint (V16, native only).
  PdfRenderPriority get priorityHint => switch (this) {
    PdfRenderClass.visiblePreview => PdfRenderPriority.high,
    PdfRenderClass.visibleTile => PdfRenderPriority.high,
    PdfRenderClass.thumbnail => PdfRenderPriority.normal,
    PdfRenderClass.prefetchTile => PdfRenderPriority.low,
  };
}

/// 6.7.1: b(s) = 1.25^n, n = ceil(log(s × 0.95) / log 1.25), clamped to [0.125, 24].
/// Over-render ≤ 25%, under-render ≤ 5%.
double bucketScale(double s) {
  if (s.isNaN || s <= 0) return PdfTuning.minScale;
  if (s.isInfinite) return PdfTuning.maxScale;
  final n =
      (math.log(s * PdfTuning.bucketUnderSampleTolerance) /
              math.log(PdfTuning.scaleBucketBase))
          .ceil();
  final b = math.pow(PdfTuning.scaleBucketBase, n).toDouble();
  return b.clamp(PdfTuning.minScale, PdfTuning.maxScale);
}

/// The scale whose full page image has [longSidePx] pixels on its long side
/// (PdfRenderRequest.fullPixelSize rounds up: the scale is a thousandth of a pixel short, so
/// floating-point noise never gives longSidePx + 1).
double scaleForLongSide(int longSidePx, ui.Size pdfPageSize) =>
    (longSidePx - _pixelSlack) /
    math.max(pdfPageSize.width, pdfPageSize.height);

const double _pixelSlack = 0.001;

/// 6.7.1: pv = min(b, 1024 / long side in displayed PDF pt). A4 → 1.216.
double previewScale(double bucket, ui.Size pdfPageSize) => math.min(
  bucket,
  scaleForLongSide(PdfTuning.previewMaxLongSidePx, pdfPageSize),
);

/// Thumbnail mode image: long side PdfTuning.thumbnailLongSidePx (256 px).
double thumbnailScale(ui.Size pdfPageSize) =>
    scaleForLongSide(PdfTuning.thumbnailLongSidePx, pdfPageSize);

/// 6.7.2 step 3: tiles only when s > pv × 1.1.
bool needsTiles(double s, double previewScale) =>
    s > previewScale * PdfTuning.tilesOnlyAboveRatio;

/// The 512 px tile grid of one page at one bucket scale (6.7.2 step 3).
@immutable
final class PdfTileGrid {
  /// Full page pixels (ceil(W·b), ceil(H·b)) — the same rounding as
  /// PdfRenderRequest.fullPixelSize, so tile regions stay inside the engine's page.
  factory PdfTileGrid(ui.Size pdfPageSize, double bucket) {
    final fullWidth = math.max(1, (pdfPageSize.width * bucket).ceil());
    final fullHeight = math.max(1, (pdfPageSize.height * bucket).ceil());
    return PdfTileGrid._(bucket, fullWidth, fullHeight);
  }

  const PdfTileGrid._(this.bucket, this.fullWidth, this.fullHeight);

  final double bucket;
  final int fullWidth, fullHeight;

  int get columns => (fullWidth / PdfTuning.tileSizePx).ceil();
  int get rows => (fullHeight / PdfTuning.tileSizePx).ceil();
  int get tileCount => columns * rows;

  /// Tile (i, j) without overlap: x = 512i, y = 512j, w = min(512, fullW − x),
  /// h = min(512, fullH − y).
  PdfPixelRect tileRect(int i, int j) {
    final x = i * PdfTuning.tileSizePx;
    final y = j * PdfTuning.tileSizePx;
    return PdfPixelRect(
      x,
      y,
      math.min(PdfTuning.tileSizePx, fullWidth - x),
      math.min(PdfTuning.tileSizePx, fullHeight - y),
    );
  }

  /// The rendered region: 1 px overlap on every side, clipped to the page.
  PdfPixelRect requestRect(int i, int j) {
    final t = tileRect(i, j);
    final left = math.max(0, t.left - PdfTuning.tileOverlapPx);
    final top = math.max(0, t.top - PdfTuning.tileOverlapPx);
    final right = math.min(fullWidth, t.right + PdfTuning.tileOverlapPx);
    final bottom = math.min(fullHeight, t.bottom + PdfTuning.tileOverlapPx);
    return PdfPixelRect(left, top, right - left, bottom - top);
  }

  /// Pixels of the rendered region that belong to the tile (overlap excluded).
  ui.Rect srcRect(int i, int j) {
    final t = tileRect(i, j);
    final r = requestRect(i, j);
    return ui.Rect.fromLTWH(
      (t.left - r.left).toDouble(),
      (t.top - r.top).toDouble(),
      t.width.toDouble(),
      t.height.toDouble(),
    );
  }

  /// The tile in displayed PDF pt.
  ui.Rect pdfRect(int i, int j) {
    final t = tileRect(i, j);
    return ui.Rect.fromLTWH(
      t.left / bucket,
      t.top / bucket,
      t.width / bucket,
      t.height / bucket,
    );
  }
}

/// One tile of a plan, in request order.
@immutable
final class PdfTileRef {
  const PdfTileRef(this.column, this.row, {required this.prefetch});
  final int column, row;

  /// Only in the 25% margin (render class 3), not in the visible rectangle (class 1).
  final bool prefetch;

  PdfRenderClass get renderClass =>
      prefetch ? PdfRenderClass.prefetchTile : PdfRenderClass.visibleTile;

  @override
  bool operator ==(Object other) =>
      other is PdfTileRef &&
      other.column == column &&
      other.row == row &&
      other.prefetch == prefetch;

  @override
  int get hashCode => Object.hash(column, row, prefetch);

  @override
  String toString() =>
      'PdfTileRef($column, $row${prefetch ? ', prefetch' : ''})';
}

/// 6.7.2 step 4. [visiblePdfRect] is in displayed PDF pt (fit.noteToPdf of the visible note
/// rect); null = the whole page. The visible rectangle grows by 25% of its size on every side
/// (clipped to the page); tiles touching the visible rectangle come first (nearest its centre
/// first), then the margin-only tiles. Limits: the whole page with more than 64 tiles → no
/// tiles (preview only); with a visible rectangle the list is cut at 64 (visible tiles kept
/// first). An empty visible rectangle (page off screen) needs no tiles.
List<PdfTileRef> tilesFor(
  PdfTileGrid grid,
  ui.Size pdfPageSize, {
  ui.Rect? visiblePdfRect,
}) {
  final page = ui.Offset.zero & pdfPageSize;
  if (visiblePdfRect == null) {
    if (grid.tileCount > PdfTuning.maxTilesPerPage) return const [];
    return [
      for (var j = 0; j < grid.rows; j++)
        for (var i = 0; i < grid.columns; i++)
          PdfTileRef(i, j, prefetch: false),
    ];
  }
  final visible = visiblePdfRect.intersect(page);
  if (visible.width <= 0 || visible.height <= 0) return const [];
  final margin = PdfTuning.prefetchMarginFraction;
  final wanted = ui.Rect.fromLTRB(
    visible.left - visible.width * margin,
    visible.top - visible.height * margin,
    visible.right + visible.width * margin,
    visible.bottom + visible.height * margin,
  ).intersect(page);
  final (c0, r0, c1, r1) = _cellRange(grid, wanted);
  final centre = visible.center;
  final near = <(double, PdfTileRef)>[];
  final far = <(double, PdfTileRef)>[];
  for (var j = r0; j <= r1; j++) {
    for (var i = c0; i <= c1; i++) {
      final rect = grid.pdfRect(i, j);
      final distance = (rect.center - centre).distanceSquared;
      if (_overlaps(rect, visible)) {
        near.add((distance, PdfTileRef(i, j, prefetch: false)));
      } else {
        far.add((distance, PdfTileRef(i, j, prefetch: true)));
      }
    }
  }
  int byDistance((double, PdfTileRef) a, (double, PdfTileRef) b) =>
      a.$1.compareTo(b.$1);
  near.sort(byDistance);
  far.sort(byDistance);
  final tiles = [for (final (_, t) in near) t, for (final (_, t) in far) t];
  return tiles.length > PdfTuning.maxTilesPerPage
      ? tiles.sublist(0, PdfTuning.maxTilesPerPage)
      : tiles;
}

/// Positive-area overlap (touching edges do not count).
bool _overlaps(ui.Rect a, ui.Rect b) =>
    a.left < b.right &&
    b.left < a.right &&
    a.top < b.bottom &&
    b.top < a.bottom;

/// Inclusive column / row range of the cells overlapping [pdfRect] (displayed PDF pt).
(int, int, int, int) _cellRange(PdfTileGrid grid, ui.Rect pdfRect) {
  final size = PdfTuning.tileSizePx;
  int clampCol(int v) => v.clamp(0, grid.columns - 1);
  int clampRow(int v) => v.clamp(0, grid.rows - 1);
  final b = grid.bucket;
  return (
    clampCol((pdfRect.left * b / size).floor()),
    clampRow((pdfRect.top * b / size).floor()),
    // The cell holding the last pixel strictly inside the right / bottom edge.
    clampCol((pdfRect.right * b / size).ceil() - 1),
    clampRow((pdfRect.bottom * b / size).ceil() - 1),
  );
}

/// What one page background draws (6.7.2): a thumbnail alone, or a preview plus tiles.
@immutable
final class PdfRenderPlan {
  const PdfRenderPlan._({
    required this.fit,
    required this.pdfPageSize,
    required this.scale,
    required this.thumbnailMode,
    required this.baseScale,
    required this.grid,
    required this.tiles,
  });

  /// [pdfPageSize] = the displayed size of the PDF page (PdfPageInfo width × height).
  factory PdfRenderPlan.of(PdfBackgroundParams params, ui.Size pdfPageSize) {
    final fit = PdfPageFit(
      notePageSize: params.pageSize,
      pdfPageSize: pdfPageSize,
    );
    // device px per displayed PDF pt (6.7.1).
    final s = params.deviceScale * fit.k;
    if (params.usesThumbnailMode) {
      return PdfRenderPlan._(
        fit: fit,
        pdfPageSize: pdfPageSize,
        scale: s,
        thumbnailMode: true,
        baseScale: thumbnailScale(pdfPageSize),
        grid: null,
        tiles: const [],
      );
    }
    final b = bucketScale(s);
    final pv = previewScale(b, pdfPageSize);
    PdfTileGrid? grid;
    var tiles = const <PdfTileRef>[];
    if (needsTiles(s, pv)) {
      final g = PdfTileGrid(pdfPageSize, b);
      final visible = params.visiblePageRect;
      tiles = tilesFor(
        g,
        pdfPageSize,
        visiblePdfRect: visible == null ? null : fit.noteToPdf(visible),
      );
      if (tiles.isNotEmpty) grid = g;
    }
    return PdfRenderPlan._(
      fit: fit,
      pdfPageSize: pdfPageSize,
      scale: s,
      thumbnailMode: false,
      baseScale: pv,
      grid: grid,
      tiles: tiles,
    );
  }

  final PdfPageFit fit;
  final ui.Size pdfPageSize;

  /// s = deviceScale × fit.k (device px per displayed PDF pt).
  final double scale;

  /// Thumbnail mode (6.7.1): one 256 px image, no tiles.
  final bool thumbnailMode;

  /// Scale of the base image: the thumbnail scale, or the preview scale pv.
  final double baseScale;
  PdfRenderKind get baseKind =>
      thumbnailMode ? PdfRenderKind.thumbnail : PdfRenderKind.preview;

  /// Null when the plan has no tiles.
  final PdfTileGrid? grid;

  /// Tiles in request order (visible nearest-first, then prefetch).
  final List<PdfTileRef> tiles;

  double? get tileBucket => grid?.bucket;

  /// Note-pt rect of a tile (6.7.2 step 4: placed with fit.pdfToNote).
  ui.Rect tilePageRect(int column, int row) =>
      fit.pdfToNote(grid!.pdfRect(column, row));
}
