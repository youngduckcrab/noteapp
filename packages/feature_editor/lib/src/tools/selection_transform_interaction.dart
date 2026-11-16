// lib/src/tools/selection_transform_interaction.dart — 04-editor 6.6.5 (moving /
// resizing the selection). (v2, E2-06 — m5-7/04-editor 6.6.2) a move starts
// only past the move-start threshold; a down that ends before it is a
// selection tap (no command). (v2, E2-06 part 2 — 6.6.4–6.6.6) the rotate
// handle (15° snapping — the relative angle for several elements and a
// polyline shape, the absolute angle for an object whose frame rotates), a
// single object's corners scale about its rotated opposite corner
// (ObjectResize.cornerScale) and a selection of unknown objects only does not
// move.
import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:flutter/gestures.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../commands/editor_commands.dart';
import '../input/input_sample.dart';
import '../input/input_targets.dart';
import '../viewport/viewport_controller.dart';
import 'object_resize.dart';
import 'selection.dart';
import 'selection_hit_test.dart';
import 'tool_interaction.dart';

/// Drags the selection of [controller] (6.6.5): [handle] null = move, a
/// resize handle = a keepAspect resize from that corner, the rotate handle =
/// a rotation. Every move sets INK's preview transform (INK paints it): move
/// = ink.SelectionGeometry.move(clampTranslation(bounds, delta, pageSize)),
/// resize = ink.SelectionGeometry.resize(bounds, handle, delta, keepAspect:
/// true) — (v2) for a single object ObjectResize.cornerScale(object.frame,
/// …) — delta in page pt from pen down; rotate = 6.6.6. At the end
/// sel.commitTransform() → EditorCommands.commitInkEdit; [onCommitted] (the
/// host re-selects the same ids — TransformElements keeps ids) only when the
/// command was accepted. A rejected commit has already called discardEdit, so
/// the strokes show at their old place and the selection stays. Cancel resets
/// the preview. [onFinished] runs once at end or cancel (setDragging(false)).
///
/// (v2) A move ([handle] null) previews nothing until the pen has gone
/// [moveStartThresholdPx] screen px from the down; ending before that is a
/// selection tap: no preview, no command, [onTap] (the host may start a text
/// edit — 6.6.2). The 1st round made a TransformElements step of every small
/// wobble.
///
/// (v2, 6.6.6) Rotate: φ₀ is the down's angle about the centre c, φ the
/// pen's. Several elements and a single polyline shape: Δ = snapAngle(φ − φ₀)
/// about `sel.bounds.center` ([onRotate] gets Δ — the relative angle). One
/// object whose frame rotates (rotatesByFrame): θ' = snapAngle(θ + (φ − φ₀)),
/// Δ = θ' − θ about the frame centre ([onRotate] gets θ' — the absolute
/// angle).
final class SelectionTransformInteraction extends ToolInteraction {
  SelectionTransformInteraction._({
    required super.source,
    required super.startedAt,
    required this.controller,
    required this.pageIndex,
    required this.handle,
    required this._selection,
    required this._single,
    required this._immovable,
    required this._bounds,
    required this._rotateCentre,
    required this._pageSize,
    required this._startPage,
    required this._viewport,
    required this._commands,
    required Offset start,
    required this._onCommitted,
    required this._onFinished,
    required this._onTap,
    required this._onRotate,
  }) : _last = start,
       _start = start,
       _moving = handle != null;

  factory SelectionTransformInteraction.start({
    required InputSample down,
    required InteractionSource source,
    required ink.InkPageController controller,
    required ink.InkSelection selection,
    required int pageIndex,
    required Size pageSize,
    required FrameHandle? handle,
    required ViewportController viewport,
    required EditorCommands commands,
    required void Function(Set<String> strokeIds) onCommitted,
    required void Function() onFinished,
    void Function()? onTap,
    void Function(double radians)? onRotate,
  }) {
    final single = singleObjectOf(selection);
    final bounds = selection.bounds;
    final byFrame = single != null && rotatesByFrame(single);
    final centre = byFrame
        ? Offset(single.frame.center.x, single.frame.center.y)
        : bounds.center;
    return SelectionTransformInteraction._(
      source: source,
      startedAt: down.timeStamp,
      controller: controller,
      pageIndex: pageIndex,
      handle: handle,
      selection: selection,
      single: single,
      immovable: isImmovableSelection(selection),
      bounds: bounds,
      rotateCentre: centre,
      pageSize: pageSize,
      startPage: viewport.screenToPage(pageIndex, down.position),
      viewport: viewport,
      commands: commands,
      start: down.position,
      onCommitted: onCommitted,
      onFinished: onFinished,
      onTap: onTap,
      onRotate: onRotate,
    );
  }

  /// (v2, 6.6.2) Screen px a body drag must go before the move starts.
  static const double moveStartThresholdPx = 4;

  final ink.InkPageController controller;
  final int pageIndex;

  /// null = move the selection; a corner = resize from it; (v2) the rotate
  /// handle = rotate.
  final FrameHandle? handle;

  final ink.InkSelection _selection;

  /// (v2) The selection's single object (no strokes), or null.
  final core.PageObject? _single;

  /// (v2) Only unknown objects: nothing previews, nothing commits (6.6.4).
  final bool _immovable;
  final Rect _bounds;

  /// (v2) The rotation centre (page pt): the single rotating object's frame
  /// centre, else the bounds centre.
  final Offset _rotateCentre;
  final Size _pageSize;
  final Offset _startPage;
  final ViewportController _viewport;
  final EditorCommands _commands;
  final void Function(Set<String> strokeIds) _onCommitted;
  final void Function() _onFinished;
  final void Function()? _onTap;
  final void Function(double radians)? _onRotate;
  final Offset _start;
  Offset _last;
  double _travelled = 0;
  bool _done = false;

  /// false while a move has not passed the threshold (a handle: always true).
  bool _moving;

  @override
  double get travelled => _travelled;

  /// (v2) Whether the move has started (past [moveStartThresholdPx]); a
  /// handle drag is moving from the down.
  bool get isMoving => _moving;

  void _update(Offset screen) {
    _travelled += (screen - _last).distance;
    _last = screen;
    if (!_moving) {
      if ((screen - _start).distance <= moveStartThresholdPx) return;
      _moving = true;
    }
    if (_immovable) return; // unknown objects only: no preview (6.6.4)
    final page = _viewport.screenToPage(pageIndex, screen);
    final delta = page - _startPage;
    final h = handle;
    final core.Affine2 t;
    if (h == null) {
      t = ink.SelectionGeometry.move(
        SelectionHitTest.clampTranslation(_bounds, delta, _pageSize),
      );
    } else if (h.isRotate) {
      final rotation = _rotation(page);
      if (rotation == null) return;
      t = rotation;
    } else {
      final single = _single;
      if (single != null) {
        final min = ObjectResize.minimumOf(single);
        final range = ObjectResize.scaleRangeOf(single);
        t = ObjectResize.cornerScale(
          single.frame,
          h.resize!,
          delta,
          minWidth: min.width,
          minHeight: min.height,
          minScale: range.min,
          maxScale: range.max,
        );
      } else {
        t = ink.SelectionGeometry.resize(
          bounds: _bounds,
          handle: h.resize!,
          delta: delta,
          keepAspect: true,
        );
      }
    }
    _selection.setPreviewTransform(t);
  }

  /// (v2, 6.6.6) The rotation for the pen at [page] (page pt), or null while
  /// the pen sits on the centre (no angle).
  core.Affine2? _rotation(Offset page) {
    final c = _rotateCentre;
    final now = page - c, down = _startPage - c;
    if (now.distance < 1e-6 || down.distance < 1e-6) return null;
    final turned = normalizeAngle(now.direction - down.direction);
    final single = _single;
    final double radians;
    if (single != null && rotatesByFrame(single)) {
      final theta = single.frame.rotation;
      final target = ink.SelectionGeometry.snapAngle(
        normalizeAngle(theta + turned),
      );
      radians = target - theta;
      _onRotate?.call(target);
    } else {
      radians = ink.SelectionGeometry.snapAngle(turned);
      _onRotate?.call(radians);
    }
    return radians == 0
        ? core.Affine2.identity
        : core.Affine2.rotation(radians, originX: c.dx, originY: c.dy);
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
      _update(sample.position);
      if (!_moving) {
        _onTap?.call(); // a selection tap: no command (6.6.2)
        return;
      }
      if (_immovable) return;
      final ids = _selection.allIds.toSet();
      final edit = _selection.commitTransform();
      if (edit != null && _commands.commitInkEdit(controller, edit)) {
        _onCommitted(ids);
      }
    } finally {
      _onFinished();
    }
  }

  @override
  void cancel() {
    if (_done) return;
    _done = true;
    _selection.setPreviewTransform(core.Affine2.identity);
    _onFinished();
  }
}

/// [radians] folded into (−π, π].
double normalizeAngle(double radians) {
  var a = radians % (2 * math.pi); // [0, 2π)
  if (a > math.pi) a -= 2 * math.pi;
  return a;
}
