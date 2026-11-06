// lib/src/tools/selection_transform_interaction.dart — 04-editor 6.6.5 (moving /
// resizing the selection).
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
  }) : _last = start;

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
  );

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
  Offset _last;
  double _travelled = 0;
  bool _done = false;

  @override
  double get travelled => _travelled;

  void _update(Offset screen) {
    _travelled += (screen - _last).distance;
    _last = screen;
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
