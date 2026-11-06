// m5-7/03-ink 8.2 T35 (6.11.3 M-4 — 'finite'): a visible working set larger
// than the image budget. A small-budget cache, a page with 20 image objects that
// are all visible, and another page on the same cache:
// - the underlay chunks are recorded again at most assets × 2 times;
// - at last all 20 frames show image pixels (no placeholder);
// - the other page's chunks are not recorded again;
// - no endless decoding (decodes ≤ assets × 2); some requests were lowered
//   (downgraded) and the smallest bucket overflowed the budget.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/image/image_cache.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkPageRenderOf, inkUnderlayCacheOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import '../../support/pixels.dart';

const int _count = 20;

/// The color of asset [i] (distinct bytes → distinct asset ids).
int _colorOf(int i) =>
    0xFF000000 + (40 + i * 9) * 0x10000 + (200 - i * 7) * 0x100 + 90;

core.PageRect _frameOf(int i) {
  final col = i % 5, row = i ~/ 5;
  final x = 10.0 + col * 115, y = 10.0 + row * 90;
  return core.PageRect(x, y, x + 100, y + 75);
}

InkPageContent _content(String pageId, List<core.PageObject> objects) =>
    InkPageContent.fromCore(
      page: SyntheticInk.page(pageId: pageId),
      strokes: const [],
      objects: objects,
      revision: 1,
    );

void _paintAll(InkPageController c) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final render = inkPageRenderOf(c);
  for (final layer in InkRenderLayer.values) {
    render.paint(canvas, layer, 1);
  }
  recorder.endRecording().dispose();
}

/// Paints and lets the decodes arrive until nothing is queued and no underlay chunk
/// waits to be recorded.
Future<int> _settle(InkPageController c, InkImageCache cache) async {
  for (var round = 1; round <= 200; round++) {
    _paintAll(c);
    for (var i = 0; i < 2000 && cache.stats.queued > 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await pumpEventQueue();
    if (inkUnderlayCacheOf(c).dirtyCount == 0 && cache.stats.queued == 0) {
      return round;
    }
  }
  fail('the images did not settle');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('working set > budget: finite re-records, all drawn, the other page '
      'untouched', () async {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final assets = <String>[];
    for (var i = 0; i < _count + 2; i++) {
      final png = await testPngBytes(
        width: 400,
        height: 300,
        argb: _colorOf(i),
      );
      final asset = await store.assets.put(
        png,
        type: core.AssetType.image,
        mimeType: 'image/png',
      );
      assets.add(asset.id);
    }
    // one 256 px decode is 192 KiB: about three of them fit, most are lowered
    final cache = InkImageCache(assets: store.assets, budgetBytes: 600 * 1024);
    addTearDown(cache.dispose);
    final builders = <PageBackgroundLayerBuilder>[
      ImageBackgroundLayerBuilder(assets: store.assets, images: cache),
      const TemplateBackgroundLayerBuilder(),
    ];
    core.ImageObject image(String pageId, int i, {core.PageRect? at}) =>
        core_testing.PageObjectFixtures.image(
          pageId: pageId,
          assetId: assets[i],
          rect: at ?? _frameOf(i),
          id: 'img$pageId$i',
        );

    // the other page first: two images of its own, settled
    final other = createTestPageController(
      pageId: 'p2',
      backgroundBuilders: builders,
    );
    addTearDown(other.dispose);
    other.updateContent(
      _content('p2', [
        image('p2', _count, at: _frameOf(0)),
        image('p2', _count + 1, at: _frameOf(7)),
      ]),
    );
    await _settle(other, cache);
    final otherRecords = inkUnderlayCacheOf(other).recordCount;

    final c = createTestPageController(backgroundBuilders: builders);
    addTearDown(c.dispose);
    c.updateContent(
      _content('p1', [for (var i = 0; i < _count; i++) image('p1', i)]),
    );
    _paintAll(c);
    final first = inkUnderlayCacheOf(c).recordCount;
    expect(first, greaterThan(0));
    await _settle(c, cache);
    final again = inkUnderlayCacheOf(c).recordCount - first;
    expect(again, lessThanOrEqualTo(_count * 2), reason: 're-records');
    expect(again, greaterThan(0));
    final decodes = debugImageDecodes(cache)
        .where((d) => assets.take(_count).contains(d.assetId))
        .length;
    expect(decodes, lessThanOrEqualTo(_count * 2), reason: 'decodes');
    expect(cache.stats.downgraded, greaterThan(0));
    expect(inkUnderlayCacheOf(other).recordCount, otherRecords);

    // a few more paints change nothing (no loop)
    final settled = inkUnderlayCacheOf(c).recordCount;
    for (var i = 0; i < 3; i++) {
      _paintAll(c);
      await pumpEventQueue();
    }
    expect(inkUnderlayCacheOf(c).recordCount, settled);

    // every frame shows its image (the top-left quarter is the asset color)
    final pixels = await renderPixels(600, 400, (canvas) {
      paintPaper(canvas, 0xFFFFFFFF);
      final render = inkPageRenderOf(c);
      for (final layer in InkRenderLayer.values) {
        render.paint(canvas, layer, 1);
      }
    });
    for (var i = 0; i < _count; i++) {
      final r = _frameOf(i);
      final p = pixels.at(
        (r.left + r.width * 0.25).round(),
        (r.top + r.height * 0.25).round(),
      );
      final argb = _colorOf(i);
      expect(
        samePixel(p, [
          (argb ~/ 0x10000) % 256,
          (argb ~/ 0x100) % 256,
          argb % 256,
          255,
        ], tol: 3),
        isTrue,
        reason: 'image $i drawn: $p',
      );
    }
    expect(inkUnderlayCacheOf(c).heldPinCount, greaterThanOrEqualTo(_count));
  });
}
