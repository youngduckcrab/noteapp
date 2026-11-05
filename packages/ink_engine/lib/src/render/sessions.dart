// lib/src/render/sessions.dart — StrokeSession / EraserSession / LassoSession
// (end() → InkEdit?), contract 7.2.15 (03-ink 4.8).
//
// Foundation step B3 (03-ink 4.15), replaced step by step:
//  * StrokeSession: the StrokeBuilder pipeline of 6.3–6.7 (INK T06) →
//    createdAt = pen-down nowMillis() → one core.Stroke (several after a
//    rollover, 6.7 F8) → InkEdit(addStroke) (live layers: INK T10);
//  * EraserSession: a stroke is touched when the eraser circle (swept between
//    samples) overlaps its CORE bounds; stroke mode → eraseStrokes, partial
//    mode → splitStrokes without fragments (toCommand = RemoveStrokes)
//    (exact geometry: INK T15 / T16);
//  * LassoSession: a stroke is selected when its bounds center is inside the
//    lasso polygon (nonzero winding) (the coverage rule of LassoOptions: T17).
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../edit/eraser_spec.dart';
import '../edit/ink_edit.dart';
import '../edit/lasso_options.dart';
import '../geometry/outline_generator.dart';
import '../input/ink_sample.dart';
import '../input/pressure_capability.dart';
import '../interop/core_interop.dart' as interop;
import '../model/ink_layer.dart';
import '../model/ink_points.dart';
import '../pen/style_ink.dart';
import '../stroke/stroke_builder.dart';
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
    : _polylineMode = _style.profile.layer == InkLayer.highlighter;

  final core.StrokeStyle _style;
  final bool _polylineMode;

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
  ui.Path get tailPath {
    final open = _open;
    if (_polylineMode || open == null) return ui.Path();
    return _tailPath ??= OutlineGenerator.outlineOf(
      open,
      width: _style.width,
      profile: _style.profile,
    ).toPath();
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

/// Freezes one chunk (fill pens): its outline joins frozenPath for good.
@internal
void liveFreezeChunk(LiveStrokeGeometry live, InkPoints chunk) {
  final path = OutlineGenerator.outlineOf(
    chunk,
    width: live._style.width,
    profile: live._style.profile,
  ).toPath();
  live._frozenChunks.add(path);
  live._frozen.addPath(path, ui.Offset.zero);
  live._changed();
}

/// Replaces the open part: [tail] after the stable points, [open] = open chunk
/// + tail with live widthQ (fill pens), [straight] (highlighter alwaysStraight).
@internal
void liveSetOpen(
  LiveStrokeGeometry live, {
  required List<ui.Offset> tail,
  required InkPoints? open,
  required (ui.Offset, ui.Offset)? straight,
  required ui.Rect bounds,
}) {
  live
    .._tail = tail
    .._open = open
    .._straight = straight
    .._bounds = bounds
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
  StrokeSession._(this._host, this._builder, this._penDownMillis);

  final InkPageHost _host;
  final StrokeBuilder _builder;
  final core.EpochMillis _penDownMillis;
  bool _active = true;

  /// normalized
  core.StrokeStyle get style => _builder.style;
  PressureSource get pressureSource => _builder.pressureSource;
  LiveStrokeGeometry get live => _builder.live;

  InkRenderLayer get _layer => style.profile.layer == InkLayer.highlighter
      ? InkRenderLayer.highlighterActive
      : InkRenderLayer.inkActive;

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
  InkEdit? end([InkSample? last]) {
    _checkActive();
    _active = false;
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
  core.EpochMillis penDownMillis,
) => StrokeSession._(host, builder, penDownMillis);

// --- eraser --------------------------------------------------------------------

final class EraserSession implements InkGestureSession {
  EraserSession._(this._host, this.spec, ui.Offset first) : _last = first {
    _touchAlong(first, first);
  }

  final InkPageHost _host;
  final EraserSpec spec;
  final LinkedHashSet<String> _touched = LinkedHashSet<String>();
  ui.Offset _last;
  bool _active = true;

  Set<String> get touchedStrokeIds => UnmodifiableSetView(_touched);

  void addSample(InkSample sample) {
    if (!_active) throw StateError('The eraser session has ended');
    _host.diagnostics.onSamples([sample], receiveUs: _host.clock.nowUs());
    _touchAlong(_last, sample.position);
    _last = sample.position;
  }

  /// stroke mode → eraseStrokes(removedIds); partial → splitStrokes(removedIds, added =
  /// fragments made with core.Stroke.fragment). null if nothing was touched.
  InkEdit? end([InkSample? last]) {
    if (!_active) throw StateError('The eraser session has ended');
    if (last != null) _touchAlong(_last, last.position);
    _active = false;
    InkEdit? edit;
    final content = _host.content;
    if (_touched.isNotEmpty && content != null) {
      final ordered = _touched.toList()
        ..sort((a, b) => content.zIndexOf(a).compareTo(content.zIndexOf(b)));
      final removed = Set<String>.unmodifiable(LinkedHashSet.of(ordered));
      edit = InkEdit(
        pageId: _host.pageId,
        kind: spec.mode == EraserMode.stroke
            ? InkEditKind.eraseStrokes
            : InkEditKind.splitStrokes,
        removedIds: removed,
      );
      _host.addPending(edit);
    }
    _touched.clear();
    _host.sessionEnded(this);
    return edit;
  }

  @override
  bool get isActive => _active;

  @override
  void cancel() {
    if (!_active) return;
    _active = false;
    _touched.clear();
    _host.sessionEnded(this);
  }

  void _touchAlong(ui.Offset a, ui.Offset b) {
    final content = _host.content;
    if (content == null) return;
    var changed = false;
    for (final s in content.strokes) {
      if (_touched.contains(s.id) || _host.isPendingRemoved(s.id)) continue;
      if (!interop.filterAccepts(spec.filter, s.style.tool)) continue;
      if (_segmentRectDistance(a, b, s.bounds) <= spec.radius) {
        _touched.add(s.id);
        changed = true;
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

double _pointRectDistance(ui.Offset p, ui.Rect r) {
  final dx = math.max(math.max(r.left - p.dx, 0.0), p.dx - r.right);
  final dy = math.max(math.max(r.top - p.dy, 0.0), p.dy - r.bottom);
  return math.sqrt(dx * dx + dy * dy);
}

double _pointSegmentDistance(ui.Offset p, ui.Offset a, ui.Offset b) {
  final abx = b.dx - a.dx, aby = b.dy - a.dy;
  final len2 = abx * abx + aby * aby;
  var t = 0.0;
  if (len2 > 0) {
    t = (((p.dx - a.dx) * abx + (p.dy - a.dy) * aby) / len2).clamp(0.0, 1.0);
  }
  final x = a.dx + abx * t - p.dx, y = a.dy + aby * t - p.dy;
  return math.sqrt(x * x + y * y);
}

/// Liang–Barsky: does segment a→b cross rectangle r?
bool _segmentHitsRect(ui.Offset a, ui.Offset b, ui.Rect r) {
  var t0 = 0.0, t1 = 1.0;
  final dx = b.dx - a.dx, dy = b.dy - a.dy;
  final p = [-dx, dx, -dy, dy];
  final q = [a.dx - r.left, r.right - a.dx, a.dy - r.top, r.bottom - a.dy];
  for (var i = 0; i < 4; i++) {
    if (p[i] == 0) {
      if (q[i] < 0) return false;
    } else {
      final t = q[i] / p[i];
      if (p[i] < 0) {
        if (t > t1) return false;
        if (t > t0) t0 = t;
      } else {
        if (t < t0) return false;
        if (t < t1) t1 = t;
      }
    }
  }
  return true;
}

double _segmentRectDistance(ui.Offset a, ui.Offset b, ui.Rect r) {
  if (_segmentHitsRect(a, b, r)) return 0;
  return [
    _pointRectDistance(a, r),
    _pointRectDistance(b, r),
    _pointSegmentDistance(r.topLeft, a, b),
    _pointSegmentDistance(r.topRight, a, b),
    _pointSegmentDistance(r.bottomLeft, a, b),
    _pointSegmentDistance(r.bottomRight, a, b),
  ].reduce(math.min);
}

// --- lasso ---------------------------------------------------------------------

final class LassoSession implements InkGestureSession {
  LassoSession._(this._host, ui.Offset first, this._options) {
    _points.add(first);
  }

  final InkPageHost _host;
  final LassoOptions _options;
  final List<ui.Offset> _points = [];
  bool _active = true;

  List<ui.Offset> get points => UnmodifiableListView(_points);

  /// The lasso polygon, closed end → start.
  ui.Path get previewPath {
    final path = ui.Path();
    if (_points.isEmpty) return path;
    path.moveTo(_points.first.dx, _points.first.dy);
    for (var i = 1; i < _points.length; i++) {
      path.lineTo(_points[i].dx, _points[i].dy);
    }
    return path..close();
  }

  void addPoint(ui.Offset pagePoint) {
    if (!_active) throw StateError('The lasso session has ended');
    _points.add(pagePoint);
    _host.repaint(InkRenderLayer.overlay);
  }

  /// Selection by the LassoOptions rule (null if degenerate or empty).
  /// A non-null result becomes controller.selection.
  InkSelection? end() {
    if (!_active) throw StateError('The lasso session has ended');
    _active = false;
    InkSelection? result;
    final content = _host.content;
    if (content != null && !_isDegenerate()) {
      final ids = <String>[
        for (final s in content.strokes)
          if (!_host.isPendingRemoved(s.id) &&
              _windingNumber(s.bounds.center) != 0)
            s.id,
      ];
      if (ids.isNotEmpty) {
        result = newInkSelection(_host, ids);
        _host.lassoSelected(result);
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

  bool _isDegenerate() {
    if (_points.length < 3) return true;
    var area2 = 0.0;
    for (var i = 0; i < _points.length; i++) {
      final a = _points[i], b = _points[(i + 1) % _points.length];
      area2 += a.dx * b.dy - b.dx * a.dy;
    }
    return area2.abs() / 2 < _options.minAreaPt2;
  }

  /// Nonzero winding number of [p] around the closed lasso polygon.
  int _windingNumber(ui.Offset p) {
    var wn = 0;
    final n = _points.length;
    for (var i = 0; i < n; i++) {
      final a = _points[i], b = _points[(i + 1) % n];
      final cross =
          (b.dx - a.dx) * (p.dy - a.dy) - (p.dx - a.dx) * (b.dy - a.dy);
      if (a.dy <= p.dy) {
        if (b.dy > p.dy && cross > 0) wn++;
      } else {
        if (b.dy <= p.dy && cross < 0) wn--;
      }
    }
    return wn;
  }
}

@internal
LassoSession newLassoSession(
  InkPageHost host,
  ui.Offset first,
  LassoOptions options,
) => LassoSession._(host, first, options);
