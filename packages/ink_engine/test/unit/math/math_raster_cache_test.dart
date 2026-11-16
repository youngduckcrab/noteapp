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
import 'package:ink_engine/src/text/text_layout.dart' show rasterScaleFor;
import 'package:ink_engine/src/tuning.dart';

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

  group('(math resize fix) a resized formula', () {
    MathFormula sized(double pt) =>
        (latex: 'x^2', colorArgb: 0xFF000000, fontSizePt: pt);

    /// The laid-out size at [pt]: 50 × 25 pt at 18 pt, linear in the font size.
    ui.Size layoutAt(double pt) => _frame * (pt / 18);

    /// The frame fits the layout (contain scale 1) unless [frameScale] says so.
    MathRaster? peekAt(
      double pt, {
      double scale = 2,
      bool live = false,
      double frameScale = 1,
      int nowUs = 0,
    }) => cache.peek(
      sized(pt),
      deviceScale: scale,
      framePt: layoutAt(pt) * frameScale,
      nowUs: nowUs,
      live: live,
    );

    /// Rasters at the formula's own laid-out size (≈ 20,000 B × (pt / 18)² at bucket 2).
    Future<OffscreenRaster?> sizedRaster(MathFormula f, double k) async {
      final size = layoutAt(f.fontSizePt);
      final w = rasterScaleFor(size.width, size.height, k);
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
          .drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint());
      final picture = recorder.endRecording();
      final image = picture.toImageSync(
        (size.width * w).ceil(),
        (size.height * w).ceil(),
      );
      picture.dispose();
      return (image: image, size: size);
    }

    final asked = <(double, double)>[];
    MathRasterCache makeSized(int budget, {MathRasterizer? rasterizer}) {
      asked.clear();
      final c = MathRasterCache(
        budgetBytes: budget,
        rasterizer:
            rasterizer ??
            (f, k) {
              asked.add((f.fontSizePt, k));
              return sizedRaster(f, k);
            },
      );
      sub = c.changes.listen(changes.add);
      return c;
    }

    test('draws the raster of its old font size until its own arrives — '
        'never the empty placeholder', () async {
      cache = makeSized(1 << 20);
      peekAt(18);
      await settle();
      final old = peekAt(18)!;
      final bigger = peekAt(36);
      expect(identical(bigger, old), isTrue, reason: 'the 18 pt raster');
      expect(asked, hasLength(2), reason: '36 pt is asked');
      await settle();
      final own = peekAt(36)!;
      expect(own.key.formula.fontSizePt, 36);
    });

    test('a resize drag rasterizes one size at a time and the last size '
        'asked next — not every intermediate one', () async {
      cache = makeSized(1 << 20);
      peekAt(18);
      await settle();
      // the drag: a new font size on every move, all while 20 is in flight
      for (final pt in [20.0, 22.0, 24.0, 26.0, 28.0, 30.0]) {
        expect(
          peekAt(pt, live: true),
          isNotNull,
          reason: 'the 18 pt raster meanwhile',
        );
      }
      List<double> sizes() => [for (final a in asked) a.$1];
      expect(sizes(), [18, 20], reason: 'one request in flight per formula');
      expect(cache.stats.queued, 1);
      await settle();
      expect(sizes(), [18, 20, 30], reason: 'the latest size is asked next');
      await settle();
      expect(peekAt(30)!.key.formula.fontSizePt, 30);
      // the sizes nobody asked again were told to ask again, not rasterized
      final told = {for (final c in changes) c.formula.fontSizePt};
      expect(told, containsAll(<double>[22, 24, 26, 28]));
      expect(sizes(), [18, 20, 30]);
      expect(cache.stats.downgraded, 0, reason: 'no queue of reservations');
    });

    test('the sizes a drag went past (drawn by no chunk) stop holding the '
        'budget, so the final size keeps its bucket', () async {
      // bucket 2: 20 pt ≈ 24.7 kB, 22 ≈ 29.9, 24 ≈ 35.6, 26 ≈ 41.8, 30 ≈ 55.6
      cache = makeSized(150000);
      for (final pt in [20.0, 22.0, 24.0, 26.0]) {
        peekAt(pt, live: true); // only the live layer draws them
        await settle();
      }
      peekAt(30);
      await settle();
      final last = peekAt(30)!;
      expect(last.key.formula.fontSizePt, 30);
      expect(last.bucket, 2, reason: 'not lowered by the fresh drag sizes');
      expect(cache.stats.downgraded, 0);
      expect(cache.stats.bytes, lessThanOrEqualTo(150000));
    });

    test('a size a chunk asked (another object with the same formula) keeps '
        'holding the budget when a sibling arrives', () async {
      for (final live in [false, true]) {
        cache.dispose();
        cache = makeSized(90000);
        peekAt(18, live: live); // 20 kB
        await settle();
        peekAt(22); // 29.9 kB: 18 pt is stale now only if live
        await settle();
        const other = (latex: 'y', colorArgb: 0xFF000000, fontSizePt: 30.0);
        cache.peek(other, deviceScale: 2, framePt: layoutAt(30), nowUs: 0);
        await settle();
        expect(
          cache.capOf(other),
          live ? isNull : isNotNull,
          reason: live
              ? '18 pt only drawn live: evictable, 30 pt fits whole'
              : '18 pt asked by a chunk: still fresh, 30 pt is lowered',
        );
        expect(cache.isCached((formula: sized(18), bucket: 2)), !live);
      }
    });

    test('a size that waited is fit-checked when it is asked, not while the '
        'request ahead still holds its reservation', () async {
      cache = makeSized(90000);
      peekAt(18, live: true); // 20 kB
      await settle();
      peekAt(20, live: true); // in flight: 24.7 kB reserved
      peekAt(30); // 55.6 kB: 90 − 20 − 24.7 < 55.6 if checked now
      expect(
        cache.capOf(sized(30)),
        isNull,
        reason: 'not lowered while waiting',
      );
      await settle();
      expect(cache.capOf(sized(30)), isNull);
      expect(asked.last, (30.0, 2.0), reason: 'asked at the full bucket');
      await settle();
      expect(peekAt(30)!.bucket, 2);
      expect(cache.stats.downgraded, 0);
    });

    test('a waiting ask of the same font size at another bucket is told to '
        'ask again', () async {
      cache = makeSized(1 << 20);
      peekAt(18);
      await settle();
      peekAt(20); // in flight
      peekAt(30, scale: 3); // waits (bucket 3) …
      peekAt(30); // … and the latest (bucket 2) is asked next
      await settle();
      await settle();
      expect(asked.map((a) => a.$1), [18, 20, 30]);
      final events = changes.where((c) => c.formula == sized(30)).length;
      expect(events, 2, reason: 'told (bucket 3 waited) + bucket 2 arrived');
    });

    test('a request that never settles stops holding the slot after '
        'mathRasterTimeoutMs; its late raster is still kept', () async {
      final hung = Completer<OffscreenRaster?>();
      cache = makeSized(
        1 << 20,
        rasterizer: (f, k) {
          asked.add((f.fontSizePt, k));
          return f.fontSizePt == 18 ? hung.future : sizedRaster(f, k);
        },
      );
      peekAt(18);
      peekAt(20, nowUs: 1000000); // waits behind the hung 18 pt
      await settle();
      expect(asked.map((a) => a.$1), [18]);
      peekAt(20, nowUs: InkTuning.mathRasterTimeoutMs * 1000 + 1);
      expect(asked.map((a) => a.$1), [18, 20], reason: 'the slot is free');
      expect(cache.stats.failures, 1);
      await settle();
      expect(changes.any((c) => c.failed && c.formula == sized(18)), isTrue);
      expect(peekAt(20, nowUs: 1)!.key.formula.fontSizePt, 20);
      hung.complete(await sizedRaster(sized(18), 2));
      await settle();
      expect(cache.isCached((formula: sized(18), bucket: 2)), isTrue);
      expect(cache.stats.queued, 0);
    });

    test('a frame bigger than its laid-out formula (stretched before the fix) '
        'asks the bucket of device scale × contain scale', () async {
      cache = makeSized(64 << 20);
      for (final (frameScale, want) in [(1.1, 2.0), (2.0, 4.0), (3.0, 8.0)]) {
        final pt = 18 + frameScale; // a formula per case
        peekAt(pt, frameScale: frameScale);
        await settle(); // the laid-out size is known from this raster …
        peekAt(pt, frameScale: frameScale); // … so the sharper one is asked
        await settle();
        final r = peekAt(pt, frameScale: frameScale)!;
        expect(r.bucket, want, reason: 'frame × $frameScale');
        expect(
          r.pixelsPerPt / frameScale,
          greaterThanOrEqualTo(frameScale > 1.25 ? 2 : 2 / frameScale),
          reason: 'px per frame pt ≥ the device scale',
        );
      }
    });

    test('the sharpest raster of the family is drawn meanwhile', () async {
      cache = makeSized(1 << 20);
      peekAt(18);
      await settle();
      peekAt(36);
      await settle();
      // 30 pt at bucket 2: 18 pt gives 1.2 px per pt, 36 pt gives 2.4
      expect(peekAt(30)!.key.formula.fontSizePt, 36);
      // another formula or another color is never borrowed
      expect(
        cache.peek(
          (latex: 'x^2', colorArgb: 0xFFFF0000, fontSizePt: 30),
          deviceScale: 2,
          framePt: layoutAt(30),
          nowUs: 0,
        ),
        isNull,
      );
    });
  });
}
