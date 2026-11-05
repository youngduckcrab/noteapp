// lib/src/render/ink_page_controller.dart — contract 7.2.15 (03-ink 4.8).
//
// Content diff by id + identity (6.12 R2) feeding the vector caches of the
// base layers (INK T10: ink chunk pictures R3/R4, highlighter page picture
// with the active groups left out, 6.10-6), the three gesture sessions,
// selection, pending hand-off (6.12 R6: pendingIds, updateContent
// resolution, discardPending, discardEdit, timeout), bounds-based hitTest /
// strokeIdsInRect (exact: INK T14) and the viewport report of 6.12 R9
// (currentBucket). Raster tiles come with INK T19.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart' as meta;
import 'package:note_core/note_core.dart' as core;

import '../background/background_builder.dart';
import '../diagnostics/diagnostics.dart';
import '../diagnostics/ink_clock.dart';
import '../edit/eraser_spec.dart';
import '../edit/ink_edit.dart';
import '../edit/lasso_options.dart';
import '../geometry/outline_generator.dart';
import '../input/ink_sample.dart';
import '../input/pressure_capability.dart';
import '../input/pressure_detector.dart';
import '../input/pressure_mode.dart';
import '../interop/core_interop.dart' as interop;
import '../model/ink_layer.dart';
import '../model/ink_stroke.dart';
import '../pen/style_ink.dart';
import '../stroke/stroke_builder.dart';
import '../stroke/stroke_meta.dart';
import '../tuning.dart';
import 'base_cache.dart';
import 'cache_pool.dart';
import 'highlighter_compositor.dart';
import 'ink_page_content.dart';
import 'page_host.dart';
import 'pencil_grain.dart';
import 'render_config.dart';
import 'selection.dart';
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

enum InkRenderLayer {
  background,
  highlighterBase,
  highlighterActive,
  inkBase,
  inkActive,
  overlay,
}

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
  }) : _backgroundBuilders = List.unmodifiable(backgroundBuilders) {
    _host = _Host(this);
    _render = InkPageRender._(this);
    for (final layer in InkRenderLayer.values) {
      _repaints[layer] = _Repaint();
    }
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
  );
  final HighlighterBaseCache _hl = HighlighterBaseCache();

  /// The ids the base caches were last told to leave out (display.hidden).
  Set<String> _baseHidden = const {};

  /// A chunk was recorded with a pencil stroke before the grain was ready.
  bool _chunksMissingGrain = false;

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
  StrokeSession beginStroke(
    InkSample first, {
    required core.StrokeStyle style,
    required double viewScale,
    InkStrokeMeta meta = const InkStrokeMeta(),
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
    final session = newStrokeSession(_host, builder, penDownMillis);
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
    final session = newLassoSession(_host, firstPagePoint, options);
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

  /// Ids not on this page are ignored; replaces the current selection. An empty result
  /// clears the selection and returns an empty InkSelection (isEmpty).
  InkSelection select(Set<String> strokeIds) {
    _checkNotDisposed();
    final content = _content;
    final ids = <String>[
      if (content != null)
        for (final s in content.strokes)
          if (strokeIds.contains(s.id)) s.id,
    ];
    if (ids.isEmpty) {
      clearSelection();
      return newInkSelection(_host, const []);
    }
    return _setSelection(newInkSelection(_host, ids));
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
  /// B3: the stroke's CORE bounds inflated by [tolerance] (exact distance: INK T14).
  InkStroke? hitTest(
    ui.Offset pagePoint, {
    double tolerance = 4.0,
    core.StrokeFilter filter = core.StrokeFilter.all,
  }) {
    final content = _content;
    if (content == null) return null;
    for (var i = content.strokes.length - 1; i >= 0; i--) {
      final s = content.strokes[i];
      if (_isPendingRemoved(s.id)) continue;
      if (!interop.filterAccepts(filter, s.style.tool)) continue;
      if (s.bounds.inflate(tolerance).contains(pagePoint)) return s;
    }
    return null;
  }

  /// Ids (z-order) of the strokes whose CORE bounds overlap [pageRect].
  List<String> strokeIdsInRect(ui.Rect pageRect) {
    final content = _content;
    if (content == null) return const [];
    return [
      for (final s in content.strokes)
        if (!_isPendingRemoved(s.id) && s.bounds.overlaps(pageRect)) s.id,
    ];
  }

  // --- commit hand-off (6.12 R6) — pendingIds / discardPending / discardEdit: contract 7.2.15
  /// Ids whose display is overridden until CORE content reflects the edit
  /// (new / duplicated strokes, erased or split originals, transformed / recolored targets).
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
    _visiblePageRect = visiblePageRect;
    _deviceScale = deviceScale;
    _isScaling = isScaling;
    _bucket = _bucketFor(deviceScale);
    // B3 draws vectors only: no picture depends on the bucket yet.
  }

  /// Smallest scale bucket >= [deviceScale]; null above the largest (vector only, 6.13).
  double? _bucketFor(double deviceScale) {
    double? best;
    for (final b in config.scaleBuckets) {
      if (b + 1e-9 >= deviceScale && (best == null || b < best)) best = b;
    }
    return best;
  }

  Listenable layerRepaint(InkRenderLayer layer) => _repaints[layer]!;

  InkPageRenderStats get renderStats => InkPageRenderStats(
    strokeCount: _content?.strokes.length ?? 0,
    chunkPictures: _chunks.pictureCount,
    rasterTiles: 0,
    rasterBytes: 0,
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
    _chunks.dispose();
    _hl.dispose();
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
          for (final id in edit.targetIds) id: content?.strokeById(id)?.source,
        },
      ),
    );
    _invalidate();
  }

  void _resolvePending(InkPageContent content) {
    var resetPreview = false;
    _pending.removeWhere((p) {
      p.addedIds.removeWhere((id) => content.strokeById(id) != null);
      p.removedIds.removeWhere((id) => content.strokeById(id) == null);
      p.targetIds.removeWhere((id) {
        final now = content.strokeById(id)?.source;
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
    if (retainSelectionIds(sel, (id) => content.strokeById(id) != null)) {
      return;
    }
    disposeInkSelection(sel);
    _selection = null;
    notifyListeners();
  }

  void _invalidate() {
    _display = null;
    if (_disposed) return;
    for (final r in _repaints.values) {
      r.fire();
    }
  }

  _Display _currentDisplay() {
    final cached = _display;
    if (cached != null) return cached;
    final d = _display = _computeDisplay();
    _syncHidden(d.hidden);
    return d;
  }

  /// R2–R4: what the content change means for the base caches. Appended
  /// strokes (top of the z order) become small chunk pictures; everything
  /// else marks the chunks it touches dirty. Highlighters: one page picture.
  void _applyDiff(InkContentDiff diff, InkPageContent content) {
    if (diff.isNoop) return;
    if (diff.isReset) {
      _chunks.reset(content.pageSize);
      _hl.markDirty();
      return;
    }
    var highlighters = diff.backgroundChanged;
    void dirty(InkStroke s) {
      if (s.layer == InkLayer.highlighter) {
        highlighters = true;
      } else {
        _chunks.markDirty(s.bounds);
      }
    }

    diff.inserted.forEach(dirty);
    diff.removed.forEach(dirty);
    for (final (before, now) in diff.changed) {
      dirty(before);
      dirty(now);
    }
    for (final s in diff.appended) {
      if (s.layer == InkLayer.highlighter) {
        highlighters = true;
      } else if (!_baseHidden.contains(s.id)) {
        _chunks.append(s, _drawInk);
      }
    }
    if (highlighters) _hl.markDirty();
  }

  /// R7: ids that start or stop being hidden (pending erase, previews,
  /// discarded edits) mark the base pictures they appear in dirty.
  void _syncHidden(Set<String> hidden) {
    final content = _content;
    if (content != null) {
      var highlighters = false;
      void touch(String id) {
        final s = content.strokeById(id);
        if (s == null) return;
        if (s.layer == InkLayer.highlighter) {
          highlighters = true;
        } else {
          _chunks.markDirty(s.bounds);
        }
      }

      for (final id in hidden) {
        if (!_baseHidden.contains(id)) touch(id);
      }
      for (final id in _baseHidden) {
        if (!hidden.contains(id)) touch(id);
      }
      if (highlighters) _hl.markDirty();
    }
    _baseHidden = hidden;
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
    for (final p in _pending) {
      removed.addAll(p.removedIds);
      for (final s in p.edit.added) {
        if (p.addedIds.contains(s.id) && content?.strokeById(s.id) == null) {
          added.add(s);
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
      }
    }
    final active = _active;
    if (active is EraserSession && active.isActive) {
      removed.addAll(eraserTouched(active));
    }
    final sel = _selection;
    if (sel != null && !sel.isDisposed && !sel.previewTransform.isIdentity) {
      for (final id in sel.strokeIds) {
        transforms.putIfAbsent(id, () => sel.previewTransform);
      }
    }
    final overrides = <_Override>[
      if (content != null)
        for (final s in content.strokes)
          if (!removed.contains(s.id) &&
              (transforms.containsKey(s.id) || colors.containsKey(s.id)))
            _Override(s, transforms[s.id], colors[s.id]),
    ];
    final hidden = {...removed, ...transforms.keys, ...colors.keys};
    // 6.10-6: a group with anything being written, pending or previewed is
    // composited by the active layer only (committed lines included).
    final activeKeys = <HighlighterGroupKey>{
      for (final o in overrides)
        if (o.stroke.layer == InkLayer.highlighter)
          HighlighterGroupKey.of(o.stroke.style, colorArgb: o.colorArgb),
      for (final s in added)
        if (s.style.profile.layer == InkLayer.highlighter)
          HighlighterGroupKey.of(s.style),
      if (active is StrokeSession &&
          active.isActive &&
          active.style.profile.layer == InkLayer.highlighter)
        HighlighterGroupKey.of(active.style),
    };
    return _Display(
      hidden: hidden,
      overrides: overrides,
      added: added,
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
        _chunks.paint(canvas, [
          for (final s in content.strokes)
            if (s.layer == InkLayer.ink && !display.hidden.contains(s.id)) s,
        ], _drawInk);
        if (diagnostics.enabled) {
          diagnostics.onCacheStats(
            cachePool.stats,
            visibleStrokes: content.strokes.length - display.hidden.length,
          );
        }
      case InkRenderLayer.highlighterActive:
        _paintActiveHighlighters(canvas, display, paper, margin);
      case InkRenderLayer.inkActive:
        _paintActiveInk(canvas, display, margin);
      case InkRenderLayer.overlay:
        final active = _active;
        if (active is! LassoSession || !active.isActive) return;
        if (active.points.length < 2) return;
        final path = active.previewPath;
        final scale = _currentViewScale;
        canvas
          ..drawPath(
            path,
            ui.Paint()
              ..style = ui.PaintingStyle.fill
              ..color = const ui.Color(InkTuning.lassoFillArgb),
          )
          ..drawPath(
            path,
            ui.Paint()
              ..style = ui.PaintingStyle.stroke
              ..strokeWidth = 1.5 / scale
              ..color = const ui.Color(InkTuning.lassoPathArgb),
          );
    }
  }

  /// The previewed copy of an override (transform → core.Stroke.transformed).
  InkStroke _overrideStroke(_Override o) {
    final m = o.transform;
    return m == null
        ? o.stroke
        : InkStroke.of(interop.previewTransformedOf(o.stroke.source, m));
  }

  /// Ink-layer previews, pending strokes and the stroke being written (R5–R7).
  void _paintActiveInk(ui.Canvas canvas, _Display display, double margin) {
    // Committed-looking strokes are drawn under the chunk clips, like the
    // chunk pictures that take them over (pixel-exact hand-off, R6).
    for (final o in display.overrides) {
      if (o.stroke.layer != InkLayer.ink) continue;
      final s = _overrideStroke(o);
      final outline = o.transform == null
          ? cachePool.outlineFor(s)
          : OutlineGenerator.outline(s);
      final grain = s.profile.textured ? _grain() : null;
      _chunks.paintClipped(
        canvas,
        s,
        (c, s) => paintFillStroke(
          c,
          s,
          outline,
          colorArgb: o.colorArgb,
          grain: grain,
        ),
      );
    }
    for (final added in display.added) {
      final s = InkStroke.of(added);
      if (s.layer != InkLayer.ink) continue;
      _chunks.paintClipped(canvas, s, _drawInk);
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
    for (final added in display.added) {
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
}

/// INTERNAL render access for InkPageView (not exported).
@meta.internal
final class InkPageRender {
  InkPageRender._(this._controller);

  final InkPageController _controller;
  Object? _view;

  /// Paints [layer] in page pt (the caller already scaled the canvas by [viewScale]).
  void paint(ui.Canvas canvas, InkRenderLayer layer, double viewScale) {
    _controller._currentViewScale = viewScale;
    _controller._paintLayer(canvas, layer);
  }

  /// One InkPageView per controller (debug assert, 6.12 R9 ⑤).
  void attachView(Object view) {
    assert(
      _view == null || identical(_view, view),
      'InkPageController(${_controller.pageId}) already has an InkPageView',
    );
    _view = view;
  }

  void detachView(Object view) {
    if (identical(_view, view)) _view = null;
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

/// INTERNAL (tests): the highlighter page picture of [controller] (6.10-6/-7).
@meta.internal
HighlighterBaseCache inkHighlighterCacheOf(InkPageController controller) =>
    controller._hl;

final class _Repaint extends ChangeNotifier {
  void fire() => notifyListeners();
}

final class _Pending {
  _Pending(this.edit, this.createdUs, {required this.targetsAtCommit})
    : addedIds = {for (final s in edit.added) s.id},
      removedIds = {...edit.removedIds},
      targetIds = {...edit.targetIds};

  final InkEdit edit;
  final int createdUs;
  final Map<String, core.Stroke?> targetsAtCommit;
  final Set<String> addedIds;
  final Set<String> removedIds;
  final Set<String> targetIds;

  bool get isEmpty =>
      addedIds.isEmpty && removedIds.isEmpty && targetIds.isEmpty;
}

final class _Override {
  _Override(this.stroke, this.transform, this.colorArgb);
  final InkStroke stroke;
  final core.Affine2? transform;
  final int? colorArgb;
}

final class _Display {
  _Display({
    required this.hidden,
    required this.overrides,
    required this.added,
    required this.highlighters,
    required this.activeHighlighterKeys,
  });
  final Set<String> hidden;
  final List<_Override> overrides;
  final List<core.Stroke> added;

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
