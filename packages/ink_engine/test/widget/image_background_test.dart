// m5-7/03-ink 8.2 T35 (6.11.1, 6.11.5): ImageBackgroundLayerBuilder.
// - build: the paper, then the image with its fit — contain (inside, centred),
//   cover (covers the page, cut to it), fill (stretched); imageFit null → contain;
//   paper only until the decode is there, then the widget redraws (it listens to
//   its own asset) and pins the decode it shows until it goes;
// - the 1st-round scale rule: layout size = page × viewScale (never ×
//   ancestorScale); the bucket comes from deviceScale (ancestorScale included);
// - the size comes from the PNG header: the decode is at the bucket, never at
//   the source resolution (the decoder sees the target size);
// - renderStill: pixelSize, the fit, bytes not there → null.
// The decoder is replaced by one that makes the target-size image at once (two
// tones like testPngBytes: the bottom-right quarter inverted), so the widget test
// needs no real asynchronous work.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/image/image_cache.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/memory_asset_store.dart';
import '../support/page_view.dart' show capturePixels;
import '../support/pixels.dart';

const int _blue = 0xFF3366CC;
const int _inverted = 0xFFCC9933;
const int _paper = 0xFFFFFFFF;
final _key = GlobalKey(debugLabel: 'background');

/// The decode stand-in: a two-tone image at the target size.
Future<ui.Image> _decoder(
  Uint8List bytes, {
  int? targetWidth,
  int? targetHeight,
}) async {
  final w = targetWidth!, h = targetHeight ?? targetWidth;
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(_blue),
    )
    ..drawRect(
      Rect.fromLTWH(w / 2, h / 2, w / 2, h / 2),
      Paint()..color = const Color(_inverted),
    );
  final picture = recorder.endRecording();
  try {
    return picture.toImageSync(w, h);
  } finally {
    picture.dispose();
  }
}

PageBackgroundContext _ctx({
  String? assetId = 'img',
  core.ImageFit? fit,
  Size pageSize = const Size(200, 100),
  double viewScale = 1,
  double ancestorScale = 1,
  bool isScaling = false,
}) => PageBackgroundContext(
  pageId: 'p1',
  pageSize: pageSize,
  background: InkBackgroundSpec(
    kind: InkBackgroundKind.image,
    assetId: assetId,
    imageFit: fit,
  ),
  viewScale: viewScale,
  ancestorScale: ancestorScale,
  devicePixelRatio: 1,
  isScaling: isScaling,
);

Future<void> _pump(
  WidgetTester tester,
  ImageBackgroundLayerBuilder builder,
  PageBackgroundContext ctx,
) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(800, 600);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _key,
          child: Builder(builder: (context) => builder.build(context, ctx)),
        ),
      ),
    ),
  );
}

/// Lets the queued decode run (microtasks only — the stand-in decoder) and redraw.
Future<void> _decode(WidgetTester tester, InkImageCache cache) async {
  for (var i = 0; i < 20 && cache.stats.queued > 0; i++) {
    await tester.pump();
  }
  await tester.pump();
}

bool _is(List<int> px, int argb) => samePixel(px, [
  (argb ~/ 0x10000) % 256,
  (argb ~/ 0x100) % 256,
  argb % 256,
  255,
], tol: 2);

void main() {
  late Uint8List square; // 100 × 100
  late Uint8List large; // 1600 × 1200
  setUpAll(() async {
    square = await testPngBytes(width: 100, height: 100);
    large = await testPngBytes(width: 1600, height: 1200);
  });

  late MemoryAssetStore store;
  late InkImageCache cache;
  late ImageBackgroundLayerBuilder builder;
  setUp(() {
    store = MemoryAssetStore()..bytes['img'] = square;
    store.bytes['large'] = large;
    cache = InkImageCache(assets: store);
    debugSetImageDecoder(cache, _decoder);
    builder = ImageBackgroundLayerBuilder(assets: store, images: cache);
  });
  tearDown(() async {
    cache.dispose();
    await store.close();
  });

  testWidgets('paper first, then the image when its decode arrives; pinned '
      'while shown', (tester) async {
    await _pump(tester, builder, _ctx());
    var p = await capturePixels(tester, key: _key);
    expect(_is(p.at(100, 50), _paper), isTrue, reason: 'paper only');
    await _decode(tester, cache);
    p = await capturePixels(tester, key: _key);
    expect(_is(p.at(60, 10), _blue), isTrue);
    expect(debugImageIsPinned(cache, 'img', 128), isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(debugImageIsPinned(cache, 'img', 128), isFalse, reason: 'released');
  });

  testWidgets('contain · cover · fill; no fit → contain', (tester) async {
    // contain: 100 × 100 in the middle of 200 × 100
    for (final fit in [core.ImageFit.contain, null]) {
      await _pump(tester, builder, _ctx(fit: fit));
      await _decode(tester, cache);
      final p = await capturePixels(tester, key: _key);
      expect(_is(p.at(25, 50), _paper), isTrue, reason: 'left of it: paper');
      expect(_is(p.at(175, 50), _paper), isTrue);
      expect(_is(p.at(60, 10), _blue), isTrue);
      expect(_is(p.at(140, 90), _inverted), isTrue);
    }
    // cover: 200 × 200 centred (y −50 … 150), cut to the page
    await _pump(tester, builder, _ctx(fit: core.ImageFit.cover));
    await _decode(tester, cache);
    var p = await capturePixels(tester, key: _key);
    expect(_is(p.at(5, 5), _blue), isTrue);
    expect(_is(p.at(95, 45), _blue), isTrue);
    expect(_is(p.at(105, 55), _inverted), isTrue);
    expect(_is(p.at(195, 95), _inverted), isTrue);
    expect(_is(p.at(195, 5), _blue), isTrue);
    // fill: stretched to 200 × 100
    await _pump(tester, builder, _ctx(fit: core.ImageFit.fill));
    await _decode(tester, cache);
    p = await capturePixels(tester, key: _key);
    expect(_is(p.at(5, 5), _blue), isTrue);
    expect(_is(p.at(95, 45), _blue), isTrue);
    expect(_is(p.at(105, 55), _inverted), isTrue);
    expect(_is(p.at(195, 95), _inverted), isTrue);
  });

  testWidgets('layout = page × viewScale; the bucket from deviceScale; the '
      'size from the header — no full-resolution decode', (tester) async {
    await _pump(tester, builder, _ctx(assetId: 'large', ancestorScale: 2));
    final box = tester.renderObject<RenderBox>(find.byKey(_key));
    expect(box.size, const Size(200, 100), reason: 'never × ancestorScale');
    await _decode(tester, cache);
    // 200 pt × deviceScale 2 = 400 px → bucket 512; the source is 1600 × 1200
    expect(debugImageDecodes(cache), [
      (assetId: 'large', width: 512, height: 384),
    ]);
    // while scaling, no other bucket is asked for
    await _pump(
      tester,
      builder,
      _ctx(assetId: 'large', ancestorScale: 4, isScaling: true),
    );
    await _decode(tester, cache);
    expect(debugImageDecodes(cache), hasLength(1));
    await _pump(tester, builder, _ctx(assetId: 'large', ancestorScale: 4));
    await _decode(tester, cache);
    expect(debugImageDecodes(cache).last, (
      assetId: 'large',
      width: 1024,
      height: 768,
    ));
    expect(debugImageIsPinned(cache, 'large', 1024), isTrue);
    expect(debugImageIsPinned(cache, 'large', 512), isFalse);
  });

  test('renderStill: pixelSize, the fit; bytes not there → null', () async {
    final real = InkImageCache(assets: store);
    addTearDown(real.dispose);
    final still = ImageBackgroundLayerBuilder(assets: store, images: real);
    final image = await still.renderStill(
      _ctx(fit: core.ImageFit.contain).background,
      pageSize: const Size(200, 100),
      pixelSize: const Size(400, 200),
    );
    expect([image!.width, image.height], [400, 200]);
    final bytes = (await image.toByteData())!;
    final p = Pixels(400, 200, bytes);
    image.dispose();
    expect(_is(p.at(50, 100), _paper), isTrue);
    expect(_is(p.at(120, 20), _blue), isTrue);
    expect(_is(p.at(280, 180), _inverted), isTrue);
    expect(debugImageIsPinned(real, 'img', 128), isFalse, reason: 'released');
    expect(
      await still.renderStill(
        _ctx(assetId: 'nothing').background,
        pageSize: const Size(200, 100),
        pixelSize: const Size(40, 20),
      ),
      isNull,
    );
  });
}
