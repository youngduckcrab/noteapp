// lib/src/ui/top_bar/selection_bar.dart — 05-library 6.9: the bar that
// replaces the top bar in selection mode (64):
//
//   [✕ 완료] 'n개 선택됨' [모두 선택 | 모두 해제] … [☆ 즐겨찾기] [복사] [이동]
//   [PDF 내보내기] [휴지통]
//
// Every batch action takes the selected items in display order
// (selection.inDisplayOrder(content.orderedKeys)) and ends selection mode
// when it is done (a cancelled dialog keeps it). With nothing selected the
// actions are disabled; 즐겨찾기 and PDF 내보내기 need a note. PDF 내보내기
// is hidden while libraryPdfExportActionProvider is null.
//
// Wide bars label their buttons; narrower ones show icons with tooltips; the
// narrowest (compact) keeps 이동 · 휴지통 and moves the rest into ⋯. The
// trash section's bar has 복원 · 영구 삭제 over the trash entries
// (trashItemsProvider order, 6.13) and no export (trash notes are read-only).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show Folder, FolderId, Note, NoteId, TrashItem, trashItemsProvider;
import 'package:ui_kit/ui_kit.dart';

import '../../integration/pdf_flows.dart';
import '../../integration/pdf_slots.dart';
import '../../l10n/library_strings.dart';
import '../../model/item_key.dart';
import '../../model/section.dart';
import '../../state/providers.dart';
import '../layout/library_metrics.dart';
import '../library_scope.dart';
import '../menus/item_action_flows.dart';

/// One button of the bar, drawn per width (label / icon / menu entry).
typedef _BarAction = ({
  AppIconKind icon,
  String label,

  /// Shown instead of the label as the tooltip while disabled.
  String? disabledHint,
  VoidCallback? onPressed,
});

class SelectionBar extends ConsumerStatefulWidget {
  const SelectionBar({super.key, required this.section});

  final LibrarySection section;

  /// Bars at least this wide label their action buttons.
  static const double labeledMinWidth = 900;

  /// Narrower bars keep only 이동 · 휴지통 outside the ⋯ menu.
  static const double iconsMinWidth = 520;

  @override
  ConsumerState<SelectionBar> createState() => _SelectionBarState();
}

class _SelectionBarState extends ConsumerState<SelectionBar> {
  /// An export started here runs (the button waits for it).
  bool _exporting = false;

  Future<void> _export(
    LibraryPdfExportAction action,
    List<NoteId> noteIds,
    VoidCallback end,
  ) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final ran = await runLibraryPdfExport(
        context,
        action: action,
        noteIds: noteIds,
      );
      if (ran) end();
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = LibraryScope.of(context);
    final section = widget.section;
    final provider = librarySelectionProvider(scope.routeFolderId);
    final selection = ref.watch(provider);
    final content = ref.watch(libraryContentProvider(section)).value;
    final exportAction = ref.watch(libraryPdfExportActionProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    void end() => container.read(provider.notifier).end();

    final inTrash = section is TrashSection;
    // The trash view lists trashItemsProvider (newest first), not content.
    final trashItems = inTrash
        ? ref.watch(trashItemsProvider).value ?? const <TrashItem>[]
        : const <TrashItem>[];
    final trashNames = <LibraryItemKey, String>{
      for (final t in trashItems) keyOfRef(t.ref): t.name,
    };
    final ordered = inTrash
        ? trashNames.keys.toList()
        : content?.orderedKeys ?? const <LibraryItemKey>[];
    final items = selection.inDisplayOrder(ordered);
    final folders = <LibraryItemKey, Folder>{
      for (final f in content?.folders ?? const <Folder>[]) folderKey(f.id): f,
    };
    final notes = <LibraryItemKey, Note>{
      for (final n in content?.notes ?? const <Note>[]) noteKey(n.id): n,
    };
    final selectedNotes = [for (final k in items) ?notes[k]];
    final parents = <LibraryItemKey, FolderId?>{
      for (final k in items)
        k: k.isFolder ? folders[k]?.parentId : notes[k]?.folderId,
    };
    String? nameOf(LibraryItemKey k) => inTrash
        ? trashNames[k]
        : k.isFolder
        ? folders[k]?.name
        : notes[k]?.title;
    final allSelected = ordered.isNotEmpty && ordered.every(selection.contains);
    final any = items.isNotEmpty;

    final _BarAction selectAll = (
      icon: allSelected ? AppIconKind.deselect : AppIconKind.selectAll,
      label: allSelected
          ? LibraryStrings.deselectAll
          : LibraryStrings.selectAll,
      disabledHint: null,
      onPressed: ordered.isEmpty
          ? null
          : () {
              final notifier = ref.read(provider.notifier);
              allSelected ? notifier.clearKeys() : notifier.selectAll(ordered);
            },
    );

    final allFavorite =
        selectedNotes.isNotEmpty && selectedNotes.every((n) => n.isFavorite);
    final _BarAction favorite = (
      icon: allFavorite ? AppIconKind.favoriteOn : AppIconKind.favorite,
      label: allFavorite
          ? LibraryStrings.favoriteRemove
          : LibraryStrings.favoriteAdd,
      disabledHint: null,
      onPressed: selectedNotes.isEmpty
          ? null
          : () => runFavoriteFlow(
              context,
              ids: [for (final n in selectedNotes) n.id],
              favorite: !allFavorite,
              onDone: end,
            ),
    );
    final _BarAction copy = (
      icon: AppIconKind.duplicate,
      label: LibraryStrings.copy,
      disabledHint: null,
      onPressed: !any
          ? null
          : () => runCopyToFlow(
              context,
              items: items,
              parents: parents,
              initialFolderId: switch (section) {
                FolderSection(:final folderId) => folderId,
                _ => null,
              },
              onDone: end,
            ),
    );
    final _BarAction move = (
      icon: AppIconKind.move,
      label: LibraryStrings.move,
      disabledHint: null,
      onPressed: !any
          ? null
          : () => runMoveFlow(
              context,
              items: items,
              parents: parents,
              onDone: end,
            ),
    );
    final _BarAction? export = exportAction == null
        ? null
        : (
            icon: AppIconKind.exportPdf,
            label: LibraryStrings.exportPdfBulk,
            disabledHint: LibraryStrings.exportNeedsNote,
            onPressed: selectedNotes.isEmpty || _exporting
                ? null
                : () => _export(exportAction, [
                    for (final n in selectedNotes) n.id,
                  ], end),
          );
    final _BarAction trash = (
      icon: AppIconKind.trash,
      label: LibraryStrings.trash,
      disabledHint: null,
      onPressed: !any
          ? null
          : () => runTrashFlow(
              context,
              items: items,
              singleName: items.length == 1 ? nameOf(items.single) : null,
              onDone: end,
            ),
    );
    final singleName = items.length == 1 ? nameOf(items.single) : null;
    final _BarAction restore = (
      icon: AppIconKind.restore,
      label: LibraryStrings.restore,
      disabledHint: null,
      onPressed: !any
          ? null
          : () => runRestoreFlow(
              context,
              items: items,
              singleName: singleName,
              onDone: end,
            ),
    );
    final _BarAction purge = (
      icon: AppIconKind.deleteForever,
      label: LibraryStrings.purge,
      disabledHint: null,
      onPressed: !any
          ? null
          : () => runPurgeFlow(
              context,
              items: items,
              singleName: singleName,
              onDone: end,
            ),
    );
    final actions = <_BarAction>[
      if (inTrash) ...[
        restore,
        purge,
      ] else ...[
        favorite,
        copy,
        move,
        ?export,
        trash,
      ],
    ];

    return Material(
      color: theme.colorScheme.surface,
      child: SizedBox(
        height: LibraryMetrics.topBarHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final labeled = width >= SelectionBar.labeledMinWidth;
            final narrow = width < SelectionBar.iconsMinWidth && !inTrash;
            final inline = narrow ? <_BarAction>[move, trash] : actions;
            final overflow = narrow
                ? <_BarAction>[selectAll, favorite, copy, ?export]
                : const <_BarAction>[];
            return Row(
              children: [
                const SizedBox(width: 8),
                IconButton(
                  icon: const AppIcon(AppIconKind.close),
                  tooltip: LibraryStrings.done,
                  onPressed: end,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      LibraryStrings.selectedCount(selection.count),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                if (!narrow) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: selectAll.onPressed,
                    child: Text(selectAll.label),
                  ),
                ],
                const Spacer(),
                for (final action in inline)
                  labeled ? _LabeledButton(action) : _IconAction(action),
                if (overflow.isNotEmpty) _OverflowMenu(overflow),
                const SizedBox(width: 8),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LabeledButton extends StatelessWidget {
  const _LabeledButton(this.action);

  final _BarAction action;

  @override
  Widget build(BuildContext context) {
    final button = TextButton.icon(
      icon: AppIcon(action.icon),
      label: Text(action.label),
      onPressed: action.onPressed,
    );
    final hint = action.disabledHint;
    final child = action.onPressed == null && hint != null
        // Why it is disabled: also on a long press (HoverNames makes plain
        // tooltips hover-only).
        ? Tooltip(
            message: hint,
            triggerMode: TooltipTriggerMode.longPress,
            child: button,
          )
        : button;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: child,
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction(this.action);

  final _BarAction action;

  @override
  Widget build(BuildContext context) {
    final hint = action.disabledHint;
    return IconButton(
      icon: AppIcon(action.icon),
      tooltip: action.onPressed == null && hint != null ? hint : action.label,
      onPressed: action.onPressed,
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu(this.actions);

  final List<_BarAction> actions;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final action in actions)
          MenuItemButton(
            leadingIcon: AppIcon(action.icon),
            onPressed: action.onPressed,
            child: Text(action.label),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        icon: const AppIcon(AppIconKind.more),
        tooltip: LibraryStrings.moreActions,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
