// lib/src/tools/selection_transform_interaction.dart — 04-editor 6.6.5 (moving /
// resizing the selection). (v2, E2-06 — m5-7/04-editor 6.6.2) a move starts
// only past the move-start threshold; a down that ends before it is a
// selection tap (no command).
import 'dart:ui' show Rect, Size;

import 'package:flutter/gestures.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../commands/editor_commands.dart';
import '../input/input_sample.dart';
import '../input/input_targets.dart';
import '../viewport/viewport_controller.dart';
import 'selection_hit_test.dart';
import 'tool_interaction.dart';

/// Drags the selection of [controller] (6.6.5): [handle] null = move, else a
/// keepAspect resize from that corner. Every move sets INK's preview transform
/// (INK paints it): move = ink.SelectionGeometry.move(clampTranslation(bounds,
/// delta, pageSize)), resize = ink.SelectionGeometry.resize(bounds, handle,
/// delta, keepAspect: true) — delta in page pt from pen down. At the end
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
final class SelectionTransformInteraction extends ToolInteraction {
  SelectionTransformInteraction._({
    required super.source,
    required super.startedAt,
    required this.controller,
    required this.pageIndex,
    required this.handle,
    required this._selection,
    required this._bounds,
    required this._pageSize,
    required this._startPage,
    required this._viewport,
    required this._commands,
    required Offset start,
    required this._onCommitted,
    required this._onFinished,
    required this._onTap,
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
    required ink.SelectionHandle? handle,
    required ViewportController viewport,
    required EditorCommands commands,
    required void Function(Set<String> strokeIds) onCommitted,
    required void Function() onFinished,
    void Function()? onTap,
  }) => SelectionTransformInteraction._(
    source: source,
    startedAt: down.timeStamp,
    controller: controller,
    pageIndex: pageIndex,
    handle: handle,
    selection: selection,
    bounds: selection.bounds,
    pageSize: pageSize,
    startPage: viewport.screenToPage(pageIndex, down.position),
    viewport: viewport,
    commands: commands,
    start: down.position,
    onCommitted: onCommitted,
    onFinished: onFinished,
    onTap: onTap,
  );

  /// (v2, 6.6.2) Screen px a body drag must go before the move starts.
  static const double moveStartThresholdPx = 4;

  final ink.InkPageController controller;
  final int pageIndex;

  /// null = move the selection; a corner = resize from it.
  final ink.SelectionHandle? handle;

  final ink.InkSelection _selection;
  final Rect _bounds;
  final Size _pageSize;
  final Offset _startPage;
  final ViewportController _viewport;
  final EditorCommands _commands;
  final void Function(Set<String> strokeIds) _onCommitted;
  final void Function() _onFinished;
  final void Function()? _onTap;
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
    final delta = _viewport.screenToPage(pageIndex, screen) - _startPage;
    final h = handle;
    final core.Affine2 t = h == null
        ? ink.SelectionGeometry.move(
            SelectionHitTest.clampTranslation(_bounds, delta, _pageSize),
          )
        : ink.SelectionGeometry.resize(
            bounds: _bounds,
            handle: h,
            delta: delta,
            keepAspect: true,
          );
    _selection.setPreviewTransform(t);
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
