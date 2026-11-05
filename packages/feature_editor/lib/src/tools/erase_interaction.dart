// lib/src/tools/erase_interaction.dart — 04-editor 6.6.4.
import 'package:flutter/gestures.dart';
import 'package:ink_engine/ink_engine.dart' as ink;

import '../commands/editor_commands.dart';
import '../input/input_sample.dart';
import '../input/input_targets.dart';
import '../viewport/viewport_controller.dart';
import 'pen_interaction.dart' show toInkSample;
import 'tool_interaction.dart';
import 'tool_state.dart';

/// Drives one ink.EraserSession from pen down to up (6.6.4):
///   1. start: controller.beginErase(toInk(down), spec: eraser.toSpec() — radius =
///      diameter / 2 pt, filter — viewScale: camera scale after settleNow);
///   2. every move → erase.addSample (no filtering; partial-eraser pieces are
///      INK's job — contract 7.2.7, CD-10);
///   3. up → erase.end(toInk(up)) → EditorCommands.commitInkEdit: the whole
///      gesture is ONE RemoveStrokes / SplitStrokes (F-08, one undo step).
///      [onCommitted] (return to the previous tool) only when the command was
///      accepted — a rejected commit has already called discardEdit, so the
///      erased strokes show again;
///   4. cancel → erase.cancel(): no command, the touched strokes show again.
/// [onPosition] gets every screen position (the eraser ring follows the pen)
/// and [onFinished] runs once at end or cancel (the ring hides).
final class EraseInteraction extends ToolInteraction {
  EraseInteraction._({
    required super.source,
    required super.startedAt,
    required this.controller,
    required this.pageIndex,
    required this.viewScale,
    required this.eraser,
    required this._viewport,
    required this._commands,
    required this._session,
    required Offset start,
    required this._onPosition,
    required this._onFinished,
    required this._onCommitted,
  }) : _last = start;

  /// Starts erasing at [down]. The caller has already settled the viewport
  /// (InteractionHost: viewport.settleNow()).
  factory EraseInteraction.start({
    required InputSample down,
    required InteractionSource source,
    required ink.InkPageController controller,
    required int pageIndex,
    required ViewportController viewport,
    required EraserSettings eraser,
    required EditorCommands commands,
    void Function(Offset screen)? onPosition,
    void Function()? onFinished,
    void Function()? onCommitted,
  }) {
    final viewScale = viewport.camera.scale;
    final session = controller.beginErase(
      toInkSample(viewport, pageIndex, down.event),
      spec: eraser.toSpec(),
      viewScale: viewScale,
    );
    onPosition?.call(down.position);
    return EraseInteraction._(
      source: source,
      startedAt: down.timeStamp,
      controller: controller,
      pageIndex: pageIndex,
      viewScale: viewScale,
      eraser: eraser,
      viewport: viewport,
      commands: commands,
      session: session,
      start: down.position,
      onPosition: onPosition,
      onFinished: onFinished,
      onCommitted: onCommitted,
    );
  }

  final ink.InkPageController controller;
  final int pageIndex;

  /// The viewScale handed to INK (logical px per page pt at pen down).
  final double viewScale;

  /// The eraser settings of this gesture (taken at pen down).
  final EraserSettings eraser;

  final ViewportController _viewport;
  final EditorCommands _commands;
  final ink.EraserSession _session;
  final void Function(Offset screen)? _onPosition;
  final void Function()? _onFinished;
  final void Function()? _onCommitted;
  Offset _last;
  double _travelled = 0;
  bool _done = false;

  /// Whether the gesture has ended or been cancelled.
  bool get isDone => _done;

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
    _onPosition?.call(sample.position);
  }

  @override
  void end(InputSample sample) {
    if (_done) return;
    _done = true;
    _track(sample.position);
    final ink.InkEdit? edit;
    try {
      edit = _session.end(toInkSample(_viewport, pageIndex, sample.event));
    } finally {
      _onFinished?.call();
    }
    if (edit == null) return; // nothing touched → no command
    if (_commands.commitInkEdit(controller, edit)) _onCommitted?.call();
  }

  @override
  void cancel() {
    if (_done) return;
    _done = true;
    _session.cancel();
    _onFinished?.call();
  }
}
