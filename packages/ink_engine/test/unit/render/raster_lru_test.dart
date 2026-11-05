// T19 (03-ink 6.13 L3, -5, -6, -7): the app-wide raster tile LRU — over the
// budget the least recently USED tiles go first (the owner is told), a tile
// larger than the budget is not kept — and the tiles of one page: other
// buckets dropped on store, the stretched fallback order, stale
// generations, the evicted chunks left to vectors until the viewport changes.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/cache_pool.dart' show rasterTileLruOf;
import 'package:ink_engine/src/render/raster_tiles.dart';

/// A [side] × [side] tile (side² × 4 bytes).
RasterTile _tile(int side, {double bucket = 1, int generation = 0}) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 4, 4),
    ui.Paint()..color = const ui.Color(0xFF000000),
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(side, side);
  picture.dispose();
  return RasterTile(
    image: image,
    pageRect: ui.Rect.fromLTWH(0, 0, side / bucket, side / bucket),
    bucket: bucket,
    generation: generation,
    appendedCount: 0,
  );
}

final class _Owner implements RasterTileOwner {
  final List<RasterTileKey> evicted = [];
  @override
  void tileEvicted(RasterTileKey key) => evicted.add(key);
}

RasterTileKey _k(Object owner, int chunk, [double bucket = 1]) =>
    (owner: owner, chunk: chunk, bucket: bucket);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RasterTileLru', () {
    test('within the budget every tile stays; bytes = w × h × 4', () {
      final lru = RasterTileLru(budgetBytes: 4 * 100 * 100 * 4);
      addTearDown(lru.dispose);
      final owner = _Owner();
      for (var i = 0; i < 4; i++) {
        lru.put(_k(owner, i), _tile(100));
      }
      expect(lru.length, 4);
      expect(lru.bytes, 4 * 40000);
      expect(owner.evicted, isEmpty);
    });

    test('over the budget: the oldest go first, the owner is told', () {
      final lru = RasterTileLru(budgetBytes: 3 * 40000);
      addTearDown(lru.dispose);
      final owner = _Owner();
      final tiles = [for (var i = 0; i < 5; i++) _tile(100)];
      for (var i = 0; i < 5; i++) {
        lru.put(_k(owner, i), tiles[i]);
      }
      expect(lru.keys, [_k(owner, 2), _k(owner, 3), _k(owner, 4)]);
      expect(owner.evicted, [_k(owner, 0), _k(owner, 1)]);
      expect(lru.bytes, 3 * 40000);
      expect(tiles[0].image.debugDisposed, isTrue);
      expect(tiles[1].image.debugDisposed, isTrue);
      expect(tiles[2].image.debugDisposed, isFalse);
    });

    test('"oldest" = least recently used, not least recently made', () {
      final lru = RasterTileLru(budgetBytes: 3 * 40000);
      addTearDown(lru.dispose);
      final owner = _Owner();
      for (var i = 0; i < 3; i++) {
        lru.put(_k(owner, i), _tile(100));
      }
      expect(lru.use(_k(owner, 0)), isNotNull); // drawn again
      expect(lru.peek(_k(owner, 1)), isNotNull); // peek does not count
      lru.put(_k(owner, 3), _tile(100));
      expect(owner.evicted, [_k(owner, 1)]);
      expect(lru.keys, [_k(owner, 2), _k(owner, 0), _k(owner, 3)]);
    });

    test('mixed sizes: as many old tiles go as the new one needs', () {
      final lru = RasterTileLru(budgetBytes: 100000);
      addTearDown(lru.dispose);
      final owner = _Owner();
      lru
        ..put(_k(owner, 0), _tile(50)) // 10 000
        ..put(_k(owner, 1), _tile(50)) // 10 000
        ..put(_k(owner, 2), _tile(100)) // 40 000
        ..put(_k(owner, 3), _tile(100)); // 40 000 → 100 000, fits
      expect(owner.evicted, isEmpty);
      lru.put(_k(owner, 4), _tile(70)); // 19 600 → two small ones go
      expect(owner.evicted, [_k(owner, 0), _k(owner, 1)]);
      expect(lru.bytes, 99600);
    });

    test('a tile larger than the whole budget is not kept', () {
      final lru = RasterTileLru(budgetBytes: 1000);
      addTearDown(lru.dispose);
      final owner = _Owner();
      final big = _tile(100);
      lru.put(_k(owner, 0), big);
      expect(lru.length, 0);
      expect(lru.bytes, 0);
      expect(big.image.debugDisposed, isTrue);
      expect(owner.evicted, [_k(owner, 0)]);
    });

    test('the same key replaces (the old image is freed, not evicted)', () {
      final lru = RasterTileLru(budgetBytes: 1024 * 1024);
      addTearDown(lru.dispose);
      final owner = _Owner();
      final a = _tile(100);
      final b = _tile(50);
      lru
        ..put(_k(owner, 0), a)
        ..put(_k(owner, 0), b);
      expect(lru.length, 1);
      expect(lru.bytes, 10000);
      expect(a.image.debugDisposed, isTrue);
      expect(owner.evicted, isEmpty);
    });

    test('remove / removeWhere free without telling; per-owner counts', () {
      final lru = RasterTileLru(budgetBytes: 16 * 1024 * 1024);
      addTearDown(lru.dispose);
      final p = _Owner();
      final q = _Owner();
      for (var i = 0; i < 3; i++) {
        lru
          ..put(_k(p, i), _tile(10))
          ..put(_k(q, i), _tile(20));
      }
      expect((lru.countOf(p), lru.bytesOf(p)), (3, 1200));
      expect((lru.countOf(q), lru.bytesOf(q)), (3, 4800));
      expect(lru.remove(_k(p, 0)), isTrue);
      expect(lru.remove(_k(p, 0)), isFalse);
      lru.removeWhere((k) => identical(k.owner, q) && k.chunk > 0);
      expect((lru.countOf(p), lru.countOf(q)), (2, 1));
      expect(lru.bytes, 2 * 400 + 1600);
      expect(p.evicted, isEmpty);
      expect(q.evicted, isEmpty);
    });

    test('trimTo evicts least recently used first and tells the owners', () {
      final lru = RasterTileLru(budgetBytes: 16 * 1024 * 1024);
      addTearDown(lru.dispose);
      final p = _Owner();
      for (var i = 0; i < 4; i++) {
        lru.put(_k(p, i), _tile(100));
      }
      lru
        ..use(_k(p, 0))
        ..trimTo(2 * 40000);
      expect(lru.keys, [_k(p, 3), _k(p, 0)]);
      expect(p.evicted, [_k(p, 1), _k(p, 2)]);
    });

    test('dispose frees everything; later puts are freed at once', () {
      final lru = RasterTileLru(budgetBytes: 16 * 1024 * 1024);
      final owner = _Owner();
      final a = _tile(10);
      lru
        ..put(_k(owner, 0), a)
        ..dispose();
      expect(a.image.debugDisposed, isTrue);
      expect((lru.length, lru.bytes), (0, 0));
      final b = _tile(10);
      lru.put(_k(owner, 1), b);
      expect(b.image.debugDisposed, isTrue);
      expect(lru.length, 0);
      expect(owner.evicted, [_k(owner, 1)], reason: 'not made again');
    });
  });

  group('InkCachePool raster stats', () {
    test('stats count the tiles of every page; trimTo(rasterBytes:)', () {
      final pool = InkCachePool(
        const InkRenderConfig(rasterBudgetBytes: 5 * 40000),
      );
      addTearDown(pool.dispose);
      final lru = rasterTileLruOf(pool);
      expect(lru.budgetBytes, 5 * 40000);
      final p = PageRasterTiles(lru, const [1, 2]);
      final q = PageRasterTiles(lru, const [1, 2]);
      for (var i = 0; i < 3; i++) {
        p.store(i, _tile(100));
      }
      q.store(0, _tile(100));
      expect(pool.stats.rasterTiles, 4);
      expect(pool.stats.rasterBytes, 4 * 40000);
      expect(pool.stats.totalBytes, pool.stats.outlineBytes + 4 * 40000);
      expect((p.count, p.bytes, q.count), (3, 3 * 40000, 1));
      pool.trimTo(rasterBytes: 40000);
      expect(pool.stats.rasterTiles, 1);
      expect(q.count, 1, reason: 'the most recently stored');
      expect([for (var i = 0; i < 3; i++) p.wasEvicted(i)], everyElement(true));
      pool.dispose();
      expect(pool.stats.rasterTiles, 0);
    });
  });

  group('PageRasterTiles', () {
    late RasterTileLru lru;
    late PageRasterTiles page;

    setUp(() {
      lru = RasterTileLru(budgetBytes: 64 * 1024 * 1024);
      page = PageRasterTiles(lru, const [0.5, 1, 1.5, 2, 3, 4]);
    });
    tearDown(() => lru.dispose());

    test('store keeps one bucket per chunk', () {
      page.store(0, _tile(10, bucket: 1));
      final b2 = _tile(20, bucket: 2);
      page.store(0, b2);
      expect(page.has(0, 1), isFalse);
      expect(page.has(0, 2), isTrue);
      expect(page.count, 1);
      expect(page.tileFor(0, 2, 0), same(b2));
    });

    test('fallback: the bucket, else the nearest finer, else the nearest '
        'coarser one (stretched, 6.13-5)', () {
      final t3 = _tile(30, bucket: 3);
      page.store(1, t3);
      expect(page.tileFor(1, 3, 0), same(t3));
      expect(page.tileFor(1, 1, 0), same(t3), reason: 'finer');
      expect(page.tileFor(1, 4, 0), same(t3), reason: 'coarser');
      expect(page.tileFor(0, 1, 0), isNull, reason: 'no tile → vector');
      // two at once (not via store): the finer one nearest above wins
      final t2 = _tile(20, bucket: 2);
      final t4 = _tile(40, bucket: 4);
      lru
        ..put((owner: page, chunk: 5, bucket: 2.0), t2)
        ..put((owner: page, chunk: 5, bucket: 4.0), t4);
      expect(page.tileFor(5, 1.5, 0), same(t2));
      expect(page.tileFor(5, 3, 0), same(t4));
      expect(page.tileFor(5, 4, 0), same(t4));
    });

    test('a tile of another generation is dropped (6.13-6)', () {
      final t = _tile(10, generation: 3);
      page.store(0, t);
      expect(page.tileFor(0, 1, 3), same(t));
      expect(page.tileFor(0, 1, 4), isNull);
      expect(page.count, 0);
      expect(t.image.debugDisposed, isTrue);
    });

    test('dropChunk / dropWhere / dropAll free only this page', () {
      final other = PageRasterTiles(lru, const [1]);
      for (var i = 0; i < 4; i++) {
        page.store(i, _tile(10));
        other.store(i, _tile(10));
      }
      page.dropChunk(0);
      expect(page.count, 3);
      page.dropWhere((chunk) => chunk.isOdd);
      expect(
        [for (var i = 0; i < 4; i++) page.has(i, 1)],
        [false, false, true, false],
      );
      page.dropAll();
      expect(page.count, 0);
      expect(other.count, 4);
    });

    test('a chunk evicted for the budget is left to vectors until the '
        'viewport changes', () {
      final small = RasterTileLru(budgetBytes: 2 * 400);
      addTearDown(small.dispose);
      final p = PageRasterTiles(small, const [1]);
      p
        ..store(0, _tile(10))
        ..store(1, _tile(10))
        ..store(2, _tile(10));
      expect(p.wasEvicted(0), isTrue);
      expect(p.wasEvicted(1) || p.wasEvicted(2), isFalse);
      p.store(0, _tile(10)); // made again anyway: no longer "evicted"
      expect(p.wasEvicted(0), isFalse);
      expect(p.wasEvicted(1), isTrue);
      p.clearEvicted();
      expect(p.wasEvicted(1), isFalse);
    });
  });
}
