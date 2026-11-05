// lib/src/ui/content/new_note_tile.dart — 05-library 6.7: the first cell of
// a folder section's grid (dashed border + Icons.add + '새 노트'). Hidden in
// selection mode; the list view has none.
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show FolderId;

import '../../l10n/library_strings.dart';
import '../layout/grid_metrics.dart';
import 'new_note_trigger.dart';
import 'tile_parts.dart';

class NewNoteTile extends StatelessWidget {
  const NewNoteTile({super.key, required this.folderId, required this.metrics});

  final FolderId? folderId;
  final GridMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NewNoteTrigger(
      folderId: folderId,
      builder: (context, onPressed) => SizedBox(
        width: metrics.tileWidth,
        height: metrics.tileHeight,
        child: Semantics(
          container: true,
          button: true,
          enabled: onPressed != null,
          label: LibraryStrings.newNote,
          excludeSemantics: true,
          onTap: onPressed,
          child: InkWell(
            onTap: onPressed,
            borderRadius: TileCoverBox.radius,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: metrics.tileWidth,
                  height: metrics.coverHeight,
                  child: CustomPaint(
                    painter: _DashedBorderPainter(color: scheme.outline),
                    child: Center(
                      child: Icon(Icons.add, size: 40, color: scheme.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const TileFooterText(title: LibraryStrings.newNote, meta: ''),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 1.5 px dashes (6 on, 4 off) along a rounded rectangle (corner 8).
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = (Offset.zero & size).deflate(0.75);
    final outline = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));
    const dash = 6.0, gap = 4.0;
    for (final metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = distance + dash;
        canvas.drawPath(
          metric.extractPath(
            distance,
            end < metric.length ? end : metric.length,
          ),
          paint,
        );
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
