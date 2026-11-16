// T19 (03-ink 4.9, 6.13): the render config values — native and web defaults
// (6.13 budgets, contract 7.4.10 for the web), the platform pick, copyWith and
// value equality. test/web/render_config_web_test.dart runs this in Chrome,
// where platformDefault must be webDefaults.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';

const _mb = 1024 * 1024;

void main() {
  test('nativeDefaults: chunk 256 pt, outline 64 MB, raster 128 MB', () {
    const c = InkRenderConfig.nativeDefaults;
    expect(c.chunkSizePt, 256);
    expect(c.outlineBudgetBytes, 64 * _mb);
    expect(c.rasterBudgetBytes, 128 * _mb);
    // the constructor defaults are the native values
    // ignore: use_named_constants
    expect(c, const InkRenderConfig());
  });

  test('webDefaults: chunk 128 pt, outline 32 MB, raster 96 MB', () {
    const c = InkRenderConfig.webDefaults;
    expect(c.chunkSizePt, 128);
    expect(c.outlineBudgetBytes, 32 * _mb);
    expect(c.rasterBudgetBytes, 96 * _mb);
    // 7.4.10: INK's managed caches on the web stay at 128 MB together
    expect(c.outlineBudgetBytes + c.rasterBudgetBytes, 128 * _mb);
    // the rest as native — (v2.15-math) but formula rasters 8 MiB (native 24)
    expect(
      c,
      InkRenderConfig.nativeDefaults.copyWith(
        chunkSizePt: 128,
        outlineBudgetBytes: 32 * _mb,
        rasterBudgetBytes: 96 * _mb,
        mathRasterCacheBytes: 8 * _mb,
      ),
    );
    expect(InkRenderConfig.nativeDefaults.mathRasterCacheBytes, 24 * _mb);
  });

  test(
    '(m5-7 T43, 6.22) the web INK app cache total: outline 32 + the shared '
    'raster ledger 96 (tiles + decoded images) + formula rasters 8 = 136 MiB',
    () {
      const c = InkRenderConfig.webDefaults;
      expect(
        c.imageCacheBytes,
        isNull,
        reason: 'images share the ledger on the web',
      );
      expect(
        c.outlineBudgetBytes + c.rasterBudgetBytes + c.mathRasterCacheBytes,
        136 * _mb,
      );
    },
  );

  test('the shared defaults (6.13, 6.28)', () {
    for (final c in const [
      InkRenderConfig.nativeDefaults,
      InkRenderConfig.webDefaults,
    ]) {
      expect(c.rasterTiles, isTrue);
      expect(c.scaleBuckets, [0.5, 1.0, 1.5, 2.0, 3.0, 4.0]);
      expect(c.idleBeforeRasterMs, 300);
      expect(c.zoomSettleMs, 150);
      expect(c.frameWorkBudgetMs, 4.0);
      expect(c.maxTileRastersPerFrame, 1);
      expect(c.releaseInvisibleAfterMs, 2000);
      expect(c.maxAppendedPictures, 16);
      expect(c.pendingCommitTimeoutMs, 3000);
    }
  });

  test('tile size: chunk × the largest bucket (6.13 L3)', () {
    // native 256 pt × 4 = 1024 px (4 MB), web 128 pt × 4 = 512 px (1 MB)
    for (final (c, px) in [
      (InkRenderConfig.nativeDefaults, 1024),
      (InkRenderConfig.webDefaults, 512),
    ]) {
      expect(c.chunkSizePt * c.scaleBuckets.last, px);
    }
  });

  test('platformDefault: webDefaults in the browser, nativeDefaults '
      'elsewhere', () {
    expect(
      InkRenderConfig.platformDefault,
      kIsWeb ? InkRenderConfig.webDefaults : InkRenderConfig.nativeDefaults,
    );
  });

  test('copyWith changes one field; equality by value (buckets too)', () {
    const base = InkRenderConfig.nativeDefaults;
    expect(base.copyWith(), base);
    expect(base.copyWith().hashCode, base.hashCode);
    final changed = [
      base.copyWith(rasterTiles: false),
      base.copyWith(chunkSizePt: 64),
      base.copyWith(scaleBuckets: [1, 2]),
      base.copyWith(rasterBudgetBytes: 1),
      base.copyWith(outlineBudgetBytes: 1),
      base.copyWith(idleBeforeRasterMs: 1),
      base.copyWith(zoomSettleMs: 1),
      base.copyWith(frameWorkBudgetMs: 1),
      base.copyWith(maxTileRastersPerFrame: 2),
      base.copyWith(releaseInvisibleAfterMs: 1),
      base.copyWith(maxAppendedPictures: 1),
      base.copyWith(pendingCommitTimeoutMs: 1),
    ];
    for (final c in changed) {
      expect(c, isNot(base));
    }
    expect(
      base.copyWith(scaleBuckets: [0.5, 1.0, 1.5, 2.0, 3.0, 4.0]),
      base,
      reason: 'a new list with the same buckets',
    );
    expect(
      () => base.copyWith(scaleBuckets: [1]).scaleBuckets.add(2),
      throwsUnsupportedError,
    );
  });
}
