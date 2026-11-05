// lib/src/ui/presets/preset_manager_sheet.dart — 04-editor 6.10 ([⚙] →
// PresetManagerSheet), 5.1.5 (updatePreset · deletePreset · reorderPresets).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../state/popup.dart';
import '../../state/preset_bar.dart';
import '../../tools/tool_controller.dart';
import '../editor_strings.dart';
import 'save_preset_dialog.dart';

/// Every active preset in CORE order (core.penPresetsProvider), one row each:
/// drag handle (order → reorderPresets, the full active order), preview
/// (ink.PenPreviewPainter, line shape, with the PencilGrain object), name,
/// group, '툴바에 고정' switch and ⋯ [이름 바꾸기, 그룹 변경, 현재 펜으로
/// 업데이트, 삭제 (confirmed)] → updatePreset(p.copyWith(…)) / deletePreset(id).
/// Shown by PopupHost in the middle of the screen (PresetManagerPopup);
/// writes are not awaited ([runPresetWrite]).
class PresetManagerSheet extends ConsumerStatefulWidget {
  const PresetManagerSheet({super.key});

  static const double width = 440;
  static const panelKey = ValueKey('editor.presetManager');
  static const closeKey = ValueKey('editor.presetManager.close');
  static ValueKey<String> rowKey(String id) =>
      ValueKey('editor.presetManager.row.$id');
  static ValueKey<String> handleKey(String id) =>
      ValueKey('editor.presetManager.handle.$id');
  static ValueKey<String> previewKey(String id) =>
      ValueKey('editor.presetManager.preview.$id');
  static ValueKey<String> pinnedKey(String id) =>
      ValueKey('editor.presetManager.pinned.$id');
  static ValueKey<String> menuKey(String id) =>
      ValueKey('editor.presetManager.menu.$id');
  static ValueKey<String> renameKey(String id) =>
      ValueKey('editor.presetManager.rename.$id');
  static ValueKey<String> groupKey(String id) =>
      ValueKey('editor.presetManager.group.$id');
  static ValueKey<String> updateKey(String id) =>
      ValueKey('editor.presetManager.update.$id');
  static ValueKey<String> deleteKey(String id) =>
      ValueKey('editor.presetManager.delete.$id');

  @override
  ConsumerState<PresetManagerSheet> createState() => _PresetManagerSheetState();
}

class _PresetManagerSheetState extends ConsumerState<PresetManagerSheet> {
  /// The order just sent to reorderPresets, shown until CORE's list changes
  /// (the list must not jump back while the commit is on its way).
  List<String>? _order;

  @override
  Widget build(BuildContext context) {
    ref.listen(core.penPresetsProvider, (previous, next) {
      if (_order != null && next.hasValue) setState(() => _order = null);
    });
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final presets = presetsInOrder(
      ref.watch(core.penPresetsProvider).value ?? const [],
      _order,
    );
    final maxHeight = (MediaQuery.sizeOf(context).height - 120).clamp(
      200.0,
      600.0,
    );
    return Material(
      key: PresetManagerSheet.panelKey,
      elevation: 3,
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: PresetManagerSheet.width,
          maxWidth: PresetManagerSheet.width,
          maxHeight: maxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      EditorStrings.presetManage,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: PresetManagerSheet.closeKey,
                    onPressed: () =>
                        ref.read(editorPopupProvider.notifier).close(),
                    icon: const Icon(
                      Icons.close,
                      semanticLabel: EditorStrings.close,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: presets.length,
                onReorderItem: (oldIndex, newIndex) =>
                    _reorder(presets, oldIndex, newIndex),
                itemBuilder: (context, i) => _PresetRow(
                  key: PresetManagerSheet.rowKey(presets[i].id),
                  preset: presets[i],
                  index: i,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _reorder(List<core.PenPreset> presets, int oldIndex, int newIndex) {
    final order = PresetOrdering.reorderSubset(
      all: presets,
      subsetIds: [for (final p in presets) p.id],
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
    setState(() => _order = order);
    final repo = ref.read(core.penPresetRepositoryProvider);
    runPresetWrite(
      context,
      'reordering presets',
      () => repo.reorderPresets(order),
    );
  }
}

class _PresetRow extends ConsumerWidget {
  const _PresetRow({super.key, required this.preset, required this.index});

  final core.PenPreset preset;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final grain = ref.watch(ink.pencilGrainProvider);
    final p = preset;
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            ReorderableDragStartListener(
              key: PresetManagerSheet.handleKey(p.id),
              index: index,
              child: SizedBox(
                width: 44,
                height: 52,
                child: Icon(
                  Icons.drag_handle,
                  color: scheme.onSurfaceVariant,
                  semanticLabel: EditorStrings.presetReorder,
                ),
              ),
            ),
            Container(
              width: 72,
              height: 32,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: scheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: CustomPaint(
                key: PresetManagerSheet.previewKey(p.id),
                size: const Size(72, 32),
                painter: ink.PenPreviewPainter(
                  style: p.style,
                  shape: ink.PenPreviewShape.line,
                  pencilGrain: grain,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                  Text(
                    p.group ?? EditorStrings.presetNoGroup,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Semantics(
              label: EditorStrings.presetPinned,
              child: Switch(
                key: PresetManagerSheet.pinnedKey(p.id),
                value: p.pinned,
                onChanged: (pinned) => _update(
                  context,
                  ref,
                  p.copyWith(pinned: pinned),
                  'pinning a preset',
                ),
              ),
            ),
            _RowMenu(preset: p),
          ],
        ),
      ),
    );
  }
}

void _update(
  BuildContext context,
  WidgetRef ref,
  core.PenPreset next,
  String what,
) {
  final repo = ref.read(core.penPresetRepositoryProvider);
  runPresetWrite(context, what, () => repo.updatePreset(next));
}

class _RowMenu extends ConsumerStatefulWidget {
  const _RowMenu({required this.preset});

  final core.PenPreset preset;

  @override
  ConsumerState<_RowMenu> createState() => _RowMenuState();
}

class _RowMenuState extends ConsumerState<_RowMenu> {
  final MenuController _controller = MenuController();

  core.PenPreset get _p => widget.preset;

  Future<void> _rename() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => PresetRenameDialog(initial: _p.name),
    );
    if (name == null || !mounted || name == _p.name) return;
    _update(context, ref, _p.copyWith(name: name), 'renaming a preset');
  }

  Future<void> _changeGroup() async {
    final groups = ref.read(editorPresetGroupsProvider);
    final result = await showDialog<({String? group})>(
      context: context,
      builder: (_) => PresetGroupDialog(groups: groups, initial: _p.group),
    );
    if (result == null || !mounted || result.group == _p.group) return;
    final group = result.group;
    _update(
      context,
      ref,
      group == null ? _p.copyWith(clearGroup: true) : _p.copyWith(group: group),
      'changing the group of a preset',
    );
  }

  void _updateStyle() {
    final pen = ref.read(editorToolProvider).currentPen;
    _update(context, ref, _p.copyWith(style: pen), 'updating a preset');
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text(EditorStrings.presetUpdated)),
      );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => PresetDeleteDialog(name: _p.name),
    );
    if (confirmed != true || !mounted) return;
    final repo = ref.read(core.penPresetRepositoryProvider);
    final id = _p.id;
    runPresetWrite(context, 'deleting a preset', () => repo.deletePreset(id));
  }

  @override
  Widget build(BuildContext context) {
    final id = _p.id;
    return MenuAnchor(
      controller: _controller,
      menuChildren: [
        MenuItemButton(
          key: PresetManagerSheet.renameKey(id),
          onPressed: () => unawaited(_rename()),
          child: const Text(EditorStrings.presetRename),
        ),
        MenuItemButton(
          key: PresetManagerSheet.groupKey(id),
          onPressed: () => unawaited(_changeGroup()),
          child: const Text(EditorStrings.presetChangeGroup),
        ),
        MenuItemButton(
          key: PresetManagerSheet.updateKey(id),
          onPressed: _updateStyle,
          child: const Text(EditorStrings.presetUpdateStyle),
        ),
        MenuItemButton(
          key: PresetManagerSheet.deleteKey(id),
          onPressed: () => unawaited(_delete()),
          child: Text(
            EditorStrings.presetDelete,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
      child: IconButton(
        key: PresetManagerSheet.menuKey(id),
        onPressed: () =>
            _controller.isOpen ? _controller.close() : _controller.open(),
        icon: const Icon(Icons.more_horiz, semanticLabel: EditorStrings.more),
      ),
    );
  }
}

/// 이름 바꾸기: pops the new trimmed name (1–20 characters), null on cancel.
class PresetRenameDialog extends StatefulWidget {
  const PresetRenameDialog({super.key, required this.initial});

  final String initial;

  static const fieldKey = ValueKey('editor.presetRename.field');
  static const saveKey = ValueKey('editor.presetRename.save');

  @override
  State<PresetRenameDialog> createState() => _PresetRenameDialogState();
}

class _PresetRenameDialogState extends State<PresetRenameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial.characters.take(kPresetNameMaxLength).toString(),
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = presetNameOf(_name.text);
    if (name != null) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(EditorStrings.presetRename),
    content: PresetNameField(
      key: PresetRenameDialog.fieldKey,
      controller: _name,
      autofocus: true,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text(EditorStrings.cancel),
      ),
      FilledButton(
        key: PresetRenameDialog.saveKey,
        onPressed: presetNameOf(_name.text) == null ? null : _save,
        child: const Text(EditorStrings.save),
      ),
    ],
  );
}

/// 그룹 변경: pops (group: the chosen group or null for 그룹 없음), null on
/// cancel.
class PresetGroupDialog extends StatefulWidget {
  const PresetGroupDialog({
    super.key,
    required this.groups,
    required this.initial,
  });

  final List<String> groups;
  final String? initial;

  static const saveKey = ValueKey('editor.presetGroupDialog.save');

  @override
  State<PresetGroupDialog> createState() => _PresetGroupDialogState();
}

class _PresetGroupDialogState extends State<PresetGroupDialog> {
  late String? _group = widget.initial;
  bool _valid = true;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(EditorStrings.presetChangeGroup),
    content: SizedBox(
      width: 320,
      child: PresetGroupPicker(
        groups: widget.groups,
        initial: widget.initial,
        onChanged: (group, valid) => setState(() {
          _group = group;
          _valid = valid;
        }),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text(EditorStrings.cancel),
      ),
      FilledButton(
        key: PresetGroupDialog.saveKey,
        onPressed: _valid
            ? () => Navigator.of(context).pop((group: _group))
            : null,
        child: const Text(EditorStrings.save),
      ),
    ],
  );
}

/// 삭제 confirmation: pops true on 삭제.
class PresetDeleteDialog extends StatelessWidget {
  const PresetDeleteDialog({super.key, required this.name});

  final String name;

  static const confirmKey = ValueKey('editor.presetDelete.confirm');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(EditorStrings.presetDeleteTitle(name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(EditorStrings.cancel),
        ),
        FilledButton(
          key: confirmKey,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(EditorStrings.presetDelete),
        ),
      ],
    );
  }
}
