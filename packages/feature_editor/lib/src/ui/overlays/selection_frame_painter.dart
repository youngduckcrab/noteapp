// lib/src/ui/overlays/selection_frame_painter.dart — 04-editor 6.6.5 (selection display).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';

import '../../document/mounted_pages.dart';
import '../../scope/editor_scope.dart';
import '../../tools/selection.dart';
import '../../tools/selection_hit_test.dart';
import '../../viewport/viewport_controller.dart';

/// Paints the selection frame in viewport coordinates: INK's previewBounds
/// (page pt) on screen as a dashed 1 px rectangle (colorScheme.primary, dash
/// 6 / 4) and the 4 corner handles (12 px circles, [fill] inside, primary
/// border). Repaints from the viewport and the selected page's INK controller
/// (selection changes and preview transforms) — no provider state changes
/// while dragging.
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
    final rect = selectionRectOnScreen(viewport, pages, selection);
    if (rect == null) return;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..color = color;
    _dashed(canvas, rect.topLeft, rect.topRight, line);
    _dashed(canvas, rect.topRight, rect.bottomRight, line);
    _dashed(canvas, rect.bottomRight, rect.bottomLeft, line);
    _dashed(canvas, rect.bottomLeft, rect.topLeft, line);
    final inside = Paint()..color = fill;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = handleBorder
      ..color = color;
    for (final handle in SelectionHitTest.cornerHandles) {
      final c = SelectionHitTest.handlePosition(rect, handle);
      canvas
        ..drawCircle(c, SelectionHitTest.handleVisualRadius, inside)
        ..drawCircle(c, SelectionHitTest.handleVisualRadius, border);
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
class SelectionFrame extends ConsumerWidget {
  const SelectionFrame({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(editorSelectionProvider);
    final viewport = ref.watch(editorViewportProvider);
    final pages = ref.watch(editorMountedPagesProvider);
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: SelectionFramePainter(
            viewport: viewport,
            pages: pages,
            selection: selection,
            color: scheme.primary,
            fill: scheme.surface,
            repaint: selectionRepaint(viewport, pages, selection),
          ),
        ),
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
