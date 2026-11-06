// lib/src/tools/text_tool_interaction.dart — m5-7/04-editor 6.11.1 (E2-10):
// the text tool's down on the canvas. A down only gets here past the
// selection priority (a′) (6.6.2): a handle of the selection never does, the
// body of a lasso / paste / insert selection moves it; a tap-selected object's
// body (origin tap) drops that selection and starts here — a new box.
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';

import '../input/input_sample.dart';
import '../input/input_targets.dart';
import '../text/text_box_placement.dart';
import '../viewport/viewport_controller.dart';
import 'tool_interaction.dart';

/// The empty box outline while a new box is dragged (6.11.1 — drawn by the
/// EDITOR overlay NewTextBoxOutline, never an INK preview object): [rectPt]
/// in page pt of page [pageIndex].
@immutable
final class NewTextBoxOutlineState {
  const NewTextBoxOutlineState({
    required this.pageId,
    required this.pageIndex,
    required this.rectPt,
  });
  final String pageId;
  final int pageIndex;
  final Rect rectPt;

  @override
  bool operator ==(Object other) =>
      other is NewTextBoxOutlineState &&
      other.pageId == pageId &&
      other.pageIndex == pageIndex &&
      other.rectPt == rectPt;

  @override
  int get hashCode => Object.hash(pageId, pageIndex, rectPt);
}

/// A tap or a drag of the text tool (6.11.1). Every move past [tapSlopPx]
/// (the farthest point from the down, screen px) shows the new box's outline
/// through [onOutline]: top-left = the dragged rectangle's top-left, width =
/// its width (at least [TextBoxPlacement.minWidth]), height = one line
/// ([lineHeightPt]); the points are kept on the page. The end: never past
/// the slop → a tap, [onTap] with the down's screen point (the host edits the
/// text box there, selects another object or starts a new box by the tap
/// rule); else [onDrag] with the outline's rectangle (a new box there).
/// Either way the outline is cleared. Cancel: the outline cleared, nothing
/// else.
final class TextToolInteraction extends ToolInteraction {
  TextToolInteraction._({
    required super.source,
    required super.startedAt,
    required this.pageId,
    required this.pageIndex,
    required this.lineHeightPt,
    required this._viewport,
    required this._onOutline,
    required this._onTap,
    required this._onDrag,
    required Offset start,
  }) : _start = start,
       _last = start;

  factory TextToolInteraction.start({
    required InputSample down,
    required InteractionSource source,
    required String pageId,
    required int pageIndex,
    required double lineHeightPt,
    required ViewportController viewport,
    required void Function(NewTextBoxOutlineState? outline) onOutline,
    required void Function(Offset screen) onTap,
    required void Function(Rect rectPt) onDrag,
  }) => TextToolInteraction._(
    source: source,
    startedAt: down.timeStamp,
    pageId: pageId,
    pageIndex: pageIndex,
    lineHeightPt: lineHeightPt,
    viewport: viewport,
    onOutline: onOutline,
    onTap: onTap,
    onDrag: onDrag,
    start: down.position,
  );

  /// A down → up that never got farther than this (screen px) is a tap —
  /// the shape tool's number (6.9.2).
  static const double tapSlopPx = 8;

  final String pageId;
  final int pageIndex;

  /// One line of the new box's style (fontSizePt × lineHeight).
  final double lineHeightPt;
  final ViewportController _viewport;
  final void Function(NewTextBoxOutlineState?) _onOutline;
  final void Function(Offset screen) _onTap;
  final void Function(Rect rectPt) _onDrag;
  final Offset _start;
  Offset _last;
  double _travelled = 0;
  double _farthest = 0;
  bool _done = false;
  Rect? _rect;

  @override
  double get travelled => _travelled;

  /// The outline's rectangle for a drag from the down to [screen] (page pt).
  Rect _rectTo(Offset screen) {
    final size = _viewport.pages[pageIndex].size;
    Offset onPage(Offset s) {
      final p = _viewport.screenToPage(pageIndex, s);
      return Offset(
        p.dx.clamp(0.0, size.width).toDouble(),
        p.dy.clamp(0.0, size.height).toDouble(),
      );
    }

    final a = onPage(_start), b = onPage(screen);
    final width = math.max((b.dx - a.dx).abs(), TextBoxPlacement.minWidth);
    var left = math.min(a.dx, b.dx);
    // A narrow drag at the page's right edge: the box moves left (6.11.1).
    if (left + width > size.width) {
      left = math.max(0.0, size.width - width);
    }
    return Rect.fromLTWH(left, math.min(a.dy, b.dy), width, lineHeightPt);
  }

  void _update(Offset screen) {
    _travelled += (screen - _last).distance;
    _last = screen;
    final d = (screen - _start).distance;
    if (d > _farthest) _farthest = d;
    if (_farthest <= tapSlopPx) return;
    final rect = _rect = _rectTo(screen);
    _onOutline(
      NewTextBoxOutlineState(
        pageId: pageId,
        pageIndex: pageIndex,
        rectPt: rect,
      ),
    );
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
      _onOutline(null);
      final rect = _rect;
      if (_farthest <= tapSlopPx || rect == null) {
        _onTap(_start);
      } else {
        _onDrag(rect);
      }
    } finally {
      _onOutline(null);
    }
  }

  @override
  void cancel() {
    if (_done) return;
    _done = true;
    _onOutline(null);
  }
}
