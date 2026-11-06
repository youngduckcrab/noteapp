// lib/src/render/ink_page_controller.dart — contract 7.2.15 (03-ink 4.8).
//
// Content diff by id + identity (6.12 R2) feeding the vector caches of the
// base layers (INK T10: ink chunk pictures R3/R4, highlighter page picture
// with the active groups left out, 6.10-6), the three gesture sessions,
// selection with its live preview pictures (6.22 / R7, INK T18:
// selection_preview.dart), pending hand-off (6.12 R6: pendingIds, updateContent
// resolution, discardPending, discardEdit, timeout), the spatial index with
// exact ink hitTest / strokeIdsInRect (6.18, INK T14), the viewport report
// of 6.12 R9 (currentBucket) and the second render cache stage (6.13 L3,
// INK T19: raster tiles of the ink chunks in the pool LRU, made one per frame
// when quiet, plus the time-sliced first recording of a page's chunks).
//
// 2nd round (contract 7.2.9, m5-7/03-ink 4.3, 4.13 — foundation step R2-B3):
// nine render layers (L-1); page objects drawn simply in their layer
// (images → underlay, shapes → ink, text boxes / formulas / unknown objects →
// annotation); (m5-7 T32b, 6.8.3) from the layer caches: the ink chunks hold
// strokes and shapes z mixed, underlay and annotation have their own chunk
// pictures (draw keys per chunk — assets, fonts, hairlines), cover one page
// picture of the tapes, and inkActive ends with the layer 4′ stage (6.1);
// select / hitTestObject / setHiddenObjectIds / setPreviewObjects (a preview
// with a committed id replaces it; previews win over hidden ids); the
// read-only getters; playback focus as state only (T40); hitTestRecorded;
// the memorization tape state (tapes still draw as ballpoint — T31).
// (m5-7 T36, 6.12.3) Formulas are drawn from the pool's raster cache: the chunk
// that drew one pins its raster (InkDrawHold), a raster that arrives records
// only the annotation chunks that drew that formula, another bucket after
// setViewport asks the page's formulas again.
import 'dart:async' show StreamSubscription, scheduleMicrotask, unawaited;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart' as meta;
import 'package:note_core/note_core.dart' as core;

import '../background/background_builder.dart';
import '../diagnostics/diagnostics.dart';
import '../diagnostics/ink_clock.dart';
import '../edit/eraser_spec.dart';
import '../edit/hit_test.dart';
import '../edit/ink_edit.dart';
import '../edit/lasso_options.dart';
import '../edit/spatial_index.dart';
import '../geometry/outline_generator.dart';
import '../geometry/stroke_outline.dart';
import '../input/ink_sample.dart';
import '../input/pressure_capability.dart';
import '../input/pressure_detector.dart';
import '../input/pressure_mode.dart';
import '../interop/core_interop.dart' as interop;
import '../math/math_raster_cache.dart';
import '../model/ink_layer.dart';
import '../model/ink_stroke.dart';
import '../object/object_painter.dart';
import '../object/object_view.dart';
import '../pen/style_ink.dart';
import '../shape/shape_assist.dart';
import '../stroke/stroke_builder.dart';
import '../stroke/stroke_meta.dart';
import '../text/fonts.dart';
import 'base_cache.dart';
import 'cache_pool.dart';
import 'highlighter_compositor.dart';
import 'ink_page_content.dart';
import 'lasso_overlay.dart';
import 'page_host.dart';
import 'pencil_grain.dart';
import 'playback.dart' show InkPlaybackFocus;
import 'raster_tiles.dart';
import 'render_config.dart';
import 'selection.dart';
import 'selection_preview.dart';
import 'sessions.dart';
import 'stroke_painter.dart';

// --- page controller --- contract 7.2.15
@immutable
final class InkCoreServices {
  const InkCoreServices({required this.newStrokeId, required this.nowMillis});

  /// from core.idGeneratorProvider
  final String Function() newStrokeId;

  /// from core.clockProvider
  final core.EpochMillis Function() nowMillis;

  @override
  bool operator ==(Object other) =>
      other is InkCoreServices &&
      other.newStrokeId == newStrokeId &&
      other.nowMillis == nowMillis;

  @override
  int get hashCode => Object.hash(newStrokeId, nowMillis);
}

/// (v2.0) L-1, bottom → top. Layer 4′ (playback emphasis, shape assist preview) is the last
/// step of the inkActive painter, not a value (m5-7/03-ink 4.1).
enum InkRenderLayer {
  background,
  underlay,
  highlighterBase,
  highlighterActive,
  inkBase,
  inkActive,
  annotation,
  cover,
  overlay,
}

InkShapeFitter _noShapeFitter() => const NoShapeFitter();

@immutable
final class InkPageRenderStats {
  const InkPageRenderStats({
    required this.strokeCount,
    required this.chunkPictures,
    required this.rasterTiles,
    required this.rasterBytes,
    required this.pendingCommits,
    required this.currentBucket,
  });
  final int strokeCount;
  final int chunkPictures;
  final int rasterTiles;
  final int rasterBytes;
  final int pendingCommits;
  final double? currentBucket;

  @override
  bool operator ==(Object other) =>
      other is InkPageRenderStats &&
      other.strokeCount == strokeCount &&
      other.chunkPictures == chunkPictures &&
      other.rasterTiles == rasterTiles &&
      other.rasterBytes == rasterBytes &&
      other.pendingCommits == pendingCommits &&
      other.currentBucket == currentBucket;

  @override
  int get hashCode => Object.hash(
    strokeCount,
    chunkPictures,
    rasterTiles,
    rasterBytes,
    pendingCommits,
    currentBucket,
  );

  @override
  String toString() =>
      'InkPageRenderStats(strokes $strokeCount, pending $pendingCommits, '
      'bucket $currentBucket)';
}

/// Hub for one page: content snapshot, render caches, gesture sessions, selection.
final class InkPageController extends ChangeNotifier {
  InkPageController({
    required this.pageId,
    required this.services,
    required this.config,
    required this.cachePool,
    required this.pressureStore,
    required this.pressureMode,
    required this.diagnostics,
    required this.clock,
    required this.pencilGrain,
    required List<PageBackgroundLayerBuilder> backgroundBuilders,
    this.shapeFitter = _noShapeFitter,
  }) : _backgroundBuilders = List.unmodifiable(backgroundBuilders) {
    _host = _Host(this);
    _render = InkPageRender._(this);
    for (final layer in InkRenderLayer.values) {
      _repaints[layer] = _Repaint();
    }
    _removePictureCount = addChunkPictureCount(
      cachePool,
      () => _chunks.pictureCount,
    );
  }

  final String pageId;
  final InkCoreServices services;
  final InkRenderConfig config;
  final InkCachePool cachePool;
  final PressureCapabilityStore pressureStore;

  /// read at every beginStroke
  final PressureMode Function() pressureMode;
  final InkDiagnostics diagnostics;
  final InkClock clock;
  final PencilGrain pencilGrain;

  /// (v2.0) read at every beginStroke with ShapeAssist.holdToSnap (inkShapeFitterProvider —
  /// a changed override applies from the next stroke, S-12)
  final InkShapeFitter Function() shapeFitter;
  final List<PageBackgroundLayerBuilder> _backgroundBuilders;
  List<PageBackgroundLayerBuilder> get backgroundBuilders =>
      _backgroundBuilders;

  late final _Host _host;
  late final InkPageRender _render;
  final Map<InkRenderLayer, _Repaint> _repaints = {};
  InkPageContent? _content;
  InkGestureSession? _active;
  InkSelection? _selection;
  final List<_Pending> _pending = [];
  _Display? _display;
  bool _disposed = false;

  // base-layer vector caches (6.12 R2–R4, 6.10-6/-7, 6.13 L2/L4)
  late final InkChunkCache _chunks = InkChunkCache(
    chunkSizePt: config.chunkSizePt,
    maxAppended: config.maxAppendedPictures,
    onChunkCleared: _tiles.dropChunk,
  );
  late final void Function() _removePictureCount;

  // raster tiles (6.13 L3, INK T19)
  late final PageRasterTiles _tiles = PageRasterTiles(
    rasterTileLruOf(cachePool),
    config.scaleBuckets,
  );
  late final RasterScheduler _rasterSchedule = RasterScheduler(
    idleMs: config.idleBeforeRasterMs,
    settleMs: config.zoomSettleMs,
    releaseMs: config.releaseInvisibleAfterMs,
    onQuiet: _rasterQuiet,
    onRelease: _releaseInvisibleTiles,
  );
  final InkBaseStats _baseStats = InkBaseStats();
  bool _baseFrameRequested = false;

  /// Chunk indices, visible ones first (6.13-3), for [_chunkOrderRect].
  List<int>? _chunkOrder;
  ui.Rect? _chunkOrderRect;

  /// The view's visible rect at paint time: the loading order of the first
  /// frames, before the first setViewport report (6.12 R9 ④).
  ui.Rect? _paintVisibleHint;
  final HighlighterBaseCache _hl = HighlighterBaseCache();

  /// R7 selection preview pictures (6.22).
  late final SelectionPreviewCache _selectionPreview = SelectionPreviewCache(
    budgetUs: config.frameWorkBudgetMs * 1000,
    nowUs: clock.nowUs,
    requestFrame: _requestActiveInkFrame,
  );
  bool _activeInkFrameRequested = false;

  /// The ids the base caches were last told to leave out (display.hidden).
  Set<String> _baseHidden = const {};

  // (m5-7 T32b, 6.8.3) the object layer caches: underlay (images) and annotation (text
  // boxes, formulas, unknown objects) chunk pictures — no raster tiles — and the cover
  // layer's page picture of the tapes
  late final InkChunkCache _underlay = InkChunkCache(
    chunkSizePt: config.chunkSizePt,
    maxAppended: config.maxAppendedPictures,
    drawKeysOf: _objectDrawKeys,
  );
  late final InkChunkCache _annotation = InkChunkCache(
    chunkSizePt: config.chunkSizePt,
    maxAppended: config.maxAppendedPictures,
    drawKeysOf: _objectDrawKeys,
  );
  final CoverPictureCache _cover = CoverPictureCache();

  /// The objects the base caches were last told to leave out (display.objectsHidden).
  Set<String> _baseObjectsHidden = const {};

  /// The zoom octave (a power of two of the view scale) the hairlines of the cached
  /// object pictures were drawn at (InkDrawKeys.hairline).
  double _hairlineScale = 1;

  /// (T32b, tests) Drawn by the layer 4′ stage after everything else of inkActive.
  void Function(ui.Canvas canvas)? _debugEndStage;

  /// A chunk was recorded with a pencil stroke before the grain was ready.
  bool _chunksMissingGrain = false;

  /// 6.18: built on first use, then kept up to date from the R2 diff.
  StrokeSpatialIndex? _spatial;

  // (v2.0) objects, playback, tapes (m5-7/03-ink 4.3, 4.10)
  Set<String> _hiddenObjectIds = const {};
  List<core.PageObject> _previewObjects = const [];
  InkPlaybackFocus? _playbackFocus;
  final Set<String> _revealedTapes = {};

  /// (T34) An implicit NoteSans load this controller started or joined is running.
  bool _fontsWaiting = false;

  /// (T34) A text box was drawn with the system font: listening for the fonts.
  bool _fontsListening = false;

  // (T36, 6.12.3) formula rasters: the pool's cache, its change notices (listened to
  // once a formula was drawn), the formulas the live part drew in the last paint, the
  // formulas warned about as invalid, the bucket the formulas were last asked at
  late final MathRasterCache _math = mathRasterCacheOf(cachePool);
  StreamSubscription<MathRasterChange>? _mathChanges;
  final Set<MathFormula> _liveMath = {};
  final Set<String> _mathInvalidWarned = {};
  double? _mathBucket;

  // viewport (6.12 R9)
  ui.Rect? _visiblePageRect;
  double? _deviceScale;
  bool _isScaling = false;
  double? _bucket;

  // --- content -----------------------------------------------------------
  InkPageContent? get content => _content;

  /// Diffs by id + identity (6.12 R2, K-4); same revision and same list → no-op.
  /// Resolves pending edits whose result is now visible (R6). content.pageId != pageId → ArgumentError.
  void updateContent(InkPageContent content) {
    _checkNotDisposed();
    if (content.pageId != pageId) {
      throw ArgumentError.value(
        content.pageId,
        'content.pageId',
        'this controller draws page $pageId',
      );
    }
    final old = _content;
    if (old != null && old == content) return;
    final pageChanged =
        old == null ||
        old.page.size != content.page.size ||
        old.page.background != content.page.background;
    final diff = InkContentDiff.between(old, content);
    _content = content;
    _revealedTapes.removeWhere((id) => !_isTapeId(content, id));
    _applyDiff(diff, content);
    _resolvePending(content);
    _pruneTimedOut();
    _refreshSelection(content);
    _invalidate();
    if (pageChanged) notifyListeners();
  }

  // --- sessions (one active at a time; starting a new one cancels the previous) ---
  InkGestureSession? get activeSession {
    final s = _active;
    return s != null && s.isActive ? s : null;
  }

  /// (v1.1) viewScale (all three sessions) = logical px per page pt at gesture start
  /// (no devicePixelRatio, no ancestor transform). INK's screen-distance thresholds use it.
  /// viewScale: logical px per page pt (no devicePixelRatio; the device scale reaches
  /// setViewport through InkPageView, never from EDITOR).
  /// beginStroke: [style] is normalized() here; pen-down time for createdAt =
  /// services.nowMillis() (now).
  /// (v2.0) [shapeAssist]: StrokeSession.shapeAssist returns it as given; holdToSnap reads
  /// [shapeFitter] now (ignored for highlighter, laser and tape). R2-B3: the hold is not
  /// detected yet (shapePreview stays null — T39).
  StrokeSession beginStroke(
    InkSample first, {
    required core.StrokeStyle style,
    required double viewScale,
    InkStrokeMeta meta = const InkStrokeMeta(),
    ShapeAssist shapeAssist = ShapeAssist.off,
  }) {
    _beginGesture(viewScale);
    final kind = first.kind;
    final mode = pressureMode();
    final prior = pressureStore.capabilityOf(kind);
    // 6.4: the detector reports its decisions to the store as it makes them.
    final detector = PressureDetector(
      kind: kind,
      mode: mode,
      prior: prior,
      store: pressureStore,
    );
    final builder = StrokeBuilder(
      style: style,
      viewScale: viewScale,
      pressure: detector,
      meta: meta,
    );
    final penDownMillis = services.nowMillis();
    builder.add(first);
    final fitter =
        shapeAssist == ShapeAssist.holdToSnap && shapeAssistAllowed(style.tool)
        ? shapeFitter()
        : null;
    final session = newStrokeSession(
      _host,
      builder,
      penDownMillis,
      shapeAssist: shapeAssist,
      fitter: fitter,
    );
    _active = session;
    diagnostics
      ..onSamples([first], receiveUs: clock.nowUs())
      ..onWidthFactor(
        1.0,
        detector.source,
        pressureStore.capabilityOf(InkPointerKind.stylus),
      );
    _sessionStarted();
    return session;
  }

  /// [spec].radius must be > 0 (ArgumentError).
  EraserSession beginErase(
    InkSample first, {
    required EraserSpec spec,
    required double viewScale,
  }) {
    if (!(spec.radius > 0)) {
      throw ArgumentError.value(spec.radius, 'spec.radius', 'must be > 0');
    }
    _beginGesture(viewScale);
    final session = newEraserSession(_host, spec, first.position);
    _active = session;
    diagnostics.onSamples([first], receiveUs: clock.nowUs());
    _sessionStarted();
    return session;
  }

  LassoSession beginLasso(
    ui.Offset firstPagePoint, {
    required double viewScale,
    LassoOptions options = const LassoOptions(),
  }) {
    _beginGesture(viewScale);
    final session = newLassoSession(_host, firstPagePoint, viewScale, options);
    _active = session;
    _sessionStarted();
    return session;
  }

  void _beginGesture(double viewScale) {
    _checkNotDisposed();
    if (!(viewScale > 0) || viewScale.isInfinite) {
      throw ArgumentError.value(viewScale, 'viewScale', 'must be > 0');
    }
    final previous = _active;
    if (previous != null && previous.isActive) previous.cancel();
    _pruneTimedOut();
  }

  void _sessionStarted() {
    _invalidate();
    notifyListeners();
  }

  // --- selection ---------------------------------------------------------
  InkSelection? get selection => _selection;

  /// ids may mix strokes and objects; unknown ids ignored.
  /// Ids not on this page are ignored; replaces the current selection; the result is in z
  /// order whatever the input order. An empty result clears the selection and returns an
  /// empty InkSelection (isEmpty).
  InkSelection select(Set<String> elementIds) {
    _checkNotDisposed();
    final content = _content;
    final elements = <core.PageElement>[
      if (content != null) ...[
        for (final s in content.strokes)
          if (elementIds.contains(s.id)) s.source,
        for (final o in content.objects)
          if (elementIds.contains(o.id)) o,
      ],
    ]..sort(core.Stroke.compareOrder);
    if (elements.isEmpty) {
      clearSelection();
      return newInkSelection(_host, const []);
    }
    return _setSelection(newInkSelection(_host, elements.map((e) => e.id)));
  }

  void clearSelection() {
    final old = _selection;
    if (old == null) return;
    disposeInkSelection(old);
    _selection = null;
    _invalidate();
    if (!_disposed) notifyListeners();
  }

  InkSelection _setSelection(InkSelection selection) {
    final old = _selection;
    if (old != null) disposeInkSelection(old);
    _selection = selection;
    _invalidate();
    notifyListeners();
    return selection;
  }

  // --- queries -------------------------------------------------------------
  /// Topmost stroke whose ink lies within [tolerance] pt of [pagePoint] (eyedropper, tap).
  /// 6.18: spatial index candidates → exact ink distance (radiusAt per point;
  /// highlighter width / 2) → the largest z. Strokes hidden by a pending erase
  /// or delete are skipped.
  InkStroke? hitTest(
    ui.Offset pagePoint, {
    double tolerance = 4.0,
    core.StrokeFilter filter = core.StrokeFilter.all,
  }) {
    final content = _content;
    if (content == null || !pagePoint.isFinite) return null;
    final radius = tolerance > 0 && tolerance.isFinite ? tolerance : 0.0;
    final candidates = [
      for (final s in _strokesNear(
        ui.Rect.fromCircle(center: pagePoint, radius: radius),
      ))
        if (interop.filterAccepts(filter, s.style.tool)) s,
    ];
    return InkHitTest.topmostAt(
      candidates,
      pagePoint,
      radius,
      zOf: (s) => content.zIndexOf(s.id),
    );
  }

  /// Topmost object at the point (annotation → ink → underlay); UnknownObject included.
  /// (v2.0, 03-ink 4.10) Hidden objects count (the text box under EDITOR's editor can be
  /// tapped again); previews and pending-removed objects do not. Within a layer the
  /// larger z wins. R2-B3: the frame (shapes too) contains the point within [tolerance].
  core.PageObject? hitTestObject(
    ui.Offset pagePoint, {
    double tolerance = 4.0,
  }) {
    final content = _content;
    if (content == null || !pagePoint.isFinite) return null;
    final tol = tolerance > 0 && tolerance.isFinite ? tolerance : 0.0;
    final p = core.PagePoint(pagePoint.dx, pagePoint.dy);
    for (final layer in const [
      InkObjectLayer.annotation,
      InkObjectLayer.ink,
      InkObjectLayer.underlay,
    ]) {
      final objects = _objectsOfLayer(content, layer);
      for (var i = objects.length - 1; i >= 0; i--) {
        final o = objects[i];
        if (_isPendingRemoved(o.id)) continue;
        if (o.frame.contains(p, tolerance: tol)) return o;
      }
    }
    return null;
  }

  /// Not drawn (e.g. the text box under EDITOR's EditableText). Selection still sees them.
  /// Ids not on the page are kept (an object arriving later starts hidden); the same set
  /// again does nothing.
  void setHiddenObjectIds(Set<String> ids) {
    _checkNotDisposed();
    if (_hiddenObjectIds.length == ids.length &&
        _hiddenObjectIds.containsAll(ids)) {
      return;
    }
    _hiddenObjectIds = Set.unmodifiable(ids);
    _invalidateObjectDisplay();
  }

  /// Transient objects drawn with the same renderer (shape tool drag, vertex drag, image being
  /// placed). An entry whose id equals a committed object REPLACES it on screen; the others are
  /// drawn in their L-1 layer. (v2.1) A preview is drawn even when its id is hidden (preview wins
  /// over setHiddenObjectIds). Empty list = none. Never stored, never exported.
  /// Every object must be on this page (ArgumentError). Hit tests, selection, exports and
  /// thumbnails never see previews.
  void setPreviewObjects(List<core.PageObject> objects) {
    _checkNotDisposed();
    for (final o in objects) {
      if (o.pageId != pageId) {
        throw ArgumentError.value(
          o.pageId,
          'objects',
          'preview object ${o.id} belongs to another page than $pageId',
        );
      }
    }
    if (objects.isEmpty && _previewObjects.isEmpty) return;
    _previewObjects = List.unmodifiable(objects);
    _invalidateObjectDisplay();
  }

  // (v2.1) read-only views of what was set (EDITOR tests observe their own calls — EDITOR M-1)
  /// The last set given to setHiddenObjectIds (unmodifiable, absent ids included).
  Set<String> get hiddenObjectIds => _hiddenObjectIds;

  /// The last list given to setPreviewObjects (unmodifiable, duplicates included).
  List<core.PageObject> get previewObjects => _previewObjects;

  /// The last value given to setPlaybackFocus (as given); null = off.
  InkPlaybackFocus? get playbackFocus => _playbackFocus;

  // playback (M6)
  /// null = off (K-7). The same value again does nothing. R2-B3: state only (T40 draws it).
  void setPlaybackFocus(InkPlaybackFocus? focus) {
    _checkNotDisposed();
    if (focus == _playbackFocus) return;
    _playbackFocus = focus;
    _repaints[InkRenderLayer.inkActive]!.fire();
  }

  /// Topmost stroke linked to a recording ([recordingId] when given, else any) whose ink is
  /// within [tolerance] pt of [pagePoint] (every tool, tape included; the exact distance of
  /// hitTest). Pending-removed strokes are skipped.
  InkStroke? hitTestRecorded(
    ui.Offset pagePoint, {
    String? recordingId,
    double tolerance = 8.0,
  }) {
    final content = _content;
    if (content == null || !pagePoint.isFinite) return null;
    final radius = tolerance > 0 && tolerance.isFinite ? tolerance : 0.0;
    final candidates = [
      for (final s in _strokesNear(
        ui.Rect.fromCircle(center: pagePoint, radius: radius),
      ))
        if (s.source.recordingId case final id?)
          if (recordingId == null || id == recordingId) s,
    ];
    return InkHitTest.topmostAt(
      candidates,
      pagePoint,
      radius,
      zOf: (s) => content.zIndexOf(s.id),
    );
  }

  // memorization tape (state per controller, never stored — U10)
  /// Topmost tape stroke whose CORE bounds contain [pagePoint] (R2-B3: bounds — T31 uses
  /// the band). Pending-removed tapes are skipped.
  InkStroke? hitTestTape(ui.Offset pagePoint) {
    final content = _content;
    if (content == null || !pagePoint.isFinite) return null;
    InkStroke? best;
    var bestZ = -1;
    for (final s in _strokesNear(
      ui.Rect.fromLTWH(pagePoint.dx, pagePoint.dy, 0, 0),
    )) {
      if (s.style.tool != core.PenTool.tape) continue;
      final b = s.bounds;
      if (pagePoint.dx < b.left ||
          pagePoint.dx > b.right ||
          pagePoint.dy < b.top ||
          pagePoint.dy > b.bottom) {
        continue;
      }
      final z = content.zIndexOf(s.id);
      if (z > bestZ) {
        bestZ = z;
        best = s;
      }
    }
    return best;
  }

  /// false for ids that are not tapes of this page.
  bool isTapeRevealed(String strokeId) {
    final content = _content;
    return content != null &&
        _revealedTapes.contains(strokeId) &&
        _isTapeId(content, strokeId);
  }

  /// Covered ↔ revealed; ids that are not tapes of this page are ignored.
  void toggleTape(String strokeId) {
    _checkNotDisposed();
    final content = _content;
    if (content == null || !_isTapeId(content, strokeId)) return;
    if (!_revealedTapes.remove(strokeId)) _revealedTapes.add(strokeId);
    _cover.markDirty();
    _repaints[InkRenderLayer.cover]!.fire();
  }

  /// Applies to the tapes present now; tapes that arrive later start covered. (v2.1) EDITOR keeps
  /// the note-level 'show all' and re-applies it after every updateContent. Lifetime = controller.
  void setAllTapesRevealed(bool revealed) {
    _checkNotDisposed();
    if (revealed) {
      final content = _content;
      if (content != null) {
        for (final s in content.strokes) {
          if (s.style.tool == core.PenTool.tape) _revealedTapes.add(s.id);
        }
      }
    } else {
      _revealedTapes.clear();
    }
    _cover.markDirty();
    _repaints[InkRenderLayer.cover]!.fire();
  }

  static bool _isTapeId(InkPageContent content, String id) =>
      content.strokeById(id)?.style.tool == core.PenTool.tape;

  static List<core.PageObject> _objectsOfLayer(
    InkPageContent content,
    InkObjectLayer layer,
  ) => switch (layer) {
    InkObjectLayer.underlay => underlayObjectsOf(content),
    InkObjectLayer.ink => inkObjectsOf(content),
    InkObjectLayer.annotation => annotationObjectsOf(content),
  };

  /// The committed objects whose CORE bounds meet [pageRect] (closed), z order, without the
  /// pending-removed ones (R2-B3: a scan).
  List<core.PageObject> _objectsNear(ui.Rect pageRect) {
    final content = _content;
    if (content == null) return const [];
    return [
      for (final o in content.objects)
        if (!_isPendingRemoved(o.id) &&
            interop.rectOf(o.bounds).overlaps(pageRect.inflate(1e-9)))
          o,
    ];
  }

  /// Ids (z-order) of the strokes whose ink meets [pageRect] (closed; 6.18
  /// exact test). Strokes hidden by a pending erase or delete are left out.
  List<String> strokeIdsInRect(ui.Rect pageRect) {
    final content = _content;
    if (content == null) return const [];
    final hits = [
      for (final s in _strokesNear(pageRect))
        if (InkHitTest.rectTouches(s, pageRect)) s,
    ]..sort((a, b) => content.zIndexOf(a.id).compareTo(content.zIndexOf(b.id)));
    return [for (final s in hits) s.id];
  }

  /// 6.18: the committed strokes whose CORE bounds meet [pageRect] (closed),
  /// without those a pending edit hides; no particular order.
  List<InkStroke> _strokesNear(ui.Rect pageRect) {
    final content = _content;
    if (content == null) return const [];
    final index = _spatial ??= StrokeSpatialIndex.of(
      content.pageSize,
      content.strokes,
    );
    return [
      for (final s in index.query(pageRect))
        if (!_isPendingRemoved(s.id)) s,
    ];
  }

  // --- commit hand-off (6.12 R6) — pendingIds / discardPending / discardEdit: contract 7.2.15
  /// Ids whose display is overridden until CORE content reflects the edit
  /// (new / duplicated strokes, erased or split originals, transformed / recolored targets).
  /// (v2.0) Objects of the edit too.
  Set<String> get pendingIds => {
    for (final p in _pending) ...[
      ...p.addedIds,
      ...p.removedIds,
      ...p.targetIds,
    ],
  };

  /// Drops the pending override of ONE id only (rare). On a failed commit EDITOR calls
  /// discardEdit, not this (contract 7.2.15 v1.1).
  void discardPending(String strokeId) {
    var changed = false;
    var resetPreview = false;
    _pending.removeWhere((p) {
      changed =
          p.addedIds.remove(strokeId) |
          p.removedIds.remove(strokeId) |
          p.targetIds.remove(strokeId) |
          changed;
      if (!p.isEmpty) return false;
      resetPreview |= p.edit.kind == InkEditKind.transformStrokes;
      return true;
    });
    if (resetPreview) _resetSelectionPreview();
    if (changed) _invalidate();
  }

  /// (v1.1) EDITOR calls this when execute(edit.toCommand()) throws (ReadOnlyNoteException
  /// etc.): drops the pending display of EVERY id of [edit] (added ids, removedIds,
  /// targetIds) in the same call → erased / split strokes reappear at once, previews end.
  void discardEdit(InkEdit edit) {
    var changed = false;
    var resetPreview = false;
    _pending.removeWhere((p) {
      if (!identical(p.edit, edit) && p.edit != edit) return false;
      changed = true;
      resetPreview |= p.edit.kind == InkEditKind.transformStrokes;
      return true;
    });
    if (resetPreview || edit.kind == InkEditKind.transformStrokes) {
      _resetSelectionPreview();
    }
    if (changed || resetPreview) _invalidate();
  }

  // --- render side -----------------------------------------------------------
  /// (v1.1) Called ONLY by InkPageView from its own arguments (visiblePageRect, isScaling,
  /// deviceScale = viewScale × ancestorScale × devicePixelRatio). EDITOR never calls it;
  /// it passes ancestorScale / isScaling / visiblePageRect to InkPageView.
  /// INK timing (6.12 R9): InkPageView calls it from a post-frame callback after layout,
  /// never during build / layout. It never calls notifyListeners(); it stores the values,
  /// updates renderStats.currentBucket and the raster plan, and repaints through
  /// layerRepaint(inkBase) only if the picture must change.
  void setViewport({
    ui.Rect? visiblePageRect,
    required double deviceScale,
    required bool isScaling,
  }) {
    final visibleChanged = visiblePageRect != _visiblePageRect;
    final scaleChanged = deviceScale != _deviceScale;
    final scalingChanged = isScaling != _isScaling;
    final oldBucket = _bucket;
    _visiblePageRect = visiblePageRect;
    _deviceScale = deviceScale;
    _isScaling = isScaling;
    _bucket = scaleBucketFor(config.scaleBuckets, deviceScale);
    if (_disposed) return;
    _syncMathBucket();
    if (!config.rasterTiles) return;
    if (visibleChanged || scaleChanged) _tiles.clearEvicted();
    if (visibleChanged || scaleChanged || scalingChanged) {
      _rasterSchedule.viewportChanged(isScaling: isScaling);
    }
    if (visibleChanged) _rasterSchedule.scheduleRelease();
    // 6.13-5: another bucket keeps drawing the tiles there are (stretched);
    // only crossing the vector-only line changes the picture now.
    if ((oldBucket == null) != (_bucket == null) && _tiles.count > 0) {
      _repaints[InkRenderLayer.inkBase]!.fire();
    }
  }

  Listenable layerRepaint(InkRenderLayer layer) => _repaints[layer]!;

  InkPageRenderStats get renderStats => InkPageRenderStats(
    strokeCount: _content?.strokes.length ?? 0,
    chunkPictures: _chunks.pictureCount,
    rasterTiles: _tiles.count,
    rasterBytes: _tiles.bytes,
    pendingCommits: _pending.length,
    currentBucket: _bucket,
  );

  @override
  void dispose() {
    if (_disposed) return;
    final active = _active;
    _disposed = true;
    if (active != null && active.isActive) active.cancel();
    _active = null;
    final sel = _selection;
    if (sel != null) disposeInkSelection(sel);
    _selection = null;
    _pending.clear();
    if (_fontsListening) InkFontsDebug.removeLoadedListener(_onFontsLoaded);
    _fontsListening = false;
    unawaited(_mathChanges?.cancel());
    _mathChanges = null;
    _rasterSchedule.dispose();
    _chunks.dispose();
    _underlay.dispose();
    _annotation.dispose();
    _cover.dispose();
    _tiles.dropAll();
    _removePictureCount();
    _hl.dispose();
    _selectionPreview.dispose();
    for (final r in _repaints.values) {
      r.dispose();
    }
    super.dispose();
  }

  // --- internals -------------------------------------------------------------
  void _notify() => notifyListeners();

  void _checkNotDisposed() {
    if (_disposed) throw StateError('InkPageController($pageId) is disposed');
  }

  bool _isPendingRemoved(String id) {
    for (final p in _pending) {
      if (p.removedIds.contains(id)) return true;
    }
    return false;
  }

  void _addPending(InkEdit edit) {
    final content = _content;
    _pending.add(
      _Pending(
        edit,
        clock.nowUs(),
        targetsAtCommit: {
          for (final id in edit.targetIds)
            id: content == null ? null : _elementOf(content, id),
        },
      ),
    );
    _invalidate();
  }

  /// The committed stroke (core value) or object [id] of [content].
  static Object? _elementOf(InkPageContent content, String id) =>
      content.strokeById(id)?.source ?? objectByIdOf(content, id);

  void _resolvePending(InkPageContent content) {
    var resetPreview = false;
    _pending.removeWhere((p) {
      p.addedIds.removeWhere((id) => _elementOf(content, id) != null);
      p.removedIds.removeWhere((id) => _elementOf(content, id) == null);
      p.targetIds.removeWhere((id) {
        final now = _elementOf(content, id);
        return now == null || !identical(now, p.targetsAtCommit[id]);
      });
      if (!p.isEmpty) return false;
      resetPreview |= p.edit.kind == InkEditKind.transformStrokes;
      return true;
    });
    if (resetPreview) _resetSelectionPreview();
  }

  void _pruneTimedOut() {
    if (_pending.isEmpty) return;
    final now = clock.nowUs();
    final limitUs = config.pendingCommitTimeoutMs * 1000;
    var resetPreview = false;
    var dropped = 0;
    _pending.removeWhere((p) {
      if (now - p.createdUs <= limitUs) return false;
      dropped++;
      resetPreview |= p.edit.kind == InkEditKind.transformStrokes;
      return true;
    });
    for (var i = 0; i < dropped; i++) {
      diagnostics.onWarning('pendingCommitTimeout');
    }
    if (resetPreview) _resetSelectionPreview();
    if (dropped > 0) _invalidate();
  }

  void _resetSelectionPreview() {
    final sel = _selection;
    if (sel != null) resetSelectionPreview(sel);
  }

  void _refreshSelection(InkPageContent content) {
    final sel = _selection;
    if (sel == null) return;
    if (retainSelectionIds(sel, (id) => _elementOf(content, id) != null)) {
      return;
    }
    disposeInkSelection(sel);
    _selection = null;
    notifyListeners();
  }

  void _invalidate() {
    _display = null;
    if (_disposed) return;
    // 6.13-2 (b): input and display changes put raster tiles off
    if (config.rasterTiles) _rasterSchedule.activity();
    for (final r in _repaints.values) {
      r.fire();
    }
  }

  /// (m5-7 T38, 6.17) The hidden or the preview objects changed: only the layers whose
  /// drawing changes are told to repaint — the base layer of the committed objects that
  /// start or stop being left out of the base drawing (_syncHidden marks their chunks
  /// dirty: the chunk pictures are recorded again only when that set changes), and the
  /// live part of the object layers whose live list changed (a preview moved 60 times
  /// repaints that live part 60 times and records nothing). Strokes are not affected.
  void _invalidateObjectDisplay() {
    final before = _display;
    if (before == null || _disposed) {
      _invalidate();
      return;
    }
    _display = null;
    final after = _currentDisplay();
    final layers = <InkRenderLayer>{};
    final content = _content;
    if (content != null) {
      void base(String id) {
        final o = objectByIdOf(content, id);
        if (o != null) layers.add(_baseRenderLayerOf(objectLayerOf(o)));
      }

      for (final id in after.objectsHidden) {
        if (!before.objectsHidden.contains(id)) base(id);
      }
      for (final id in before.objectsHidden) {
        if (!after.objectsHidden.contains(id)) base(id);
      }
    }
    for (final layer in InkObjectLayer.values) {
      bool inLayer(core.PageObject o) => objectLayerOf(o) == layer;
      if (!listEquals(
        before.liveObjects.where(inLayer).toList(),
        after.liveObjects.where(inLayer).toList(),
      )) {
        layers.add(_liveRenderLayerOf(layer));
      }
    }
    if (layers.isEmpty) return;
    if (config.rasterTiles) _rasterSchedule.activity();
    for (final layer in layers) {
      _repaints[layer]!.fire();
    }
  }

  /// The render layer that draws the committed objects of [layer] (its chunk pictures).
  static InkRenderLayer _baseRenderLayerOf(InkObjectLayer layer) =>
      switch (layer) {
        InkObjectLayer.underlay => InkRenderLayer.underlay,
        InkObjectLayer.ink => InkRenderLayer.inkBase,
        InkObjectLayer.annotation => InkRenderLayer.annotation,
      };

  /// The render layer that draws the live objects of [layer] (pending, selection preview,
  /// setPreviewObjects).
  static InkRenderLayer _liveRenderLayerOf(InkObjectLayer layer) =>
      switch (layer) {
        InkObjectLayer.underlay => InkRenderLayer.underlay,
        InkObjectLayer.ink => InkRenderLayer.inkActive,
        InkObjectLayer.annotation => InkRenderLayer.annotation,
      };

  _Display _currentDisplay() {
    final cached = _display;
    if (cached != null) return cached;
    final d = _display = _computeDisplay();
    _syncHidden(d.hidden, d.objectsHidden);
    return d;
  }

  /// R2–R4: what the content change means for the base caches. Appended
  /// items (top of the z order) become small chunk pictures; everything
  /// else marks the chunks it touches dirty. Highlighters: one page picture.
  /// (m5-7 T32b, 6.8.2) The ink chunks append the top run of the merged strokes
  /// + shapes (inkAppended); underlay / annotation objects go to their own chunks;
  /// tapes (InkLayer.cover) to the cover picture.
  void _applyDiff(InkContentDiff diff, InkPageContent content) {
    if (diff.isNoop) return;
    if (diff.isReset) {
      _chunks.reset(content.pageSize);
      _underlay.reset(content.pageSize);
      _annotation.reset(content.pageSize);
      _cover.markDirty();
      _chunkOrder = null;
      _hl.markDirty();
      _spatial = null;
      return;
    }
    final spatial = _spatial;
    if (spatial != null) {
      for (final s in diff.removed) {
        spatial.remove(s.id);
      }
      diff.inserted.forEach(spatial.insert);
      diff.appended.forEach(spatial.insert);
      for (final (_, now) in diff.changed) {
        spatial.insert(now);
      }
    }
    final inkAppended = {for (final item in diff.inkAppended) item.id};
    var highlighters = diff.backgroundChanged;
    void dirty(InkStroke s) {
      switch (s.layer) {
        case InkLayer.highlighter:
          highlighters = true;
        case InkLayer.cover:
          _cover.markDirty();
        case InkLayer.ink:
          _chunks.markDirty(s.bounds);
      }
    }

    void added(InkStroke s) {
      // a new ink stroke at the top of the merged ink layer is appended below
      if (s.layer != InkLayer.ink || !inkAppended.contains(s.id)) dirty(s);
    }

    diff.inserted.forEach(added);
    diff.appended.forEach(added);
    diff.removed.forEach(dirty);
    for (final (before, now) in diff.changed) {
      dirty(before);
      dirty(now);
    }
    if (highlighters) _hl.markDirty();
    // objects (6.8.2): inserted / removed / changed → dirty where they are and were
    void objectsDirty(InkObjectDiff d, InkChunkCache cache) {
      for (final v in d.inserted) {
        cache.markDirty(v.bounds);
      }
      for (final v in d.removed) {
        cache.markDirty(v.bounds);
      }
      for (final (before, now) in d.changed) {
        cache
          ..markDirty(before.bounds)
          ..markDirty(now.bounds);
      }
    }

    objectsDirty(diff.underlay, _underlay);
    objectsDirty(diff.shapes, _chunks);
    objectsDirty(diff.annotation, _annotation);
    if (diff.backgroundChanged) {
      // the placeholders take their tint from the paper (6.11.5)
      _underlay.markAllDirty();
      _annotation.markAllDirty();
    }
    // appended: the ink layer's top run (strokes + shapes, z mixed), the others' own
    for (final item in diff.inkAppended) {
      final hidden = switch (item) {
        InkStrokeItem() => _baseHidden.contains(item.id),
        InkObjectView() => _baseObjectsHidden.contains(item.id),
      };
      if (!hidden) _chunks.append(item, _drawInkItem);
    }
    for (final v in diff.underlay.appended) {
      if (!_baseObjectsHidden.contains(v.id)) _underlay.append(v, _drawObject);
    }
    for (final v in diff.annotation.appended) {
      if (!_baseObjectsHidden.contains(v.id)) {
        _annotation.append(v, _drawObject);
      }
    }
  }

  /// R7: ids that start or stop being hidden (pending erase, previews,
  /// discarded edits) mark the base pictures they appear in dirty. (m5-7 T32b) Objects
  /// too ([objectsHidden]: hidden ids, pending, transformed, replaced by a preview).
  void _syncHidden(Set<String> hidden, Set<String> objectsHidden) {
    final content = _content;
    if (content != null) {
      var highlighters = false;
      void touch(String id) {
        final s = content.strokeById(id);
        if (s == null) return;
        switch (s.layer) {
          case InkLayer.highlighter:
            highlighters = true;
          case InkLayer.cover:
            _cover.markDirty();
          case InkLayer.ink:
            _chunks.markDirty(s.bounds);
        }
      }

      void touchObject(String id) {
        final o = objectByIdOf(content, id);
        if (o == null) return;
        final v = InkObjectView.of(o);
        _objectCache(v.layer).markDirty(v.bounds);
      }

      for (final id in hidden) {
        if (!_baseHidden.contains(id)) touch(id);
      }
      for (final id in _baseHidden) {
        if (!hidden.contains(id)) touch(id);
      }
      for (final id in objectsHidden) {
        if (!_baseObjectsHidden.contains(id)) touchObject(id);
      }
      for (final id in _baseObjectsHidden) {
        if (!objectsHidden.contains(id)) touchObject(id);
      }
      if (highlighters) _hl.markDirty();
    }
    _baseHidden = hidden;
    _baseObjectsHidden = objectsHidden;
  }

  /// The chunk cache of an object layer (shapes: the ink chunks).
  InkChunkCache _objectCache(InkObjectLayer layer) => switch (layer) {
    InkObjectLayer.underlay => _underlay,
    InkObjectLayer.ink => _chunks,
    InkObjectLayer.annotation => _annotation,
  };

  /// One item of the ink chunks: a committed ink stroke or a shape (z mixed, 6.8.1).
  void _drawInkItem(ui.Canvas canvas, InkLayerItem item) {
    switch (item) {
      case InkStrokeItem(:final stroke):
        _drawInk(canvas, stroke);
      case InkObjectView():
        _drawObject(canvas, item);
    }
  }

  /// One object into a chunk picture (or the live part): the R2-B3 painter, the hairlines
  /// at the recorded zoom octave (InkDrawKeys.hairline). Never throws (4.0).
  void _drawObject(ui.Canvas canvas, InkLayerItem item) {
    if (item is! InkObjectView) return;
    final o = item.object;
    if (o is core.TextBoxObject) _wantFonts();
    final paper = _content?.background.paperColorArgb ?? core.PaperColors.white;
    if (!paintObjectSimple(
      canvas,
      o,
      paperArgb: paper,
      onePx: 1 / _hairlineScale,
      mathRasterOf: _mathRasterFor,
    )) {
      diagnostics.onWarning('objectPaintFailed');
    }
  }

  /// (6.8.3, 6.11.3) What an object's chunk picture depends on besides the object: its
  /// image asset, NoteSans when it is not loaded yet, the hairline width, (T36) the
  /// formula (its raster at some bucket or its placeholder) and the hold that pins the
  /// raster the chunk draws (an invalid formula: the hairline placeholder).
  Iterable<Object> _objectDrawKeys(InkLayerItem item) sync* {
    if (item is! InkObjectView) return;
    switch (item.object) {
      case core.ImageObject(:final assetId):
        yield InkDrawKeys.asset(assetId);
        yield InkDrawKeys.hairline;
      case core.TextBoxObject():
        if (!InkFontsDebug.isLoaded) yield InkDrawKeys.fonts;
      case core.UnknownObject():
        yield InkDrawKeys.hairline;
      case final core.MathObject o:
        if (!isRenderableMath(o)) {
          yield InkDrawKeys.hairline;
          break;
        }
        final f = mathFormulaOf(o);
        yield InkDrawKeys.math(f.latex, f.colorArgb, f.fontSizePt);
        final raster = _mathRasterFor(o);
        if (raster != null) yield _math.holdOf(raster);
      case core.ShapeObject():
        break;
    }
  }

  /// (T36, 6.12.3) The raster to draw [o] with now (null → the placeholder): asks the
  /// pool's cache at this view's bucket (a missing one is queued; the chunks that drew
  /// the formula are recorded again when it arrives — _onMathChange). A formula that does
  /// not parse warns mathInvalid once per object (6.24).
  MathRaster? _mathRasterFor(core.MathObject o) {
    if (_disposed) return null;
    if (!isRenderableMath(o)) {
      if (_mathInvalidWarned.add(o.id)) diagnostics.onWarning('mathInvalid');
      return null;
    }
    _mathChanges ??= _math.changes.listen(_onMathChange);
    final r = o.frame.rect;
    return _math.peek(
      mathFormulaOf(o),
      deviceScale: _deviceScale,
      framePt: ui.Size(r.width, r.height),
      nowUs: clock.nowUs(),
    );
  }

  /// [_mathRasterFor] for the live part (pending, selection preview, previews): the
  /// formula is remembered so its arrival repaints the layer.
  MathRaster? _liveMathRasterFor(core.MathObject o) {
    final raster = _mathRasterFor(o);
    if (isRenderableMath(o)) _liveMath.add(mathFormulaOf(o));
    return raster;
  }

  /// (T36) A formula raster arrived: only the annotation chunks that drew that formula
  /// are recorded again (InkDrawKeys.math), the layer repaints when one did or the live
  /// part draws it. A failed raster (glyph pictures not settled) warns mathRasterFailed
  /// when this page draws the formula; its placeholder stays until the next content or
  /// bucket change asks again (after InkTuning.mathRasterRetryMs).
  void _onMathChange(MathRasterChange change) {
    if (_disposed) return;
    final f = change.formula;
    final key = InkDrawKeys.math(f.latex, f.colorArgb, f.fontSizePt);
    final live = _liveMath.contains(f);
    if (change.failed) {
      if (live || _annotation.hasKey(key)) {
        diagnostics.onWarning('mathRasterFailed');
      }
      return;
    }
    final n = _annotation.markDirtyWithKey(key);
    if (n > 0 || live) _repaints[InkRenderLayer.annotation]!.fire();
  }

  /// (T36) Another formula bucket (setViewport, not while scaling): the formulas of the
  /// page are asked at it now — each arrival records only the chunks that drew it.
  void _syncMathBucket() {
    if (_isScaling || _mathChanges == null) return;
    final bucket = _math.wantedBucket(_deviceScale);
    if (bucket == _mathBucket) return;
    final first = _mathBucket == null;
    _mathBucket = bucket;
    // the first report: the formulas drawn so far were asked at this bucket already
    if (first && bucket == _math.wantedBucket(null)) return;
    final content = _content;
    if (content == null) return;
    for (final v in objectViewsOf(content, InkObjectLayer.annotation)) {
      final o = v.object;
      if (o is core.MathObject && !_baseObjectsHidden.contains(o.id)) {
        _mathRasterFor(o);
      }
    }
  }

  /// The zoom octave of [viewScale]: the power of two nearest to it.
  static double _octaveOf(double viewScale) {
    if (!(viewScale > 0) || !viewScale.isFinite) return 1;
    final e = (math.log(viewScale) / math.ln2).round().clamp(-16, 16);
    return math.pow(2, e).toDouble();
  }

  /// Another zoom octave: the cached pictures with hairlines are recorded again.
  void _syncHairlines() {
    final octave = _octaveOf(_currentViewScale);
    if (octave == _hairlineScale) return;
    _hairlineScale = octave;
    _underlay.markDirtyWithKey(InkDrawKeys.hairline);
    _annotation.markDirtyWithKey(InkDrawKeys.hairline);
  }

  /// One committed ink stroke into a chunk picture (6.8 fill, 6.11 grain).
  void _drawInk(ui.Canvas canvas, InkStroke s) {
    ui.Image? grain;
    if (s.profile.textured) {
      grain = _grain();
      if (grain == null) _chunksMissingGrain = true;
    }
    paintFillStroke(canvas, s, cachePool.outlineFor(s), grain: grain);
  }

  _Display _computeDisplay() {
    final content = _content;
    final removed = <String>{};
    final transforms = <String, core.Affine2>{};
    final colors = <String, int>{};
    final added = <core.Stroke>[];
    // (v2.0) objects: recolored values and pending added objects
    final recolored = <String, core.PageObject>{};
    final addedObjects = <core.PageObject>[];
    for (final p in _pending) {
      removed.addAll(p.removedIds);
      for (final s in p.edit.added) {
        if (p.addedIds.contains(s.id) && content?.strokeById(s.id) == null) {
          added.add(s);
        }
      }
      for (final o in p.edit.addedObjects) {
        if (p.addedIds.contains(o.id) &&
            (content == null || objectByIdOf(content, o.id) == null)) {
          addedObjects.add(o);
        }
      }
      final m = p.edit.transform;
      if (p.edit.kind == InkEditKind.transformStrokes && m != null) {
        for (final id in p.targetIds) {
          final prior = transforms[id];
          transforms[id] = prior == null ? m : prior.then(m);
        }
      }
      final color = p.edit.colorArgb;
      if (p.edit.kind == InkEditKind.recolorStrokes && color != null) {
        for (final id in p.targetIds) {
          colors[id] = color;
        }
        for (final o in p.edit.updatedObjects) {
          if (p.targetIds.contains(o.id)) recolored[o.id] = o;
        }
      }
    }
    final active = _active;
    final previews = <core.Stroke>[];
    if (active is EraserSession && active.isActive) {
      removed.addAll(eraserTouched(active));
      removed.addAll(eraserTouchedObjects(active));
      // 6.20 P8: the pieces the partial eraser leaves, instead of the originals
      previews.addAll(eraserPreviewPieces(active));
    }
    final sel = _selection;
    final selectionPreviewIds = <String>{};
    if (sel != null && !sel.isDisposed && !sel.previewTransform.isIdentity) {
      for (final id in selectionIdsOf(sel)) {
        if (transforms.containsKey(id)) continue; // a pending transform wins
        if (content != null &&
            objectByIdOf(content, id) is core.UnknownObject) {
          continue; // an unknown object stays in place (6.14)
        }
        transforms[id] = sel.previewTransform;
        selectionPreviewIds.add(id);
      }
    }
    // (v2.0) objects drawn by the live part instead of the base drawing (6.8.4, 6.17):
    // pending / selection transforms and recolors (CORE PageObject.transformed — the
    // resolver's rule), pending added objects, then setPreviewObjects (preview wins over
    // hidden; a preview with a committed id replaces it).
    final liveObjects = <core.PageObject>[];
    final objectsHidden = <String>{..._hiddenObjectIds};
    if (content != null) {
      for (final o in content.objects) {
        if (removed.contains(o.id)) {
          objectsHidden.add(o.id);
          continue;
        }
        final m = transforms[o.id];
        final recolor = recolored[o.id];
        if (m == null && recolor == null) continue;
        objectsHidden.add(o.id);
        if (_hiddenObjectIds.contains(o.id)) continue;
        final base = recolor ?? o;
        liveObjects.add(
          m == null ? base : base.transformed(m, scaleWidth: true),
        );
      }
    }
    for (final o in addedObjects) {
      if (!_hiddenObjectIds.contains(o.id)) liveObjects.add(o);
    }
    final previewById = <String, core.PageObject>{};
    for (final o in _previewObjects) {
      previewById.remove(o.id); // the later entry of a repeated id is drawn
      previewById[o.id] = o;
    }
    objectsHidden.addAll(previewById.keys);
    liveObjects
      ..removeWhere((o) => previewById.containsKey(o.id))
      ..addAll(previewById.values);
    final overrides = <_Override>[
      if (content != null)
        for (final s in content.strokes)
          if (!removed.contains(s.id) &&
              (transforms.containsKey(s.id) || colors.containsKey(s.id)))
            _Override(
              s,
              transforms[s.id],
              colors[s.id],
              fromSelection: selectionPreviewIds.contains(s.id),
            ),
    ];
    final hidden = <String>{
      for (final id in {...removed, ...transforms.keys, ...colors.keys})
        if (content == null || content.strokeById(id) != null) id,
    };
    // 6.10-6: a group with anything being written, pending or previewed is
    // composited by the active layer only (committed lines included).
    final activeKeys = <HighlighterGroupKey>{
      for (final o in overrides)
        if (o.stroke.layer == InkLayer.highlighter)
          HighlighterGroupKey.of(o.stroke.style, colorArgb: o.colorArgb),
      for (final s in [...added, ...previews])
        if (s.style.profile.layer == InkLayer.highlighter)
          HighlighterGroupKey.of(s.style),
      if (active is StrokeSession &&
          active.isActive &&
          active.style.profile.layer == InkLayer.highlighter)
        HighlighterGroupKey.of(active.style),
    };
    return _Display(
      hidden: hidden,
      objectsHidden: objectsHidden,
      liveObjects: liveObjects,
      overrides: overrides,
      added: added,
      previews: previews,
      highlighters: [
        if (content != null)
          for (final s in content.strokes)
            if (s.layer == InkLayer.highlighter && !hidden.contains(s.id)) s,
      ],
      activeHighlighterKeys: activeKeys,
    );
  }

  void _paintLayer(ui.Canvas canvas, InkRenderLayer layer) {
    if (_disposed) return;
    final content = _content;
    final display = _currentDisplay();
    final margin = 1 / _currentViewScale; // 1 logical px (6.7 K-1 6)
    final paper = content?.background.paperColorArgb ?? core.PaperColors.white;
    switch (layer) {
      case InkRenderLayer.background:
        return;
      case InkRenderLayer.underlay:
        _paintObjects(canvas, content, display, InkObjectLayer.underlay, paper);
      case InkRenderLayer.annotation:
        _paintObjects(
          canvas,
          content,
          display,
          InkObjectLayer.annotation,
          paper,
        );
      case InkRenderLayer.cover:
        // (T32b) the page picture of the committed tapes; R2-B3: PenProfile.of(tape) is
        // still the ballpoint (ink layer), so it stays empty until T31
        if (content == null) return;
        _cover.paint(canvas, [
          for (final s in content.strokes)
            if (s.layer == InkLayer.cover && !display.hidden.contains(s.id)) s,
        ], _drawInk);
      case InkRenderLayer.highlighterBase:
        if (content == null) return;
        _hl.paintBase(
          canvas,
          display.highlighters,
          excluded: display.activeHighlighterKeys,
          paperColorArgb: paper,
          marginPt: margin,
        );
      case InkRenderLayer.inkBase:
        if (content == null) return;
        _paintInkBase(canvas, content, display);
        if (diagnostics.enabled) {
          diagnostics.onCacheStats(
            cachePool.stats,
            visibleStrokes: content.strokes.length - display.hidden.length,
          );
        }
      case InkRenderLayer.highlighterActive:
        _paintActiveHighlighters(canvas, display, paper, margin);
      case InkRenderLayer.inkActive:
        _paintActiveInk(canvas, display, margin, paper);
      case InkRenderLayer.overlay:
        final active = _active;
        if (active is! LassoSession || !active.isActive) return;
        if (active.points.length < 2) return;
        paintLassoOverlay(canvas, active.previewPath, _currentViewScale);
    }
  }

  /// 6.12 R4 + 6.13: records what the chunks miss (a newly shown page within
  /// the frame budget, visible chunks first), makes at most
  /// maxTileRastersPerFrame raster tiles when quiet and the budget is left,
  /// then draws each chunk from its tile (+ later appends) or its pictures.
  /// Unfinished work asks for the next frame.
  void _paintInkBase(
    ui.Canvas canvas,
    InkPageContent content,
    _Display display,
  ) {
    final startUs = clock.nowUs();
    final budgetUs = config.frameWorkBudgetMs * 1000;
    bool outOfTime() => clock.nowUs() - startUs >= budgetUs;
    final order = _currentChunkOrder();
    // (T32b, 6.8.1) the ink strokes and shapes merged by compareOrder
    final recorded = _chunks.record(
      [
        for (final item in inkLayerItemsOf(content))
          if (!(item is InkStrokeItem
              ? display.hidden.contains(item.id)
              : display.objectsHidden.contains(item.id)))
            item,
      ],
      _drawInkItem,
      order: order,
      outOfTime: outOfTime,
    );
    var more = !recorded;
    var tiles = 0;
    final bucket = config.rasterTiles ? _bucket : null;
    if (bucket != null && _rasterAllowed) {
      while (tiles < config.maxTileRastersPerFrame && !outOfTime()) {
        final next = _nextTileChunk(bucket, order);
        if (next == null) break;
        _rasterTile(next, bucket);
        tiles++;
      }
      more |= _nextTileChunk(bucket, order) != null;
    }
    _chunks.drawChunks(
      canvas,
      other: bucket == null ? null : (c, i) => _drawTile(c, i, bucket),
    );
    _baseStats
      ..lastPaintUs = clock.nowUs() - startUs
      ..lastPaintTiles = tiles
      ..paints += 1;
    if (more) _requestBaseFrame();
  }

  /// The chunk priority order for the visible rect (the reported one, or the
  /// view's own before the first report).
  List<int> _currentChunkOrder() {
    final visible = _deviceScale == null ? _paintVisibleHint : _visiblePageRect;
    final cached = _chunkOrder;
    if (cached != null && visible == _chunkOrderRect) return cached;
    _chunkOrderRect = visible;
    return _chunkOrder = _chunks.priorityOrder(visible);
  }

  /// 6.13-2: tiles are made only when the scheduler is quiet (idle after
  /// input, zoom settled, not scaling), with no gesture and a view attached.
  bool get _rasterAllowed =>
      !_disposed &&
      config.rasterTiles &&
      _bucket != null &&
      _rasterSchedule.quiet &&
      activeSession == null;

  /// 6.13-3: the first chunk of [order] (visible, nearest the centre) within
  /// the visible rect + 1 chunk that has strokes and no [bucket] tile.
  int? _nextTileChunk(double bucket, List<int> order) {
    final keep = _keepRect();
    for (final i in order) {
      if (_chunks.pictureOf(i) == null) continue;
      if (_chunks.strokeCountOf(i) == 0) continue;
      if (!_chunks.cellRectOf(i).overlaps(keep)) continue;
      if (_tiles.wasEvicted(i) || _tiles.has(i, bucket)) continue;
      return i;
    }
    return null;
  }

  /// The visible rect (whole page when null) + one chunk on every side
  /// (6.13-7).
  ui.Rect _keepRect() {
    final content = _content;
    final page = content == null
        ? ui.Rect.zero
        : ui.Offset.zero & content.pageSize;
    return (_visiblePageRect ?? page).inflate(config.chunkSizePt);
  }

  /// 6.13-4: the chunk picture + appended pictures → toImageSync at
  /// [bucket]; the time goes to InkDiagnostics.onTileRaster.
  void _rasterTile(int index, double bucket) {
    final start = clock.nowUs();
    final RasterTile tile;
    try {
      tile = rasterizeChunk(
        picture: _chunks.pictureOf(index)!,
        appended: _chunks.appendedOf(index),
        chunkRect: _chunks.pageRectOf(index),
        bucket: bucket,
        generation: _chunks.generationOf(index),
      );
    } on Object catch (error, stack) {
      // 4.0: the render path never throws — the chunk stays vector
      _tiles.tileEvicted((owner: _tiles, chunk: index, bucket: bucket));
      diagnostics.onWarning('tileRasterFailed');
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'ink_engine',
          context: ErrorDescription('while making a raster tile'),
        ),
      );
      return;
    }
    _tiles.store(index, tile);
    final end = clock.nowUs();
    _baseStats.tilesMade++;
    diagnostics.onTileRaster((end - start) / 1000);
  }

  /// 6.13-5: the chunk's tile (this bucket's, else another's stretched) and
  /// the pictures appended after it; false → vector.
  bool _drawTile(ui.Canvas canvas, int index, double bucket) {
    final tile = _tiles.tileFor(index, bucket, _chunks.generationOf(index));
    if (tile == null) return false;
    tile.draw(canvas);
    final appended = _chunks.appendedOf(index);
    for (var k = tile.appendedCount; k < appended.length; k++) {
      canvas.drawPicture(appended[k]);
    }
    return true;
  }

  /// The scheduler became quiet: one inkBase frame if a tile is due.
  void _rasterQuiet() {
    final bucket = _bucket;
    if (!_rasterAllowed || bucket == null || _content == null) return;
    if (_nextTileChunk(bucket, _currentChunkOrder()) != null) {
      _repaints[InkRenderLayer.inkBase]!.fire();
    }
  }

  /// 6.13-7: the tiles of chunks outside the visible rect + 1 chunk go
  /// (releaseInvisibleAfterMs after the last viewport change).
  void _releaseInvisibleTiles() {
    if (_disposed) return;
    final keep = _keepRect();
    _tiles.dropWhere((i) => !_chunks.cellRectOf(i).overlaps(keep));
  }

  /// The next inkBase frame (unfinished loading or tiles). Not during paint:
  /// after the current task.
  void _requestBaseFrame() {
    if (_baseFrameRequested) return;
    _baseFrameRequested = true;
    scheduleMicrotask(() {
      _baseFrameRequested = false;
      if (!_disposed) _repaints[InkRenderLayer.inkBase]!.fire();
    });
  }

  void _viewAttached() {
    if (_disposed || !config.rasterTiles) return;
    _rasterSchedule.attach(isScaling: _isScaling);
  }

  /// No view draws the tiles any more: they go at once.
  void _viewDetached() {
    _rasterSchedule.detach();
    if (!_disposed) _tiles.dropAll();
  }

  /// The previewed copy of an override (transform → core.Stroke.transformed).
  InkStroke _overrideStroke(_Override o) {
    final m = o.transform;
    return m == null
        ? o.stroke
        : InkStroke.of(interop.previewTransformedOf(o.stroke.source, m));
  }

  /// (v2.0) One object layer: (T32b, 6.8.3) the layer's chunk pictures of the committed
  /// objects not hidden, then the live ones (pending, selection preview,
  /// setPreviewObjects) — redrawn on every paint.
  void _paintObjects(
    ui.Canvas canvas,
    InkPageContent? content,
    _Display display,
    InkObjectLayer layer,
    int paper,
  ) {
    _syncHairlines();
    // (T34) cached text in the system font: ask for NoteSans again (after a failure's pause)
    if (_fontsListening && layer == InkObjectLayer.annotation) _wantFonts();
    if (layer == InkObjectLayer.annotation) _liveMath.clear();
    if (content != null) {
      final views = objectViewsOf(content, layer);
      if (views.isNotEmpty) {
        final cache = _objectCache(layer);
        cache.record([
          for (final v in views)
            if (!display.objectsHidden.contains(v.id)) v,
        ], _drawObject);
        cache.drawChunks(canvas);
      }
    }
    _paintObjectList(
      canvas,
      [
        for (final o in display.liveObjects)
          if (objectLayerOf(o) == layer) o,
      ],
      const {},
      paper,
    );
  }

  void _paintObjectList(
    ui.Canvas canvas,
    List<core.PageObject> objects,
    Set<String> hidden,
    int paper,
  ) {
    if (objects.isEmpty) return;
    final onePx = 1 / _currentViewScale;
    for (final o in objects) {
      if (hidden.contains(o.id)) continue;
      if (o is core.TextBoxObject) _wantFonts();
      if (!paintObjectSimple(
        canvas,
        o,
        paperArgb: paper,
        onePx: onePx,
        mathRasterOf: _liveMathRasterFor,
      )) {
        diagnostics.onWarning('objectPaintFailed');
      }
    }
  }

  /// A text box is drawn before NoteSans is there (6.10.3): it is drawn with the system
  /// font, NoteSans is loaded implicitly (7.4.5 'when first drawn') and, once loaded —
  /// by this load or anyone's — the chunks that drew a text box are recorded again
  /// (InkDrawKeys.fonts — annotation only). A failed load warns `fontLoadFailed` (6.24)
  /// and the text stays in the system font; after the 30 s pause (4.10) the next paint
  /// of the annotation layer tries again.
  void _wantFonts() {
    if (_disposed || InkFontsDebug.isLoaded) return;
    if (!_fontsListening) {
      _fontsListening = true;
      InkFontsDebug.addLoadedListener(_onFontsLoaded);
    }
    if (_fontsWaiting) return;
    final load = InkFontsDebug.loadImplicitly();
    // pausing after a failure: no load runs (the next paint asks again)
    if (!InkFontsDebug.isLoading) return;
    _fontsWaiting = true;
    unawaited(
      load.then((_) {
        _fontsWaiting = false;
        if (_disposed || InkFontsDebug.isLoaded) return;
        diagnostics.onWarning('fontLoadFailed');
      }),
    );
  }

  void _onFontsLoaded() {
    InkFontsDebug.removeLoadedListener(_onFontsLoaded);
    _fontsListening = false;
    if (_disposed) return;
    // (T32b) only the chunks that drew a text box with the system font
    _annotation.markDirtyWithKey(InkDrawKeys.fonts);
    _invalidate();
  }

  /// Ink-layer previews, pending strokes and the stroke being written (R5–R7).
  void _paintActiveInk(
    ui.Canvas canvas,
    _Display display,
    double margin,
    int paper,
  ) {
    // (v2.0) live shapes (pending, selection preview, setPreviewObjects) — (T32b) under the
    // chunk clips like the chunk pictures that take them over (R6)
    for (final o in display.liveObjects) {
      if (objectLayerOf(o) != InkObjectLayer.ink) continue;
      _chunks.paintClipped(canvas, InkObjectView.of(o), _drawLiveObject);
    }
    // Committed-looking strokes are drawn under the chunk clips, like the
    // chunk pictures that take them over (pixel-exact hand-off, R6).
    final selectionItems = <SelectionPreviewItem>[];
    core.Affine2? selectionTransform;
    for (final o in display.overrides) {
      if (o.stroke.layer != InkLayer.ink) continue;
      if (o.fromSelection) {
        // R7 / 6.22: the live selection preview has its own pictures
        selectionItems.add((stroke: o.stroke, colorArgb: o.colorArgb));
        selectionTransform = o.transform;
        continue;
      }
      final s = _overrideStroke(o);
      final outline = o.transform == null
          ? cachePool.outlineFor(s)
          : OutlineGenerator.outline(s);
      final grain = s.profile.textured ? _grain() : null;
      _chunks.paintClipped(
        canvas,
        InkStrokeItem.of(s),
        (c, _) => paintFillStroke(
          c,
          s,
          outline,
          colorArgb: o.colorArgb,
          grain: grain,
        ),
      );
    }
    if (selectionTransform == null) {
      _selectionPreview.reset();
    } else {
      _selectionPreview.paint(
        canvas,
        selectionItems,
        selectionTransform,
        grain: _grain,
        outlineOf: cachePool.outlineFor,
      );
    }
    for (final added in display.added) {
      final s = InkStroke.of(added);
      if (s.layer != InkLayer.ink) continue;
      _chunks.paintClipped(canvas, InkStrokeItem.of(s), _drawInkItem);
    }
    for (final piece in display.previews) {
      final s = InkStroke.of(piece);
      if (s.layer != InkLayer.ink) continue;
      final outline = _previewOutlines[s] ??= OutlineGenerator.outline(s);
      final grain = s.profile.textured ? _grain() : null;
      _chunks.paintClipped(
        canvas,
        InkStrokeItem.of(s),
        (c, _) => paintFillStroke(c, s, outline, grain: grain),
      );
    }
    final active = _active;
    if (active is StrokeSession &&
        active.isActive &&
        active.style.profile.layer == InkLayer.ink) {
      final start = clock.nowUs();
      final live = active.live;
      final style = active.style;
      if (!live.isEmpty) {
        paintFillPaths(
          canvas,
          [live.frozenPath, live.tailPath],
          profile: style.profile,
          colorArgb: style.colorArgb,
          opacity:
              style.opacity *
              tiltOpacityFactor(style.profile, liveMeanTiltK(live)),
          bounds: live.bounds.inflate(margin),
          grain: style.profile.textured ? _grain() : null,
        );
      }
      final end = clock.nowUs();
      diagnostics.onActivePaint(paintUs: end, updateMs: (end - start) / 1000);
    }
    _paintEndStage(canvas);
  }

  /// (v2.1, CD2-09 — 6.1) Layer 4′: the last step of inkActive, above every ink item and
  /// below the annotation and cover layers (text, formulas and covered tapes stay on
  /// top). T39 (shape assist preview) and T40 (playback emphasis) draw here.
  void _paintEndStage(ui.Canvas canvas) {
    final debug = _debugEndStage;
    if (debug != null) debug(canvas);
  }

  /// A live object (pending, selection preview, preview) with the exact one-px width of
  /// this paint.
  void _drawLiveObject(ui.Canvas canvas, InkLayerItem item) {
    if (item is! InkObjectView) return;
    _paintObjectList(
      canvas,
      [item.object],
      const {},
      _content?.background.paperColorArgb ?? core.PaperColors.white,
    );
  }

  /// The active highlighter groups (6.10-6): for each, ONE composite of its
  /// committed lines (cached opaque picture), its previews, its pending
  /// strokes and the highlighter being written — so a new stroke over a
  /// committed one of the same color never darkens the overlap.
  void _paintActiveHighlighters(
    ui.Canvas canvas,
    _Display display,
    int paper,
    double margin,
  ) {
    final keys = display.activeHighlighterKeys;
    _hl.retainGroups(keys);
    if (keys.isEmpty) return;
    // group order: lowest z of the committed lines, then the rest
    final groups = <HighlighterGroupKey, HighlighterGroup>{};
    HighlighterGroup groupOf(HighlighterGroupKey key) =>
        groups.putIfAbsent(key, () => HighlighterGroup(key));
    for (final s in display.highlighters) {
      final key = HighlighterGroupKey.of(s.style);
      if (keys.contains(key)) groupOf(key);
    }
    for (final o in display.overrides) {
      if (o.stroke.layer != InkLayer.highlighter) continue;
      groupOf(HighlighterGroupKey.of(o.stroke.style, colorArgb: o.colorArgb))
          .lines
          .add(HighlighterLine.of(_overrideStroke(o)));
    }
    for (final added in [...display.added, ...display.previews]) {
      if (added.style.profile.layer != InkLayer.highlighter) continue;
      groupOf(HighlighterGroupKey.of(added.style)).lines
          .add(HighlighterLine.of(InkStroke.of(added)));
    }
    final active = _active;
    final writing =
        active is StrokeSession &&
        active.isActive &&
        active.style.profile.layer == InkLayer.highlighter;
    final start = writing ? clock.nowUs() : 0;
    HighlighterGroupKey? liveKey;
    HighlighterLine? liveLine;
    if (writing) {
      final xy = active.live.polyline;
      if (xy != null && xy.isNotEmpty) {
        liveKey = HighlighterGroupKey.of(active.style);
        liveLine = HighlighterLine(xy, active.style.width);
        groupOf(liveKey);
      }
    }
    final blend = highlighterBlendFor(paper);
    for (final g in groups.values) {
      final committed = _hl.groupOpaque(g.key, display.highlighters);
      final line = g.key == liveKey ? liveLine : null;
      ui.Rect? extraBounds = committed?.bounds;
      final lineBounds = line?.bounds;
      if (lineBounds != null) {
        extraBounds = extraBounds == null
            ? lineBounds
            : extraBounds.expandToInclude(lineBounds);
      }
      if (g.lines.isEmpty && extraBounds == null) continue;
      paintHighlighterGroup(
        canvas,
        g,
        blend: blend,
        marginPt: margin,
        extraBounds: extraBounds,
        extra: committed == null && line == null
            ? null
            : (c, color) {
                if (committed != null) c.drawPicture(committed.picture);
                if (line != null) {
                  drawHighlighterLine(
                    c,
                    line.xy,
                    highlighterLinePaint(line.width, color),
                  );
                }
              },
      );
    }
    if (writing) {
      final end = clock.nowUs();
      diagnostics.onActivePaint(paintUs: end, updateMs: (end - start) / 1000);
    }
  }

  bool _grainWaiting = false;

  /// Outlines of the partial-eraser preview pieces (6.23: not in the pool;
  /// gone with the piece objects).
  final Expando<StrokeOutline> _previewOutlines = Expando('previewOutline');

  /// The pencil grain when ready; otherwise null (paint without grain, 6.11)
  /// and one repaint once it is ready. Only asked for when a textured stroke
  /// is painted, so pages without pencil never start the generation.
  ui.Image? _grain() {
    final image = pencilGrain.value;
    if (image == null && !_grainWaiting) {
      _grainWaiting = true;
      pencilGrain.ready.then((_) {
        if (_disposed) return;
        if (_chunksMissingGrain) {
          _chunksMissingGrain = false;
          _chunks.markAllDirty();
        }
        _invalidate();
      }, onError: (Object _) {});
    }
    return image;
  }

  /// Logical px per pt of the view being painted (set by InkPageRender.paint).
  double _currentViewScale = 1;

  /// One more inkActive frame after this one (an unfinished selection
  /// preview recording). Not during paint: after the current task.
  void _requestActiveInkFrame() {
    if (_activeInkFrameRequested) return;
    _activeInkFrameRequested = true;
    scheduleMicrotask(() {
      _activeInkFrameRequested = false;
      if (!_disposed) _repaints[InkRenderLayer.inkActive]!.fire();
    });
  }
}

/// INTERNAL render access for InkPageView (not exported).
@meta.internal
final class InkPageRender {
  InkPageRender._(this._controller);

  final InkPageController _controller;
  Object? _view;

  /// Paints [layer] in page pt (the caller already scaled the canvas by [viewScale]).
  /// [visiblePageRect]: the view's own argument — the chunk loading order of
  /// the frames before its first setViewport report (6.13 time slicing).
  void paint(
    ui.Canvas canvas,
    InkRenderLayer layer,
    double viewScale, {
    ui.Rect? visiblePageRect,
  }) {
    _controller
      .._currentViewScale = viewScale
      .._paintVisibleHint = visiblePageRect
      .._paintLayer(canvas, layer);
  }

  /// One InkPageView per controller (debug assert, 6.12 R9 ⑤). Raster
  /// tiles (6.13 L3) are made and kept only while a view is attached.
  void attachView(Object view) {
    assert(
      _view == null || identical(_view, view),
      'InkPageController(${_controller.pageId}) already has an InkPageView',
    );
    if (identical(_view, view)) return;
    _view = view;
    _controller._viewAttached();
  }

  void detachView(Object view) {
    if (!identical(_view, view)) return;
    _view = null;
    _controller._viewDetached();
  }

  ui.Rect? get visiblePageRect => _controller._visiblePageRect;
  double? get deviceScale => _controller._deviceScale;
  bool get isScaling => _controller._isScaling;
}

/// INTERNAL: the render access of [controller] (InkPageView only).
@meta.internal
InkPageRender inkPageRenderOf(InkPageController controller) =>
    controller._render;

/// INTERNAL (tests): the ink chunk pictures of [controller] (6.12 R3/R4).
@meta.internal
InkChunkCache inkChunkCacheOf(InkPageController controller) =>
    controller._chunks;

/// INTERNAL (tests): the underlay chunk pictures of [controller] (m5-7 T32b, 6.8.3).
@meta.internal
InkChunkCache inkUnderlayCacheOf(InkPageController controller) =>
    controller._underlay;

/// INTERNAL (tests): the annotation chunk pictures of [controller] (m5-7 T32b, 6.8.3).
@meta.internal
InkChunkCache inkAnnotationCacheOf(InkPageController controller) =>
    controller._annotation;

/// INTERNAL (tests): the cover page picture of [controller] (m5-7 T32b, 6.8.3).
@meta.internal
CoverPictureCache inkCoverCacheOf(InkPageController controller) =>
    controller._cover;

/// INTERNAL (tests): draws [paint] at the layer 4′ stage of [controller]'s inkActive
/// layer (m5-7 T32b, 6.1); null removes it.
@meta.internal
void debugSetInkActiveEndStage(
  InkPageController controller,
  void Function(ui.Canvas canvas)? paint,
) {
  controller._debugEndStage = paint;
  if (!controller._disposed) {
    controller._repaints[InkRenderLayer.inkActive]!.fire();
  }
}

/// INTERNAL (tests): the inkBase paint counters of [controller] (6.13).
@meta.internal
InkBaseStats inkBaseStatsOf(InkPageController controller) =>
    controller._baseStats;

/// INTERNAL (tests): the raster tiles of [controller] (6.13 L3).
@meta.internal
PageRasterTiles inkRasterTilesOf(InkPageController controller) =>
    controller._tiles;

/// INTERNAL: inkBase paint counters (6.13 time slicing and raster tiles).
@meta.internal
final class InkBaseStats {
  /// Clock time of the last inkBase paint (recording + tiles + drawing).
  int lastPaintUs = 0;

  /// Tiles made by the last inkBase paint.
  int lastPaintTiles = 0;

  /// Tiles made since the controller was created.
  int tilesMade = 0;

  /// inkBase paints since the controller was created.
  int paints = 0;
}

/// INTERNAL (tests): the R7 selection preview counters of [controller] (6.22).
@meta.internal
SelectionPreviewStats selectionPreviewStatsOf(InkPageController controller) =>
    controller._selectionPreview.stats;

/// INTERNAL (tests): the highlighter page picture of [controller] (6.10-6/-7).
@meta.internal
HighlighterBaseCache inkHighlighterCacheOf(InkPageController controller) =>
    controller._hl;

final class _Repaint extends ChangeNotifier {
  void fire() => notifyListeners();
}

final class _Pending {
  _Pending(this.edit, this.createdUs, {required this.targetsAtCommit})
    : addedIds = {
        for (final s in edit.added) s.id,
        for (final o in edit.addedObjects) o.id,
      },
      removedIds = {...edit.removedIds},
      targetIds = {...edit.targetIds};

  final InkEdit edit;
  final int createdUs;

  /// The committed stroke (core value) or object instance of each target at commit time.
  final Map<String, Object?> targetsAtCommit;
  final Set<String> addedIds;
  final Set<String> removedIds;
  final Set<String> targetIds;

  bool get isEmpty =>
      addedIds.isEmpty && removedIds.isEmpty && targetIds.isEmpty;
}

final class _Override {
  _Override(
    this.stroke,
    this.transform,
    this.colorArgb, {
    required this.fromSelection,
  });
  final InkStroke stroke;
  final core.Affine2? transform;
  final int? colorArgb;

  /// [transform] is the live selection preview (not a pending edit).
  final bool fromSelection;
}

final class _Display {
  _Display({
    required this.hidden,
    required this.objectsHidden,
    required this.liveObjects,
    required this.overrides,
    required this.added,
    required this.previews,
    required this.highlighters,
    required this.activeHighlighterKeys,
  });

  /// Strokes left out of the base caches.
  final Set<String> hidden;

  /// (v2.0) Committed objects left out of the base drawing (hidden ids, pending removed,
  /// transformed / recolored, replaced by a preview).
  final Set<String> objectsHidden;

  /// (v2.0) Objects drawn by the live part of their layer.
  final List<core.PageObject> liveObjects;
  final List<_Override> overrides;
  final List<core.Stroke> added;

  /// Memory-only partial-eraser pieces (6.20 P8): outlines never enter the
  /// cache pool.
  final List<core.Stroke> previews;

  /// Committed highlighters not hidden, z order.
  final List<InkStroke> highlighters;

  /// Groups composited by highlighterActive instead of highlighterBase (6.10-6).
  final Set<HighlighterGroupKey> activeHighlighterKeys;
}

final class _Host implements InkPageHost {
  _Host(this._c);
  final InkPageController _c;

  @override
  String get pageId => _c.pageId;
  @override
  InkCoreServices get services => _c.services;
  @override
  InkClock get clock => _c.clock;
  @override
  InkDiagnostics get diagnostics => _c.diagnostics;
  @override
  PressureCapability get stylusCapability =>
      _c.pressureStore.capabilityOf(InkPointerKind.stylus);
  @override
  InkPageContent? get content => _c._content;
  @override
  bool isPendingRemoved(String id) => _c._isPendingRemoved(id);
  @override
  List<InkStroke> strokesNear(ui.Rect pageRect) => _c._strokesNear(pageRect);
  @override
  List<core.PageObject> objectsNear(ui.Rect pageRect) =>
      _c._objectsNear(pageRect);
  @override
  void addPending(InkEdit edit) => _c._addPending(edit);

  @override
  void repaint(InkRenderLayer layer) {
    if (_c._disposed) return;
    _c._repaints[layer]!.fire();
  }

  @override
  void displayChanged() => _c._invalidate();

  @override
  void sessionEnded(InkGestureSession session) {
    if (!identical(_c._active, session)) return;
    _c._active = null;
    _c._invalidate();
    if (!_c._disposed) _c._notify();
  }

  @override
  void lassoSelected(InkSelection selection) {
    if (_c._disposed) return;
    _c._setSelection(selection);
  }
}
