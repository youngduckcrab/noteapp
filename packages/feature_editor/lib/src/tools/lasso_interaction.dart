// lib/src/tools/lasso_interaction.dart — 04-editor 6.6.5 (drawing the lasso).
// (v2, E2-06 — m5-7/04-editor 6.6.3) the lasso takes strokes and objects
// (INK's allIds); a tap with the lasso tool selects the object under it.
import 'package:flutter/gestures.dart';
import 'package:ink_engine/ink_engine.dart' as ink;

import '../input/input_sample.dart';
import '../input/input_targets.dart';
import '../input/input_thresholds.dart';
import '../viewport/viewport_controller.dart';
import 'tool_interaction.dart';

/// Drives one ink.LassoSession (6.6.5). The caller cleared the old selection
/// and settled the viewport. A point joins the lasso only after the pen moved
/// [minStepPx] screen px from the last one; the path is painted by INK's
/// overlay. At the end a non-null selection (INK's inclusion rule — contract
/// LassoOptions) goes to [onSelected]; a degenerate or empty lasso selects
/// nothing. The lasso stays on the page it started on (points outside the
/// page are kept as they are).
///
/// (v2) The selection is INK's allIds (strokes and objects — LassoOptions
/// includeObjects: an object whose frame centre is inside). A tap (the pen
/// stayed within the tap distance of its source: 4 px for a pen or a mouse,
/// 20 px for a finger) that selects nothing picks the topmost object under
/// the down point (controller.hitTestObject — 6.3.5 ④).
final class LassoInteraction extends ToolInteraction {
  LassoInteraction._({
    required super.source,
    required super.startedAt,
    required this.controller,
    required this.pageIndex,
    required this.pageId,
    required this._viewport,
    required this._session,
    required Offset start,
    required this._onSelected,
  }) : _start = start,
       _last = start,
       _lastAdded = start;

  factory LassoInteraction.start({
    required InputSample down,
    required InteractionSource source,
    required ink.InkPageController controller,
    required int pageIndex,
    required String pageId,
    required ViewportController viewport,
    required void Function(String pageId, Set<String> elementIds) onSelected,
  }) {
    final session = controller.beginLasso(
      viewport.screenToPage(pageIndex, down.position),
      viewScale: viewport.camera.scale,
    );
    return LassoInteraction._(
      source: source,
      startedAt: down.timeStamp,
      controller: controller,
      pageIndex: pageIndex,
      pageId: pageId,
      viewport: viewport,
      session: session,
      start: down.position,
      onSelected: onSelected,
    );
  }

  /// Screen distance a point must be from the last lasso point (6.6.5).
  static const double minStepPx = 3;

  final ink.InkPageController controller;
  final int pageIndex;
  final String pageId;
  final ViewportController _viewport;
  final ink.LassoSession _session;
  final void Function(String pageId, Set<String> elementIds) _onSelected;
  final Offset _start;
  Offset _last;
  Offset _lastAdded;
  double _travelled = 0;
  double _maxFromStart = 0;
  bool _done = false;

  @override
  double get travelled => _travelled;

  /// (v2) How far from the down a lasso may go and still be a tap.
  double get _tapSlop => switch (source) {
    InteractionSource.finger => const InputThresholds().tapMaxMovement,
    InteractionSource.stylus ||
    InteractionSource.mouse => const InputThresholds().penTapMaxMovement,
  };

  void _add(Offset screen) {
    _travelled += (screen - _last).distance;
    final fromStart = (screen - _start).distance;
    if (fromStart > _maxFromStart) _maxFromStart = fromStart;
    _last = screen;
    if ((screen - _lastAdded).distance < minStepPx) return;
    _lastAdded = screen;
    _session.addPoint(_viewport.screenToPage(pageIndex, screen));
  }

  @override
  void move(InputSample sample) {
    if (_done) return;
    _add(sample.position);
  }

  @override
  void end(InputSample sample) {
    if (_done) return;
    _done = true;
    _add(sample.position);
    final selection = _session.end();
    if (selection != null && !selection.isEmpty) {
      _onSelected(pageId, selection.allIds);
      return;
    }
    if (_maxFromStart > _tapSlop) return;
    final object = controller.hitTestObject(
      _viewport.screenToPage(pageIndex, _start),
    );
    if (object != null) _onSelected(pageId, {object.id});
  }

  @override
  void cancel() {
    if (_done) return;
    _done = true;
    _session.cancel();
  }
}
