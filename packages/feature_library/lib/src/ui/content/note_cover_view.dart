// lib/src/ui/content/note_cover_view.dart — 05-library 6.15.1. The cover box
// of a note tile / row. Task L10 draws the placeholder for every cover; the
// four cover kinds (first page thumbnail, color card, asset image) and the
// thumbnail scheduler come with L11 (it becomes a ConsumerStatefulWidget
// then; the constructor stays).
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show Note;

class NoteCoverView extends StatelessWidget {
  const NoteCoverView({
    super.key,
    required this.note,
    required this.width,
    required this.height,
  });
  final Note note;
  final double width, height; // logical px of the cover box

  @override
  Widget build(BuildContext context) =>
      CoverPlaceholder(width: width, height: height);
}

/// surfaceContainerHigh + Icons.description_outlined (onSurfaceVariant 60%),
/// 40 px (smaller boxes scale it down).
class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({
    super.key,
    required this.width,
    required this.height,
  });

  final double width, height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shortest = width < height ? width : height;
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: scheme.surfaceContainerHigh,
        child: Center(
          child: Icon(
            Icons.description_outlined,
            size: shortest < 64 ? shortest * 0.6 : 40,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}
