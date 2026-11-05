// lib/src/ui/pen/pen_preview.dart — 04-editor 6.9.3 #2 (preview 300 × 56).
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../scope/editor_scope.dart';
import '../editor_strings.dart';

/// INK's sample stroke for [style] at the note's zoom: the canvas is
/// Transform.scale'd by clamp(settledScale, 0.5, 4.0) and painted by
/// ink.PenPreviewPainter with the PencilGrain object itself (contract 7.2.16
/// v1.1 — the painter repaints on it when the grain is ready). When width ×
/// zoom passes [maxInkPx] the stroke is cut and '확대 n%' is shown.
class PenPreview extends ConsumerWidget {
  const PenPreview({
    super.key,
    required this.style,
    this.size = const Size(300, 56),
  });

  final core.StrokeStyle style;
  final Size size;

  static const paintKey = ValueKey('editor.pen.preview.paint');
  static const zoomLabelKey = ValueKey('editor.pen.preview.zoom');

  static const double minScale = 0.5;
  static const double maxScale = 4.0;

  /// Thickest stroke the preview shows uncut (px).
  static const double maxInkPx = 48;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grain = ref.watch(ink.pencilGrainProvider);
    final viewport = ref.watch(editorViewportProvider);
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => ValueListenableBuilder<double>(
        valueListenable: viewport.settledScale,
        builder: (context, settled, _) => _build(
          context,
          scheme,
          grain,
          Size(math.min(size.width, constraints.maxWidth), size.height),
          settled.clamp(minScale, maxScale),
        ),
      ),
    );
  }

  Widget _build(
    BuildContext context,
    ColorScheme scheme,
    ink.PencilGrain grain,
    Size box,
    double scale,
  ) {
    final cut = style.width * scale > maxInkPx;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: box.width,
        height: box.height,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0, // loose constraints: the canvas keeps its own size
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topLeft,
                child: CustomPaint(
                  key: paintKey,
                  size: Size(box.width / scale, box.height / scale),
                  painter: ink.PenPreviewPainter(
                    style: style,
                    pencilGrain: grain,
                  ),
                ),
              ),
            ),
            if (cut)
              Positioned(
                right: 6,
                bottom: 4,
                child: Text(
                  EditorStrings.previewZoom((scale * 100).round()),
                  key: zoomLabelKey,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
