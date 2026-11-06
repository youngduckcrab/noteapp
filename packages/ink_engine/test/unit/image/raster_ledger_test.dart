// m5-7/03-ink 8.2 T35 (6.11.3, 6.22, 7.4.5 v2.1): the raster ledger.
// - Web rule (the pool's ledger, also made on the VM with debugCachePoolWithLedger):
//   the raster tiles and the decoded images are one budget (rasterBudgetBytes) and
//   one least-recently-used order; a pinned image stays while tiles are evicted
//   (their owner is told); a released image goes in LRU order with the tiles; an
//   image request counts the tiles as evictable (no lowered bucket for them).
// - Native rule: no shared ledger — the tiles keep rasterBudgetBytes, the images
//   an own 128 MiB; filling one does not evict the other.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/image/image_cache.dart';
import 'package:ink_engine/src/render/cache_pool.dart';
import 'package:ink_engine/src/render/raster_tiles.dart';
import 'package:ink_engine/testing.dart';

import '../../support/memory_asset_store.dart';

/// 64 × 64 px RGBA = 16 KiB (one tile and one image in these tests).
const int _unit = 64 * 64 * 4;

ui.Image _blank(int w, int h) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder);
  final picture = recorder.endRecording();
  try {
    return picture.toImageSync(w, h);
  } finally {
    picture.dispose();
  }
}

final class _Owner implements RasterTileOwner {
  final List<RasterTileKey> evicted = [];
  @override
  void tileEvicted(RasterTileKey key) => evicted.add(key);
}

RasterTile _tile() => RasterTile(
  image: _blank(64, 64),
  pageRect: const ui.Rect.fromLTWH(0, 0, 64, 64),
  bucket: 1,
  generation: 0,
  appendedCount: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryAssetStore store;
  setUp(() async {
    store = MemoryAssetStore();
    for (final id in ['a', 'b', 'c']) {
      store.bytes[id] = await testPngBytes(width: 64, height: 64);
    }
  });
  tearDown(() => store.close());

  group('web rule: tiles and images share one ledger', () {
    late InkCachePool pool;
    late InkImageCache images;
    late RasterTileLru tiles;
    setUp(() {
      pool = debugCachePoolWithLedger(
        const InkRenderConfig(rasterBudgetBytes: 4 * _unit),
        shared: true,
      );
      images = InkImageCache(assets: store, pool: pool);
      tiles = rasterTileLruOf(pool);
    });
    tearDown(() {
      images.dispose();
      pool.dispose();
    });

    test('one budget: the pool raster budget, shared', () {
      expect(rasterLedgerOf(pool), isNotNull);
      expect(debugImageCacheIsShared(images), isTrue);
      expect(images.budgetBytes, 4 * _unit);
      expect(tiles.budgetBytes, 4 * _unit);
      expect(identical(tiles.ledger, rasterLedgerOf(pool)), isTrue);
    });

    test(
      'a pinned image stays; tiles are evicted first and their owner told',
      () async {
        final owner = _Owner();
        await images.load('a', longSidePx: 64);
        final pin = images.pin('a', 128);
        for (var i = 0; i < 5; i++) {
          tiles.put((owner: owner, chunk: i, bucket: 1), _tile());
        }
        // 4 units: the image + 3 tiles; the two oldest tiles went
        expect(images.contains('a', 128), isTrue);
        expect(tiles.length, 3);
        expect(owner.evicted.map((k) => k.chunk), [0, 1]);
        expect(rasterLedgerOf(pool)!.bytes, 4 * _unit);
        // an image request: the tiles can go, so it is not lowered
        final b = await images.load('b', longSidePx: 64);
        expect(b, isNotNull);
        expect(images.stats.downgraded, 0);
        expect(owner.evicted.map((k) => k.chunk), [0, 1, 2]);
        expect(images.contains('a', 128), isTrue, reason: 'pinned');
        pin.release();
      },
    );

    test(
      'released images and tiles go in one least-recently-used order',
      () async {
        final owner = _Owner();
        final events = <({String assetId, int bucket})>[];
        final sub = images.changes.listen(events.add);
        addTearDown(sub.cancel);
        await images.load('a', longSidePx: 64);
        images.pin('a', 128).release(); // drawn once, not held now
        tiles.put((owner: owner, chunk: 0, bucket: 1), _tile());
        tiles.put((owner: owner, chunk: 1, bucket: 1), _tile());
        await images.load('b', longSidePx: 64);
        images.pin('b', 128).release();
        expect(rasterLedgerOf(pool)!.bytes, 4 * _unit);
        await pumpEventQueue(); // the decode notices
        events.clear();
        // full: the next tile evicts the least recently used — image a
        tiles.put((owner: owner, chunk: 2, bucket: 1), _tile());
        expect(images.contains('a', 128), isFalse);
        expect(owner.evicted, isEmpty);
        await pumpEventQueue();
        expect(events, [(assetId: 'a', bucket: 128)]);
        // then tile 0, then tile 1 …
        tiles.put((owner: owner, chunk: 3, bucket: 1), _tile());
        expect(owner.evicted.map((k) => k.chunk), [0]);
        // using b makes it the most recent: tile 1 goes before it
        images.peek('b', longSidePx: 64);
        tiles.put((owner: owner, chunk: 4, bucket: 1), _tile());
        expect(owner.evicted.map((k) => k.chunk), [0, 1]);
        expect(images.contains('b', 128), isTrue);
      },
    );

    test('an image not drawn yet (fresh) is not evicted by tiles', () async {
      final owner = _Owner();
      await images.load('a', longSidePx: 64); // arrived, no picture drew it
      for (var i = 0; i < 6; i++) {
        tiles.put((owner: owner, chunk: i, bucket: 1), _tile());
      }
      expect(images.contains('a', 128), isTrue);
      expect(tiles.length, 3);
    });
  });

  group('native rule: own budgets', () {
    test(
      'the VM pool has no shared ledger; filling the tiles keeps the images',
      () async {
        final config = const InkRenderConfig(rasterBudgetBytes: 2 * _unit);
        for (final pool in [
          InkCachePool(config),
          debugCachePoolWithLedger(config, shared: false),
        ]) {
          final images = InkImageCache(assets: store, pool: pool);
          expect(rasterLedgerOf(pool), isNull);
          expect(debugImageCacheIsShared(images), isFalse);
          expect(images.budgetBytes, 128 * 1024 * 1024);
          final tiles = rasterTileLruOf(pool);
          expect(tiles.budgetBytes, 2 * _unit);
          await images.load('a', longSidePx: 64);
          images.pin('a', 128).release();
          final owner = _Owner();
          for (var i = 0; i < 4; i++) {
            tiles.put((owner: owner, chunk: i, bucket: 1), _tile());
          }
          expect(tiles.length, 2);
          expect(owner.evicted.map((k) => k.chunk), [0, 1]);
          expect(images.contains('a', 128), isTrue);
          images.dispose();
          pool.dispose();
        }
      },
    );

    test(
      'a budget given to the cache is its own ledger even with a shared pool',
      () {
        final pool = debugCachePoolWithLedger(
          const InkRenderConfig(rasterBudgetBytes: 4 * _unit),
          shared: true,
        );
        final images = InkImageCache(
          assets: store,
          budgetBytes: 1234,
          pool: pool,
        );
        expect(debugImageCacheIsShared(images), isFalse);
        expect(images.budgetBytes, 1234);
        images.dispose();
        pool.dispose();
      },
    );
  });
}
