// lib/src/ui/dialogs/folder_picker_dialog.dart — 05-library 6.11: where to
// move / copy items. A '홈' row on top, the folder tree below (its own
// expansion state, starting with the path to initialFolderId open; the same
// flattenFolderTree and order as the sidebar). Disabled rows (a moved folder
// and its sub-folders) are drawn at opacity 0.38 and cannot be pressed; the
// chosen row is highlighted. Bottom row: [새 폴더] on the left (made inside
// the chosen folder, which is then chosen), [취소] [<confirm>] on the right;
// the confirm button is disabled for noOpTargets. At most 480 × 600; full
// screen in the compact class.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show FolderId, FolderTree, folderTreeProvider;

import '../../appearance/folder_appearance.dart';
import '../../l10n/library_strings.dart';
import '../../model/location_label.dart';
import '../../model/tree_rows.dart';
import '../../state/library_actions.dart';
import '../../state/providers.dart';
import '../content/tile_parts.dart';
import '../feedback/library_snack_bar.dart';
import '../layout/library_metrics.dart';
import '../layout/size_class.dart';
import '../sidebar/sidebar_rows.dart';
import 'new_folder_dialog.dart';

@immutable
final class FolderPickerResult {
  const FolderPickerResult(this.folderId);

  /// null = 홈 (a valid choice).
  final FolderId? folderId;

  @override
  bool operator ==(Object other) =>
      other is FolderPickerResult && other.folderId == folderId;

  @override
  int get hashCode => folderId.hashCode;

  @override
  String toString() => 'FolderPickerResult(${folderId ?? 'home'})';
}

/// Shows the picker; null when cancelled.
Future<FolderPickerResult?> showFolderPickerDialog(
  BuildContext context, {
  required String title,

  /// '여기로 이동' | '여기에 복사'.
  required String confirmLabel,
  required FolderId? initialFolderId,

  /// Move: the selected folders and their sub-folders.
  Set<FolderId> disabled = const {},

  /// The confirm button is disabled for these (move: when every item is
  /// already there).
  Set<FolderId?> noOpTargets = const {},
}) => showDialog<FolderPickerResult>(
  context: context,
  builder: (_) => FolderPickerDialog(
    title: title,
    confirmLabel: confirmLabel,
    initialFolderId: initialFolderId,
    disabled: disabled,
    noOpTargets: noOpTargets,
  ),
);

class FolderPickerDialog extends ConsumerStatefulWidget {
  const FolderPickerDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.initialFolderId,
    this.disabled = const {},
    this.noOpTargets = const {},
  });

  final String title;
  final String confirmLabel;
  final FolderId? initialFolderId;
  final Set<FolderId> disabled;
  final Set<FolderId?> noOpTargets;

  @override
  ConsumerState<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends ConsumerState<FolderPickerDialog> {
  late FolderId? _selected = widget.initialFolderId;

  /// Seeded from the first tree: the path to initialFolderId (inclusive).
  Set<FolderId>? _expanded;

  /// A '새 폴더' in progress (both bottom buttons wait for it).
  bool _creating = false;

  Set<FolderId> _seedExpanded(FolderTree tree) {
    final initial = widget.initialFolderId;
    if (initial == null) return <FolderId>{};
    return {for (final f in tree.pathTo(initial)) f.id};
  }

  void _toggle(FolderId id) => setState(() {
    final expanded = _expanded!;
    if (!expanded.remove(id)) expanded.add(id);
  });

  bool _canChoose(FolderTree? tree, FolderId? id) {
    if (id == null) return true;
    if (widget.disabled.contains(id)) return false;
    return tree?.byId(id) != null;
  }

  Future<void> _newFolder(FolderTree tree) async {
    final parentId = _selected;
    final actions = ref.read(libraryActionsProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final sizeClass = librarySizeClassFor(MediaQuery.sizeOf(context).width);
    setState(() => _creating = true);
    try {
      final spec = await showNewFolderDialog(
        context,
        initialName: actions.uniqueFolderName(parentId, tree),
        locationLabel: locationLabel(tree, parentId),
      );
      if (spec == null) return;
      final outcome = await actions.createFolder(spec, parentId: parentId);
      switch (outcome) {
        case ActionSuccess(:final value):
          if (!mounted) return;
          setState(() {
            if (parentId != null) _expanded?.add(parentId);
            _selected = value.id;
          });
        case ActionFailure(:final kind):
          if (messenger != null) {
            showLibrarySnackBarOn(
              messenger,
              message: libraryFailureMessage(kind),
              sizeClass: sizeClass,
            );
          }
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tree = ref.watch(folderTreeProvider).value;
    final order = folderTreeOrderFor(ref.watch(libraryPrefsProvider).sort);
    if (tree != null) _expanded ??= _seedExpanded(tree);
    final rows = tree == null
        ? const <FolderTreeRow>[]
        : flattenFolderTree(tree, expanded: _expanded!, order: order);
    final selected = _selected;
    final canConfirm =
        !_creating &&
        _canChoose(tree, selected) &&
        !widget.noOpTargets.contains(selected);
    final canCreate = !_creating && tree != null && _canChoose(tree, selected);
    final compact =
        librarySizeClassFor(MediaQuery.sizeOf(context).width) ==
        LibrarySizeClass.compact;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Semantics(
            header: true,
            child: Text(widget.title, style: theme.textTheme.headlineSmall),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: tree == null
              ? const SizedBox.shrink()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemExtent: LibraryMetrics.treeRowHeight,
                  itemCount: rows.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return FolderPickerRow(
                        key: const ValueKey<String>('picker-home'),
                        label: LibraryStrings.home,
                        icon: Icons.home_outlined,
                        iconColor: theme.colorScheme.onSurfaceVariant,
                        depth: 0,
                        selected: selected == null,
                        enabled: true,
                        onTap: () => setState(() => _selected = null),
                      );
                    }
                    final row = rows[index - 1];
                    final folder = row.folder;
                    final enabled = !widget.disabled.contains(folder.id);
                    return FolderPickerRow(
                      key: ValueKey<FolderId>(folder.id),
                      label: folder.name,
                      icon: FolderIcons.iconFor(folder.icon),
                      iconColor: folderColorOr(
                        folder.colorArgb,
                        theme.colorScheme,
                      ),
                      depth: row.depth + 1,
                      hasChildren: row.hasChildren,
                      isExpanded: row.isExpanded,
                      selected: selected == folder.id,
                      enabled: enabled,
                      onTap: () => setState(() => _selected = folder.id),
                      onToggle: () => _toggle(folder.id),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 24, 16),
          child: Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text(LibraryStrings.newFolder),
                onPressed: canCreate ? () => _newFolder(tree) : null,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(LibraryStrings.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: canConfirm
                    ? () =>
                          Navigator.of(context)
                              .pop(FolderPickerResult(selected))
                    : null,
                child: Text(widget.confirmLabel),
              ),
            ],
          ),
        ),
      ],
    );
    if (compact) return Dialog.fullscreen(child: SafeArea(child: content));
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: LibraryMetrics.pickerDialogMaxWidth,
          maxHeight: LibraryMetrics.pickerDialogMaxHeight,
        ),
        child: content,
      ),
    );
  }
}

/// One row of the picker (44): `[▸/▾ 44][indent][icon 24][8][name]`, the
/// chosen row on secondaryContainer (corner 12), a disabled row at opacity
/// 0.38 with nothing to press.
class FolderPickerRow extends StatelessWidget {
  const FolderPickerRow({
    super.key,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.depth,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.hasChildren = false,
    this.isExpanded = false,
    this.onToggle,
  });

  final String label;
  final IconData icon;
  final Color iconColor;

  /// 0 = the 홈 row; top-level folders are 1.
  final int depth;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final bool hasChildren;
  final bool isExpanded;
  final VoidCallback? onToggle;

  static const BorderRadius _radius = BorderRadius.all(Radius.circular(12));

  /// Opacity of a disabled row.
  static const double disabledOpacity = 0.38;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        type: selected ? MaterialType.canvas : MaterialType.transparency,
        color: selected ? scheme.secondaryContainer : null,
        borderRadius: _radius,
        child: Semantics(
          button: true,
          selected: selected,
          enabled: enabled,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: _radius,
            child: Row(
              children: [
                if (hasChildren && enabled)
                  IconButton(
                    icon: Icon(
                      isExpanded ? Icons.expand_more : Icons.chevron_right,
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
                    tooltip: isExpanded
                        ? LibraryStrings.collapseFolder
                        : LibraryStrings.expandFolder,
                    onPressed: onToggle,
                  )
                else
                  const SizedBox(width: LibraryMetrics.minTapTarget),
                SizedBox(width: SidebarTreeRow.indentFor(depth)),
                Icon(icon, size: 24, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: selected
                          ? scheme.onSecondaryContainer
                          : scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
    return enabled ? row : Opacity(opacity: disabledOpacity, child: row);
  }
}
