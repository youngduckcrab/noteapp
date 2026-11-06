// T12 (03-ink 8, 4.13, contract 7.2.15 / 7.2.16): the Riverpod providers —
// a ProviderContainer with core.noteStoreProvider overridden by the CORE fake
// store builds a page controller wired to the shared providers (stroke ids and
// pen-down time from CORE), the controller is disposed by autoDispose once its
// last listener goes, keepAlive services live until the container is
// disposed, pressureModeProvider.notifier.set reaches the next stroke without
// rebuilding the controller, every provider's name = its variable name, and
// both readers of pageBackgroundBuildersProvider follow its override.
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/dev_tools.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:riverpod/misc.dart' show Override;
import 'package:riverpod/riverpod.dart';

void main() {
  late core.NoteStore store;
  late ProviderContainer container;

  ProviderContainer containerWith([List<Override> more = const []]) {
    final c = ProviderContainer(
      overrides: [core.noteStoreProvider.overrideWithValue(store), ...more],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Keeps inkPageControllerProvider(pageId) alive until the returned
  /// subscription is closed (EDITOR's page widget watches it).
  ProviderSubscription<InkPageController> watchPage(
    ProviderContainer c,
    String pageId,
  ) => c.listen(inkPageControllerProvider(pageId), (_, _) {});

  core.AddStrokes drawStroke(
    InkPageController controller, {
    List<InkSample>? samples,
    core.PenTool tool = core.PenTool.ballpoint,
  }) {
    final s =
        samples ??
        SyntheticInk.line(const Offset(40, 60), const Offset(240, 90));
    final session = controller.beginStroke(
      s.first,
      style: core.StrokeStyle.defaultsFor(tool),
      viewScale: 1,
    )..addSamples(s.skip(1));
    return session.end(s.last)!.toCommand() as core.AddStrokes;
  }

  setUp(() {
    store = core_testing.createFakeNoteStore(
      ids: core.SequentialIdGenerator(prefix: 'core'),
    );
    addTearDown(store.close);
    container = containerWith();
  });

  test('every provider name = its variable name (7.4.4)', () {
    final names = <String?, String>{
      inkRenderConfigProvider.name: 'inkRenderConfigProvider',
      inkClockProvider.name: 'inkClockProvider',
      pressureModeProvider.name: 'pressureModeProvider',
      pressureCapabilityProvider.name: 'pressureCapabilityProvider',
      inkCoreServicesProvider.name: 'inkCoreServicesProvider',
      inkCachePoolProvider.name: 'inkCachePoolProvider',
      inkDiagnosticsProvider.name: 'inkDiagnosticsProvider',
      pencilGrainProvider.name: 'pencilGrainProvider',
      pageBackgroundBuildersProvider.name: 'pageBackgroundBuildersProvider',
      inkPageControllerProvider.name: 'inkPageControllerProvider',
      inkPageThumbnailRendererProvider.name: 'inkPageThumbnailRendererProvider',
    };
    expect(names, hasLength(11));
    names.forEach(expect);
    expect(inkPageControllerProvider('p1').name, 'inkPageControllerProvider');
  });

  test('defaults without overrides (other than the CORE store)', () {
    expect(
      container.read(inkRenderConfigProvider),
      InkRenderConfig.platformDefault,
    );
    expect(container.read(inkClockProvider), isA<InkClock>());
    expect(container.read(pressureModeProvider), PressureMode.auto);
    expect(
      container.read(pressureCapabilityProvider),
      const PressureCapabilityState(),
    );
    // (v2.0) default = defaultPageBackgroundBuilders(ref) = [image, template]
    expect(container.read(pageBackgroundBuildersProvider), [
      isA<ImageBackgroundLayerBuilder>(),
      const TemplateBackgroundLayerBuilder(),
    ]);
    expect(
      container.read(inkPageThumbnailRendererProvider),
      isA<InkPageThumbnailRenderer>(),
    );
    // keepAlive singletons
    expect(
      identical(
        container.read(inkCachePoolProvider),
        container.read(inkCachePoolProvider),
      ),
      isTrue,
    );
  });

  test('the controller is wired to the shared providers and to CORE', () {
    final sub = watchPage(container, 'p1');
    addTearDown(sub.close);
    final c = sub.read();
    expect(c.pageId, 'p1');
    expect(c.config, container.read(inkRenderConfigProvider));
    expect(
      identical(c.cachePool, container.read(inkCachePoolProvider)),
      isTrue,
    );
    expect(
      identical(c.diagnostics, container.read(inkDiagnosticsProvider)),
      isTrue,
    );
    expect(identical(c.clock, container.read(inkClockProvider)), isTrue);
    expect(
      identical(c.pencilGrain, container.read(pencilGrainProvider)),
      isTrue,
    );
    expect(
      identical(
        c.pressureStore,
        container.read(pressureCapabilityProvider.notifier),
      ),
      isTrue,
    );
    expect(
      c.backgroundBuilders,
      container.read(pageBackgroundBuildersProvider),
    );

    // stroke ids from core.idGeneratorProvider, pen-down time from core.clockProvider
    c.updateContent(SyntheticInk.pageContent());
    final before = store.clock.now().millisecondsSinceEpoch;
    final command = drawStroke(c);
    final after = store.clock.now().millisecondsSinceEpoch;
    final stroke = command.strokes.single;
    expect(stroke.id, 'core-000001');
    expect(stroke.createdAt, inInclusiveRange(before, after));
    expect(stroke.pageId, 'p1');
    expect(store.ids.newId(), 'core-000002'); // the same CORE generator

    // one controller per page id
    final other = watchPage(container, 'p2');
    addTearDown(other.close);
    expect(other.read().pageId, 'p2');
    expect(identical(other.read(), c), isFalse);
    expect(identical(watchPage(container, 'p1').read(), c), isTrue);
  });

  test(
    'autoDispose: the controller goes when its last listener goes',
    () async {
      final sub = watchPage(container, 'p1');
      final first = sub.read();
      final keep = watchPage(container, 'p2');
      addTearDown(keep.close);
      final pool = container.read(inkCachePoolProvider);
      final diagnostics = container.read(inkDiagnosticsProvider);

      sub.close();
      await container.pump();
      expect(container.exists(inkPageControllerProvider('p1')), isFalse);
      expect(
        () => first.updateContent(SyntheticInk.pageContent()),
        throwsStateError,
      );
      // the other page's controller and the keepAlive services stay
      expect(container.exists(inkPageControllerProvider('p2')), isTrue);
      keep.read().updateContent(SyntheticInk.pageContent(pageId: 'p2'));
      expect(identical(container.read(inkCachePoolProvider), pool), isTrue);
      expect(
        identical(container.read(inkDiagnosticsProvider), diagnostics),
        isTrue,
      );

      // watching again builds a fresh controller
      final again = watchPage(container, 'p1');
      addTearDown(again.close);
      expect(identical(again.read(), first), isFalse);
      again.read().updateContent(SyntheticInk.pageContent());
    },
  );

  test('keepAlive services are disposed with the container', () {
    final c = containerWith();
    final grain = c.read(pencilGrainProvider);
    final diagnostics = c.read(inkDiagnosticsProvider);
    final pool = c.read(inkCachePoolProvider);
    final controller = c
        .listen(inkPageControllerProvider('p1'), (_, _) {})
        .read();
    ChangeNotifier.debugAssertNotDisposed(grain);
    ChangeNotifier.debugAssertNotDisposed(diagnostics);

    c.dispose();
    expect(
      () => ChangeNotifier.debugAssertNotDisposed(grain),
      throwsFlutterError,
    );
    expect(
      () => ChangeNotifier.debugAssertNotDisposed(diagnostics),
      throwsFlutterError,
    );
    diagnostics.enabled = true; // ignored once disposed
    expect(diagnostics.enabled, isFalse);
    // a disposed pool no longer keeps outlines
    final stroke = InkStroke.of(
      InkDevTools.syntheticStrokes(
        pageId: 'p1',
        pageSize: core.PageSize.a4Portrait,
        count: 1,
        newId: () => 'k',
        createdAt: 0,
      ).single,
    );
    pool.outlineFor(stroke);
    expect(pool.stats.outlineEntries, 0);
    expect(
      () => controller.updateContent(SyntheticInk.pageContent()),
      throwsStateError,
    );
  });

  test('pressureModeProvider.notifier.set reaches the next stroke; no rebuild', () {
    final sub = watchPage(container, 'p1');
    addTearDown(sub.close);
    final c = sub.read()..updateContent(SyntheticInk.pageContent());
    final notifier = container.read(pressureModeProvider.notifier);
    expect(c.pressureMode(), PressureMode.auto);
    notifier.set(PressureMode.alwaysSimulated);
    expect(c.pressureMode(), PressureMode.alwaysSimulated);
    notifier.set(PressureMode.alwaysReal);
    expect(c.pressureMode(), PressureMode.alwaysReal);
    expect(identical(sub.read(), c), isTrue);

    // the detector reports to pressureCapabilityProvider (6.4); the controller
    // is not rebuilt by the state change either
    notifier.set(PressureMode.auto);
    drawStroke(
      c,
      samples: SyntheticInk.wave(
        const Offset(30, 300),
        samples: 40,
        pressureAt: (t) => 0.2 + 0.6 * t,
      ),
    );
    expect(
      container.read(pressureCapabilityProvider).stylus,
      PressureCapability.supported,
    );
    expect(identical(sub.read(), c), isTrue);
  });

  test('overrides: render config, clock, core services', () {
    const config = InkRenderConfig(rasterTiles: false, chunkSizePt: 128);
    final clock = FakeInkClock(startUs: 9);
    final services = testInkCoreServices(idPrefix: 'svc', startMillis: 77);
    final c = containerWith([
      inkRenderConfigProvider.overrideWithValue(config),
      inkClockProvider.overrideWithValue(clock),
      inkCoreServicesProvider.overrideWithValue(services),
    ]);
    final sub = watchPage(c, 'p1');
    addTearDown(sub.close);
    final controller = sub.read()..updateContent(SyntheticInk.pageContent());
    expect(controller.config, config);
    expect(identical(controller.clock, clock), isTrue);
    expect(identical(controller.services, services), isTrue);
    final stroke = drawStroke(controller).strokes.single;
    expect((stroke.id, stroke.createdAt), ('svc-000001', 77));
  });

  test(
    'both readers follow the pageBackgroundBuildersProvider override',
    () async {
      final pdfContent = core.PageContent(
        page: SyntheticInk.page(
          background: const core.PdfBackground(assetId: 'a', pdfPageIndex: 0),
        ),
        strokes: const [],
        revision: 3,
      );
      // default (templates only): a pdf page has no still renderer → null
      expect(
        await container
            .read(inkPageThumbnailRendererProvider)
            .render(pdfContent),
        isNull,
      );

      const solid = SolidBackgroundBuilder();
      final c = containerWith([
        pageBackgroundBuildersProvider.overrideWithValue(const [
          solid,
          TemplateBackgroundLayerBuilder(),
        ]),
      ]);
      final sub = watchPage(c, 'p1');
      addTearDown(sub.close);
      expect(sub.read().backgroundBuilders, const [
        solid,
        TemplateBackgroundLayerBuilder(),
      ]);
      final thumb = await c
          .read(inkPageThumbnailRendererProvider)
          .render(pdfContent, maxSidePx: 64);
      expect(thumb, isNotNull);
      expect(thumb!.height, 64);
      expect(thumb.contentRevision, pdfContent.page.contentRevision);
    },
  );
}
