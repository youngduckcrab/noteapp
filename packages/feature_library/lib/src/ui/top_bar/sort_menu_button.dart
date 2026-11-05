// lib/src/ui/top_bar/sort_menu_button.dart — 05-library 6.7: the sort menu
// (folder sections only), the grid ↔ list toggle (every section but trash),
// and the compact class's ⋯ menu that holds both ('선택' joins it in L14).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show LibrarySortField;

import '../../l10n/library_strings.dart';
import '../../model/view_prefs.dart';
import '../../state/providers.dart';

const List<(LibrarySortField, String)> _sortChoices = [
  (LibrarySortField.name, LibraryStrings.sortName),
  (LibrarySortField.createdAt, LibraryStrings.sortCreated),
  (LibrarySortField.updatedAt, LibraryStrings.sortUpdated),
  (LibrarySortField.custom, LibraryStrings.sortCustom),
];

/// 이름 / 만든 날짜 / 수정한 날짜 / 사용자 지정: the current one has a check
/// and its direction (↑ ascending, ↓ descending; custom has none). Choosing
/// it again flips the direction (LibrarySort.select).
List<Widget> _sortMenuItems(WidgetRef ref, LibrarySort sort) => [
  for (final (field, label) in _sortChoices)
    MenuItemButton(
      leadingIcon: sort.field == field
          ? const Icon(Icons.check)
          : const SizedBox(width: 24),
      trailingIcon: sort.field == field && field != LibrarySortField.custom
          ? Icon(
              sort.descending ? Icons.arrow_downward : Icons.arrow_upward,
              size: 18,
            )
          : null,
      onPressed: () =>
          ref.read(libraryPrefsProvider.notifier).selectSort(field),
      child: Text(label),
    ),
];

class SortMenuButton extends ConsumerWidget {
  const SortMenuButton({super.key, required this.enabled});

  /// False outside folder sections: disabled, with the reason as tooltip.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!enabled) {
      return const IconButton(
        icon: Icon(Icons.sort),
        tooltip: LibraryStrings.sortFixed,
        onPressed: null,
      );
    }
    final sort = ref.watch(libraryPrefsProvider.select((p) => p.sort));
    return MenuAnchor(
      menuChildren: _sortMenuItems(ref, sort),
      builder: (context, controller, _) => IconButton(
        icon: const Icon(Icons.sort),
        tooltip: LibraryStrings.sort,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// Grid ↔ list; the icon shows the mode it switches to (in the grid:
/// Icons.view_list).
class ViewModeButton extends ConsumerWidget {
  const ViewModeButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(libraryPrefsProvider.select((p) => p.viewMode));
    final toList = mode == LibraryViewMode.grid;
    return IconButton(
      icon: Icon(toList ? Icons.view_list : Icons.grid_view),
      tooltip: toList ? LibraryStrings.viewAsList : LibraryStrings.viewAsGrid,
      onPressed: () => ref
          .read(libraryPrefsProvider.notifier)
          .setViewMode(toList ? LibraryViewMode.list : LibraryViewMode.grid),
    );
  }
}

/// Compact class: ⋯ with 정렬 (sub-menu) and the view toggle. Nothing when
/// neither applies (trash).
class CompactListingMenu extends ConsumerWidget {
  const CompactListingMenu({
    super.key,
    required this.sortEnabled,
    required this.showViewToggle,
  });

  final bool sortEnabled;
  final bool showViewToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!sortEnabled && !showViewToggle) return const SizedBox.shrink();
    final (sort, mode) = ref.watch(
      libraryPrefsProvider.select((p) => (p.sort, p.viewMode)),
    );
    final toList = mode == LibraryViewMode.grid;
    return MenuAnchor(
      menuChildren: [
        if (sortEnabled)
          SubmenuButton(
            leadingIcon: const Icon(Icons.sort),
            menuChildren: _sortMenuItems(ref, sort),
            child: const Text(LibraryStrings.sort),
          ),
        if (showViewToggle)
          MenuItemButton(
            leadingIcon: Icon(toList ? Icons.view_list : Icons.grid_view),
            onPressed: () => ref
                .read(libraryPrefsProvider.notifier)
                .setViewMode(
                  toList ? LibraryViewMode.list : LibraryViewMode.grid,
                ),
            child: Text(
              toList ? LibraryStrings.viewAsList : LibraryStrings.viewAsGrid,
            ),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        icon: const Icon(Icons.more_vert),
        tooltip: LibraryStrings.moreActions,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
