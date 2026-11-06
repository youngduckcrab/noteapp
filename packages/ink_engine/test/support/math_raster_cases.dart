// m5-7/03-ink 8.2 T36 (6.12.2): the raster host cases shared by the VM tests
// (unit/math/offscreen_queue_test.dart, widget/math_render_test.dart) and the
// Chrome test (web/offscreen_math_web_test.dart) — the same bodies, so the
// web run proves the same rules on CanvasKit without the KaTeX fonts.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/math/offscreen_host.dart';

import 'delayed_svg_loader.dart';

/// RGBA pixels of [image] (real async — a plain test or tester.runAsync).
Future<({int width, int height, ByteData bytes})> imagePixels(
  ui.Image image,
) async => (
  width: image.width,
  height: image.height,
  bytes: (await image.toByteData())!,
);

/// Pixels in [region] (image px) with alpha above [minAlpha] — ink on a transparent raster.
int inkIn(
  ({int width, int height, ByteData bytes}) p, {
  ui.Rect? region,
  int minAlpha = 64,
}) {
  final r =
      region ?? ui.Rect.fromLTWH(0, 0, p.width.toDouble(), p.height.toDouble());
  final x0 = r.left.floor().clamp(0, p.width),
      x1 = r.right.ceil().clamp(0, p.width);
  final y0 = r.top.floor().clamp(0, p.height),
      y1 = r.bottom.ceil().clamp(0, p.height);
  var n = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      if (p.bytes.getUint8((y * p.width + x) * 4 + 3) > minAlpha) n++;
    }
  }
  return n;
}

/// Red pixels (the delayed loader's square) of [p].
int redPixels(({int width, int height, ByteData bytes}) p) {
  var n = 0;
  for (var i = 0; i < p.width * p.height; i++) {
    final o = i * 4;
    final r = p.bytes.getUint8(o), g = p.bytes.getUint8(o + 1);
    final b = p.bytes.getUint8(o + 2), a = p.bytes.getUint8(o + 3);
    if (a > 128 && r > 160 && g < 96 && b < 96) n++;
  }
  return n;
}

Future<ui.Image?> _raster(String latex, {double pixelsPerPt = 2}) =>
    InkMathRenderer.rasterize(
      latex,
      colorArgb: 0xFF000000,
      fontSizePt: 18,
      pixelsPerPt: pixelsPerPt,
    );

/// The queue and the wait for glyph pictures through the delayed loader seam (6.12.2).
void offscreenQueueCases() {
  tearDown(() {
    OffscreenMathHost.debugExtraSvgLoader = null;
    OffscreenMathHost.debugNowUs = _realNowUs;
  });

  test('a glyph picture that arrives 30 ms late is waited for: the raster has '
      'its pixels', () async {
    final loader = DelayedSvgLoader(const Duration(milliseconds: 30));
    OffscreenMathHost.debugExtraSvgLoader = loader;
    final image = await _raster(r'x+y');
    expect(image, isNotNull);
    final p = await imagePixels(image!);
    image.dispose();
    expect(loader.loads, 1);
    expect(redPixels(p), greaterThan(16), reason: 'the late picture is in it');
  });

  test(
    'a glyph picture later than the settle cap (2,000 ms > 1,000 ms) → null, '
    'counted as a failure (mathRasterFailed)',
    () {
      fakeAsync((async) {
        OffscreenMathHost.debugNowUs = () => async.elapsed.inMicroseconds;
        OffscreenMathHost.debugExtraSvgLoader = DelayedSvgLoader(
          const Duration(milliseconds: 2000),
        );
        final failures = OffscreenMathHost.debugSettleFailures;
        var done = false;
        ui.Image? image;
        unawaited(
          _raster('x').then((i) {
            image = i;
            done = true;
          }),
        );
        async.elapse(const Duration(milliseconds: 900));
        expect(done, isFalse, reason: 'still waiting inside the cap');
        async.elapse(const Duration(milliseconds: 200));
        expect(done, isTrue);
        expect(image, isNull);
        expect(OffscreenMathHost.debugSettleFailures, failures + 1);
        async.elapse(
          const Duration(seconds: 2),
        ); // the late picture lands, unused
        expect(OffscreenMathHost.rasterHost.pendingCount, 0);
      });
    },
  );

  test('a second request while the first waits runs after it (FIFO, one at a '
      'time); layout answers at once meanwhile (two hosts)', () {
    fakeAsync((async) {
      OffscreenMathHost.debugNowUs = () => async.elapsed.inMicroseconds;
      final gate = Completer<void>();
      OffscreenMathHost.debugExtraSvgLoader = DelayedSvgLoader(
        Duration.zero,
        gate: gate,
      );
      final jobs = OffscreenMathHost.debugRasterJobs;
      final order = <String>[];
      final images = <ui.Image?>[];
      unawaited(
        _raster('a').then((i) {
          order.add('a');
          images.add(i);
        }),
      );
      unawaited(
        _raster('b').then((i) {
          order.add('b');
          images.add(i);
        }),
      );
      async.elapse(const Duration(milliseconds: 100));
      expect(OffscreenMathHost.debugRasterJobs, jobs + 1, reason: 'b waits');
      expect(order, isEmpty);
      expect(OffscreenMathHost.rasterHost.pendingCount, 2);
      // the layout host never waits for the raster host
      expect(InkMathRenderer.layout(r'x^2', fontSizePt: 18), isNotNull);
      gate.complete();
      async.elapse(const Duration(milliseconds: 100));
      expect(order, ['a', 'b']);
      expect(OffscreenMathHost.debugRasterJobs, jobs + 2);
      expect(images, everyElement(isNotNull));
      for (final i in images) {
        i!.dispose();
      }
    });
  });

  test('the same request while queued joins its job; every caller gets its '
      'own image', () {
    fakeAsync((async) {
      final jobs = OffscreenMathHost.debugRasterJobs;
      final images = <ui.Image?>[];
      unawaited(_raster(r'\frac{1}{2}').then(images.add));
      unawaited(_raster(r'\frac{1}{2}').then(images.add));
      expect(OffscreenMathHost.rasterHost.pendingCount, 1);
      unawaited(_raster(r'\frac{1}{2}', pixelsPerPt: 3).then(images.add));
      expect(OffscreenMathHost.rasterHost.pendingCount, 2);
      async.elapse(const Duration(milliseconds: 50));
      expect(OffscreenMathHost.debugRasterJobs, jobs + 2);
      expect(images, hasLength(3));
      expect(images, everyElement(isNotNull));
      expect(identical(images[0], images[1]), isFalse);
      expect(
        (images[0]!.width, images[0]!.height),
        (images[1]!.width, images[1]!.height),
      );
      images[0]!.dispose();
      expect(images[1]!.debugDisposed, isFalse);
      images[1]!.dispose();
      images[2]!.dispose();
    });
  });

  test('a request never runs synchronously: it starts once the caller is '
      'done (outside any frame phase) and leaves no timer behind', () {
    fakeAsync((async) {
      final jobs = OffscreenMathHost.debugRasterJobs;
      ui.Image? image;
      unawaited(_raster('z').then((i) => image = i));
      expect(OffscreenMathHost.debugRasterJobs, jobs, reason: 'not yet');
      async.flushMicrotasks();
      expect(OffscreenMathHost.debugRasterJobs, jobs + 1);
      expect(
        OffscreenMathHost.debugLastJobPhase,
        isNot(SchedulerPhase.persistentCallbacks),
      );
      expect(image, isNotNull);
      expect(async.pendingTimers, isEmpty);
      image!.dispose();
    });
  });

  test('invalid LaTeX, a bad size or scale → null', () async {
    expect(await _raster(r'\frac{a'), isNull);
    expect(await _raster(r'\foo'), isNull);
    expect(await _raster(''), isNull);
    expect(await _raster('x', pixelsPerPt: 0), isNull);
    expect(
      await InkMathRenderer.rasterize(
        'x',
        colorArgb: 0xFF000000,
        fontSizePt: double.nan,
        pixelsPerPt: 2,
      ),
      isNull,
    );
  });
}

int _realNowUs() => _clock.elapsedMicroseconds;
final Stopwatch _clock = Stopwatch()..start();

/// A request made while the app paints runs after the frame (S-9).
void paintPhaseRequestCase() {
  testWidgets('a rasterize request made inside paint runs after the frame '
      '(outside the frame phases), no timer left', (tester) async {
    final jobs = OffscreenMathHost.debugRasterJobs;
    final requests = <({Future<ui.Image?> future, int jobsAtRequest})>[];
    await tester.pumpWidget(
      CustomPaint(
        painter: _RequestingPainter(requests),
        size: const Size(10, 10),
      ),
    );
    expect(requests, hasLength(1));
    expect(requests.single.jobsAtRequest, jobs, reason: 'not run in paint');
    expect(OffscreenMathHost.debugRasterJobs, jobs + 1, reason: 'after it');
    expect(OffscreenMathHost.debugLastJobPhase, SchedulerPhase.idle);
    ui.Image? image;
    unawaited(requests.single.future.then((i) => image = i));
    await tester.pump();
    expect(image, isNotNull);
    image!.dispose();
    expect(tester.takeException(), isNull);
  });
}

final class _RequestingPainter extends CustomPainter {
  _RequestingPainter(this.requests);
  final List<({Future<ui.Image?> future, int jobsAtRequest})> requests;

  @override
  void paint(Canvas canvas, Size size) {
    if (requests.isNotEmpty) return;
    final future = _raster(r'\alpha');
    requests.add((
      future: future,
      jobsAtRequest: OffscreenMathHost.debugRasterJobs,
    ));
  }

  @override
  bool shouldRepaint(_RequestingPainter oldDelegate) => false;
}

/// The SVG glyph samples (6.12.2, M-3): the parts drawn by flutter_svg pictures have ink —
/// root sign: its top bar over the radicand; vector: the arrow above the letter; stretchy
/// arrow: the shaft at the left / right ends; brace: the left band.
void svgGlyphCases() {
  Future<({int width, int height, ByteData bytes})> pixelsOf(
    String latex,
  ) async {
    final image = await _raster(latex, pixelsPerPt: 4);
    expect(image, isNotNull, reason: latex);
    final p = await imagePixels(image!);
    image.dispose();
    return p;
  }

  ui.Rect band(
    ({int width, int height, ByteData bytes}) p, {
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) => ui.Rect.fromLTRB(
    p.width * left,
    p.height * top,
    p.width * right,
    p.height * bottom,
  );

  test(r'\sqrt{x}, \sqrt[3]{x}: the root sign (top left, and its bar over the '
      'radicand)', () async {
    for (final latex in [r'\sqrt{x}', r'\sqrt[3]{x}']) {
      final p = await pixelsOf(latex);
      expect(
        inkIn(p, region: band(p, left: 0.55, top: 0, right: 1, bottom: 0.2)),
        greaterThan(0),
        reason: '$latex: the bar over the radicand',
      );
      expect(
        inkIn(p, region: band(p, left: 0, top: 0, right: 0.5, bottom: 0.5)),
        greaterThan(0),
        reason: '$latex: the top left of the box',
      );
    }
  });

  test(r'\vec{v}: the arrow above the letter (top band)', () async {
    final p = await pixelsOf(r'\vec{v}');
    expect(
      inkIn(p, region: band(p, left: 0, top: 0, right: 1, bottom: 0.3)),
      greaterThan(0),
    );
  });

  test(r'\xrightarrow{f}: the shaft (middle band at the ends)', () async {
    final p = await pixelsOf(r'\xrightarrow{f}');
    for (final (l, r) in [(0.0, 0.2), (0.8, 1.0)]) {
      expect(
        inkIn(
          p,
          region: band(p, left: l, top: 0.25, right: r, bottom: 0.85),
        ),
        greaterThan(0),
        reason: 'columns $l..$r',
      );
    }
  });

  test(
    r'\left\{\begin{array}{l}a\\b\end{array}\right.: the brace (left band)',
    () async {
      final p = await pixelsOf(
        r'\left\{\begin{array}{l}a\\b\end{array}\right.',
      );
      expect(
        inkIn(p, region: band(p, left: 0, top: 0, right: 0.3, bottom: 1)),
        greaterThan(0),
      );
    },
  );
}
