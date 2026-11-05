// lib/src/ui/content/tile_parts.dart — 05-library 6.8: pieces shared by the
// grid tiles and list rows.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show Folder, FolderId, Note;

import '../../appearance/folder_appearance.dart';
import '../../dnd/drag_payload.dart';
import '../../dnd/library_draggable.dart';
import '../../l10n/library_strings.dart';
import '../../model/item_key.dart';
import '../../state/providers.dart';
import '../../state/selection_notifier.dart';
import '../feedback/library_snack_bar.dart';
import '../layout/library_metrics.dart';
import '../library_scope.dart';
import 'note_meta.dart';

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

/// Long press on an item: selection mode with [key] included (6.9) — the
/// drag start (LibraryDraggable.onDragStarted) and the screen reader's long
/// press action.
void addItemToSelection(BuildContext context, LibraryItemKey key) =>
    _selectionNotifier(context).add(key);

/// The drag source of a content tile / row (6.10.1): the payload is the
/// selection (in selection mode) plus this item in display order, built
/// lazily at the drag start; the drag start adds this item to the selection.
class ContentItemDraggable extends StatelessWidget {
  const ContentItemDraggable({
    super.key,
    required this.itemKey,
    required this.parentId,
    required this.icon,
    required this.label,
    required this.child,
    this.iconColor,
  });

  final LibraryItemKey itemKey;

  /// Current parent of the item (folder.parentId / note.folderId).
  final FolderId? parentId;

  /// Of the drag card when only this item is dragged.
  final IconData icon;
  final Color? iconColor;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final container = ProviderScope.containerOf(context, listen: false);
    final route = LibraryScope.of(context).routeFolderId;
    return LibraryDraggable(
      payloadBuilder: () {
        final section = container.read(librarySectionProvider(route));
        return contentDragPayload(
          pressed: itemKey,
          pressedParent: parentId,
          selection: container.read(librarySelectionProvider(route)),
          content: container.read(libraryContentProvider(section)).value,
        );
      },
      feedbackBuilder: (payload) => LibraryDragFeedback(
        payload: payload,
        icon: icon,
        iconColor: iconColor,
        label: label,
      ),
      onDragStarted: () => addItemToSelection(context, itemKey),
      child: child,
    );
  }
}

/// Where a reorder drop would put the dragged items (6.8): a 3 px primary bar
/// — vertical in the middle of the gap left / right of a grid tile, or
/// horizontal along the top / bottom edge of a list row.
class DropInsertionBar extends StatelessWidget {
  const DropInsertionBar({super.key, required this.axis});

  /// The axis the items follow (grid: horizontal → a vertical bar).
  final Axis axis;

  /// In the Stack of a grid tile ([gap] = grid gap; the Stack must not clip).
  static Widget forTile({required bool after, required double gap}) {
    const t = LibraryMetrics.dropInsertionBarThickness;
    final outside = -(gap + t) / 2;
    return Positioned(
      top: 0,
      bottom: 0,
      left: after ? null : outside,
      right: after ? outside : null,
      width: t,
      child: const DropInsertionBar(axis: Axis.horizontal),
    );
  }

  /// In the Stack of a list row.
  static Widget forRow({required bool after}) => Positioned(
    left: 0,
    right: 0,
    top: after ? null : 0,
    bottom: after ? 0 : null,
    height: LibraryMetrics.dropInsertionBarThickness,
    child: const DropInsertionBar(axis: Axis.vertical),
  );

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ColoredBox(color: Theme.of(context).colorScheme.primary),
  );
}

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
    this.dropInto = false,
  });

  final Folder folder;
  final double iconSize;

  /// False in list rows (icon only).
  final bool background;

  /// A drop would go into this folder: primaryContainer background (6.8).
  final bool dropInto;

  @override
  Widget build(BuildContext context) => FolderGlyph(
    colorArgb: folder.colorArgb,
    icon: folder.icon,
    iconSize: iconSize,
    background: background,
    dropInto: dropInto,
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
    this.dropInto = false,
  });

  final int? colorArgb;

  /// FolderIcons key (null / unknown = the folder icon).
  final String? icon;
  final double iconSize;
  final bool background;

  /// primaryContainer background (a drop target, 6.8).
  final bool dropInto;

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
      color: dropInto
          ? scheme.primaryContainer
          : argb != null
          ? Color(argb).withValues(alpha: 0.15)
          : scheme.surfaceContainerHigh,
      child: glyph,
    );
  }
}

/// Cover box of a grid tile: corner 8, 1 px outlineVariant border — 3 px
/// primary when the item is selected, 2 px primary when a drop would go into
/// it (6.8).
class TileCoverBox extends StatelessWidget {
  const TileCoverBox({
    super.key,
    required this.width,
    required this.height,
    required this.child,
    this.selected = false,
    this.dropInto = false,
  });

  final double width, height;
  final Widget child;
  final bool selected;
  final bool dropInto;

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
          border: selected || dropInto
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: selected ? 3 : LibraryMetrics.dropIntoBorderWidth,
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
  const TileFooterText({
    super.key,
    required this.title,
    required this.meta,
    this.highlight,
  });

  final String title;
  final String meta;

  /// Search query whose match in [title] is highlighted (6.14).
  final String? highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: LibraryMetrics.maxTileTextScale,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            highlightedTitleSpan(context, title, highlight),
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
