// lib/src/image/image_cache.dart — contract 7.2.9 (m5-7/03-ink 4.7, members 4.10).
//
// Foundation step R2-B3 (03-ink 4.13): the signatures work, nothing is
// decoded yet — peek → null, load → null, changes never emits. T35 brings
// the buckets, the reference counts, the shared web ledger and the
// per-asset change notices of 6.11.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:note_core/note_core.dart' as core;

import '../render/cache_pool.dart';

/// Web build (dart2js / dart2wasm): the image budget is the shared raster ledger.
const bool _isWeb = bool.fromEnvironment('dart.library.js_interop');

/// Decoded image cache shared by image objects, image backgrounds and thumbnails.
/// Budget (v2.1, 7.4.5): web — shares the 96 MB raster ledger with the tiles; native 128 MB.
/// Decodes at the display bucket (no full-res decode). (v2.1) Entries drawn by live pictures are
/// counted and not evicted; a request over budget gets the next lower bucket (no evict / re-decode
/// loop); change notices name the asset, so only chunks that draw it are re-recorded. Budgets are
/// InkRenderConfig fields (CP-INK-5: imageCacheBytes, mathRasterCacheBytes).
final class InkImageCache {
  /// [budgetBytes] / [pool] null → InkRenderConfig.platformDefault rule above (web without a
  /// pool: an own 96 MiB ledger — tests only). inkImageCacheProvider passes the app pool.
  InkImageCache({
    required core.AssetStore assets,
    int? budgetBytes,
    InkCachePool? pool,
  }) : // the contract names the parameters; the fields stay private
       // ignore: prefer_initializing_formals
       _assets = assets,
       // ignore: prefer_initializing_formals
       _budgetBytes = budgetBytes,
       // ignore: prefer_initializing_formals
       _pool = pool;

  final core.AssetStore _assets;
  final int? _budgetBytes;
  final InkCachePool? _pool;
  final StreamController<({String assetId, int bucket})> _changes =
      StreamController.broadcast();
  bool _disposed = false;

  static const int _nativeBudgetBytes = 128 * 1024 * 1024;
  static const int _webOwnLedgerBytes = 96 * 1024 * 1024;

  /// The store the images are read from.
  core.AssetStore get assets => _assets;

  /// [budgetBytes] when given; otherwise native → 128 MiB, web → the pool's raster
  /// budget (the shared ledger) or 96 MiB without a pool.
  int get budgetBytes {
    final own = _budgetBytes;
    if (own != null) return own;
    if (!_isWeb) return _nativeBudgetBytes;
    final pool = _pool;
    return pool == null
        ? _webOwnLedgerBytes
        : cachePoolConfigOf(pool).rasterBudgetBytes;
  }

  /// Decoded image of [assetId] at the bucket for [longSidePx]: the smallest
  /// InkTuning.imageBucketsPx ≥ longSidePx, never above the source size, lowered one bucket at a
  /// time while it does not fit the budget (6.11.3 — computed before decoding, one decode);
  /// else the best decoded one so far; null = none yet (a decode is queued). Never throws. The
  /// cache owns the handle: callers draw it at once and never dispose it.
  /// (R2-B3: always null — nothing is decoded before T35.)
  ui.Image? peek(
    String assetId, {
    required int longSidePx,
    int? pixelWidth,
    int? pixelHeight,
  }) => null;

  /// Same, waiting for that bucket's decode. null = bytes not on this device or undecodable.
  /// (R2-B3: always null.)
  Future<ui.Image?> load(
    String assetId, {
    required int longSidePx,
    int? pixelWidth,
    int? pixelHeight,
  }) => Future<ui.Image?>.value();

  /// (v2.1) One event per (asset, bucket) change: a decode finished, core.AssetStore.bytesArrived
  /// brought a missing asset (bucket 0 = 'ask again'), an entry was evicted or capped to a lower
  /// bucket. Broadcast, delivered asynchronously. Listeners re-record only what draws [assetId].
  /// (R2-B3: never emits.)
  Stream<({String assetId, int bucket})> get changes => _changes.stream;

  ({
    int images,
    int bytes,
    int pinnedBytes,
    int queued,
    int failures,
    int downgraded,
  })
  get stats => (
    images: 0,
    bytes: 0,
    pinnedBytes: 0,
    queued: 0,
    failures: 0,
    downgraded: 0,
  );

  bool get isDisposed => _disposed;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_changes.close());
  }
}
