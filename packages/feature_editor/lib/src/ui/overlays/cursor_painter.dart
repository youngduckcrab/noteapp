// lib/src/ui/overlays/cursor_painter.dart — 04-editor 6.6.9.
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../tools/interaction_host.dart';

/// Paints the hover cursor in viewport coordinates: a filled dot in the pen
/// colour (PenDotCursor) or a 1.5 px ring (EraserRingCursor, [ringColor]).
/// Repaints from [cursor] directly (hot path — no widget rebuild).
class CursorPainter extends CustomPainter {
  CursorPainter({required this.cursor, required this.ringColor})
    : super(repaint: cursor);

  final ValueListenable<CursorState?> cursor;

  /// colorScheme.onSurface at 60% (6.6.9).
  final Color ringColor;

  static const double ringWidth = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    switch (cursor.value) {
      case PenDotCursor(:final position, :final diameter, :final color):
        canvas.drawCircle(position, diameter / 2, Paint()..color = color);
      case EraserRingCursor(:final position, :final diameter):
        canvas.drawCircle(
          position,
          diameter / 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = ringWidth
            ..color = ringColor,
        );
      case null:
        break;
    }
  }

  @override
  bool shouldRepaint(CursorPainter oldDelegate) =>
      !identical(oldDelegate.cursor, cursor) ||
      oldDelegate.ringColor != ringColor;
}
