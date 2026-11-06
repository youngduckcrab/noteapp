// lib/src/render/sessions.dart — StrokeSession / EraserSession / LassoSession
// (end() → InkEdit?), contract 7.2.15 (03-ink 4.8).
//
// Foundation step B3 (03-ink 4.15), replaced step by step:
//  * StrokeSession: the StrokeBuilder pipeline of 6.3–6.7 (INK T06) →
//    createdAt = pen-down nowMillis() → one core.Stroke (several after a
//    rollover, 6.7 F8) → InkEdit(addStroke) (live layers: INK T10);
//  * EraserSession: a stroke is touched when its ink meets the capsule swept
//    from the previous sample (6.19, INK T15: spatial index + exact contact);
//    stroke mode → eraseStrokes; partial mode → the vector split of 6.20
//    (INK T16: PartialEraser P2–P6, CORE fragments P7, splitStrokes P8 —
//    toCommand = SplitStrokes, or RemoveStrokes when nothing is left);
//  * LassoSession: the LassoOptions rule of 6.21 (INK T17): RDP-simplified
//    closed polygon, nonzero winding with a y-band index, spatial index
//    candidates, centerline coverage of segment midpoints >= coverage.
//
// 2nd round (contract 7.2.9, m5-7/03-ink 4.4, 4.6, 4.13 — foundation step
// R2-B3):
//  * StrokeSession: receives ShapeAssist (the shapeAssist getter is what
//    beginStroke got) and reads the shape fitter then; shapePreview stays
//    null (the hold detection is T39). A laser stroke draws like a ballpoint
//    while written and end() returns null — no InkEdit, nothing pending
//    (K-9; the fading trail is T30).
//  * EraserSession: EraserSpec.eraseShapes — a shape the swept capsule touches
//    is removed whole (removedObjectIds; never with highlighterOnly; since
//    m5-7 T37b the exact rule of 6.15 — object_hit.dart: the outline within
//    R + w / 2, a head within R, the inside of a filled shape).
//  * LassoSession: LassoOptions.includeObjects — an object whose frame
//    center is inside (nonzero) is selected.
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../edit/eraser_spec.dart';
import '../edit/hit_test.dart';
import '../edit/ink_edit.dart';
import '../edit/lasso_options.dart';
import '../edit/lasso_polygon.dart';
import '../edit/partial_eraser.dart';
import '../geometry/outline_generator.dart';
import '../input/ink_sample.dart';
import '../input/pressure_capability.dart';
import '../interop/core_interop.dart' as interop;
import '../model/ink_layer.dart';
import '../model/ink_points.dart';
import '../object/object_hit.dart';
import '../pen/pen_profile.dart';
import '../pen/style_ink.dart';
import '../shape/shape_assist.dart';
import '../stroke/stroke_builder.dart';
import 'ink_page_content.dart';
import 'ink_page_controller.dart';
import 'page_host.dart';
import 'selection.dart';

abstract interface class InkGestureSession {
  bool get isActive;

  /// Discards the gesture: no edit, previews removed (palm rejection, PointerCancel).
  void cancel();
}

/// Live geometry for the active layer (page pt). Unquantized; replaced by the CORE
/// (quantized) stroke when the session ends.
final class LiveStrokeGeometry {
  LiveStrokeGeometry._(this._style)
    : _polylineMode = _style.profile.layer == InkLayer.highlighter,
      _dashMode = _style.profile.renderMethod == InkRenderMethod.dashedPolyline;

  final core.StrokeStyle _style;
  final bool _polylineMode;

  /// (m5-7/03-ink T29, 6.5 'live') the dashed pen: frozenPath holds every finished
  /// dash (append-only), tailPath the open dash + the dashes on the raw tail.
  final bool _dashMode;

  /// dashed: the pattern (multiples of the width) from the open dash on, and where
  /// that dash starts along the open points (pt — > 0 when it starts on the tail)
  List<double> _openDashPattern = OutlineSpec.defaultDashPattern;
  double _openDashLead = 0;

  /// stable (filtered) centerline positions, append-only during one stroke
  final List<ui.Offset> _stable = [];

  /// raw tail (+ predicted samples) after the stable points, replaced on every update
  List<ui.Offset> _tail = const [];

  /// highlighter alwaysStraight: start → current position (replaces the centerline)
  (ui.Offset, ui.Offset)? _straight;

  /// Σ K4 tilt weight of the stable points (pencil opacity, 6.11)
  double _tiltKSum = 0;

  final ui.Path _frozen = ui.Path();
  final List<ui.Path> _frozenChunks = [];
  InkPoints? _open;
  ui.Path? _tailPath;
  Float32List? _polyline;
  ui.Rect _bounds = ui.Rect.zero;
  int _version = 0;

  /// frozen chunks (append-only during one stroke), fill pens only
  ui.Path get frozenPath => _frozen;

  /// open chunk + raw tail, rebuilt on every update, fill pens only
  /// (dashed: the open dash and the dashes after it, 6.5 'live')
  ui.Path get tailPath {
    final open = _open;
    if (_polylineMode || open == null) return ui.Path();
    if (_dashMode) {
      return _tailPath ??= OutlineGenerator.dashed(
        open,
        width: _style.width,
        pattern: _openDashPattern,
        lead: _openDashLead,
        // the open part is about one dash: no D5 stretch
        maxSegments: 1 << 30,
      ).toPath();
    }
    return _tailPath ??= OutlineGenerator.outlineOfStyle(open, _style).toPath();
  }

  /// highlighter centerline x,y pairs (stroked); null for fill pens
  Float32List? get polyline {
    if (!_polylineMode) return null;
    return _polyline ??= Float32List.fromList([
      for (final p in _points) ...[p.dx, p.dy],
    ]);
  }

  ui.Rect get bounds => _bounds;

  /// increments on every change
  int get version => _version;
  bool get isEmpty => _stable.isEmpty;

  List<ui.Offset> get _points {
    final s = _straight;
    if (s != null) return [s.$1, s.$2];
    return [..._stable, ..._tail];
  }

  void _changed() {
    _tailPath = null;
    _polyline = null;
    _version++;
  }

  void _clear() {
    if (_stable.isEmpty && _frozenChunks.isEmpty) return;
    _stable.clear();
    _tiltKSum = 0;
    _tail = const [];
    _straight = null;
    _frozen.reset();
    _frozenChunks.clear();
    _open = null;
    _bounds = ui.Rect.zero;
    _changed();
  }
}

@internal
LiveStrokeGeometry newLiveStrokeGeometry(core.StrokeStyle style) =>
    LiveStrokeGeometry._(style);

/// Appends one stable centerline position (StrokeBuilder) with its K4 tilt
/// weight [tiltK] (6.11).
@internal
void liveAddStable(LiveStrokeGeometry live, ui.Offset p, {double tiltK = 0}) {
  live._stable.add(p);
  live._tiltKSum += tiltK;
  live._changed();
}

/// Mean K4 tilt weight of the stable points so far: the live pencil opacity
/// loss (6.11), like the committed stroke's mean over its points.
@internal
double liveMeanTiltK(LiveStrokeGeometry live) =>
    live._stable.isEmpty ? 0 : live._tiltKSum / live._stable.length;

/// Freezes one chunk (fill pens): its outline joins frozenPath for good. (m5-7 T28)
/// The calligraphy chunks are nib outlines of the stroke's nib (6.4 'live').
@internal
void liveFreezeChunk(LiveStrokeGeometry live, InkPoints chunk) {
  final path = OutlineGenerator.outlineOfStyle(chunk, live._style).toPath();
  live._frozenChunks.add(path);
  live._frozen.addPath(path, ui.Offset.zero);
  live._changed();
}

/// (m5-7/03-ink T29) Freezes one finished dash of the dashed pen ([piece]: its
/// centerline [a + r, b − r], or one point for a dot): its outline joins
/// frozenPath for good.
@internal
void liveFreezeDash(LiveStrokeGeometry live, InkPoints piece) {
  final path = OutlineGenerator.dashPiece(
    piece,
    width: live._style.width,
  ).toPath();
  live._frozenChunks.add(path);
  live._frozen.addPath(path, ui.Offset.zero);
  live._changed();
}

/// Replaces the open part: [tail] after the stable points, [open] = open chunk
/// + tail with live widthQ (fill pens), [straight] (highlighter alwaysStraight).
/// Dashed pen: [open] starts at the open dash (or at the last stable point, the
/// open dash then starting [dashLead] pt further on the tail) and [dashPattern] is
/// the pattern from that dash on.
@internal
void liveSetOpen(
  LiveStrokeGeometry live, {
  required List<ui.Offset> tail,
  required InkPoints? open,
  required (ui.Offset, ui.Offset)? straight,
  required ui.Rect bounds,
  List<double>? dashPattern,
  double dashLead = 0,
}) {
  live
    .._tail = tail
    .._open = open
    .._straight = straight
    .._bounds = bounds
    .._openDashPattern = dashPattern ?? OutlineSpec.defaultDashPattern
    .._openDashLead = dashLead
    .._changed();
}

@internal
void liveClear(LiveStrokeGeometry live) => live._clear();

/// The live centerline: stable points + raw tail (or the straight line).
@internal
List<ui.Offset> livePoints(LiveStrokeGeometry live) => live._points;

/// The frozen chunk outlines, oldest first (tests: append-only).
@internal
List<ui.Path> liveFrozenChunks(LiveStrokeGeometry live) =>
    List.unmodifiable(live._frozenChunks);

// --- pen -----------------------------------------------------------------------

final class StrokeSession implements InkGestureSession {
  StrokeSession._(
    this._host,
    this._builder,
    this._penDownMillis,
    this._shapeAssist,
    this._fitter,
  );

  final InkPageHost _host;
  final StrokeBuilder _builder;
  final core.EpochMillis _penDownMillis;
  final ShapeAssist _shapeAssist;

  /// The fitter read at beginStroke (holdToSnap on a tool that allows it), else null.
  final InkShapeFitter? _fitter;
  final ValueNotifier<InkShapeFit?> _shapePreview = ValueNotifier(null);
  bool _active = true;

  /// (v2.0) The shape fitted after a hold, shown in layer 4′; null otherwise (moving
  /// again, end, cancel). R2-B3: always null.
  ValueListenable<InkShapeFit?> get shapePreview => _shapePreview;

  /// (v2.1) what beginStroke received
  ShapeAssist get shapeAssist => _shapeAssist;

  /// normalized
  core.StrokeStyle get style => _builder.style;
  PressureSource get pressureSource => _builder.pressureSource;
  LiveStrokeGeometry get live => _builder.live;

  /// The live layer of the stroke being written (m5-7 T31: a tape is drawn by the
  /// cover layer — above the text boxes, L-1).
  InkRenderLayer get _layer => switch (style.profile.layer) {
    InkLayer.highlighter => InkRenderLayer.highlighterActive,
    InkLayer.cover => InkRenderLayer.cover,
    InkLayer.ink => InkRenderLayer.inkActive,
  };

  void addSample(InkSample sample) {
    _checkActive();
    _builder.add(sample);
    _host.diagnostics.onSamples([sample], receiveUs: _host.clock.nowUs());
    _reportWidthFactor();
    _host.repaint(_layer);
  }

  void addSamples(Iterable<InkSample> samples) {
    _checkActive();
    final list = samples.toList(growable: false);
    if (list.isEmpty) return;
    list.forEach(_builder.add);
    _host.diagnostics.onSamples(list, receiveUs: _host.clock.nowUs());
    _reportWidthFactor();
    _host.repaint(_layer);
  }

  /// 4.12 lastWidthFactor / pressureSource / stylusCapability.
  void _reportWidthFactor() {
    final d = _host.diagnostics;
    if (!d.enabled) return;
    d.onWidthFactor(
      _builder.lastWidthFactor ?? 1.0,
      _builder.pressureSource,
      _host.stylusCapability,
    );
  }

  /// addStroke edit with ONE core.Stroke: id = services.newStrokeId(), createdAt = pen-down
  /// nowMillis (the contract's createdAt), points = core.StrokePoints.fromInterleaved(...).
  /// Several strokes (still one edit / one command) only when the pen stayed down longer
  /// than t's range of 500 000 ms (rollover, 6.7 F8).
  /// null if discarded / nothing drawn. The stroke stays visible as pending until
  /// updateContent contains it, discardEdit (failed commit) is called, or the timeout passes.
  /// (v2.0) laser: null — no InkEdit, nothing pending, the content is not changed (E-3).
  InkEdit? end([InkSample? last]) {
    _checkActive();
    _active = false;
    _shapePreview.value = null;
    if (style.tool == core.PenTool.laser) {
      liveClear(live);
      _host.sessionEnded(this);
      return null;
    }
    final finished = _builder.finish(last: last);
    final parts = [..._builder.rolledOver, ?finished];
    InkEdit? edit;
    if (parts.isNotEmpty) {
      final strokes = [
        for (final f in parts)
          interop.newCoreStroke(
            f,
            id: _host.services.newStrokeId(),
            pageId: _host.pageId,
            penDownMillis: _penDownMillis,
          ),
      ];
      edit = InkEdit(
        pageId: _host.pageId,
        kind: InkEditKind.addStroke,
        added: List.unmodifiable(strokes),
      );
      _host.addPending(edit);
    }
    liveClear(live);
    _host.sessionEnded(this);
    return edit;
  }

  @override
  bool get isActive => _active;

  @override
  void cancel() {
    if (!_active) return;
    _active = false;
    _shapePreview.value = null;
    liveClear(live);
    _host.sessionEnded(this);
  }

  void _checkActive() {
    if (!_active) throw StateError('The stroke session has ended');
  }
}

@internal
StrokeSession newStrokeSession(
  InkPageHost host,
  StrokeBuilder builder,
  core.EpochMillis penDownMillis, {
  ShapeAssist shapeAssist = ShapeAssist.off,
  InkShapeFitter? fitter,
}) => StrokeSession._(host, builder, penDownMillis, shapeAssist, fitter);

/// The shape fitter [s] read at beginStroke (null: off, or a tool without shape assist —
/// highlighter, laser, tape). Tests (S-12: a changed override applies from the next stroke).
@internal
InkShapeFitter? strokeSessionFitterOf(StrokeSession s) => s._fitter;

/// Shape assist applies to this tool (not highlighter, laser or tape — 03-ink 4.10).
@internal
bool shapeAssistAllowed(core.PenTool tool) =>
    tool != core.PenTool.highlighter &&
    tool != core.PenTool.laser &&
    tool != core.PenTool.tape;

// --- eraser --------------------------------------------------------------------

final class EraserSession implements InkGestureSession {
  EraserSession._(this._host, this.spec, ui.Offset first)
    : _last = first,
      _partial = spec.mode == EraserMode.partial
          ? PartialEraser(spec.radius)
          : null {
    _touchAlong(first, first);
  }

  final InkPageHost _host;
  final EraserSpec spec;
  final LinkedHashSet<String> _touched = LinkedHashSet<String>();

  /// (v2.0) touched shapes (removed whole)
  final LinkedHashSet<String> _touchedObjects = LinkedHashSet<String>();
  ui.Offset _last;
  bool _active = true;

  /// partial mode (6.20): the erased intervals per original
  final PartialEraser? _partial;

  /// partial mode: the kept pieces (P5/P6) of each touched original as
  /// memory-only preview strokes (P8, ids `pv-<n>`; end() gives their points
  /// to the fragments)
  final Map<String, List<core.Stroke>> _previews = {};
  int _previewSeq = 0;

  Set<String> get touchedStrokeIds => UnmodifiableSetView(_touched);

  void addSample(InkSample sample) {
    if (!_active) throw StateError('The eraser session has ended');
    _host.diagnostics.onSamples([sample], receiveUs: _host.clock.nowUs());
    final p = sample.position;
    if (!p.isFinite) return;
    _touchAlong(_last.isFinite ? _last : p, p);
    _last = p;
  }

  /// stroke mode → eraseStrokes(removedIds); partial → splitStrokes(removedIds, added =
  /// fragments made with core.Stroke.fragment). null if nothing was touched.
  /// (v2.0) Touched shapes join removedIds and removedObjectIds (RemoveElements; partial:
  /// Composite[SplitStrokes | RemoveStrokes, RemoveElements] — CP-INK-2).
  InkEdit? end([InkSample? last]) {
    if (!_active) throw StateError('The eraser session has ended');
    if (last != null && last.position.isFinite) {
      _touchAlong(_last.isFinite ? _last : last.position, last.position);
    }
    _active = false;
    InkEdit? edit;
    final content = _host.content;
    if ((_touched.isNotEmpty || _touchedObjects.isNotEmpty) &&
        content != null) {
      // originals another update removed meanwhile are left out
      final ordered = [
        for (final id in _touched)
          if (content.zIndexOf(id) >= 0) id,
      ]..sort((a, b) => content.zIndexOf(a).compareTo(content.zIndexOf(b)));
      final shapes = [
        for (final id in _touchedObjects) ?objectByIdOf(content, id),
      ]..sort(core.Stroke.compareOrder);
      if (ordered.isNotEmpty || shapes.isNotEmpty) {
        final removedElements = <core.PageElement>[
          for (final id in ordered) content.strokeById(id)!.source,
          ...shapes,
        ]..sort(core.Stroke.compareOrder);
        final removed = Set<String>.unmodifiable(
          LinkedHashSet.of(removedElements.map((e) => e.id)),
        );
        final removedObjects = Set<String>.unmodifiable(
          LinkedHashSet.of(shapes.map((o) => o.id)),
        );
        edit = _partial == null
            ? InkEdit(
                pageId: _host.pageId,
                kind: InkEditKind.eraseStrokes,
                removedIds: removed,
                removedObjectIds: removedObjects,
              )
            : InkEdit(
                pageId: _host.pageId,
                kind: InkEditKind.splitStrokes,
                removedIds: removed,
                removedObjectIds: removedObjects,
                added: List.unmodifiable(_fragments(ordered)),
              );
        _host.addPending(edit);
      }
    }
    _clear();
    _host.sessionEnded(this);
    return edit;
  }

  @override
  bool get isActive => _active;

  @override
  void cancel() {
    if (!_active) return;
    _active = false;
    _clear();
    _host.sessionEnded(this);
  }

  void _clear() {
    _touched.clear();
    _touchedObjects.clear();
    _partial?.clear();
    _previews.clear();
  }

  /// P7: the CORE fragments of every touched original (z order), each piece
  /// with a real id — from the gesture's merged intervals (the pieces of the
  /// last change). Their points are the preview pieces' points, made from
  /// the same data (T22 B5: no second StrokePoints.fromInterleaved).
  List<core.Stroke> _fragments(List<String> ordered) {
    final partial = _partial!;
    return [
      for (final id in ordered)
        if (partial.strokeOf(id) case final original?)
          for (final preview in _previews[id] ?? const <core.Stroke>[])
            interop.fragmentFromPreview(
              original.source,
              preview,
              id: _host.services.newStrokeId(),
            ),
    ];
  }

  /// 6.19 1–2 / 6.20 P1: the capsule from the previous sample to this one
  /// (the first sample: a disc) → spatial index candidates → filter → exact
  /// ink contact (stroke mode: InkHitTest.capsuleTouches; partial mode: the
  /// cut intervals of PartialEraser). The capsule fills the gap between
  /// samples, so fast scrubbing misses nothing.
  void _touchAlong(ui.Offset a, ui.Offset b) {
    if (_host.content == null || !a.isFinite || !b.isFinite) return;
    final radius = spec.radius;
    final near = _host.strokesNear(ui.Rect.fromPoints(a, b).inflate(radius));
    final partial = _partial;
    var changed = false;
    for (final s in near) {
      if (!interop.filterAccepts(spec.filter, s.style.tool)) continue;
      if (partial != null) {
        if (!partial.addCapsule(s, a, b)) continue;
        _touched.add(s.id);
        final pieces = partial.piecesOf(s.id);
        _previews[s.id] = [
          for (final data in pieces)
            interop.previewFragmentOf(s.source, data, seq: ++_previewSeq),
        ];
        changed = true;
      } else {
        if (_touched.contains(s.id)) continue;
        if (InkHitTest.capsuleTouches(s, a, b, radius)) {
          _touched.add(s.id);
          changed = true;
        }
      }
    }
    // (v2.0, m5-7 T37b — 6.15) shapes: the capsule within R + w / 2 of the outline, R of
    // an arrow head, or reaching into a filled shape → removed whole (object index
    // candidates). Never with highlighterOnly; other objects are never erased.
    if (spec.eraseShapes && spec.filter != core.StrokeFilter.highlighterOnly) {
      final area = ui.Rect.fromPoints(a, b).inflate(radius);
      for (final o in _host.objectsNear(area)) {
        if (o is! core.ShapeObject || _touchedObjects.contains(o.id)) continue;
        if (ObjectHitTest.shapeTouchesCapsule(o, a, b, radius)) {
          _touchedObjects.add(o.id);
          changed = true;
        }
      }
    }
    if (changed) _host.displayChanged();
  }
}

@internal
EraserSession newEraserSession(
  InkPageHost host,
  EraserSpec spec,
  ui.Offset first,
) => EraserSession._(host, spec, first);

@internal
Set<String> eraserTouched(EraserSession s) => s._touched;

/// (v2.0) The shapes the eraser touched so far (hidden while the gesture lasts).
@internal
Set<String> eraserTouchedObjects(EraserSession s) => s._touchedObjects;

/// Partial mode: the memory-only preview pieces of the touched originals
/// (6.20 P8), drawn instead of them while the gesture lasts.
@internal
Iterable<core.Stroke> eraserPreviewPieces(EraserSession s) =>
    s._previews.values.expand((pieces) => pieces);

/// Partial mode: the merged erased intervals of [strokeId] so far.
@internal
List<ParamInterval> eraserIntervalsOf(EraserSession s, String strokeId) =>
    s._partial?.erasedOf(strokeId) ?? const [];

// --- lasso ---------------------------------------------------------------------

final class LassoSession implements InkGestureSession {
  LassoSession._(this._host, ui.Offset first, this._viewScale, this._options) {
    if (first.isFinite) _points.add(first);
  }

  final InkPageHost _host;

  /// logical px per page pt at gesture start (the RDP tolerance, L2)
  final double _viewScale;
  final LassoOptions _options;
  final List<ui.Offset> _points = [];
  bool _active = true;

  /// The collected points (page pt; non-finite points are not kept).
  List<ui.Offset> get points => UnmodifiableListView(_points);

  /// The collected path, closed end → start (not simplified — L1 preview).
  ui.Path get previewPath {
    final path = ui.Path();
    if (_points.isEmpty) return path;
    path.moveTo(_points.first.dx, _points.first.dy);
    for (var i = 1; i < _points.length; i++) {
      path.lineTo(_points[i].dx, _points[i].dy);
    }
    return path..close();
  }

  /// L1: one more point (page pt); a non-finite point is ignored.
  void addPoint(ui.Offset pagePoint) {
    if (!_active) throw StateError('The lasso session has ended');
    if (!pagePoint.isFinite) return;
    _points.add(pagePoint);
    _host.repaint(InkRenderLayer.overlay);
  }

  /// Selection by the LassoOptions rule (null if degenerate or empty).
  /// A non-null result becomes controller.selection.
  ///
  /// L2 polygon (RDP simplifyPx / viewScale, degenerate → null) → L4 spatial
  /// index candidates of its bounds (every tool; strokes a pending edit hides
  /// are left out) → L5 coverage → ids in z order.
  InkSelection? end() {
    if (!_active) throw StateError('The lasso session has ended');
    _active = false;
    InkSelection? result;
    final content = _host.content;
    if (content != null) {
      final polygon = lassoPolygonOf(this);
      if (!polygon.isDegenerate(_options.minAreaPt2)) {
        // z looked up once per pick, not per comparison (T22 B6)
        final zPicked = [
          for (final s in _host.strokesNear(polygon.bounds))
            if (LassoSelector.selects(s, polygon, _options.coverage))
              (content.zIndexOf(s.id), s.id),
        ]..sort((a, b) => a.$1.compareTo(b.$1));
        var picked = [for (final (_, id) in zPicked) id];
        if (_options.includeObjects) {
          // (v2.0) an object is selected when its frame center is inside (nonzero)
          final objects = [
            for (final o in _host.objectsNear(polygon.bounds))
              if (polygon.contains(o.frame.center.x, o.frame.center.y)) o,
          ];
          if (objects.isNotEmpty) {
            final elements = <core.PageElement>[
              for (final id in picked) content.strokeById(id)!.source,
              ...objects,
            ]..sort(core.Stroke.compareOrder);
            picked = [for (final e in elements) e.id];
          }
        }
        if (picked.isNotEmpty) {
          result = newInkSelection(_host, picked);
          _host.lassoSelected(result);
        }
      }
    }
    _host.sessionEnded(this);
    return result;
  }

  @override
  bool get isActive => _active;

  @override
  void cancel() {
    if (!_active) return;
    _active = false;
    _host.sessionEnded(this);
  }
}

/// L2: the closed, simplified polygon of [s]'s points so far.
@internal
LassoPolygon lassoPolygonOf(LassoSession s) => LassoPolygon.simplified(
  s._points,
  tolerancePt: s._options.simplifyPx / s._viewScale,
);

@internal
LassoSession newLassoSession(
  InkPageHost host,
  ui.Offset first,
  double viewScale,
  LassoOptions options,
) => LassoSession._(host, first, viewScale, options);
