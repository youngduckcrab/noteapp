// lib/src/ui/content/note_tile.dart — 05-library 6.8: a note in the grid.
// Cover (width × width / 0.75) with the favorite ★ and the newer-app badge,
// then `[title 2 lines][⋯ 44]` and the modified date. The ⋯ menu comes with
// L13, selection with L14, dragging with L15.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show Note, clockProvider;

import '../../l10n/library_date_format.dart';
import '../../l10n/library_strings.dart';
import '../layout/grid_metrics.dart';
import '../layout/library_metrics.dart';
import 'note_cover_view.dart';
import 'tile_parts.dart';

class NoteTile extends ConsumerWidget {
  const NoteTile({super.key, required this.note, required this.metrics});

  final Note note;
  final GridMetrics metrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final date = formatLibraryDate(
      note.updatedAt,
      now: ref.watch(clockProvider).now(),
    );
    final newer = note.requiresNewerApp;
    final width = metrics.tileWidth;
    final coverHeight = metrics.coverHeight;
    void open() => openLibraryNote(context, note);
    return RepaintBoundary(
      child: SizedBox(
        width: width,
        height: metrics.tileHeight,
        child: Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                container: true,
                button: true,
                label: LibraryStrings.noteSemantics(note.title, date),
                excludeSemantics: true,
                onTap: open,
                child: InkWell(
                  onTap: open,
                  borderRadius: TileCoverBox.radius,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TileCoverBox(
                        width: width,
                        height: coverHeight,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            NoteCoverView(
                              note: note,
                              width: width,
                              height: coverHeight,
                            ),
                            if (note.isFavorite)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: CoverCornerBadge(
                                  icon: Icons.star,
                                  color: scheme.tertiary,
                                ),
                              ),
                            if (newer)
                              Positioned(
                                left: 6,
                                bottom: 6,
                                child: CoverCornerBadge(
                                  icon: Icons.upgrade,
                                  color: scheme.primary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: LibraryMetrics.minTapTarget,
                        ),
                        child: TileFooterText(
                          title: note.title,
                          meta: newer ? LibraryStrings.requiresNewerApp : date,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // L13: the ⋯ menu (44 × 44) at the end of the title row.
          ],
        ),
      ),
    );
  }
}
