// lib/src/render/cache_pool.dart — 03-ink 4.9, 6.13.
//
// Foundation step B3: the L1 outline LRU is real (keyed by stroke id, valid
// while the InkStroke instance is identical). Raster tiles and chunk pictures
// come with INK T10 / T19, so their counters stay 0.
import 'dart:collection';

import 'package:meta/meta.dart';

import '../geometry/outline_generator.dart';
import '../geometry/stroke_outline.dart';
import '../model/ink_stroke.dart';
import 'render_config.dart';

/// App-wide caches shared by page controllers (6.13).
final class InkCachePool {
  InkCachePool(InkRenderConfig config) : _config = config;

  final InkRenderConfig _config;
  final LinkedHashMap<String, _OutlineEntry> _outlines = LinkedHashMap();
  int _outlineBytes = 0;
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

  InkCacheStats get stats => InkCacheStats(
    outlineEntries: _outlines.length,
    outlineBytes: _outlineBytes,
    rasterTiles: 0,
    rasterBytes: 0,
    chunkPictures: 0,
  );

  /// Evicts least recently used entries until the totals fit.
  void trimTo({int? outlineBytes, int? rasterBytes}) {
    if (outlineBytes == null) return;
    while (_outlineBytes > outlineBytes && _outlines.isNotEmpty) {
      final key = _outlines.keys.first;
      _outlineBytes -= _outlines.remove(key)!.outline.approximateBytes;
    }
  }

  void dispose() {
    _disposed = true;
    _outlines.clear();
    _outlineBytes = 0;
  }
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
