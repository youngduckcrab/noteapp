// lib/src/ui/sidebar/sidebar_rows.dart — 05-library 6.5: the rows of the
// sidebar. Navigation rows (홈 · 최근 · 즐겨찾기 · 휴지통) and folder tree
// rows share the selected look (secondaryContainer, corner 12). The tree
// row menu is SidebarRowMenu around each tree row (sidebar_folder_tree.dart).
// A row that a drop would go to shows SidebarDropLook (6.10): folders / 홈 =
// primaryContainer, 휴지통 = errorContainer (6.13).
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../appearance/folder_appearance.dart';
import '../../l10n/library_strings.dart';
import '../../model/tree_rows.dart';
import '../layout/library_metrics.dart';

/// Horizontal inset of every sidebar row (the selected background does not
/// touch the sidebar edges).
const double _rowInset = 8;
const BorderRadius _rowRadius = BorderRadius.all(Radius.circular(12));

/// How a sidebar row shows a drag over it (6.10 / 6.13).
enum SidebarDropLook {
  none,

  /// A drop would move the items into this folder (or 홈).
  folder,

  /// A drop would move the items to the trash.
  trash,
}

({Color? background, Color foreground}) _rowColors(
  ColorScheme scheme, {
  required bool selected,
  required SidebarDropLook drop,
}) => switch (drop) {
  SidebarDropLook.folder => (
    background: scheme.primaryContainer,
    foreground: scheme.onPrimaryContainer,
  ),
  SidebarDropLook.trash => (
    background: scheme.errorContainer,
    foreground: scheme.onErrorContainer,
  ),
  SidebarDropLook.none when selected => (
    background: scheme.secondaryContainer,
    foreground: scheme.onSecondaryContainer,
  ),
  SidebarDropLook.none => (background: null, foreground: scheme.onSurface),
};

/// The selectable background of one sidebar row.
class _RowSurface extends StatelessWidget {
  const _RowSurface({
    required this.selected,
    required this.onTap,
    required this.child,
    this.drop = SidebarDropLook.none,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final SidebarDropLook drop;

  @override
  Widget build(BuildContext context) {
    final background = _rowColors(
      Theme.of(context).colorScheme,
      selected: selected,
      drop: drop,
    ).background;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _rowInset),
      child: Material(
        type: background != null
            ? MaterialType.canvas
            : MaterialType.transparency,
        color: background,
        borderRadius: _rowRadius,
        child: Semantics(
          selected: selected,
          button: true,
          child: InkWell(onTap: onTap, borderRadius: _rowRadius, child: child),
        ),
      ),
    );
  }
}

/// 홈 · 최근 · 즐겨찾기 · 휴지통 (44): `[16][icon 24][12][label][trailing][16]`.
class SidebarNavRow extends StatelessWidget {
  const SidebarNavRow({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.drop = SidebarDropLook.none,
  });

  /// (UI stage 2) The line icon of the row.
  final AppIconKind icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Shown at the end when > 0 (휴지통 entries).
  final int? count;
  final SidebarDropLook drop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = _rowColors(scheme, selected: selected, drop: drop);
    final foreground = colors.foreground;
    final count = this.count;
    return SizedBox(
      height: LibraryMetrics.navRowHeight,
      child: _RowSurface(
        selected: selected,
        onTap: onTap,
        drop: drop,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16 - _rowInset),
          child: Row(
            children: [
              AppIcon(icon, size: 24, color: foreground),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(color: foreground),
                ),
              ),
              if (count != null && count > 0)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: Text(
                    '$count',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.background != null
                          ? foreground
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One folder of the tree (44): `[▸/▾ 44×44][indent min(depth, 8) × 16]
/// [folder icon 24, folder color][8][name, 1 line]`. Without children the
/// toggle place stays empty (alignment).
class SidebarTreeRow extends StatelessWidget {
  const SidebarTreeRow({
    super.key,
    required this.row,
    required this.selected,
    required this.onOpen,
    required this.onToggle,
    this.drop = SidebarDropLook.none,
  });

  final FolderTreeRow row;
  final bool selected;

  /// SidebarDropLook.folder while a drop would go into this folder.
  final SidebarDropLook drop;

  /// Row tap → open the folder (6.4).
  final VoidCallback onOpen;

  /// ▸ / ▾ tap → expand / collapse.
  final VoidCallback onToggle;

  /// Indent of a row at [depth]: deeper rows stay at 8 × 16.
  static double indentFor(int depth) =>
      math.min(depth, LibraryMetrics.treeMaxIndentLevels) *
      LibraryMetrics.treeIndent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final folder = row.folder;
    final argb = folder.colorArgb;
    final iconColor = argb != null ? Color(argb) : scheme.onSurfaceVariant;
    final colors = _rowColors(scheme, selected: selected, drop: drop);
    return SizedBox(
      height: LibraryMetrics.treeRowHeight,
      child: _RowSurface(
        selected: selected,
        onTap: onOpen,
        drop: drop,
        child: Row(
          children: [
            if (row.hasChildren)
              IconButton(
                icon: AppIcon(
                  row.isExpanded
                      ? AppIconKind.chevronDown
                      : AppIconKind.chevronRight,
                ),
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: LibraryMetrics.minTapTarget,
                  height: LibraryMetrics.minTapTarget,
                ),
                style: const ButtonStyle(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                tooltip: row.isExpanded
                    ? LibraryStrings.collapseFolder
                    : LibraryStrings.expandFolder,
                onPressed: onToggle,
              )
            else
              const SizedBox(width: LibraryMetrics.minTapTarget),
            SizedBox(width: indentFor(row.depth)),
            Icon(FolderIcons.iconFor(folder.icon), size: 24, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.foreground,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
