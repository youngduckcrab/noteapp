// lib/src/ui/content/tile_parts.dart — 05-library 6.8: pieces shared by the
// grid tiles and list rows.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show Folder, Note;

import '../../appearance/folder_appearance.dart';
import '../../l10n/library_strings.dart';
import '../../model/item_key.dart';
import '../../state/providers.dart';
import '../../state/selection_notifier.dart';
import '../feedback/library_snack_bar.dart';
import '../layout/library_metrics.dart';
import '../library_scope.dart';

/// Opens [note] (6.4), or explains why not: a note made by a newer app
/// version (requiresNewerApp) is not opened; the same text shows in a snack
/// bar (6.8).
void openLibraryNote(BuildContext context, Note note) {
  final scope = LibraryScope.read(context);
  if (note.requiresNewerApp) {
    showLibrarySnackBar(
      context,
      message: LibraryStrings.requiresNewerApp,
      sizeClass: scope.sizeClass,
    );
    return;
  }
  scope.openNote(note.id);
}

/// Selection mode and whether [key] is selected (6.9) — rebuilds only when
/// one of the two changes.
({bool active, bool selected}) watchItemSelection(
  WidgetRef ref,
  BuildContext context,
  LibraryItemKey key,
) {
  final routeFolderId = LibraryScope.of(context).routeFolderId;
  return ref.watch(
    librarySelectionProvider(routeFolderId)
        .select((s) => (active: s.active, selected: s.contains(key))),
  );
}

/// Tap in selection mode: toggles [key] (opens nothing, 6.9).
void toggleItemSelection(BuildContext context, LibraryItemKey key) =>
    _selectionNotifier(context).toggle(key);

/// Long press on an item: selection mode with [key] included (6.9). L15
/// moves this to the drag start (LibraryDraggable.onDragStarted).
void addItemToSelection(BuildContext context, LibraryItemKey key) =>
    _selectionNotifier(context).add(key);

LibrarySelectionNotifier _selectionNotifier(BuildContext context) =>
    ProviderScope.containerOf(context, listen: false).read(
      librarySelectionProvider(LibraryScope.read(context).routeFolderId)
          .notifier,
    );

/// Folder color or the theme default (onSurfaceVariant). An unknown color
/// synced from elsewhere is drawn as it is (ARGB).
Color folderColorOr(int? colorArgb, ColorScheme scheme) =>
    colorArgb != null ? Color(colorArgb) : scheme.onSurfaceVariant;

/// The folder picture of a tile or row: background = folder color 15 % or
/// surfaceContainerHigh, the folder icon in the middle.
class FolderPicture extends StatelessWidget {
  const FolderPicture({
    super.key,
    required this.folder,
    required this.iconSize,
    this.background = true,
  });

  final Folder folder;
  final double iconSize;

  /// False in list rows (icon only).
  final bool background;

  @override
  Widget build(BuildContext context) => FolderGlyph(
    colorArgb: folder.colorArgb,
    icon: folder.icon,
    iconSize: iconSize,
    background: background,
  );
}

/// [FolderPicture] from a color and an icon key (the appearance dialog's
/// preview draws values that are not stored yet).
class FolderGlyph extends StatelessWidget {
  const FolderGlyph({
    super.key,
    required this.colorArgb,
    required this.icon,
    required this.iconSize,
    this.background = true,
  });

  final int? colorArgb;

  /// FolderIcons key (null / unknown = the folder icon).
  final String? icon;
  final double iconSize;
  final bool background;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final argb = colorArgb;
    final glyph = Center(
      child: Icon(
        FolderIcons.iconFor(icon),
        size: iconSize,
        color: folderColorOr(argb, scheme),
      ),
    );
    if (!background) return glyph;
    return ColoredBox(
      color: argb != null
          ? Color(argb).withValues(alpha: 0.15)
          : scheme.surfaceContainerHigh,
      child: glyph,
    );
  }
}

/// Cover box of a grid tile: corner 8, 1 px outlineVariant border — 3 px
/// primary when the item is selected (6.8).
class TileCoverBox extends StatelessWidget {
  const TileCoverBox({
    super.key,
    required this.width,
    required this.height,
    required this.child,
    this.selected = false,
  });

  final double width, height;
  final Widget child;
  final bool selected;

  static const BorderRadius radius = BorderRadius.all(Radius.circular(8));

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                )
              : Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: ClipRRect(borderRadius: radius, child: child),
      ),
    );
  }
}

/// Below the cover: title (2 lines, 14/20 w500) and one meta line (12/16).
/// Text grows with the system scale up to LibraryMetrics.maxTileTextScale
/// (the grid height is computed with the same cap, 6.2).
class TileFooterText extends StatelessWidget {
  const TileFooterText({super.key, required this.title, required this.meta});

  final String title;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: LibraryMetrics.maxTileTextScale,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
          Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              height: 16 / 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Decorative badge on a cover corner: 24 circle (surfaceContainerLowest)
/// with an 18 icon, visible on any cover.
class CoverCornerBadge extends StatelessWidget {
  const CoverCornerBadge({super.key, required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: 24,
        height: 24,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

/// Selection mode mark on a grid tile's cover (top left, in a 44 × 44
/// area): an empty circle, or check_circle in primary when selected. Not
/// tappable itself (the whole tile toggles) and decorative (the tile's
/// semantics carry selected).
class SelectionCheckBadge extends StatelessWidget {
  const SelectionCheckBadge({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox(
          width: LibraryMetrics.minTapTarget,
          height: LibraryMetrics.minTapTarget,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainerLowest,
              ),
              child: Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 24,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
