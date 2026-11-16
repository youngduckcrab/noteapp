// lib/src/ui/overlays/selection_frame_painter.dart — 04-editor 6.6.5 (selection
// display); (v2) m5-7/04-editor 6.6.4 (frame v2) — E2-06; (E2-08) edge
// squares, vertex circles and a line's / an arrow's segment.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../document/mounted_pages.dart';
import '../../scope/editor_scope.dart';
import '../../tools/selection.dart';
import '../../tools/selection_hit_test.dart';
import '../../viewport/viewport_controller.dart';

/// Paints the selection frame in viewport coordinates (v2 — 6.6.4,
/// selectionFrameOnScreen): a dashed 1 px quad (colorScheme.primary, dash 6 /
/// 4) — INK's bounds for several elements (turned by a rotation preview),
/// the object's own — possibly rotated — frame for one object — the corner
/// handles (12 px circles, [fill] inside, primary border), (E2-08) the edge
/// handles (10 px squares turned with the frame), the vertex handles (10 px
/// circles) — a line / an arrow: the dashed segment between its end points,
/// no box — and the rotate handle: a circle
/// [SelectionHitTest.rotateHandleOffset] px outside the top edge's middle,
/// joined to it by a line. Repaints from the viewport and
/// the selected page's INK controller (selection changes and preview
/// transforms) — no provider state changes while dragging.
class SelectionFramePainter extends CustomPainter {
  SelectionFramePainter({
    required this.viewport,
    required this.pages,
    required this.selection,
    required this.color,
    required this.fill,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final ViewportController viewport;
  final MountedPages pages;
  final EditorSelection? selection;
  final Color color;
  final Color fill;

  static const double lineWidth = 1;
  static const double dash = 6;
  static const double gap = 4;
  static const double handleBorder = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = selectionFrameOnScreen(viewport, pages, selection);
    if (frame == null) return;
    final quad = frame.quad;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..color = color;
    _dashed(canvas, quad.topLeft, quad.topRight, line);
    if (frame.boxed) {
      _dashed(canvas, quad.topRight, quad.bottomRight, line);
      _dashed(canvas, quad.bottomRight, quad.bottomLeft, line);
      _dashed(canvas, quad.bottomLeft, quad.topLeft, line);
    }
    final inside = Paint()..color = fill;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = handleBorder
      ..color = color;
    for (final handle in frame.handles) {
      final c = quad.handlePosition(handle);
      if (SelectionHitTest.cornerHandles.contains(handle)) {
        canvas
          ..drawCircle(c, SelectionHitTest.handleVisualRadius, inside)
          ..drawCircle(c, SelectionHitTest.handleVisualRadius, border);
      } else {
        // An edge handle: a square turned with the frame (6.6.4).
        canvas
          ..save()
          ..translate(c.dx, c.dy)
          ..rotate(quad.angle);
        const half = SelectionHitTest.edgeHandleHalfSide;
        const square = Rect.fromLTRB(-half, -half, half, half);
        canvas
          ..drawRect(square, inside)
          ..drawRect(square, border)
          ..restore();
      }
    }
    for (final v in frame.vertices) {
      canvas
        ..drawCircle(v, SelectionHitTest.vertexVisualRadius, inside)
        ..drawCircle(v, SelectionHitTest.vertexVisualRadius, border);
    }
    if (frame.rotatable) {
      final knob = quad.rotateHandlePosition;
      final toward = quad.rotateHandleBase - knob;
      final length = toward.distance;
      final edge = length > SelectionHitTest.handleVisualRadius
          ? knob + toward * (SelectionHitTest.handleVisualRadius / length)
          : knob;
      canvas
        ..drawLine(edge, quad.rotateHandleBase, line)
        ..drawCircle(knob, SelectionHitTest.handleVisualRadius, inside)
        ..drawCircle(knob, SelectionHitTest.handleVisualRadius, border);
    }
  }

  static void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final length = (b - a).distance;
    if (length == 0) return;
    final dir = (b - a) / length;
    for (var t = 0.0; t < length; t += dash + gap) {
      final end = t + dash < length ? t + dash : length;
      canvas.drawLine(a + dir * t, a + dir * end, paint);
    }
  }

  @override
  bool shouldRepaint(SelectionFramePainter oldDelegate) =>
      !identical(oldDelegate.viewport, viewport) ||
      !identical(oldDelegate.pages, pages) ||
      oldDelegate.selection != selection ||
      oldDelegate.color != color ||
      oldDelegate.fill != fill;
}

/// The selection frame layer of the page area (IgnorePointer — 6.4.3).
/// (v2) Under the painting, an empty box keyed [rotateHandleKey] sits on the
/// rotate handle's hit area (appendix C — app smoke tests find the handle by
/// it; the pointer still reaches the page area's Listener).
class SelectionFrame extends ConsumerWidget {
  const SelectionFrame({super.key});

  /// (v2, appendix C) The rotate handle's hit area.
  static const rotateHandleKey = ValueKey('editor.selection.rotateHandle');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(editorSelectionProvider);
    final viewport = ref.watch(editorViewportProvider);
    final pages = ref.watch(editorMountedPagesProvider);
    final repaint = selectionRepaint(viewport, pages, selection);
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ListenableBuilder(
            listenable: repaint,
            builder: (context, _) {
              final frame = selectionFrameOnScreen(viewport, pages, selection);
              if (frame == null || !frame.rotatable) {
                return const SizedBox.shrink();
              }
              const side = SelectionHitTest.handleHitRadius * 2;
              final at = frame.quad.rotateHandlePosition;
              return Stack(
                children: [
                  Positioned(
                    left: at.dx - side / 2,
                    top: at.dy - side / 2,
                    width: side,
                    height: side,
                    child: const SizedBox(key: rotateHandleKey),
                  ),
                ],
              );
            },
          ),
          RepaintBoundary(
            child: CustomPaint(
              painter: SelectionFramePainter(
                viewport: viewport,
                pages: pages,
                selection: selection,
                // (v2.14-ui) drawn on paper: the paper tokens.
                color: StyleTokens.of(context).paperAccent,
                fill: StyleTokens.of(context).inkSwatch,
                repaint: repaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What moves the selection frame: the camera, the mounted pages and the
/// selected page's INK controller (selection object, preview transform).
Listenable selectionRepaint(
  ViewportController viewport,
  MountedPages pages,
  EditorSelection? selection,
) {
  final controller = selection == null
      ? null
      : pages[selection.pageId]?.controller;
  return Listenable.merge([
    viewport,
    pages,
    if (controller != null) ...[
      controller,
      controller.layerRepaint(ink.InkRenderLayer.overlay),
    ],
  ]);
}
