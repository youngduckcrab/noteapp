// lib/src/providers.dart — Riverpod providers (03-ink 4.13, contract 7.2.15 / 7.2.16);
// (v2.0) inkShapeFitterProvider, inkImageCacheProvider, defaultPageBackgroundBuilders
// (2nd round contract 7.2.9, m5-7/03-ink 4.11).
// ink_engine depends on package:riverpod only (no flutter_riverpod, 7.4.4).
import 'package:note_core/note_core.dart' as core;
import 'package:riverpod/riverpod.dart';

import 'background/background_builder.dart';
import 'background/image_builder.dart';
import 'background/template_builder.dart';
import 'diagnostics/diagnostics.dart';
import 'diagnostics/ink_clock.dart';
import 'image/deferred_asset_store.dart';
import 'image/image_cache.dart';
import 'input/pressure_capability.dart';
import 'input/pressure_mode.dart';
import 'render/cache_pool.dart';
import 'render/ink_page_controller.dart';
import 'render/pencil_grain.dart';
import 'render/render_config.dart';
import 'render/thumbnail_renderer.dart';
import 'shape/shape_assist.dart';

/// Render tuning (platform default, 6.13). Tests may override.
final inkRenderConfigProvider = Provider<InkRenderConfig>(
  (ref) => InkRenderConfig.platformDefault,
  name: 'inkRenderConfigProvider',
);

/// Clock aligned with pointer timestamps where possible. Tests override with FakeInkClock.
final inkClockProvider = Provider<InkClock>(
  (ref) => InkClock.platform(),
  name: 'inkClockProvider',
);

// contract 7.2.15
/// Set by EDITOR from its persisted settings (no override needed).
final pressureModeProvider =
    NotifierProvider<PressureModeNotifier, PressureMode>(
      PressureModeNotifier.new,
      name: 'pressureModeProvider',
    );
final pressureCapabilityProvider =
    NotifierProvider<PressureCapabilityNotifier, PressureCapabilityState>(
      PressureCapabilityNotifier.new,
      name: 'pressureCapabilityProvider',
    ); // detection rule = INK 6.4 only

/// Stroke ids + wall clock from CORE (7.2.14). (v2.0) Read from CORE when a stroke asks for
/// them, so this provider, inkPageControllerProvider and pageBackgroundBuildersProvider can be
/// read in a container without a NoteStore override (m5-7/03-ink 4.11).
final inkCoreServicesProvider = Provider<InkCoreServices>((ref) {
  return InkCoreServices(
    newStrokeId: () => ref.read(core.idGeneratorProvider).newId(),
    nowMillis: () => ref.read(core.clockProvider).now().millisecondsSinceEpoch,
  );
}, name: 'inkCoreServicesProvider');

/// Shared caches (keepAlive; disposed with the container).
final inkCachePoolProvider = Provider<InkCachePool>((ref) {
  final pool = InkCachePool(ref.watch(inkRenderConfigProvider));
  ref.onDispose(pool.dispose);
  return pool;
}, name: 'inkCachePoolProvider');

/// Developer-overlay statistics (keepAlive). EDITOR sets enabled while the overlay is visible.
final inkDiagnosticsProvider = Provider<InkDiagnostics>((ref) {
  final d = InkDiagnostics(clock: ref.watch(inkClockProvider));
  ref.onDispose(d.dispose);
  return d;
}, name: 'inkDiagnosticsProvider');

/// Pencil grain texture (generated once).
final pencilGrainProvider = Provider<PencilGrain>((ref) {
  final g = PencilGrain();
  ref.onDispose(g.dispose);
  return g;
}, name: 'pencilGrainProvider');

// 2nd round contract 7.2.9
/// (v2.0) Shape recognition port. Overridden ONLY through ink_recognition's
/// recognitionOverrides() (7.3.3); tests may override it with FakeInkShapeFitter.
final inkShapeFitterProvider = Provider<InkShapeFitter>(
  (ref) => const NoShapeFitter(),
  name: 'inkShapeFitterProvider',
);

/// (v2.0) Decoded image cache shared by image objects, image backgrounds and thumbnails.
/// Reads core.assetStoreProvider lazily (at the first decode — a container without a
/// NoteStore override reads this without an error, 03-ink 4.11).
final inkImageCacheProvider = Provider<InkImageCache>((ref) {
  final cache = InkImageCache(
    assets: DeferredAssetStore(() => ref.read(core.assetStoreProvider)),
    budgetBytes: ref.watch(inkRenderConfigProvider).imageCacheBytes,
    pool: ref.watch(inkCachePoolProvider),
  );
  ref.onDispose(cache.dispose);
  return cache;
}, name: 'inkImageCacheProvider');

/// The default list INK uses AND the list pdf_io must keep after its own builder.
/// [image, template]; the image builder's store is read lazily from [ref]
/// (core.assetStoreProvider).
List<PageBackgroundLayerBuilder> defaultPageBackgroundBuilders(Ref ref) => [
  ImageBackgroundLayerBuilder(
    assets: DeferredAssetStore(() => ref.read(core.assetStoreProvider)),
    images: ref.watch(inkImageCacheProvider),
  ),
  const TemplateBackgroundLayerBuilder(),
];

// contract 7.2.16 v1.2
/// (v1.2) Read by inkPageControllerProvider and inkPageThumbnailRendererProvider; callers of
/// InkPageThumbnail pass its value (the widget reads no provider).
/// Overridden ONLY through pdf_io's pdfIoOverrides() (7.3.3) — which returns
/// [pdfBuilder, ...ink.defaultPageBackgroundBuilders(ref)].
/// (v2.0) default = defaultPageBackgroundBuilders(ref).
final pageBackgroundBuildersProvider =
    Provider<List<PageBackgroundLayerBuilder>>(
      defaultPageBackgroundBuilders,
      name: 'pageBackgroundBuildersProvider',
    );

/// One controller per page id; disposed when no widget watches it (off-screen release, 6.13).
final inkPageControllerProvider = Provider.autoDispose
    .family<InkPageController, String>((ref, pageId) {
      final controller = InkPageController(
        pageId: pageId,
        services: ref.watch(inkCoreServicesProvider),
        config: ref.watch(inkRenderConfigProvider),
        cachePool: ref.watch(inkCachePoolProvider),
        pressureStore: ref.watch(pressureCapabilityProvider.notifier),
        pressureMode: () => ref.read(pressureModeProvider),
        diagnostics: ref.watch(inkDiagnosticsProvider),
        clock: ref.watch(inkClockProvider),
        pencilGrain: ref.watch(pencilGrainProvider),
        backgroundBuilders: ref.watch(pageBackgroundBuildersProvider),
        // (v2.0, S-12) read at every beginStroke, so a changed override applies from
        // the next stroke
        shapeFitter: () => ref.read(inkShapeFitterProvider),
      );
      ref.onDispose(controller.dispose);
      return controller;
    }, name: 'inkPageControllerProvider');

// contract 7.2.16
/// The app shell overrides core.pageThumbnailRendererProvider with this (7.3.3).
final inkPageThumbnailRendererProvider = Provider<core.PageThumbnailRenderer>(
  (ref) => InkPageThumbnailRenderer(
    backgroundBuilders: ref.watch(pageBackgroundBuildersProvider),
    pencilGrain: ref.watch(pencilGrainProvider),
  ),
  name: 'inkPageThumbnailRendererProvider',
);
