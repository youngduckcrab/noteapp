// lib/src/ui/trash/trash_row.dart — 05-library 6.13: one trash entry (72):
// `[cover / folder icon 40×52][16][name / info][deleted date][days left][⋯]`.
// Info: '폴더 · 노트 n개, 폴더 m개 포함' / '노트 · n페이지'; days left ≤ 3 →
// errorContainer chip. A tap or ⋯ opens [복원] [영구 삭제] (a trashed note
// does not open); in selection mode a tap toggles. A long press starts
// selection mode with the entry (trash entries are not dragged, 6.10.1).
// Narrow rows (< 600) show the deleted date in the info line.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show TrashItem, TrashedFolder, TrashedNote, clockProvider;

import '../../l10n/library_date_format.dart';
import '../../l10n/library_strings.dart';
import '../../model/item_key.dart';
import '../content/note_cover_view.dart';
import '../content/tile_parts.dart';
import '../layout/library_metrics.dart';
import '../menus/item_action_flows.dart';

/// At most this many days left → the chip is drawn in errorContainer.
const int kTrashWarnDays = 3;

/// Below this row width the deleted date moves into the info line.
const double _wideRowMinWidth = 600;

class TrashRow extends ConsumerStatefulWidget {
  const TrashRow({super.key, required this.item});

  final TrashItem item;

  @override
  ConsumerState<TrashRow> createState() => _TrashRowState();
}

class _TrashRowState extends ConsumerState<TrashRow> {
  final MenuController _menu = MenuController();

  void _toggleMenu() => _menu.isOpen ? _menu.close() : _menu.open();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = widget.item;
    final key = keyOfRef(item.ref);
    final now = ref.watch(clockProvider).now();
    final (:active, :selected) = watchItemSelection(ref, context, key);
    final info = switch (item) {
      TrashedFolder(:final noteCount, :final folderCount) =>
        LibraryStrings.trashedFolderInfo(
          noteCount: noteCount,
          folderCount: folderCount,
        ),
      TrashedNote(:final note) => LibraryStrings.trashedNoteInfo(
        note.pageCount,
      ),
    };
    final deleted = LibraryStrings.deletedOn(
      formatLibraryDate(item.deletedAt, now: now),
    );
    final daysLeft = trashDaysLeft(item.expiresAt, now: now);
    final left = formatTrashRemaining(item.expiresAt, now: now);
    final warn = daysLeft <= kTrashWarnDays;
    final Widget thumb = switch (item) {
      TrashedFolder(:final folder) => FolderPicture(
        folder: folder,
        iconSize: 32,
        background: false,
      ),
      TrashedNote(:final note) => ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        child: NoteCoverView(note: note, width: 40, height: 52),
      ),
    };
    void onTap() => active ? toggleItemSelection(context, key) : _toggleMenu();

    return MenuAnchor(
      controller: _menu,
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.restore_from_trash_outlined),
          onPressed: () =>
              runRestoreFlow(context, items: [key], singleName: item.name),
          child: const Text(LibraryStrings.restore),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.delete_forever_outlined),
          onPressed: () =>
              runPurgeFlow(context, items: [key], singleName: item.name),
          child: const Text(LibraryStrings.purge),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= _wideRowMinWidth;
          final meta = wide ? info : '$info · $deleted';
          final muted = theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          );
          return Row(
            children: [
              Expanded(
                child: Semantics(
                  container: true,
                  button: true,
                  label: LibraryStrings.trashRowSemantics(
                    item.name,
                    '$info, $deleted',
                    left,
                  ),
                  selected: active ? selected : null,
                  excludeSemantics: true,
                  onTap: onTap,
                  onLongPress: () => addItemToSelection(context, key),
                  child: InkWell(
                    onTap: onTap,
                    onLongPress: () => addItemToSelection(context, key),
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: active ? 4 : 16,
                      ),
                      child: Row(
                        children: [
                          // Decorative: the row toggles and carries selected.
                          if (active)
                            IgnorePointer(
                              child: ExcludeSemantics(
                                child: Checkbox(
                                  value: selected,
                                  onChanged: (_) {},
                                ),
                              ),
                            ),
                          SizedBox(width: 40, height: 52, child: thumb),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyLarge,
                                ),
                                Text(
                                  meta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: muted,
                                ),
                              ],
                            ),
                          ),
                          if (wide) ...[
                            const SizedBox(width: 16),
                            Text(deleted, maxLines: 1, style: muted),
                          ],
                          const SizedBox(width: 12),
                          TrashDaysChip(label: left, warn: warn),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (active)
                const SizedBox(width: LibraryMetrics.minTapTarget)
              else
                IconButton(
                  icon: const Icon(Icons.more_horiz),
                  tooltip: LibraryStrings.itemMenu(item.name),
                  onPressed: _toggleMenu,
                ),
              const SizedBox(width: 8),
            ],
          );
        },
      ),
    );
  }
}

/// '30일 남음' / '오늘 삭제' — errorContainer when [warn] (≤ 3 days).
class TrashDaysChip extends StatelessWidget {
  const TrashDaysChip({super.key, required this.label, required this.warn});

  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: warn ? scheme.errorContainer : scheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          maxLines: 1,
          style: theme.textTheme.labelMedium?.copyWith(
            color: warn ? scheme.onErrorContainer : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
