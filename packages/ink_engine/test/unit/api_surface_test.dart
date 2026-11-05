// API surface of ink_engine (contract 00-overview 7.2.15 / 7.2.16, 03-ink 4.0–4.14, 8 T00).
//
// The checks are compile-time: every contract name, constructor and member is referenced
// with the contract types (typed tear-offs and typed locals), and every interface is
// implemented below member by member, so a renamed / retyped / removed member breaks the
// build. The exact set of exported names is checked by export_list_test.dart; names the
// contract removed from INK (PenStyle, InkTool, PaperColors, …) are covered there.
@TestOn('vm')
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/dev_tools.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:riverpod/misc.dart' show ProviderFamily;
import 'package:riverpod/riverpod.dart';

/// Removed by the contract (7.2.15): if InkPageController still had clearPage, the class
/// member would win over this extension and the Absent assignment below would not compile.
final class Absent {
  const Absent();
}

extension on InkPageController {
  Absent clearPage() => const Absent();
}

Never _no() => throw UnimplementedError();

// ---- interfaces, implemented member by member ------------------------------------------

final class _Builder
    implements PageBackgroundLayerBuilder, PageBackgroundStillRenderer {
  @override
  bool handles(InkBackgroundSpec background) => false;
  @override
  Widget build(BuildContext context, PageBackgroundContext ctx) => _no();
  @override
  Future<ui.Image?> renderStill(
    InkBackgroundSpec background, {
    required Size pageSize,
    required Size pixelSize,
  }) => _no();
}

final class _Session implements InkGestureSession {
  @override
  bool get isActive => false;
  @override
  void cancel() {}
}

final class _Store implements PressureCapabilityStore {
  @override
  PressureCapability capabilityOf(InkPointerKind kind) =>
      PressureCapability.unknown;
  @override
  void report(
    InkPointerKind kind,
    PressureCapability capability, {
    double? constantValue,
  }) {}
}

final class _Clock implements InkClock {
  @override
  int nowUs() => 0;
  @override
  bool get alignedWithEventTimestamps => false;
}

final class _Predictor implements InkPredictor {
  @override
  List<InkSample> predict(List<InkSample> history, {required int nowUs}) =>
      const [];
}

final class _Renderer implements core.PageThumbnailRenderer {
  @override
  Future<core.PageThumbnail?> render(
    core.PageContent content, {
    int maxSidePx = 512,
  }) => _no();
}

void main() {
  test('7.2.15 style helpers, pen profile', () {
    const HighlighterStraightening h = HighlighterStraightening.snapOnLift;
    expect(HighlighterStraightening.values, hasLength(3));
    const String key = InkStyleExtras.highlighterStraightening;
    expect(key, 'hlStraight');
    final style = core.StrokeStyle.defaultsFor(core.PenTool.highlighter);
    final PenProfile profile = style.profile;
    final double r = style.previewRadius;
    final HighlighterStraightening hs = style.highlighterStraightening;
    final core.StrokeStyle Function(HighlighterStraightening) w =
        style.withHighlighterStraightening;
    expect(w(h).highlighterStraightening, h);
    expect(hs, HighlighterStraightening.off);
    expect(r, style.width / 2);
    final PenProfile Function(core.PenTool) of = PenProfile.of;
    expect(of(core.PenTool.brush), PenProfile.ballpoint);
    expect(profile, PenProfile.highlighter);
    final InkLayer layer = profile.layer;
    final InkCap cap = profile.cap;
    final InkRenderMethod method = profile.renderMethod;
    expect(
      [layer, cap, method],
      [InkLayer.highlighter, InkCap.square, InkRenderMethod.strokedPolyline],
    );
    const PenProfile Function({
      required InkLayer layer,
      required double pressureGain,
      required double minFactor,
      required double maxFactor,
      required double velocityThinning,
      required double taperStart,
      required double taperEnd,
      required double taperMinFactor,
      required double tiltWidthGain,
      required double tiltOpacityLoss,
      required InkCap cap,
      required InkRenderMethod renderMethod,
      required bool textured,
      required bool groupComposite,
    })
    ctor = PenProfile.new;
    expect(ctor, isNotNull);
    for (final p in [
      PenProfile.ballpoint,
      PenProfile.fountain,
      PenProfile.pencil,
      PenProfile.marker,
    ]) {
      final List<Object> v = [
        p.pressureGain,
        p.minFactor,
        p.maxFactor,
        p.velocityThinning,
        p.taperStart,
        p.taperEnd,
        p.taperMinFactor,
        p.tiltWidthGain,
        p.tiltOpacityLoss,
        p.textured,
        p.groupComposite,
      ];
      expect(v, hasLength(11));
    }
  });

  test('7.2.15 input', () {
    const InkSample Function({
      required Offset position,
      required int timeUs,
      required InkPointerKind kind,
      double? pressure,
      double pressureMin,
      double pressureMax,
      double tilt,
      double orientation,
    })
    sampleCtor = InkSample.new;
    final s = sampleCtor(
      position: Offset.zero,
      timeUs: 1,
      kind: InkPointerKind.stylus,
      pressure: 0.5,
    );
    final double? np = s.normalizedPressure;
    expect(np, 0.5);
    final InkSample Function({
      Offset? position,
      int? timeUs,
      InkPointerKind? kind,
      double? pressure,
      double? pressureMin,
      double? pressureMax,
      double? tilt,
      double? orientation,
    })
    copy = s.copyWith;
    expect(copy(timeUs: 2).timeUs, 2);
    final List<Object?> fields = [
      s.position,
      s.timeUs,
      s.kind,
      s.pressure,
      s.pressureMin,
      s.pressureMax,
      s.tilt,
      s.orientation,
    ];
    expect(fields, hasLength(8));
    const InkSample Function(PointerEvent, {required Offset pagePosition})
    adapt = InkSampleAdapter.fromPointerEvent;
    final sample = adapt(
      const PointerDownEvent(kind: ui.PointerDeviceKind.stylus, pressure: 0.3),
      pagePosition: const Offset(1, 2),
    );
    expect(sample.position, const Offset(1, 2));
    expect(PressureMode.values, [
      PressureMode.auto,
      PressureMode.alwaysReal,
      PressureMode.alwaysSimulated,
    ]);
    expect(PressureCapability.values, [
      PressureCapability.unknown,
      PressureCapability.supported,
      PressureCapability.unsupported,
    ]);
    expect(PressureSource.values, [
      PressureSource.pending,
      PressureSource.real,
      PressureSource.simulated,
    ]);
    final NotifierProvider<PressureModeNotifier, PressureMode> modeProvider =
        pressureModeProvider;
    final NotifierProvider<PressureCapabilityNotifier, PressureCapabilityState>
    capabilityProvider = pressureCapabilityProvider;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final PressureModeNotifier modeNotifier = container.read(
      modeProvider.notifier,
    );
    final void Function(PressureMode) set = modeNotifier.set;
    set(PressureMode.alwaysReal);
    expect(container.read(modeProvider), PressureMode.alwaysReal);
    final PressureCapabilityNotifier capability = container.read(
      capabilityProvider.notifier,
    );
    final PressureCapabilityStore store = capability;
    final void Function() reset = capability.reset;
    store.report(InkPointerKind.stylus, PressureCapability.supported);
    final PressureCapabilityState state = container.read(capabilityProvider);
    expect(state.stylus, PressureCapability.supported);
    final double? constant = state.stylusConstantValue;
    expect(constant, isNull);
    reset();
    const PressureCapabilityState Function({
      PressureCapability stylus,
      double? stylusConstantValue,
    })
    stateCtor = PressureCapabilityState.new;
    expect(stateCtor().capabilityOf(InkPointerKind.touch), isNot(isNull));
    const InkPredictor predictor = NoopPredictor();
    expect(predictor.predict(const [], nowUs: 0), isEmpty);
    expect(_Store().capabilityOf(InkPointerKind.mouse), isNotNull);
    expect(_Predictor().predict(const [], nowUs: 0), isEmpty);
  });

  test('7.2.15 page controller, sessions, selection', () {
    const InkCoreServices Function({
      required String Function() newStrokeId,
      required core.EpochMillis Function() nowMillis,
    })
    servicesCtor = InkCoreServices.new;
    final services = servicesCtor(newStrokeId: () => 'x', nowMillis: () => 0);
    final String Function() newId = services.newStrokeId;
    final core.EpochMillis Function() now = services.nowMillis;
    expect([newId(), now()], ['x', 0]);

    const InkPageContent Function({
      required core.Page page,
      required List<core.Stroke> strokes,
      required int revision,
    })
    fromCore = InkPageContent.fromCore;
    final content = fromCore(
      page: SyntheticInk.page(),
      strokes: const [],
      revision: 0,
    );
    final core.Page page = content.page;
    final String pageId = content.pageId;
    final Size pageSize = content.pageSize;
    final InkBackgroundSpec bg = content.background;
    final List<InkStroke> strokes = content.strokes;
    final int revision = content.revision;
    final InkStroke? Function(String) byId = content.strokeById;
    final int Function(String) z = content.zIndexOf;
    expect(
      [page.id, pageId, pageSize, bg.kind, strokes, revision],
      [
        'p1',
        'p1',
        const Size(595.2756, 841.8898),
        InkBackgroundKind.blank,
        isEmpty,
        0,
      ],
    );
    expect([byId('x'), z('x')], [null, -1]);

    final InkPageController Function({
      required String pageId,
      required InkCoreServices services,
      required InkRenderConfig config,
      required InkCachePool cachePool,
      required PressureCapabilityStore pressureStore,
      required PressureMode Function() pressureMode,
      required InkDiagnostics diagnostics,
      required InkClock clock,
      required PencilGrain pencilGrain,
      required List<PageBackgroundLayerBuilder> backgroundBuilders,
    })
    controllerCtor = InkPageController.new;
    expect(controllerCtor, isNotNull);
    final c = createTestPageController();
    addTearDown(c.dispose);
    final ChangeNotifier asNotifier = c;
    expect(asNotifier, same(c));
    final List<Object> members = [
      c.pageId,
      c.services,
      c.config,
      c.cachePool,
      c.pressureStore,
      c.pressureMode,
      c.diagnostics,
      c.clock,
      c.pencilGrain,
      c.backgroundBuilders,
    ];
    expect(members, hasLength(10));
    final void Function(InkPageContent) update = c.updateContent;
    update(content);
    final InkPageContent? current = c.content;
    expect(current, same(content));
    final StrokeSession Function(
      InkSample, {
      required core.StrokeStyle style,
      required double viewScale,
      InkStrokeMeta meta,
    })
    beginStroke = c.beginStroke;
    final EraserSession Function(
      InkSample, {
      required EraserSpec spec,
      required double viewScale,
    })
    beginErase = c.beginErase;
    final LassoSession Function(
      Offset, {
      required double viewScale,
      LassoOptions options,
    })
    beginLasso = c.beginLasso;
    final InkSelection Function(Set<String>) select = c.select;
    final void Function() clearSelection = c.clearSelection;
    final InkStroke? Function(
      Offset, {
      double tolerance,
      core.StrokeFilter filter,
    })
    hitTest = c.hitTest;
    final List<String> Function(Rect) inRect = c.strokeIdsInRect;
    final Set<String> pending = c.pendingIds;
    final void Function(String) discardPending = c.discardPending;
    final void Function(InkEdit) discardEdit = c.discardEdit;
    final void Function({
      Rect? visiblePageRect,
      required double deviceScale,
      required bool isScaling,
    })
    setViewport = c.setViewport;
    final Listenable Function(InkRenderLayer) repaint = c.layerRepaint;
    final InkPageRenderStats stats = c.renderStats;
    final InkGestureSession? active = c.activeSession;
    final InkSelection? sel = c.selection;
    expect(
      [pending, active, sel, hitTest(Offset.zero), inRect(Rect.zero)],
      [isEmpty, null, null, null, isEmpty],
    );
    expect(repaint(InkRenderLayer.inkBase), isNotNull);
    setViewport(deviceScale: 2, isScaling: false);
    final double? bucket = c.renderStats.currentBucket;
    expect(bucket, 2.0);
    expect(InkRenderLayer.values, [
      InkRenderLayer.background,
      InkRenderLayer.highlighterBase,
      InkRenderLayer.highlighterActive,
      InkRenderLayer.inkBase,
      InkRenderLayer.inkActive,
      InkRenderLayer.overlay,
    ]);
    final List<Object?> statFields = [
      stats.strokeCount,
      stats.chunkPictures,
      stats.rasterTiles,
      stats.rasterBytes,
      stats.pendingCommits,
      stats.currentBucket,
    ];
    expect(statFields, hasLength(6));
    const InkPageRenderStats Function({
      required int strokeCount,
      required int chunkPictures,
      required int rasterTiles,
      required int rasterBytes,
      required int pendingCommits,
      required double? currentBucket,
    })
    statsCtor = InkPageRenderStats.new;
    expect(statsCtor, isNotNull);
    expect(c.clearPage(), isA<Absent>());

    // StrokeSession
    final first = SyntheticInk.line(Offset.zero, const Offset(10, 0)).first;
    final StrokeSession ss = beginStroke(
      first,
      style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
      viewScale: 1,
    );
    final InkGestureSession g = ss;
    final core.StrokeStyle sStyle = ss.style;
    final PressureSource src = ss.pressureSource;
    final LiveStrokeGeometry live = ss.live;
    final ui.Path frozen = live.frozenPath;
    final ui.Path tail = live.tailPath;
    final Float32List? poly = live.polyline;
    final Rect liveBounds = live.bounds;
    final int version = live.version;
    final bool liveEmpty = live.isEmpty;
    expect(
      [g.isActive, sStyle.tool, src, poly, liveEmpty],
      [true, core.PenTool.ballpoint, PressureSource.real, null, false],
    );
    expect([frozen, tail, liveBounds, version], hasLength(4));
    final void Function(InkSample) addSample = ss.addSample;
    final void Function(Iterable<InkSample>) addSamples = ss.addSamples;
    final InkEdit? Function([InkSample?]) end = ss.end;
    final void Function() cancel = ss.cancel;
    addSample(first.copyWith(position: const Offset(5, 0), timeUs: 10));
    addSamples(const []);
    final edit = end()!;
    cancel();

    // InkEdit
    const InkEdit Function({
      required String pageId,
      required InkEditKind kind,
      List<core.Stroke> added,
      Set<String> removedIds,
      Set<String> targetIds,
      core.Affine2? transform,
      int? colorArgb,
    })
    editCtor = InkEdit.new;
    expect(editCtor(pageId: 'p1', kind: InkEditKind.addStroke).isEmpty, true);
    final String ePage = edit.pageId;
    final InkEditKind kind = edit.kind;
    final List<core.Stroke> added = edit.added;
    final Set<String> removed = edit.removedIds;
    final Set<String> targets = edit.targetIds;
    final core.Affine2? transform = edit.transform;
    final int? color = edit.colorArgb;
    final bool editEmpty = edit.isEmpty;
    final core.EditCommand Function() toCommand = edit.toCommand;
    expect(
      [ePage, kind, added.length, removed, targets, transform, color],
      ['p1', InkEditKind.addStroke, 1, isEmpty, isEmpty, null, null],
    );
    expect(editEmpty, isFalse);
    expect(toCommand(), isA<core.AddStrokes>());
    expect(InkEditKind.values, [
      InkEditKind.addStroke,
      InkEditKind.eraseStrokes,
      InkEditKind.splitStrokes,
      InkEditKind.transformStrokes,
      InkEditKind.recolorStrokes,
      InkEditKind.deleteStrokes,
      InkEditKind.duplicateStrokes,
    ]);
    discardEdit(edit);
    discardPending('none');

    // EraserSession
    expect(EraserMode.values, [EraserMode.stroke, EraserMode.partial]);
    const EraserSpec Function({
      required EraserMode mode,
      required double radius,
      core.StrokeFilter filter,
    })
    specCtor = EraserSpec.new;
    final spec = specCtor(mode: EraserMode.partial, radius: 3);
    final List<Object> specFields = [spec.mode, spec.radius, spec.filter];
    expect(specFields, [EraserMode.partial, 3.0, core.StrokeFilter.all]);
    final EraserSession es = beginErase(first, spec: spec, viewScale: 1);
    final InkGestureSession eg = es;
    final EraserSpec esSpec = es.spec;
    final Set<String> touched = es.touchedStrokeIds;
    final void Function(InkSample) eAdd = es.addSample;
    final InkEdit? Function([InkSample?]) eEnd = es.end;
    final void Function() eCancel = es.cancel;
    eAdd(first);
    expect([eg.isActive, esSpec, touched], [true, spec, isEmpty]);
    expect(eEnd(), isNull);
    eCancel();

    // LassoSession
    const LassoOptions Function({
      double coverage,
      double simplifyPx,
      double minAreaPt2,
    })
    lassoCtor = LassoOptions.new;
    final options = lassoCtor();
    expect(
      [options.coverage, options.simplifyPx, options.minAreaPt2],
      [0.5, 0.75, 4.0],
    );
    final LassoSession ls = beginLasso(Offset.zero, viewScale: 1);
    final List<Offset> lp = ls.points;
    final ui.Path preview = ls.previewPath;
    final void Function(Offset) addPoint = ls.addPoint;
    final InkSelection? Function() lEnd = ls.end;
    final void Function() lCancel = ls.cancel;
    addPoint(const Offset(1, 1));
    expect([lp.length, preview], [2, isNotNull]);
    expect(lEnd(), isNull);
    lCancel();

    // InkSelection
    final InkSelection empty = select(const {});
    clearSelection();
    final Set<String> ids = empty.strokeIds;
    final List<InkStroke> selStrokes = empty.strokes;
    final bool selEmpty = empty.isEmpty;
    final Rect selBounds = empty.bounds;
    final core.Affine2 previewT = empty.previewTransform;
    final Rect previewB = empty.previewBounds;
    final bool disposed = empty.isDisposed;
    final void Function(core.Affine2) setPreview = empty.setPreviewTransform;
    final InkEdit? Function() commit = empty.commitTransform;
    final InkEdit Function() delete = empty.delete;
    final InkEdit Function({Offset offset}) duplicate = empty.duplicate;
    final InkEdit Function(int) recolor = empty.recolor;
    setPreview(core.Affine2.identity);
    expect(
      [ids, selStrokes, selEmpty, selBounds, previewT, previewB, disposed],
      [
        isEmpty,
        isEmpty,
        true,
        Rect.zero,
        core.Affine2.identity,
        Rect.zero,
        false,
      ],
    );
    expect(commit(), isNull);
    expect(delete, throwsStateError);
    expect(duplicate, throwsStateError);
    expect(() => recolor(0xFF000000), throwsStateError);
    expect(_Session().isActive, isFalse);
  });

  test('7.2.15 selection geometry, providers, diagnostics, dev tools', () {
    expect(SelectionHandle.values, hasLength(8));
    final Rect Function(Iterable<InkStroke>) boundsOf =
        SelectionGeometry.boundsOf;
    const core.Affine2 Function({
      required Rect bounds,
      required SelectionHandle handle,
      required Offset delta,
      bool keepAspect,
    })
    resize = SelectionGeometry.resize;
    const core.Affine2 Function(Offset) move = SelectionGeometry.move;
    const core.Affine2 Function({required Rect bounds, required double radians})
    rotate = SelectionGeometry.rotate;
    const double Function(double, {double step, double threshold}) snap =
        SelectionGeometry.snapAngle;
    const Rect Function(Rect, core.Affine2) tb =
        SelectionGeometry.transformedBounds;
    const List<Offset> Function(Rect, core.Affine2) corners =
        SelectionGeometry.transformedCorners;
    const double Function(double, core.Affine2) tw =
        SelectionGeometry.transformedWidth;
    expect(boundsOf(const []), Rect.zero);
    expect(
      resize(
        bounds: const Rect.fromLTWH(0, 0, 10, 10),
        handle: SelectionHandle.right,
        delta: const Offset(10, 0),
      ),
      core.Affine2.scaling(2, 1),
    );
    expect(move(const Offset(1, 2)), core.Affine2.translation(1, 2));
    expect(rotate(bounds: Rect.zero, radians: 1).isIdentity, isFalse);
    expect(snap(0.01), 0);
    expect(tb(Rect.zero, core.Affine2.identity), Rect.zero);
    expect(corners(Rect.zero, core.Affine2.identity), hasLength(4));
    expect(tw(100, core.Affine2.identity), 30);

    final ProviderFamily<InkPageController, String> controllers =
        inkPageControllerProvider;
    final Provider<InkDiagnostics> diagnostics = inkDiagnosticsProvider;
    final Provider<InkRenderConfig> config = inkRenderConfigProvider;
    final Provider<InkClock> clock = inkClockProvider;
    final Provider<InkCoreServices> services = inkCoreServicesProvider;
    final Provider<InkCachePool> pool = inkCachePoolProvider;
    final Provider<PencilGrain> grain = pencilGrainProvider;
    expect([
      controllers,
      diagnostics,
      config,
      clock,
      services,
      pool,
      grain,
    ], everyElement(isNotNull));

    final InkDiagnostics d = InkDiagnostics(clock: _Clock());
    addTearDown(d.dispose);
    final ChangeNotifier dn = d;
    d.enabled = true;
    final bool enabled = d.enabled;
    final InkStatsSnapshot snap0 = d.snapshot;
    final void Function() reset = d.reset;
    reset();
    expect([dn, enabled, snap0.clockAligned], [same(d), true, false]);
    expect(InkStatsSnapshot.empty.cache, InkCacheStats.empty);
    expect(LatencySummary.empty.count, 0);

    const List<core.Stroke> Function({
      required String pageId,
      required core.PageSize pageSize,
      required int count,
      required String Function() newId,
      required core.EpochMillis createdAt,
      int seed,
      core.PenTool tool,
    })
    synthetic = InkDevTools.syntheticStrokes;
    final ids = core.SequentialIdGenerator(prefix: 'd');
    final strokes = synthetic(
      pageId: 'p1',
      pageSize: core.PageSize.a4Portrait,
      count: 2,
      newId: ids.newId,
      createdAt: 5,
    );
    expect(strokes.map((s) => s.createdAt), [5, 6]);
  });

  test('7.2.16 background, vectors, thumbnails', () {
    expect(InkBackgroundKind.values, [
      InkBackgroundKind.blank,
      InkBackgroundKind.template,
      InkBackgroundKind.pdf,
      InkBackgroundKind.image,
      InkBackgroundKind.unknown,
    ]);
    const InkBackgroundSpec Function({
      required InkBackgroundKind kind,
      int paperColorArgb,
      core.PageTemplate? template,
      String? assetId,
      int? pdfPageIndex,
    })
    specCtor = InkBackgroundSpec.new;
    const InkBackgroundSpec Function(core.PageBackground) fromCore =
        InkBackgroundSpec.fromCore;
    final spec = specCtor(kind: InkBackgroundKind.unknown);
    final pdf = fromCore(
      const core.PdfBackground(assetId: 'a', pdfPageIndex: 2),
    );
    final List<Object?> specFields = [
      pdf.kind,
      pdf.paperColorArgb,
      pdf.template,
      pdf.assetId,
      pdf.pdfPageIndex,
      pdf.isDarkPaper,
    ];
    expect(specFields, [
      InkBackgroundKind.pdf,
      core.PaperColors.white,
      null,
      'a',
      2,
      false,
    ]);
    expect(spec.paperColorArgb, core.PaperColors.white);

    const PageBackgroundContext Function({
      required String pageId,
      required Size pageSize,
      required InkBackgroundSpec background,
      required double viewScale,
      required double ancestorScale,
      required double devicePixelRatio,
      required bool isScaling,
      Rect? visiblePageRect,
      bool isThumbnail,
    })
    ctxCtor = PageBackgroundContext.new;
    final ctx = ctxCtor(
      pageId: 'p',
      pageSize: const Size(10, 10),
      background: spec,
      viewScale: 2,
      ancestorScale: 3,
      devicePixelRatio: 4,
      isScaling: false,
    );
    final List<Object?> ctxFields = [
      ctx.pageId,
      ctx.pageSize,
      ctx.background,
      ctx.viewScale,
      ctx.ancestorScale,
      ctx.devicePixelRatio,
      ctx.isScaling,
      ctx.visiblePageRect,
      ctx.isThumbnail,
      ctx.deviceScale,
    ];
    expect(ctxFields.last, 24.0);

    final _Builder custom = _Builder();
    const PageBackgroundLayerBuilder templates =
        TemplateBackgroundLayerBuilder();
    const PageBackgroundStillRenderer still = TemplateBackgroundLayerBuilder();
    final bool Function(InkBackgroundSpec) handles = templates.handles;
    final Widget Function(BuildContext, PageBackgroundContext) build =
        templates.build;
    final Future<ui.Image?> Function(
      InkBackgroundSpec, {
      required Size pageSize,
      required Size pixelSize,
    })
    renderStill = still.renderStill;
    expect(
      [handles(spec), build, renderStill, custom.handles(spec)],
      [false, isNotNull, isNotNull, false],
    );
    final Provider<List<PageBackgroundLayerBuilder>> builders =
        pageBackgroundBuildersProvider;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(builders), [templates]);

    const List<TemplateVectorItem> Function(
      core.PageTemplate, {
      required Size pageSize,
      required int paperColorArgb,
      Rect? clip,
    })
    vectors = TemplateVectors.build;
    expect(
      vectors(
        core.PageTemplate.defaults(core.PageTemplateKind.lined),
        pageSize: const Size(100, 100),
        paperColorArgb: core.PaperColors.white,
      ),
      isA<List<TemplateVectorItem>>(),
    );
    const TemplateVectorItem line = TemplateLine(
      Offset.zero,
      Offset(1, 1),
      width: 1,
      colorArgb: 0xFF000000,
    );
    const TemplateVectorItem dot = TemplateDot(
      Offset.zero,
      radius: 1,
      colorArgb: 0xFF000000,
    );
    switch (line) {
      case TemplateLine(:final p0, :final p1, :final width, :final colorArgb):
        expect([p0, p1, width, colorArgb], hasLength(4));
      case TemplateDot():
        fail('line expected');
    }
    expect((dot as TemplateDot).radius, 1);

    // vector export (approved INK 4.11)
    expect(InkBlendMode.values, [InkBlendMode.normal, InkBlendMode.multiply]);
    const InkExportOptions Function({
      bool smooth,
      double pencilOpacityFactor,
      int paperColorArgb,
    })
    optionsCtor = InkExportOptions.new;
    final options = optionsCtor();
    expect(
      [options.smooth, options.pencilOpacityFactor, options.paperColorArgb],
      [true, 0.85, core.PaperColors.white],
    );
    const InkPageVectors Function(List<InkStroke>, {InkExportOptions options})
    exportStrokes = InkVectorExport.exportStrokes;
    const InkPageVectors Function(InkPageContent, {InkExportOptions? options})
    exportPage = InkVectorExport.exportPage;
    final vectorsOut = exportPage(SyntheticInk.pageContent());
    final List<InkHighlighterGroup> groups = vectorsOut.highlighterGroups;
    final List<InkFillShape> shapes = vectorsOut.inkShapes;
    final Rect vBounds = vectorsOut.bounds;
    final bool vEmpty = vectorsOut.isEmpty;
    expect(
      [groups, shapes, vBounds, vEmpty],
      [isEmpty, isEmpty, Rect.zero, true],
    );
    expect(exportStrokes(const []).isEmpty, isTrue);
    for (final g in groups) {
      final List<Object> f = [g.colorArgb, g.opacity, g.blend, g.lines];
      for (final l in g.lines) {
        final List<Object> lf = [l.strokeId, l.centerline, l.width, l.cap];
        expect(lf, hasLength(4));
      }
      expect(f, hasLength(4));
    }
    for (final s in shapes) {
      final List<Object> f = [
        s.strokeId,
        s.tool,
        s.path,
        s.colorArgb,
        s.opacity,
      ];
      expect(f, hasLength(5));
    }
    final InkVectorPath path = InkVectorPath(
      Uint8List.fromList([InkPathVerb.moveTo.index, InkPathVerb.lineTo.index]),
      Float32List.fromList([0, 0, 2, 3]),
    );
    final Uint8List verbs = path.verbs;
    final Float32List coords = path.coords;
    final Rect pBounds = path.bounds;
    final ui.Path Function() toUiPath = path.toUiPath;
    expect(
      [verbs.length, coords.length, pBounds],
      [2, 4, const Rect.fromLTRB(0, 0, 2, 3)],
    );
    expect(toUiPath(), isNotNull);

    // thumbnail widget / renderer / pen preview
    const InkPageThumbnail Function({
      Key? key,
      required InkPageContent content,
      required double width,
      required List<PageBackgroundLayerBuilder> backgroundBuilders,
      PencilGrain? pencilGrain,
    })
    thumbCtor = InkPageThumbnail.new;
    final thumb = thumbCtor(
      content: SyntheticInk.pageContent(),
      width: 64,
      backgroundBuilders: const [TemplateBackgroundLayerBuilder()],
    );
    final StatefulWidget asWidget = thumb;
    final List<Object?> thumbFields = [
      thumb.content,
      thumb.width,
      thumb.backgroundBuilders,
      thumb.pencilGrain,
      asWidget,
    ];
    expect(thumbFields, hasLength(5));
    const InkPageThumbnailRenderer Function({
      required List<PageBackgroundLayerBuilder> backgroundBuilders,
      PencilGrain? pencilGrain,
    })
    rendererCtor = InkPageThumbnailRenderer.new;
    final core.PageThumbnailRenderer renderer = rendererCtor(
      backgroundBuilders: const [],
    );
    final Future<core.PageThumbnail?> Function(
      core.PageContent, {
      int maxSidePx,
    })
    render = renderer.render;
    expect([render, _Renderer()], everyElement(isNotNull));
    final Provider<core.PageThumbnailRenderer> rendererProvider =
        inkPageThumbnailRendererProvider;
    expect(rendererProvider, isNotNull);
    final PenPreviewPainter Function({
      required core.StrokeStyle style,
      PenPreviewShape shape,
      int paperColorArgb,
      PencilGrain? pencilGrain,
    })
    previewCtor = PenPreviewPainter.new;
    final preview = previewCtor(
      style: core.StrokeStyle.defaultsFor(core.PenTool.pencil),
    );
    final CustomPainter painter = preview;
    final List<Object?> previewFields = [
      preview.style,
      preview.shape,
      preview.paperColorArgb,
      preview.pencilGrain,
    ];
    expect(previewFields[1], PenPreviewShape.sCurve);
    expect(painter.shouldRepaint(preview), isFalse);
    expect(PenPreviewShape.values, hasLength(2));
  });

  test('4.9 / 4.12 / 4.14 render config, caches, clock, testing helpers', () {
    expect(InkRenderConfig.platformDefault, InkRenderConfig.nativeDefaults);
    expect(InkRenderConfig.webDefaults.chunkSizePt, 128);
    final InkRenderConfig Function({bool? rasterTiles}) copy =
        InkRenderConfig.nativeDefaults.copyWith;
    expect(copy(rasterTiles: false).rasterTiles, isFalse);
    final pool = InkCachePool(InkRenderConfig.webDefaults);
    final InkCacheStats stats = pool.stats;
    final int total = stats.totalBytes;
    final void Function({int? outlineBytes, int? rasterBytes}) trim =
        pool.trimTo;
    trim(outlineBytes: 0);
    pool.dispose();
    expect(total, 0);
    final InkClock platform = InkClock.platform();
    expect(platform.alignedWithEventTimestamps, isFalse);
    final fake = FakeInkClock(startUs: 5)..advanceMs(1);
    expect(fake.nowUs(), 1005);
    final InkCoreServices services = testInkCoreServices();
    expect(services.newStrokeId(), 's-000001');
    expect([services.nowMillis(), services.nowMillis()], [1000, 1001]);
    final PressureCapabilityStore store = MemoryPressureStore();
    expect(
      store.capabilityOf(InkPointerKind.stylus),
      PressureCapability.unknown,
    );
    const PageBackgroundLayerBuilder solid = SolidBackgroundBuilder();
    expect(
      solid.handles(const InkBackgroundSpec(kind: InkBackgroundKind.pdf)),
      isTrue,
    );
    expect(InkTuning.lassoPathArgb, 0xFF2F80ED);
    expect(PencilGrain.generatePixels(size: 4), hasLength(64));
  });
}
