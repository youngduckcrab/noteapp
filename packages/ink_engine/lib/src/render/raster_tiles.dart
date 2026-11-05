// lib/src/render/raster_tiles.dart — INTERNAL (03-ink 6.13 L3, INK T19).
//
// Raster tiles of the ink layer: one image per chunk of InkChunkCache at a
// scale bucket (device px per pt).
// - scaleBucketFor: 6.13-1, the smallest bucket >= deviceScale.
// - RasterTile / rasterizeChunk: 6.13-4, the chunk picture + its appended
//   pictures recorded under scale(bucket) → Picture.toImageSync.
// - RasterTileLru: the app-wide LRU of InkCachePool (rasterBudgetBytes),
//   least recently USED first (6.13-7). A tile evicted for the budget tells
//   its owner, which then leaves that chunk to vectors until the viewport
//   changes (no evict / re-raster loop when the visible tiles do not fit).
// - PageRasterTiles: the tiles of one page controller (stretched fallback to
//   another bucket, 6.13-5; drop on dirty, 6.13-6; release, 6.13-7).
// - RasterScheduler: the timers of 6.13-2 (idle after input, zoom settle,
//   release of invisible chunks), alive only while an InkPageView is attached
//   so no timer outlives the widget tree.
import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:meta/meta.dart';

/// 6.13-1: the smallest of [buckets] >= [deviceScale]; null above the largest
/// (vector only) and for a [deviceScale] that is not a positive finite number.
/// Buckets that are not positive finite numbers are ignored.
double? scaleBucketFor(List<double> buckets, double deviceScale) {
  if (!(deviceScale > 0) || deviceScale.isInfinite) return null;
  double? best;
  for (final b in buckets) {
    if (!(b > 0) || b.isInfinite) continue;
    if (b + 1e-9 >= deviceScale && (best == null || b < best)) best = b;
  }
  return best;
}

/// (owner page, chunk index, bucket) — 6.13 L3 key.
typedef RasterTileKey = ({Object owner, int chunk, double bucket});

/// Told when the LRU drops one of its tiles for the budget.
abstract interface class RasterTileOwner {
  void tileEvicted(RasterTileKey key);
}

/// One chunk rendered at one bucket.
final class RasterTile {
  RasterTile({
    required this.image,
    required this.pageRect,
    required this.bucket,
    required this.generation,
    required this.appendedCount,
  });

  final ui.Image image;

  /// Where the image goes, in page pt: the chunk ∩ page, rounded up to whole
  /// pixels of [bucket] (1 image px = 1 / bucket pt).
  final ui.Rect pageRect;
  final double bucket;

  /// The chunk generation it was made from (InkChunkCache.generationOf).
  final int generation;

  /// The chunk's appended pictures already in the image (6.13-5: the later
  /// ones are drawn on top).
  final int appendedCount;

  int get bytes => image.width * image.height * 4;

  static final ui.Paint _paint = ui.Paint()
    // Neighbouring tiles meet on the chunk lines like the non-AA chunk clips:
    // every device pixel is drawn by exactly one tile.
    ..isAntiAlias = false
    ..filterQuality = ui.FilterQuality.low;

  void draw(ui.Canvas canvas) => canvas.drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    pageRect,
    _paint,
  );

  void dispose() => image.dispose();
}

/// 6.13-4: [picture] + [appended] (page pt) cut to [chunkRect] at [bucket]
/// device px per pt, via Picture.toImageSync.
RasterTile rasterizeChunk({
  required ui.Picture picture,
  required List<ui.Picture> appended,
  required ui.Rect chunkRect,
  required double bucket,
  required int generation,
}) {
  final w = (chunkRect.width * bucket - 1e-6).ceil().clamp(1, 16384);
  final h = (chunkRect.height * bucket - 1e-6).ceil().clamp(1, 16384);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..scale(bucket)
    ..translate(-chunkRect.left, -chunkRect.top)
    ..drawPicture(picture);
  for (final p in appended) {
    canvas.drawPicture(p);
  }
  final tilePicture = recorder.endRecording();
  final ui.Image image;
  try {
    image = tilePicture.toImageSync(w, h);
  } finally {
    tilePicture.dispose();
  }
  return RasterTile(
    image: image,
    pageRect: ui.Rect.fromLTWH(
      chunkRect.left,
      chunkRect.top,
      w / bucket,
      h / bucket,
    ),
    bucket: bucket,
    generation: generation,
    appendedCount: appended.length,
  );
}

/// The app-wide tile LRU (6.13 L3, rasterBudgetBytes): least recently used
/// first; a tile evicted for the budget is reported to its owner.
final class RasterTileLru {
  RasterTileLru({required int budgetBytes}) : _budget = budgetBytes;

  final int _budget;
  final LinkedHashMap<RasterTileKey, RasterTile> _tiles = LinkedHashMap();
  int _bytes = 0;
  bool _disposed = false;

  int get budgetBytes => _budget;
  int get length => _tiles.length;
  int get bytes => _bytes;

  /// The tile of [key], now the most recently used.
  RasterTile? use(RasterTileKey key) {
    final t = _tiles.remove(key);
    if (t != null) _tiles[key] = t;
    return t;
  }

  /// The tile of [key] without touching its LRU place.
  RasterTile? peek(RasterTileKey key) => _tiles[key];

  /// Stores [tile] as the most recently used (replacing [key]'s), then
  /// evicts the least recently used tiles until the total fits the budget —
  /// [tile] itself when it alone is larger. After dispose the tile is freed
  /// (and reported as evicted, so its owner does not make it again).
  void put(RasterTileKey key, RasterTile tile) {
    if (_disposed) {
      tile.dispose();
      final owner = key.owner;
      if (owner is RasterTileOwner) owner.tileEvicted(key);
      return;
    }
    remove(key);
    _tiles[key] = tile;
    _bytes += tile.bytes;
    trimTo(_budget);
  }

  /// Frees the tile of [key] (not an eviction: the owner is not told).
  bool remove(RasterTileKey key) {
    final t = _tiles.remove(key);
    if (t == null) return false;
    _bytes -= t.bytes;
    t.dispose();
    return true;
  }

  /// Frees every tile whose key passes [test] (not an eviction).
  void removeWhere(bool Function(RasterTileKey key) test) {
    _tiles.removeWhere((key, t) {
      if (!test(key)) return false;
      _bytes -= t.bytes;
      t.dispose();
      return true;
    });
  }

  /// Evicts least recently used tiles until [maxBytes] fits; owners are told.
  void trimTo(int maxBytes) {
    while (_bytes > maxBytes && _tiles.isNotEmpty) {
      final key = _tiles.keys.first;
      final t = _tiles.remove(key)!;
      _bytes -= t.bytes;
      t.dispose();
      final owner = key.owner;
      if (owner is RasterTileOwner) owner.tileEvicted(key);
    }
  }

  int countOf(Object owner) {
    var n = 0;
    for (final k in _tiles.keys) {
      if (identical(k.owner, owner)) n++;
    }
    return n;
  }

  int bytesOf(Object owner) {
    var n = 0;
    for (final MapEntry(:key, :value) in _tiles.entries) {
      if (identical(key.owner, owner)) n += value.bytes;
    }
    return n;
  }

  /// Keys, least recently used first.
  @visibleForTesting
  List<RasterTileKey> get keys => List.unmodifiable(_tiles.keys);

  void dispose() {
    _disposed = true;
    removeWhere((_) => true);
  }
}

/// The tiles of one page in the app-wide LRU.
final class PageRasterTiles implements RasterTileOwner {
  PageRasterTiles(this._lru, List<double> buckets)
    : _buckets = [
        for (final b in buckets)
          if (b > 0 && b.isFinite) b,
      ]..sort();

  final RasterTileLru _lru;

  /// Ascending.
  final List<double> _buckets;

  /// Chunks whose tile the budget evicted: vectors until [clearEvicted].
  final Set<int> _evicted = {};

  int get count => _lru.countOf(this);
  int get bytes => _lru.bytesOf(this);

  RasterTileKey _key(int chunk, double bucket) =>
      (owner: this, chunk: chunk, bucket: bucket);

  bool has(int chunk, double bucket) => _lru.peek(_key(chunk, bucket)) != null;

  bool wasEvicted(int chunk) => _evicted.contains(chunk);

  /// The tile to draw for [chunk] (6.13-5): the [bucket] tile, else the
  /// nearest finer one, else the nearest coarser one (stretched); null →
  /// vector picture. A tile of another [generation] is dropped.
  RasterTile? tileFor(int chunk, double bucket, int generation) {
    RasterTile? take(double b) {
      final key = _key(chunk, b);
      final t = _lru.use(key);
      if (t == null) return null;
      if (t.generation != generation) {
        _lru.remove(key);
        return null;
      }
      return t;
    }

    final exact = take(bucket);
    if (exact != null) return exact;
    for (final b in _buckets) {
      if (b > bucket) {
        final t = take(b);
        if (t != null) return t;
      }
    }
    for (final b in _buckets.reversed) {
      if (b < bucket) {
        final t = take(b);
        if (t != null) return t;
      }
    }
    return null;
  }

  /// Stores [tile] for [chunk]; the chunk's tiles at other buckets go.
  void store(int chunk, RasterTile tile) {
    for (final b in _buckets) {
      if (b != tile.bucket) _lru.remove(_key(chunk, b));
    }
    _evicted.remove(chunk);
    _lru.put(_key(chunk, tile.bucket), tile);
  }

  /// 6.13-6: the chunk was cleared (dirty, consolidated, reset).
  void dropChunk(int chunk) {
    _evicted.remove(chunk);
    if (_lru.length == 0) return;
    for (final b in _buckets) {
      _lru.remove(_key(chunk, b));
    }
  }

  /// 6.13-7: frees the tiles of the chunks [test] accepts.
  void dropWhere(bool Function(int chunk) test) =>
      _lru.removeWhere((key) => identical(key.owner, this) && test(key.chunk));

  void dropAll() {
    _evicted.clear();
    _lru.removeWhere((key) => identical(key.owner, this));
  }

  /// The viewport changed: evicted chunks may be tried again.
  void clearEvicted() => _evicted.clear();

  @override
  void tileEvicted(RasterTileKey key) => _evicted.add(key.chunk);
}

/// 6.13-2 timers: [quiet] once [idleMs] passed since the last [activity] and
/// [settleMs] since the last [viewportChanged] while not scaling; [onQuiet]
/// is called when it becomes quiet. [scheduleRelease] calls [onRelease]
/// [releaseMs] after the last call. Timers run only while attached.
final class RasterScheduler {
  RasterScheduler({
    required this.idleMs,
    required this.settleMs,
    required this.releaseMs,
    required this.onQuiet,
    required this.onRelease,
  });

  final int idleMs;
  final int settleMs;
  final int releaseMs;
  final void Function() onQuiet;
  final void Function() onRelease;

  bool _attached = false;
  bool _idle = false;
  bool _settled = false;
  bool _scaling = false;
  Timer? _idleTimer;
  Timer? _settleTimer;
  Timer? _releaseTimer;

  bool get isAttached => _attached;

  /// No input for idleMs, no viewport change for settleMs, not scaling.
  bool get quiet => _attached && _idle && _settled && !_scaling;

  /// A view is attached: both waits start over.
  void attach({required bool isScaling}) {
    _attached = true;
    activity();
    viewportChanged(isScaling: isScaling);
  }

  /// No view: no timers, not quiet.
  void detach() {
    _attached = false;
    _idle = false;
    _settled = false;
    _idleTimer?.cancel();
    _settleTimer?.cancel();
    _releaseTimer?.cancel();
    _idleTimer = _settleTimer = _releaseTimer = null;
  }

  /// Input or a display change: wait idleMs again.
  void activity() {
    _idle = false;
    _idleTimer?.cancel();
    _idleTimer = null;
    if (!_attached) return;
    _idleTimer = Timer(Duration(milliseconds: idleMs), () {
      _idleTimer = null;
      _idle = true;
      if (quiet) onQuiet();
    });
  }

  /// The scale, the visible rect or isScaling changed: settleMs after the
  /// last change with isScaling false.
  void viewportChanged({required bool isScaling}) {
    _scaling = isScaling;
    _settled = false;
    _settleTimer?.cancel();
    _settleTimer = null;
    if (!_attached || isScaling) return;
    _settleTimer = Timer(Duration(milliseconds: settleMs), () {
      _settleTimer = null;
      _settled = true;
      if (quiet) onQuiet();
    });
  }

  /// [onRelease] after releaseMs without another call.
  void scheduleRelease() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    if (!_attached) return;
    _releaseTimer = Timer(Duration(milliseconds: releaseMs), () {
      _releaseTimer = null;
      onRelease();
    });
  }

  void dispose() => detach();
}
