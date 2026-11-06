// lib/src/tools/shape_interaction.dart — m5-7/04-editor 6.9.2 (E2-09): the
// shape tool's drag. A down only gets here past the selection priority
// (a′) (6.6.2): a handle of the selection never does, the body of a shape
// just drawn (origin drawn) or tap-selected does — a circle can be drawn
// inside the rectangle drawn a moment ago (review M-4).
import 'dart:ui' show Offset;

import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../input/input_sample.dart';
import '../input/input_targets.dart';
import '../viewport/viewport_controller.dart';
import 'shape_drafts.dart';
import 'tool_interaction.dart';
import 'tool_options.dart';

/// Drags a new shape of `options.shapeKind` from the down: every move sets
/// controller.setPreviewObjects([preview]) — ShapeDrafts.geometry(kind,
/// p0, p1, options, snap: [snap]()) under the id [previewId] — read at each
/// move, so Shift / Alt work mid-drag. The end: a diagonal (down → up) under
/// [tapSlopPx] screen px is a tap → [onTap] (the host selects the object
/// there — 6.3.5 ④), else [onCommit] with the geometry and style (the host
/// makes the object and sends ONE AddObjects); either way the preview is
/// cleared. Cancel: the preview cleared, nothing else.
final class ShapeInteraction extends ToolInteraction {
  ShapeInteraction._({
    required super.source,
    required super.startedAt,
    required this.controller,
    required this.pageId,
    required this.pageIndex,
    required this.kind,
    required this._options,
    required this._viewport,
    required this._snap,
    required this._onCommit,
    required this._onTap,
    required Offset start,
    required core.PagePoint startPage,
  }) : _start = start,
       _last = start,
       _p0 = startPage;

  factory ShapeInteraction.start({
    required InputSample down,
    required InteractionSource source,
    required ink.InkPageController controller,
    required String pageId,
    required int pageIndex,
    required ToolOptions options,
    required ViewportController viewport,
    required ShapeSnap Function() snap,
    required void Function(
      core.ShapeKind kind,
      core.ShapeGeometry geometry,
      core.ShapeStyle style,
    )
    onCommit,
    required void Function(Offset screen) onTap,
  }) {
    final p = viewport.screenToPage(pageIndex, down.position);
    return ShapeInteraction._(
      source: source,
      startedAt: down.timeStamp,
      controller: controller,
      pageId: pageId,
      pageIndex: pageIndex,
      kind: options.shapeKind,
      options: options,
      viewport: viewport,
      snap: snap,
      onCommit: onCommit,
      onTap: onTap,
      start: down.position,
      startPage: core.PagePoint(p.dx, p.dy),
    );
  }

  /// The id of the preview shape (never stored).
  static const String previewId = 'editor.shapePreview';

  /// (6.9.2) A diagonal under this (screen px) is a tap.
  static const double tapSlopPx = 8;

  final ink.InkPageController controller;
  final String pageId;
  final int pageIndex;
  final core.ShapeKind kind;
  final ToolOptions _options;
  final ViewportController _viewport;
  final ShapeSnap Function() _snap;
  final void Function(core.ShapeKind, core.ShapeGeometry, core.ShapeStyle)
  _onCommit;
  final void Function(Offset screen) _onTap;
  final Offset _start;
  final core.PagePoint _p0;
  Offset _last;
  double _travelled = 0;
  bool _done = false;
  core.ShapeGeometry? _geometry;

  @override
  double get travelled => _travelled;

  late final core.ShapeStyle _style = ShapeDrafts.styleFor(kind, _options);

  void _update(Offset screen) {
    _travelled += (screen - _last).distance;
    _last = screen;
    final p = _viewport.screenToPage(pageIndex, screen);
    final geometry = ShapeDrafts.geometry(
      kind,
      _p0,
      core.PagePoint(p.dx, p.dy),
      _options,
      snap: _snap(),
    );
    _geometry = geometry;
    controller.setPreviewObjects([
      core.ShapeObject(
        id: previewId,
        pageId: pageId,
        shapeKind: kind,
        geometry: geometry,
        style: _style,
        createdAt: 0,
      ),
    ]);
  }

  @override
  void move(InputSample sample) {
    if (_done) return;
    _update(sample.position);
  }

  @override
  void end(InputSample sample) {
    if (_done) return;
    _done = true;
    try {
      if ((sample.position - _start).distance < tapSlopPx) {
        controller.setPreviewObjects(const []);
        _onTap(_start);
        return;
      }
      _update(sample.position);
      final geometry = _geometry;
      if (geometry != null) _onCommit(kind, geometry, _style);
    } finally {
      controller.setPreviewObjects(const []);
    }
  }

  @override
  void cancel() {
    if (_done) return;
    _done = true;
    controller.setPreviewObjects(const []);
  }
}
