// m5-7/03-ink 8.2 T36 (6.12.3, the 6.11.3 rules — M-4): the formula raster
// cache with a fake rasterizer (frame 50 × 25 pt → 100 × 50 px = 20,000 B at
// bucket 2, 5,000 B at 1, 1,300 B at 0.5).
// - the bucket of the device scale (2 before the first report, at most 4);
// - pinned entries are never evicted and count in the budget; released ones are
//   evicted least recently used first; an entry that arrived and was not drawn
//   yet is not evicted by later arrivals;
// - a request that does not fit takes a lower bucket (one raster), the cap is
//   remembered (no bigger request again) and goes up only when a bigger bucket
//   fits whole — straight to the highest that fits;
// - the smallest bucket is taken even over the budget (downgraded, overflow);
// - requests in flight are reserved; a failure is not asked again within
//   InkTuning.mathRasterRetryMs; change events name the formula.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/math/math_raster_cache.dart';
import 'package:ink_engine/src/math/offscreen_host.dart';

const _frame = ui.Size(50, 25);

MathFormula _f(String latex) =>
    (latex: latex, colorArgb: 0xFF000000, fontSizePt: 18);

final class _Rasterizer {
  final List<(String, double)> calls = [];
  bool fail = false;

  Future<OffscreenRaster?> call(MathFormula f, double pixelsPerPt) async {
    calls.add((f.latex, pixelsPerPt));
    if (fail) return null;
    final w = (_frame.width * pixelsPerPt).ceil();
    final h = (_frame.height * pixelsPerPt).ceil();
    final recorder = ui.PictureRecorder();
    ui.Canvas(
      recorder,
    ).drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint());
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    return (image: image, size: _frame);
  }
}

void main() {
  late _Rasterizer rasterizer;
  late MathRasterCache cache;
  final changes = <MathRasterChange>[];
  StreamSubscription<MathRasterChange>? sub;

  MathRasterCache make(int budget) {
    final c = MathRasterCache(budgetBytes: budget, rasterizer: rasterizer.call);
    sub = c.changes.listen(changes.add);
    return c;
  }

  MathRaster? peek(String latex, {double? scale = 2, int nowUs = 0}) =>
      cache.peek(_f(latex), deviceScale: scale, framePt: _frame, nowUs: nowUs);

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    rasterizer = _Rasterizer();
    changes.clear();
  });
  tearDown(() async {
    await sub?.cancel();
    cache.dispose();
  });

  test(
    'the bucket of the device scale: 2 before the first report, at most 4',
    () {
      cache = make(1 << 20);
      expect(cache.wantedBucket(null), 2);
      expect(cache.wantedBucket(1), 1);
      expect(cache.wantedBucket(1.2), 1.5);
      expect(cache.wantedBucket(2.5), 3);
      expect(cache.wantedBucket(9), 4);
      expect(cache.buckets, [0.5, 1.0, 1.5, 2.0, 3.0, 4.0]);
    },
  );

  test('a missing raster is asked once; it arrives with a change event naming '
      'the formula; the next peek draws it', () async {
    cache = make(1 << 20);
    expect(peek('a'), isNull);
    expect(peek('a'), isNull, reason: 'asking twice gives the same answer');
    expect(rasterizer.calls, [('a', 2.0)]);
    expect(cache.stats.queued, 1);
    await settle();
    expect(changes, [(formula: _f('a'), failed: false)]);
    final r = peek('a');
    expect(r, isNotNull);
    expect((r!.image.width, r.image.height), (100, 50));
    expect(r.sizePt, _frame);
    expect(r.bucket, 2);
    expect(rasterizer.calls, hasLength(1));
    // zoomed in: the bigger bucket is asked, the one there is drawn meanwhile
    expect(identical(peek('a', scale: 3.5), r), isTrue);
    expect(rasterizer.calls.last, ('a', 4.0));
  });

  test(
    'pinned entries are never evicted and count in the budget; released ones '
    'go least recently used first; fresh arrivals are not evicted by later '
    'ones',
    () async {
      cache = make(50000);
      peek('a');
      await settle();
      final pinA = cache.holdOf(peek('a')!).acquire(); // a chunk drew a
      peek('b');
      await settle();
      final pinB = cache.holdOf(peek('b')!).acquire();
      pinB.release(); // b was drawn, its picture is gone: evictable
      expect(cache.stats.pinnedBytes, 20000);
      peek('c'); // fits: 50,000 − 20,000 pinned ≥ 20,000
      await settle();
      expect(
        cache.isCached((formula: _f('a'), bucket: 2)),
        isTrue,
        reason: 'pinned',
      );
      expect(
        cache.isCached((formula: _f('b'), bucket: 2)),
        isFalse,
        reason: 'LRU',
      );
      expect(cache.isCached((formula: _f('c'), bucket: 2)), isTrue);
      expect(cache.stats.bytes, 40000);
      // c arrived but no chunk drew it yet: a lower request does not evict it
      expect(peek('d'), isNull);
      expect(rasterizer.calls.last, (
        'd',
        1.0,
      ), reason: '50,000 − 20,000 − 20,000');
      await settle();
      expect(cache.isCached((formula: _f('c'), bucket: 2)), isTrue);
      expect(cache.isCached((formula: _f('d'), bucket: 1)), isTrue);
      pinA.release();
      expect(cache.stats.pinnedBytes, 0);
    },
  );

  test(
    'a request that does not fit takes the next lower bucket that fits — one '
    'raster — and the cap is remembered',
    () async {
      cache = make(30000);
      peek('a');
      await settle();
      final pin = cache.holdOf(peek('a')!).acquire(); // 20,000 pinned
      expect(peek('b'), isNull);
      expect(rasterizer.calls, [
        ('a', 2.0),
        ('b', 1.0),
      ], reason: '2 and 1.5 do not fit');
      expect(cache.capOf(_f('b')), 1);
      expect(cache.stats.downgraded, 1);
      await settle();
      final b = peek('b');
      expect(b!.bucket, 1);
      expect(
        rasterizer.calls,
        hasLength(2),
        reason: 'the cap: not asked bigger',
      );
      final pinB = cache.holdOf(b).acquire();
      // the space comes back: the cap goes straight up to the highest bucket that fits
      pin.release();
      expect(identical(peek('b'), b), isTrue, reason: 'drawn meanwhile');
      expect(rasterizer.calls.last, ('b', 2.0));
      expect(cache.capOf(_f('b')), isNull);
      pinB.release();
    },
  );

  test('the smallest bucket is taken even when nothing fits (downgraded, '
      'overflow bytes)', () async {
    cache = make(1000);
    expect(peek('a'), isNull);
    expect(rasterizer.calls, [('a', 0.5)]);
    await settle();
    final a = peek('a');
    expect(a!.bucket, 0.5);
    expect(cache.stats.bytes, 1300);
    expect(cache.stats.overflowBytes, 300);
    expect(cache.stats.downgraded, 1);
  });

  test('requests in flight are reserved: ten formulas wanting more than the '
      'budget are lowered at once and all of them stay', () async {
    cache = make(100000);
    for (var i = 0; i < 10; i++) {
      peek('f$i');
    }
    final buckets = [for (final c in rasterizer.calls) c.$2];
    expect(buckets.take(5), everyElement(2.0));
    expect(buckets.skip(5), everyElement(0.5));
    await settle();
    for (var i = 0; i < 10; i++) {
      expect(peek('f$i'), isNotNull, reason: 'f$i');
    }
    expect(rasterizer.calls, hasLength(10));
  });

  test('a failed raster is not asked again within mathRasterRetryMs', () async {
    cache = make(1 << 20);
    rasterizer.fail = true;
    peek('a', nowUs: 0);
    await settle();
    expect(changes, [(formula: _f('a'), failed: true)]);
    expect(cache.stats.failures, 1);
    peek('a', nowUs: InkTuning.mathRasterRetryMs * 1000 - 1);
    expect(rasterizer.calls, hasLength(1));
    rasterizer.fail = false;
    peek('a', nowUs: InkTuning.mathRasterRetryMs * 1000 + 1);
    expect(rasterizer.calls, hasLength(2));
    await settle();
    expect(peek('a', nowUs: 6000000), isNotNull);
  });

  test('dispose: no more requests, arrivals are dropped', () async {
    cache = make(1 << 20);
    peek('a');
    cache.dispose();
    await settle();
    expect(peek('b'), isNull);
    expect(rasterizer.calls, hasLength(1));
    expect(cache.stats.rasters, 0);
  });
}
