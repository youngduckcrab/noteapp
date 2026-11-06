// m5-7/03-ink 8.2 T35 (6.11.1–6.11.4, 6.24): InkImageCache rules on the VM with
// real decodes (instantiateImageCodec) and a controllable store:
// - the bucket is the smallest InkTuning.imageBucketsPx ≥ the long side asked
//   for, never above the source (the decode is not larger than the source);
//   a bigger decode that is there is used for a smaller request;
// - pinned entries are never evicted and count in the budget; released ones go
//   least recently used first and are disposed;
// - a request that does not fit takes a lower bucket — one decode — and keeps
//   that cap; the cap goes up only when a bigger bucket fits whole;
// - the smallest bucket is taken even over the budget (downgraded, overflow);
// - at most two decodes run at once, in request order;
// - no bytes → null until bytesArrived → changes(asset, 0) → decoded on the
//   next ask; a decode failure / no store is not tried again;
// - changes name only the asset and bucket that changed; load waits.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/src/image/deferred_asset_store.dart';
import 'package:ink_engine/src/image/image_cache.dart';
import 'package:ink_engine/testing.dart';

import '../../support/memory_asset_store.dart';

/// Lets queued decodes start and finish (real engine decodes — no fake time).
Future<void> _settle(InkImageCache cache) async {
  for (var i = 0; i < 2000 && cache.stats.queued > 0; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(cache.stats.queued, 0, reason: 'the decodes finished');
  await pumpEventQueue();
}

/// A [w] × [h] image made at once (no engine decode).
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryAssetStore store;
  setUp(() => store = MemoryAssetStore());
  tearDown(() => store.close());

  Future<void> addPng(String id, int w, int h, {int argb = 0xFF3366CC}) async =>
      store.bytes[id] = await testPngBytes(width: w, height: h, argb: argb);

  group('buckets', () {
    test(
      'the smallest bucket ≥ the long side, never above the source',
      () async {
        await addPng('a', 400, 300);
        final cache = InkImageCache(assets: store);
        addTearDown(cache.dispose);
        expect(
          cache.peek('a', longSidePx: 200, pixelWidth: 400, pixelHeight: 300),
          isNull,
          reason: 'queued',
        );
        await _settle(cache);
        final small = cache.peek(
          'a',
          longSidePx: 200,
          pixelWidth: 400,
          pixelHeight: 300,
        )!;
        expect([small.width, small.height], [256, 192]);
        // 300 → bucket 512, but the source is 400 wide: decoded at the source size
        cache.peek('a', longSidePx: 300, pixelWidth: 400, pixelHeight: 300);
        await _settle(cache);
        final full = cache.peek(
          'a',
          longSidePx: 300,
          pixelWidth: 400,
          pixelHeight: 300,
        )!;
        expect([full.width, full.height], [400, 300]);
        // above the source: the same (biggest useful) bucket, no other decode
        expect(
          identical(
            cache.peek(
              'a',
              longSidePx: 5000,
              pixelWidth: 400,
              pixelHeight: 300,
            ),
            full,
          ),
          isTrue,
        );
        // a smaller request uses the smallest bigger decode that is there
        expect(
          identical(
            cache.peek('a', longSidePx: 100, pixelWidth: 400, pixelHeight: 300),
            small,
          ),
          isTrue,
        );
        await _settle(cache);
        expect(debugImageDecodes(cache), [
          (assetId: 'a', width: 256, height: 192),
          (assetId: 'a', width: 400, height: 300),
        ]);
        expect(store.readsOf('a'), 2);
      },
    );

    test(
      'an image background: the size from the header — no full decode',
      () async {
        await addPng('bg', 1600, 1200);
        final cache = InkImageCache(assets: store);
        addTearDown(cache.dispose);
        final image = await cache.load('bg', longSidePx: 400);
        expect([image!.width, image.height], [512, 384]);
        expect(debugImageDecodes(cache), [
          (assetId: 'bg', width: 512, height: 384),
        ]);
      },
    );
  });

  group('the ledger (6.11.3)', () {
    test(
      'pinned entries stay and count; released ones go LRU and are disposed',
      () async {
        // three 128 px squares fit (64 KiB each), a fourth does not
        final cache = InkImageCache(
          assets: store,
          budgetBytes: 3 * 128 * 128 * 4,
        );
        addTearDown(cache.dispose);
        for (final id in ['a', 'b', 'c', 'd']) {
          await addPng(id, 128, 128);
        }
        final images = <String, ui.Image>{};
        for (final id in ['a', 'b', 'c']) {
          images[id] = (await cache.load(id, longSidePx: 128))!;
        }
        final pinA = cache.pin('a', 128);
        final pinB = cache.pin('b', 128);
        cache.pin('c', 128).release(); // drawn once, not pinned now
        expect(cache.stats.pinnedBytes, 2 * 128 * 128 * 4);
        // d: c is the only one that may go
        final d = (await cache.load('d', longSidePx: 128))!;
        expect(cache.stats.images, 3);
        expect(
          images['c']!.debugDisposed,
          isTrue,
          reason: 'evicted → disposed',
        );
        expect(images['a']!.debugDisposed, isFalse);
        expect(cache.contains('c', 128), isFalse);
        // release a → it may go; b stays pinned
        pinA.release();
        cache.pin('d', 128).release();
        await addPng('e', 128, 128);
        await cache.load('e', longSidePx: 128);
        expect(cache.contains('b', 128), isTrue, reason: 'pinned');
        expect(
          images['a']!.debugDisposed,
          isTrue,
          reason: 'least recently used',
        );
        expect(d.debugDisposed, isFalse);
        pinB.release();
      },
    );

    test('a request that does not fit takes a lower bucket (one decode) and '
        'keeps the cap until a bigger one fits whole', () async {
      // budget: one 512² decode (1 MiB) + room for a 256²
      const budget = 512 * 512 * 4 + 256 * 256 * 4;
      final cache = InkImageCache(assets: store, budgetBytes: budget);
      addTearDown(cache.dispose);
      await addPng('big', 1024, 1024);
      await addPng('other', 1024, 1024);
      cache.peek('big', longSidePx: 500, pixelWidth: 1024, pixelHeight: 1024);
      await _settle(cache);
      final pin = cache.pin('big', 512);
      // 'other' wants 512² (1 MiB) but only 256² fits next to the pinned one
      cache.peek('other', longSidePx: 500, pixelWidth: 1024, pixelHeight: 1024);
      await _settle(cache);
      expect(cache.stats.downgraded, 1);
      expect(debugImageCapOf(cache, 'other'), 256);
      expect(
        debugImageDecodes(cache).where((d) => d.assetId == 'other').toList(),
        [(assetId: 'other', width: 256, height: 256)],
        reason: 'one decode at the lowered bucket',
      );
      final reads = store.readsOf('other');
      final low = cache.peek(
        'other',
        longSidePx: 500,
        pixelWidth: 1024,
        pixelHeight: 1024,
      );
      expect(low!.width, 256, reason: 'the cap holds: no bigger request');
      await _settle(cache);
      expect(store.readsOf('other'), reads);
      // the pin goes: 512² fits whole again → the cap goes up at the next ask
      pin.release();
      cache.pin('other', 256).release();
      cache.peek('other', longSidePx: 500, pixelWidth: 1024, pixelHeight: 1024);
      await _settle(cache);
      expect(debugImageCapOf(cache, 'other'), isNull);
      expect(
        cache
            .peek(
              'other',
              longSidePx: 500,
              pixelWidth: 1024,
              pixelHeight: 1024,
            )!
            .width,
        512,
      );
    });

    test('the smallest bucket is taken even over the budget', () async {
      final cache = InkImageCache(assets: store, budgetBytes: 1);
      addTearDown(cache.dispose);
      await addPng('a', 800, 600);
      cache.peek('a', longSidePx: 800, pixelWidth: 800, pixelHeight: 600);
      await _settle(cache);
      final image = cache.peek(
        'a',
        longSidePx: 800,
        pixelWidth: 800,
        pixelHeight: 600,
      )!;
      expect([image.width, image.height], [128, 96]);
      expect(cache.stats.downgraded, 1);
      expect(debugImageOverflowBytes(cache), 128 * 96 * 4 - 1);
    });
  });

  test('at most two decodes at once, in request order', () async {
    final cache = InkImageCache(assets: store);
    addTearDown(cache.dispose);
    final started = <int>[];
    final gates = <Completer<void>>[];
    debugSetImageDecoder(cache, (
      bytes, {
      int? targetWidth,
      int? targetHeight,
    }) async {
      started.add(targetWidth!);
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
      return _blank(targetWidth, targetHeight ?? targetWidth);
    });
    // five assets of different sizes (the decoder sees the order by width)
    for (var i = 0; i < 5; i++) {
      await addPng('a$i', 10 + i, 10 + i);
      cache.peek(
        'a$i',
        longSidePx: 64,
        pixelWidth: 10 + i,
        pixelHeight: 10 + i,
      );
    }
    await pumpEventQueue();
    expect(started, [10, 11]);
    gates[0].complete();
    await pumpEventQueue();
    expect(started, [10, 11, 12]);
    gates[1].complete();
    gates[2].complete();
    await pumpEventQueue();
    expect(started, [10, 11, 12, 13, 14]);
    gates[3].complete();
    gates[4].complete();
    await _settle(cache);
    expect(debugImageMaxConcurrentDecodes(cache), 2);
    expect(cache.stats.images, 5);
  });

  group('no bytes / failures (6.11.3, 6.24)', () {
    test(
      'no bytes → null until bytesArrived → changes(asset, 0) → decoded',
      () async {
        final cache = InkImageCache(assets: store);
        addTearDown(cache.dispose);
        final events = <({String assetId, int bucket})>[];
        final sub = cache.changes.listen(events.add);
        addTearDown(sub.cancel);
        expect(cache.peek('m', longSidePx: 64), isNull);
        await _settle(cache);
        expect(cache.statusOf('m'), InkImageStatus.missing);
        expect(await cache.load('m', longSidePx: 64), isNull);
        // asking again while missing does not read again
        final reads = store.readsOf('m');
        expect(cache.peek('m', longSidePx: 64), isNull);
        await _settle(cache);
        expect(store.readsOf('m'), reads);
        events.clear();
        store.arrive('m', await testPngBytes(width: 40, height: 20));
        await pumpEventQueue();
        expect(events, [(assetId: 'm', bucket: 0)]);
        expect(cache.statusOf('m'), InkImageStatus.ok);
        final image = await cache.load('m', longSidePx: 64);
        expect([image!.width, image.height], [40, 20]);
      },
    );

    test('a decode failure is not tried again', () async {
      final cache = InkImageCache(assets: store);
      addTearDown(cache.dispose);
      store.bytes['bad'] = Uint8List.fromList(List.filled(64, 7));
      expect(await cache.load('bad', longSidePx: 64), isNull);
      expect(cache.statusOf('bad'), InkImageStatus.failed);
      expect(cache.stats.failures, 1);
      expect(cache.peek('bad', longSidePx: 64), isNull);
      expect(cache.peek('bad', longSidePx: 2000), isNull);
      await _settle(cache);
      expect(store.readsOf('bad'), 1);
      expect(cache.stats.failures, 1);
    });

    test(
      'no store (a container without a NoteStore) → not tried again',
      () async {
        final deferred = DeferredAssetStore(
          () => throw UnimplementedError('no NoteStore'),
        );
        final cache = InkImageCache(assets: deferred);
        addTearDown(cache.dispose);
        expect(await cache.load('x', longSidePx: 64), isNull);
        expect(cache.statusOf('x'), InkImageStatus.storeUnavailable);
        expect(cache.peek('x', longSidePx: 64), isNull);
        expect(cache.stats.queued, 0);
      },
    );
  });

  test('changes name only the asset and bucket that changed', () async {
    final cache = InkImageCache(assets: store);
    addTearDown(cache.dispose);
    await addPng('a', 300, 300);
    await addPng('b', 300, 300);
    final events = <({String assetId, int bucket})>[];
    final sub = cache.changes.listen(events.add);
    addTearDown(sub.cancel);
    cache.peek('a', longSidePx: 200, pixelWidth: 300, pixelHeight: 300);
    await _settle(cache);
    expect(events, [(assetId: 'a', bucket: 256)]);
    cache.peek('b', longSidePx: 120, pixelWidth: 300, pixelHeight: 300);
    await _settle(cache);
    expect(events, [(assetId: 'a', bucket: 256), (assetId: 'b', bucket: 128)]);
    // the events arrive asynchronously (never inside the caller)
    events.clear();
    cache.peek('a', longSidePx: 300, pixelWidth: 300, pixelHeight: 300);
    expect(events, isEmpty);
    await _settle(cache);
    expect(events, [(assetId: 'a', bucket: 512)]);
  });

  test('load waits for its bucket; dispose ends the waits with null', () async {
    final cache = InkImageCache(assets: store);
    await addPng('a', 64, 64);
    final gate = Completer<void>();
    debugSetImageDecoder(cache, (
      bytes, {
      int? targetWidth,
      int? targetHeight,
    }) async {
      await gate.future;
      throw StateError('not reached');
    });
    final waiting = cache.load('a', longSidePx: 64);
    await pumpEventQueue();
    cache.dispose();
    expect(await waiting, isNull);
    expect(cache.peek('a', longSidePx: 64), isNull);
    gate.complete();
  });
}
