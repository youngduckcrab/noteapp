// lib/src/render/render_config.dart — 03-ink 4.9; (v2.1, CP-INK-5) imageCacheBytes,
// mathRasterCacheBytes (m5-7/03-ink 4.10). Final fields (T24).
import 'package:meta/meta.dart';

@immutable
final class InkRenderConfig {
  const InkRenderConfig({
    this.rasterTiles = true,
    this.chunkSizePt = 256,
    this.scaleBuckets = const [0.5, 1.0, 1.5, 2.0, 3.0, 4.0],
    this.rasterBudgetBytes = 128 * 1024 * 1024,
    this.outlineBudgetBytes = 64 * 1024 * 1024,
    this.idleBeforeRasterMs = 300,
    this.zoomSettleMs = 150,
    this.frameWorkBudgetMs = 4.0,
    this.maxTileRastersPerFrame = 1,
    this.releaseInvisibleAfterMs = 2000,
    this.maxAppendedPictures = 16,
    this.pendingCommitTimeoutMs = 3000,
    this.imageCacheBytes,
    this.mathRasterCacheBytes = 8 * 1024 * 1024,
  });

  /// Native (iPad / Android app): chunk 256 pt → tiles ≤ 1024 px, outline 64 MB, raster 128 MB.
  static const InkRenderConfig nativeDefaults = InkRenderConfig();

  /// Web (iPad Safari, 7.4.10): chunk 128 pt → tiles ≤ 512 px, outline 32 MB, raster 96 MB.
  static const InkRenderConfig webDefaults = InkRenderConfig(
    chunkSizePt: 128,
    rasterBudgetBytes: 96 * 1024 * 1024,
    outlineBudgetBytes: 32 * 1024 * 1024,
  );

  /// webDefaults when bool.fromEnvironment('dart.library.js_interop'), else nativeDefaults.
  static const InkRenderConfig platformDefault =
      bool.fromEnvironment('dart.library.js_interop')
      ? webDefaults
      : nativeDefaults;

  final bool rasterTiles;
  final double chunkSizePt;

  /// device px per pt; above the max → vector only
  final List<double> scaleBuckets;
  final int rasterBudgetBytes;
  final int outlineBudgetBytes;
  final int idleBeforeRasterMs;
  final int zoomSettleMs;
  final double frameWorkBudgetMs;
  final int maxTileRastersPerFrame;
  final int releaseInvisibleAfterMs;
  final int maxAppendedPictures;
  final int pendingCommitTimeoutMs;

  /// Decoded-image budget. null = platform rule: native → own ledger of 128 MiB; web → the
  /// SAME ledger as the raster tiles (rasterBudgetBytes, 96 MiB in webDefaults — 7.4.5).
  /// A value → an own ledger of that size (tests, or a native override).
  final int? imageCacheBytes;

  /// 8 MiB on both platforms (7.4.5)
  final int mathRasterCacheBytes;

  /// (v2.1) copyWith cannot clear [imageCacheBytes] back to null; pass
  /// clearImageCacheBytes: true for that.
  InkRenderConfig copyWith({
    bool? rasterTiles,
    double? chunkSizePt,
    List<double>? scaleBuckets,
    int? rasterBudgetBytes,
    int? outlineBudgetBytes,
    int? idleBeforeRasterMs,
    int? zoomSettleMs,
    double? frameWorkBudgetMs,
    int? maxTileRastersPerFrame,
    int? releaseInvisibleAfterMs,
    int? maxAppendedPictures,
    int? pendingCommitTimeoutMs,
    int? imageCacheBytes,
    bool clearImageCacheBytes = false,
    int? mathRasterCacheBytes,
  }) => InkRenderConfig(
    rasterTiles: rasterTiles ?? this.rasterTiles,
    chunkSizePt: chunkSizePt ?? this.chunkSizePt,
    scaleBuckets: scaleBuckets == null
        ? this.scaleBuckets
        : List.unmodifiable(scaleBuckets),
    rasterBudgetBytes: rasterBudgetBytes ?? this.rasterBudgetBytes,
    outlineBudgetBytes: outlineBudgetBytes ?? this.outlineBudgetBytes,
    idleBeforeRasterMs: idleBeforeRasterMs ?? this.idleBeforeRasterMs,
    zoomSettleMs: zoomSettleMs ?? this.zoomSettleMs,
    frameWorkBudgetMs: frameWorkBudgetMs ?? this.frameWorkBudgetMs,
    maxTileRastersPerFrame:
        maxTileRastersPerFrame ?? this.maxTileRastersPerFrame,
    releaseInvisibleAfterMs:
        releaseInvisibleAfterMs ?? this.releaseInvisibleAfterMs,
    maxAppendedPictures: maxAppendedPictures ?? this.maxAppendedPictures,
    pendingCommitTimeoutMs:
        pendingCommitTimeoutMs ?? this.pendingCommitTimeoutMs,
    imageCacheBytes: clearImageCacheBytes
        ? null
        : (imageCacheBytes ?? this.imageCacheBytes),
    mathRasterCacheBytes: mathRasterCacheBytes ?? this.mathRasterCacheBytes,
  );

  @override
  bool operator ==(Object other) {
    if (other is! InkRenderConfig) return false;
    if (other.scaleBuckets.length != scaleBuckets.length) return false;
    for (var i = 0; i < scaleBuckets.length; i++) {
      if (other.scaleBuckets[i] != scaleBuckets[i]) return false;
    }
    return other.rasterTiles == rasterTiles &&
        other.chunkSizePt == chunkSizePt &&
        other.rasterBudgetBytes == rasterBudgetBytes &&
        other.outlineBudgetBytes == outlineBudgetBytes &&
        other.idleBeforeRasterMs == idleBeforeRasterMs &&
        other.zoomSettleMs == zoomSettleMs &&
        other.frameWorkBudgetMs == frameWorkBudgetMs &&
        other.maxTileRastersPerFrame == maxTileRastersPerFrame &&
        other.releaseInvisibleAfterMs == releaseInvisibleAfterMs &&
        other.maxAppendedPictures == maxAppendedPictures &&
        other.pendingCommitTimeoutMs == pendingCommitTimeoutMs &&
        other.imageCacheBytes == imageCacheBytes &&
        other.mathRasterCacheBytes == mathRasterCacheBytes;
  }

  @override
  int get hashCode => Object.hash(
    rasterTiles,
    chunkSizePt,
    Object.hashAll(scaleBuckets),
    rasterBudgetBytes,
    outlineBudgetBytes,
    idleBeforeRasterMs,
    zoomSettleMs,
    frameWorkBudgetMs,
    maxTileRastersPerFrame,
    releaseInvisibleAfterMs,
    maxAppendedPictures,
    pendingCommitTimeoutMs,
    imageCacheBytes,
    mathRasterCacheBytes,
  );
}
