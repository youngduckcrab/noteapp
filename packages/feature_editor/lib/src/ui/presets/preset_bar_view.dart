// lib/src/ui/presets/preset_bar_view.dart — 04-editor 6.10 (preset bar, 44 px
// under the toolbar — 6.9.1).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../scope/editor_scope.dart';
import '../../state/popup.dart';
import '../../state/preset_bar.dart';
import '../../tools/tool_controller.dart';
import '../../tools/tool_state.dart';
import '../chrome/editor_chrome.dart' show PaletteDetachButton;
import '../editor_strings.dart';
import 'preset_chip.dart';
import 'save_preset_dialog.dart';

/// [그룹▾] (preset chips … long press + drag to reorder) [+] [⚙] — 44 px.
///
/// - Chips: editorVisiblePresetsProvider (pinned, group filter, CORE order).
///   Tap → ToolController.applyStyle(preset.style). The chip whose style
///   equals the active pen's (pen tool active) has the 2 px primary border.
/// - Long press (500 ms) and drag: a horizontal ReorderableListView
///   (buildDefaultDragHandles false, onReorderItem) with
///   ReorderableDelayedDragStartListener → PresetOrdering.reorderSubset →
///   core.PenPresetRepository.reorderPresets(full order) — one CORE commit.
/// - Empty: "자주 쓰는 펜을 저장해 보세요" + [현재 펜 저장].
/// - [그룹▾] (only when some preset has a group): 모든 그룹 / each group →
///   editorPresetBarProvider.setGroupFilter.
/// - [+] → SavePresetPopup, [⚙] → PresetManagerPopup.
/// - Read-only note: the whole bar is disabled (6.10).
class PresetBarView extends ConsumerStatefulWidget {
  const PresetBarView({super.key});

  static const double height = 44;
  static const barKey = ValueKey('editor.presetBar');
  static const listKey = ValueKey('editor.presetBar.list');
  static const groupMenuKey = ValueKey('editor.presetBar.group');
  static const allGroupsKey = ValueKey('editor.presetBar.group.all');
  static const addKey = ValueKey('editor.presetBar.add');
  static const manageKey = ValueKey('editor.presetBar.manage');
  static const emptySaveKey = ValueKey('editor.presetBar.emptySave');
  static ValueKey<String> chipKey(String id) =>
      ValueKey('editor.presetBar.chip.$id');
  static ValueKey<String> groupItemKey(String group) =>
      ValueKey('editor.presetBar.group.item.$group');

  @override
  ConsumerState<PresetBarView> createState() => _PresetBarViewState();
}

class _PresetBarViewState extends ConsumerState<PresetBarView> {
  /// The full order just sent to reorderPresets, shown until CORE's list
  /// changes (a reordered chip must not jump back while the commit is on its
  /// way).
  List<String>? _order;

  void _reorder(List<core.PenPreset> visible, int oldIndex, int newIndex) {
    final all = presetsInOrder(
      ref.read(core.penPresetsProvider).value ?? const [],
      _order,
    );
    final order = PresetOrdering.reorderSubset(
      all: all,
      subsetIds: [for (final p in visible) p.id],
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

  @override
  Widget build(BuildContext context) {
    ref.listen(core.penPresetsProvider, (previous, next) {
      if (_order != null && next.hasValue) setState(() => _order = null);
    });
    final scheme = Theme.of(context).colorScheme;
    final readOnly = ref.watch(editorReadOnlyProvider);
    final visible = ref.watch(editorVisiblePresetsProvider);
    final groups = ref.watch(editorPresetGroupsProvider);
    final popups = ref.read(editorPopupProvider.notifier);
    final list = visible.value;
    final bar = Row(
      children: [
        const SizedBox(width: 4),
        if (groups.isNotEmpty) const _GroupMenu(),
        Expanded(
          child: list == null
              ? const SizedBox.shrink() // loading or failed: nothing to show
              : list.isEmpty
              ? _Empty(onSave: () => popups.open(const SavePresetPopup()))
              : _Chips(
                  presets: presetsInOrder(list, _order),
                  onReorder: _reorder,
                ),
        ),
        IconButton(
          key: PresetBarView.addKey,
          onPressed: () => popups.open(const SavePresetPopup()),
          icon: const Icon(Icons.add, semanticLabel: EditorStrings.presetAdd),
        ),
        IconButton(
          key: PresetBarView.manageKey,
          onPressed: () => popups.open(const PresetManagerPopup()),
          icon: const Icon(
            Icons.tune,
            semanticLabel: EditorStrings.presetManage,
          ),
        ),
        // (04-editor 17) 팔레트로 떼어내기.
        const PaletteDetachButton(),
        const SizedBox(width: 4),
      ],
    );
    return Material(
      key: PresetBarView.barKey,
      color: scheme.surface,
      child: SizedBox(
        height: PresetBarView.height,
        child: readOnly
            ? IgnorePointer(
                child: ExcludeSemantics(
                  child: Opacity(opacity: 0.38, child: bar),
                ),
              )
            : bar,
      ),
    );
  }
}

class _Chips extends ConsumerWidget {
  const _Chips({required this.presets, required this.onReorder});

  final List<core.PenPreset> presets;
  final void Function(List<core.PenPreset> visible, int oldIndex, int newIndex)
  onReorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tools = ref.watch(editorToolProvider);
    final pen = tools.activeTool == EditorTool.pen ? tools.currentPen : null;
    final controller = ref.read(editorToolProvider.notifier);
    return ReorderableListView.builder(
      key: PresetBarView.listKey,
      scrollDirection: Axis.horizontal,
      buildDefaultDragHandles: false,
      itemCount: presets.length,
      onReorderItem: (oldIndex, newIndex) =>
          onReorder(presets, oldIndex, newIndex),
      itemBuilder: (context, i) {
        final p = presets[i];
        return ReorderableDelayedDragStartListener(
          key: ValueKey(p.id),
          index: i,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: PresetChip(
              key: PresetBarView.chipKey(p.id),
              preset: p,
              active: pen != null && p.style == pen,
              onTap: () => controller.applyStyle(p.style),
            ),
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onSave});

  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            EditorStrings.presetEmpty,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          key: PresetBarView.emptySaveKey,
          onPressed: onSave,
          child: const Text(EditorStrings.presetSaveCurrent),
        ),
      ],
    );
  }
}

/// [그룹▾]: 모든 그룹 + every group; the current choice is checked. Shows the
/// filter that applies (a stored group no preset has any more shows 모든 그룹).
class _GroupMenu extends ConsumerStatefulWidget {
  const _GroupMenu();

  @override
  ConsumerState<_GroupMenu> createState() => _GroupMenuState();
}

class _GroupMenuState extends ConsumerState<_GroupMenu> {
  final MenuController _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(editorPresetGroupsProvider);
    final stored = ref.watch(
      editorPresetBarProvider.select((s) => s.groupFilter),
    );
    final filter = groups.contains(stored) ? stored : null;
    final bar = ref.read(editorPresetBarProvider.notifier);
    Widget check(bool on) =>
        on ? const Icon(Icons.check, size: 18) : const SizedBox(width: 18);
    return MenuAnchor(
      controller: _controller,
      menuChildren: [
        MenuItemButton(
          key: PresetBarView.allGroupsKey,
          leadingIcon: check(filter == null),
          onPressed: () => bar.setGroupFilter(null),
          child: const Text(EditorStrings.presetAllGroups),
        ),
        for (final g in groups)
          MenuItemButton(
            key: PresetBarView.groupItemKey(g),
            leadingIcon: check(filter == g),
            onPressed: () => bar.setGroupFilter(g),
            child: Text(g),
          ),
      ],
      child: Semantics(
        label: EditorStrings.presetGroupFilter,
        child: TextButton(
          key: PresetBarView.groupMenuKey,
          onPressed: () =>
              _controller.isOpen ? _controller.close() : _controller.open(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 112),
                child: Text(
                  filter ?? EditorStrings.presetAllGroups,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
