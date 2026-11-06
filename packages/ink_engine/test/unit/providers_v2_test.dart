// T24 (m5-7/03-ink 8.1, 4.11): the 2nd round providers — names, a container
// WITHOUT a CORE store override reads pageBackgroundBuildersProvider,
// inkPageControllerProvider and inkImageCacheProvider without an error, the
// default list is [image, template], the image cache budget follows
// InkRenderConfig.imageCacheBytes, and a changed shape fitter override reaches
// the next stroke of the same controller (S-12).
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/image/deferred_asset_store.dart';
import 'package:ink_engine/src/render/sessions.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:riverpod/riverpod.dart';

void main() {
  test('names = variable names', () {
    expect(inkShapeFitterProvider.name, 'inkShapeFitterProvider');
    expect(inkImageCacheProvider.name, 'inkImageCacheProvider');
    expect(
      pageBackgroundBuildersProvider.name,
      'pageBackgroundBuildersProvider',
    );
  });

  test('a container without a CORE store override reads them without an '
      'error', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(inkShapeFitterProvider), isA<NoShapeFitter>());
    final cache = container.read(inkImageCacheProvider);
    expect(cache, isA<InkImageCache>());
    final builders = container.read(pageBackgroundBuildersProvider);
    expect(builders, [
      isA<ImageBackgroundLayerBuilder>(),
      const TemplateBackgroundLayerBuilder(),
    ]);
    final image = builders.first as ImageBackgroundLayerBuilder;
    expect(identical(image.images, cache), isTrue);
    // the store is unavailable only when something asks for bytes
    await expectLater(
      image.assets.readBytes('a1'),
      throwsA(isA<ImageStoreUnavailable>()),
    );
    expect(await image.assets.bytesArrived.isEmpty, isTrue);
    final sub = container.listen(inkPageControllerProvider('p1'), (_, _) {});
    addTearDown(sub.close);
    expect(sub.read().backgroundBuilders, hasLength(2));
  });

  test('with a CORE store the deferred store reads it', () async {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final container = ProviderContainer(
      overrides: [core.noteStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final image =
        container.read(pageBackgroundBuildersProvider).first
            as ImageBackgroundLayerBuilder;
    final png = await testPngBytes(width: 4, height: 4);
    final asset = await store.assets.put(
      png,
      type: core.AssetType.image,
      mimeType: 'image/png',
    );
    expect(await image.assets.readBytes(asset.id), png);
    expect(
      await container.read(inkImageCacheProvider).assets.hasBytes(asset.id),
      isTrue,
    );
  });

  test(
    'InkImageCache R2-B3: peek / load null, no change events, budgets',
    () async {
      final store = core_testing.createFakeNoteStore();
      addTearDown(store.close);
      final cache = InkImageCache(assets: store.assets, budgetBytes: 1234);
      addTearDown(cache.dispose);
      expect(cache.budgetBytes, 1234);
      expect(cache.peek('x', longSidePx: 256), isNull);
      expect(await cache.load('x', longSidePx: 256), isNull);
      expect(cache.stats.images, 0);
      expect(
        InkImageCache(assets: store.assets).budgetBytes,
        128 * 1024 * 1024, // native rule (this is a VM test)
      );
      final container = ProviderContainer(
        overrides: [
          inkRenderConfigProvider.overrideWithValue(
            const InkRenderConfig(imageCacheBytes: 4096),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(inkImageCacheProvider).budgetBytes, 4096);
    },
  );

  test('S-12: a changed fitter override applies from the next stroke', () {
    final first = FakeInkShapeFitter();
    final second = FakeInkShapeFitter();
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final container = ProviderContainer(
      overrides: [
        core.noteStoreProvider.overrideWithValue(store),
        inkShapeFitterProvider.overrideWithValue(first),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(inkPageControllerProvider('p1'), (_, _) {});
    addTearDown(sub.close);
    final controller = sub.read();
    controller.updateContent(SyntheticInk.pageContent());
    StrokeSession begin() => controller.beginStroke(
      SyntheticInk.line(Offset.zero, const Offset(20, 0)).first,
      style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
      viewScale: 1,
      shapeAssist: ShapeAssist.holdToSnap,
    );
    final a = begin();
    expect(strokeSessionFitterOf(a), same(first));
    a.cancel();
    container.updateOverrides([
      core.noteStoreProvider.overrideWithValue(store),
      inkShapeFitterProvider.overrideWithValue(second),
    ]);
    final b = begin();
    expect(identical(sub.read(), controller), isTrue, reason: 'not rebuilt');
    expect(strokeSessionFitterOf(b), same(second));
    b.cancel();
    // off → the fitter is not read
    final c = controller.beginStroke(
      SyntheticInk.line(Offset.zero, const Offset(20, 0)).first,
      style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
      viewScale: 1,
    );
    expect(strokeSessionFitterOf(c), isNull);
    c.cancel();
    expect(first.calls + second.calls, 0, reason: 'R2-B3 never asks it');
  });

  test('createTestPageController(shapeFitter:) wires the fitter', () {
    final fitter = FakeInkShapeFitter();
    final c = createTestPageController(shapeFitter: fitter);
    addTearDown(c.dispose);
    c.updateContent(SyntheticInk.pageContent());
    final s = c.beginStroke(
      SyntheticInk.line(Offset.zero, const Offset(20, 0)).first,
      style: core.StrokeStyle.defaultsFor(core.PenTool.fountain),
      viewScale: 1,
      shapeAssist: ShapeAssist.holdToSnap,
    );
    expect(strokeSessionFitterOf(s), same(fitter));
    s.cancel();
    for (final tool in [
      core.PenTool.highlighter,
      core.PenTool.laser,
      core.PenTool.tape,
    ]) {
      final t = c.beginStroke(
        SyntheticInk.line(Offset.zero, const Offset(20, 0)).first,
        style: core.StrokeStyle.defaultsFor(tool),
        viewScale: 1,
        shapeAssist: ShapeAssist.holdToSnap,
      );
      expect(strokeSessionFitterOf(t), isNull, reason: tool.name);
      t.cancel();
    }
  });

  test('port values: NoShapeFitter never fits, InkShapeFit == by value, '
      'FakeInkShapeFitter counts', () {
    final points = [for (var i = 0; i < 10; i++) Offset(i * 1.0, 0)];
    expect(const NoShapeFitter().fit(points, viewScale: 1), isNull);
    final geometry = core.ShapeGeometry.rectangle(
      const core.PageRect(0, 0, 10, 10),
    );
    final fit = InkShapeFit(
      kind: core.ShapeKind.rectangle,
      geometry: geometry,
      score: 0.9,
    );
    expect(
      fit,
      InkShapeFit(
        kind: core.ShapeKind.rectangle,
        geometry: geometry,
        score: 0.9,
      ),
    );
    final fake = FakeInkShapeFitter(fit: fit, minPoints: 8);
    expect(fake.fit(points.take(3).toList(), viewScale: 1), isNull);
    expect(fake.fit(points, viewScale: 2), same(fit));
    expect(fake.calls, 2);
    expect(fake.received.last, points);
    fake.result = null;
    expect(fake.fit(points, viewScale: 1), isNull);
  });
}
