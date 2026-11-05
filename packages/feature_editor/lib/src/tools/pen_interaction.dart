// lib/src/tools/pen_interaction.dart — 04-editor 6.6.3.
import 'package:flutter/gestures.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../commands/editor_commands.dart';
import '../input/input_sample.dart';
import '../input/input_targets.dart';
import '../viewport/viewport_controller.dart';
import 'tool_interaction.dart';

/// Converts a routed pointer event to an INK sample on page [pageIndex]
/// (INK 5.3 #1): the page position comes from the viewport, points outside the
/// page are kept as they are (6.2).
ink.InkSample toInkSample(
  ViewportController viewport,
  int pageIndex,
  PointerEvent event,
) => ink.InkSampleAdapter.fromPointerEvent(
  event,
  pagePosition: viewport.screenToPage(pageIndex, event.localPosition),
);

/// Drives one ink.StrokeSession from pen down to up (6.6.3):
///   1. start: controller.beginStroke(toInk(down), style: current pen, viewScale: camera
///      scale after settleNow — logical px per pt, contract 7.2.15 v1.1);
///   2. every move → stroke.addSample (no filtering or batching — contract E-1);
///   3. up → stroke.end(toInk(up)) → EditorCommands.commitInkEdit; [onCommitted] (recent
///      colour) only when the command was accepted — a rejected commit has already
///      dropped the pending stroke (discardEdit);
///   4. cancel → stroke.cancel(): no command, INK removes the preview.
final class PenInteraction extends ToolInteraction {
  PenInteraction._({
    required super.source,
    required super.startedAt,
    required this.controller,
    required this.pageIndex,
    required this.viewScale,
    required this.style,
    required this._viewport,
    required this._commands,
    required this._session,
    required Offset start,
    required this._onCommitted,
  }) : _last = start;

  /// Starts the stroke at [down]. The caller has already settled the
  /// viewport (InteractionHost: viewport.settleNow()).
  factory PenInteraction.start({
    required InputSample down,
    required InteractionSource source,
    required ink.InkPageController controller,
    required int pageIndex,
    required ViewportController viewport,
    required core.StrokeStyle style,
    required EditorCommands commands,
    required void Function(core.StrokeStyle style) onCommitted,
  }) {
    final viewScale = viewport.camera.scale;
    final session = controller.beginStroke(
      toInkSample(viewport, pageIndex, down.event),
      style: style,
      viewScale: viewScale,
    );
    return PenInteraction._(
      source: source,
      startedAt: down.timeStamp,
      controller: controller,
      pageIndex: pageIndex,
      viewScale: viewScale,
      style: session.style,
      viewport: viewport,
      commands: commands,
      session: session,
      start: down.position,
      onCommitted: onCommitted,
    );
  }

  final ink.InkPageController controller;
  final int pageIndex;

  /// The viewScale handed to INK (logical px per page pt at pen down).
  final double viewScale;

  /// The normalized style of the stroke.
  final core.StrokeStyle style;

  final ViewportController _viewport;
  final EditorCommands _commands;
  final ink.StrokeSession _session;
  final void Function(core.StrokeStyle style) _onCommitted;
  Offset _last;
  double _travelled = 0;
  bool _done = false;

  @override
  double get travelled => _travelled;

  void _track(Offset position) {
    _travelled += (position - _last).distance;
    _last = position;
  }

  @override
  void move(InputSample sample) {
    if (_done) return;
    _track(sample.position);
    _session.addSample(toInkSample(_viewport, pageIndex, sample.event));
  }

  @override
  void end(InputSample sample) {
    if (_done) return;
    _done = true;
    _track(sample.position);
    final edit = _session.end(toInkSample(_viewport, pageIndex, sample.event));
    if (edit == null) return;
    if (_commands.commitInkEdit(controller, edit)) _onCommitted(style);
  }

  @override
  void cancel() {
    if (_done) return;
    _done = true;
    _session.cancel();
  }
}
