// lib/src/render/cache_pool.dart — 03-ink 4.9, 6.13.
//
// L1: the outline LRU (keyed by stroke id, valid while the InkStroke instance
// is identical), outlineBudgetBytes. L3 (INK T19): the raster tile LRU of
// raster_tiles.dart, rasterBudgetBytes, least recently used first. The chunk
// picture count is the sum over the live page controllers (L2 lives in each
// controller). (m5-7 T36) The formula raster cache (mathRasterCacheBytes,
// 6.12.3 / 6.22) — app wide like the pool, made on first use.
import 'dart:collection';

import 'package:meta/meta.dart';

import '../geometry/outline_generator.dart';
import '../geometry/stroke_outline.dart';
import '../math/math_raster_cache.dart';
import '../model/ink_stroke.dart';
import 'raster_tiles.dart';
import 'render_config.dart';

/// App-wide caches shared by page controllers (6.13).
final class InkCachePool {
  InkCachePool(InkRenderConfig config)
    : _config = config,
      _tiles = RasterTileLru(budgetBytes: config.rasterBudgetBytes);

  final InkRenderConfig _config;
  final LinkedHashMap<String, _OutlineEntry> _outlines = LinkedHashMap();
  int _outlineBytes = 0;
  final RasterTileLru _tiles;
  final Set<int Function()> _pictureCounts = {};
  MathRasterCache? _math;
  bool _disposed = false;

  /// LRU keyed by stroke id, valid while the InkStroke instance is identical (K-4).
  StrokeOutline outlineFor(InkStroke stroke) {
    final hit = _outlines.remove(stroke.id);
    if (hit != null && identical(hit.stroke, stroke)) {
      _outlines[stroke.id] = hit; // most recently used
      return hit.outline;
    }
    if (hit != null) _outlineBytes -= hit.outline.approximateBytes;
    final outline = OutlineGenerator.outline(stroke);
    if (!_disposed) {
      _outlines[stroke.id] = _OutlineEntry(stroke, outline);
      _outlineBytes += outline.approximateBytes;
      trimTo(outlineBytes: _config.outlineBudgetBytes);
    }
    return outline;
  }

  InkCacheStats get stats {
    var pictures = 0;
    for (final count in _pictureCounts) {
      pictures += count();
    }
    return InkCacheStats(
      outlineEntries: _outlines.length,
      outlineBytes: _outlineBytes,
      rasterTiles: _tiles.length,
      rasterBytes: _tiles.bytes,
      chunkPictures: pictures,
    );
  }

  /// Evicts least recently used entries until the totals fit.
  void trimTo({int? outlineBytes, int? rasterBytes}) {
    if (outlineBytes != null) {
      while (_outlineBytes > outlineBytes && _outlines.isNotEmpty) {
        final key = _outlines.keys.first;
        _outlineBytes -= _outlines.remove(key)!.outline.approximateBytes;
      }
    }
    if (rasterBytes != null) _tiles.trimTo(rasterBytes);
  }

  void dispose() {
    _disposed = true;
    _outlines.clear();
    _outlineBytes = 0;
    _tiles.dispose();
    _pictureCounts.clear();
    _math?.dispose();
  }
}

/// INTERNAL (m5-7 T36): the formula raster cache of [pool] (6.12.3), made on first use
/// with the pool's mathRasterCacheBytes and scale buckets.
@internal
MathRasterCache mathRasterCacheOf(InkCachePool pool) {
  final cache = pool._math ??= MathRasterCache(
    budgetBytes: pool._config.mathRasterCacheBytes,
    scaleBuckets: pool._config.scaleBuckets,
  );
  if (pool._disposed) cache.dispose(); // peek → null, nothing is requested
  return cache;
}

/// INTERNAL: the raster tile LRU of [pool] (6.13 L3).
@internal
RasterTileLru rasterTileLruOf(InkCachePool pool) => pool._tiles;

/// INTERNAL: a page controller adds its chunk picture count to
/// [InkCachePool.stats] while it lives; returns the removal.
@internal
void Function() addChunkPictureCount(InkCachePool pool, int Function() count) {
  if (pool._disposed) return () {};
  pool._pictureCounts.add(count);
  return () => pool._pictureCounts.remove(count);
}

final class _OutlineEntry {
  _OutlineEntry(this.stroke, this.outline);
  final InkStroke stroke;
  final StrokeOutline outline;
}

@immutable
final class InkCacheStats {
  const InkCacheStats({
    required this.outlineEntries,
    required this.outlineBytes,
    required this.rasterTiles,
    required this.rasterBytes,
    required this.chunkPictures,
  });
  final int outlineEntries;
  final int outlineBytes;
  final int rasterTiles;
  final int rasterBytes;
  final int chunkPictures;

  /// outlineBytes + rasterBytes (developer overlay, 7.4.10 sum)
  int get totalBytes => outlineBytes + rasterBytes;
  static const InkCacheStats empty = InkCacheStats(
    outlineEntries: 0,
    outlineBytes: 0,
    rasterTiles: 0,
    rasterBytes: 0,
    chunkPictures: 0,
  );

  @override
  bool operator ==(Object other) =>
      other is InkCacheStats &&
      other.outlineEntries == outlineEntries &&
      other.outlineBytes == outlineBytes &&
      other.rasterTiles == rasterTiles &&
      other.rasterBytes == rasterBytes &&
      other.chunkPictures == chunkPictures;

  @override
  int get hashCode => Object.hash(
    outlineEntries,
    outlineBytes,
    rasterTiles,
    rasterBytes,
    chunkPictures,
  );

  @override
  String toString() =>
      'InkCacheStats(outlines $outlineEntries / $outlineBytes B, '
      'tiles $rasterTiles / $rasterBytes B, pictures $chunkPictures)';
}

/// INTERNAL: the render config [pool] was made with (the web image budget is its raster
/// ledger — m5-7/03-ink 4.10).
@internal
InkRenderConfig cachePoolConfigOf(InkCachePool pool) => pool._config;
