@TestOn('browser')
library;

// m5-7/03-ink 8.2 T35 (6.11.1, 6.11.3, 6.23) on the web (Chrome = CanvasKit):
// the image cache decodes at the target size (instantiateImageCodec targetWidth /
// targetHeight — a 1600 × 1200 PNG asked at 400 px is 512 × 384), the PNG / JPEG
// header is read in pure Dart (ImageDescriptor.width is not supported on the
// web and INK does not use it — no_platform_imports_test), and the pool's raster
// ledger is shared by the tiles and the images (one rasterBudgetBytes budget).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/image/image_cache.dart';
import 'package:ink_engine/src/image/image_header.dart';
import 'package:ink_engine/src/render/cache_pool.dart';
import 'package:ink_engine/testing.dart';

import '../support/jpeg_samples.dart';
import '../support/memory_asset_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'target-size decode: a 1600 × 1200 PNG at 400 px is 512 × 384',
    () async {
      final store = MemoryAssetStore();
      addTearDown(store.close);
      store.bytes['bg'] = await testPngBytes(width: 1600, height: 1200);
      store.bytes['obj'] = await testPngBytes(width: 400, height: 300);
      final cache = InkImageCache(assets: store);
      addTearDown(cache.dispose);
      final bg = await cache.load('bg', longSidePx: 400);
      expect([bg!.width, bg.height], [512, 384]);
      final obj = await cache.load(
        'obj',
        longSidePx: 200,
        pixelWidth: 400,
        pixelHeight: 300,
      );
      expect([obj!.width, obj.height], [256, 192]);
      expect(debugImageDecodes(cache), [
        (assetId: 'bg', width: 512, height: 384),
        (assetId: 'obj', width: 256, height: 192),
      ]);
    },
  );

  test('the header is read in pure Dart', () async {
    final png = await testPngBytes(width: 37, height: 21);
    expect(readImagePixelSize(png), (width: 37, height: 21));
    expect(readImagePixelSize(base64Decode(jpegProgressive9x4)), (
      width: 9,
      height: 4,
    ));
    expect(readImagePixelSize(base64Decode(jpegExif6x8)), (
      width: 6,
      height: 8,
    ));
  });

  test('the web pool shares one raster ledger with the images', () {
    const config = InkRenderConfig(rasterBudgetBytes: 1 << 20);
    final pool = InkCachePool(config);
    addTearDown(pool.dispose);
    final store = MemoryAssetStore();
    addTearDown(store.close);
    final cache = InkImageCache(assets: store, pool: pool);
    addTearDown(cache.dispose);
    expect(rasterLedgerOf(pool), isNotNull);
    expect(debugImageCacheIsShared(cache), isTrue);
    expect(cache.budgetBytes, 1 << 20);
    expect(rasterTileLruOf(pool).budgetBytes, 1 << 20);
    // without a pool: an own 96 MiB ledger; a given budget: its own
    final own = InkImageCache(assets: store);
    addTearDown(own.dispose);
    expect(own.budgetBytes, 96 * 1024 * 1024);
    expect(debugImageCacheIsShared(own), isFalse);
  });
}
