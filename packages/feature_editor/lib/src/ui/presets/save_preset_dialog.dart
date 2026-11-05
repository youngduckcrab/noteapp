// lib/src/ui/presets/save_preset_dialog.dart — 04-editor 6.10 ([+] →
// SavePresetDialog), 5.1.5 (createPreset).
//
// Also the pieces the manager sheet shares: the name rule (trimmed 1–20
// characters, longer input blocked), the group picker (기존 그룹 / 그룹 없음 /
// 새 그룹) and [runPresetWrite].
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../state/popup.dart';
import '../../state/preset_bar.dart';
import '../../tools/tool_controller.dart';
import '../editor_strings.dart';
import '../popup_host.dart';

/// EDITOR's input limit for preset names (contract 7.2.4; CORE stores 1–60).
const int kPresetNameMaxLength = 20;

/// Group names typed in the picker have the same limit.
const int kPresetGroupMaxLength = 20;

/// [raw] trimmed when it is 1–[kPresetNameMaxLength] characters, else null.
String? presetNameOf(String raw) {
  final name = raw.trim();
  if (name.isEmpty || name.characters.length > kPresetNameMaxLength) {
    return null;
  }
  return name;
}

/// Runs a preset repository write without holding the UI on it: the Future
/// stays pending while CORE retries a failed commit (contract 7.2.9 v1.2), so
/// nothing waits for it. An error (an argument error, a preset deleted on
/// another device …) is reported (library 'feature_editor') and shows
/// '실행하지 못했어요'.
void runPresetWrite(
  BuildContext context,
  String what,
  Future<Object?> Function() write,
) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  unawaited(() async {
    try {
      await write();
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'feature_editor',
          context: ErrorDescription('while $what'),
        ),
      );
      if (messenger != null && messenger.mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text(EditorStrings.commandFailed)),
          );
      }
    }
  }());
}

/// The name field of the save dialog and the rename dialog: input past
/// [kPresetNameMaxLength] characters is blocked (counter shown).
class PresetNameField extends StatelessWidget {
  const PresetNameField({
    super.key,
    required this.controller,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    maxLength: kPresetNameMaxLength,
    maxLengthEnforcement: MaxLengthEnforcement.enforced,
    textInputAction: TextInputAction.done,
    decoration: const InputDecoration(
      labelText: EditorStrings.presetName,
      helperText: EditorStrings.presetNameRule,
    ),
    onChanged: onChanged,
    onSubmitted: onSubmitted,
  );
}

/// 그룹: [그룹 없음] [existing groups…] [새 그룹] — with a name field while
/// 새 그룹 is chosen. Reports (group, valid): group null = no group; valid is
/// false while 새 그룹 has no name. A typed name equal to an existing group is
/// that group.
class PresetGroupPicker extends StatefulWidget {
  const PresetGroupPicker({
    super.key,
    required this.groups,
    required this.initial,
    required this.onChanged,
  });

  final List<String> groups;
  final String? initial;
  final void Function(String? group, bool valid) onChanged;

  static const noGroupKey = ValueKey('editor.presetGroup.none');
  static const newGroupKey = ValueKey('editor.presetGroup.new');
  static const newGroupFieldKey = ValueKey('editor.presetGroup.newField');
  static ValueKey<String> groupKey(String group) =>
      ValueKey('editor.presetGroup.group.$group');

  @override
  State<PresetGroupPicker> createState() => _PresetGroupPickerState();
}

/// Which chip of the picker is on.
sealed class _GroupChoice {
  const _GroupChoice();
}

final class _NoGroup extends _GroupChoice {
  const _NoGroup();
}

final class _Existing extends _GroupChoice {
  const _Existing(this.name);
  final String name;
}

final class _NewGroup extends _GroupChoice {
  const _NewGroup();
}

class _PresetGroupPickerState extends State<PresetGroupPicker> {
  late _GroupChoice _choice;
  final TextEditingController _newName = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _choice = initial == null
        ? const _NoGroup()
        : widget.groups.contains(initial)
        ? _Existing(initial)
        : const _NewGroup();
    if (initial != null && _choice is _NewGroup) _newName.text = initial;
  }

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  void _select(_GroupChoice choice) {
    setState(() => _choice = choice);
    _report();
  }

  void _report() {
    switch (_choice) {
      case _NoGroup():
        widget.onChanged(null, true);
      case _Existing(:final name):
        widget.onChanged(name, true);
      case _NewGroup():
        final name = _newName.text.trim();
        widget.onChanged(name.isEmpty ? null : name, name.isNotEmpty);
    }
  }

  @override
  Widget build(BuildContext context) {
    final choice = _choice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          EditorStrings.presetGroup,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ChoiceChip(
              key: PresetGroupPicker.noGroupKey,
              label: const Text(EditorStrings.presetNoGroup),
              selected: choice is _NoGroup,
              onSelected: (_) => _select(const _NoGroup()),
            ),
            for (final g in widget.groups)
              ChoiceChip(
                key: PresetGroupPicker.groupKey(g),
                label: Text(g),
                selected: choice is _Existing && choice.name == g,
                onSelected: (_) => _select(_Existing(g)),
              ),
            ChoiceChip(
              key: PresetGroupPicker.newGroupKey,
              avatar: const Icon(Icons.add, size: 18),
              label: const Text(EditorStrings.presetNewGroup),
              selected: choice is _NewGroup,
              onSelected: (_) => _select(const _NewGroup()),
            ),
          ],
        ),
        if (choice is _NewGroup)
          TextField(
            key: PresetGroupPicker.newGroupFieldKey,
            controller: _newName,
            autofocus: true,
            maxLength: kPresetGroupMaxLength,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            decoration: const InputDecoration(
              labelText: EditorStrings.presetNewGroupName,
            ),
            onChanged: (_) => _report(),
          ),
      ],
    );
  }
}

/// [+] / [프리셋으로 저장] (6.10): name (default "{펜 이름} {굵기}pt", trimmed
/// 1–20 characters, longer input blocked), group (기존 그룹 / 그룹 없음 / 새
/// 그룹 — starts on the bar's group filter, so the new preset shows on the
/// bar), '툴바에 고정' (on) → core.PenPresetRepository.createPreset(name:,
/// style: current pen, group:, pinned:). Shown by PopupHost in the middle of
/// the screen (SavePresetPopup).
class SavePresetDialog extends ConsumerStatefulWidget {
  const SavePresetDialog({super.key});

  static const panelKey = ValueKey('editor.savePreset');
  static const nameFieldKey = ValueKey('editor.savePreset.name');
  static const pinnedKey = ValueKey('editor.savePreset.pinned');
  static const saveKey = ValueKey('editor.savePreset.save');
  static const cancelKey = ValueKey('editor.savePreset.cancel');

  @override
  ConsumerState<SavePresetDialog> createState() => _SavePresetDialogState();
}

class _SavePresetDialogState extends ConsumerState<SavePresetDialog> {
  final TextEditingController _name = TextEditingController();
  late final List<String> _groups;
  String? _group;
  bool _groupValid = true;
  bool _pinned = true;

  @override
  void initState() {
    super.initState();
    final pen = ref.read(editorToolProvider).currentPen;
    final name = EditorStrings.presetDefaultName(pen.tool, pen.width);
    _name.text = name.characters.take(kPresetNameMaxLength).toString();
    _groups = ref.read(editorPresetGroupsProvider);
    final all = ref.read(core.penPresetsProvider).value ?? const [];
    _group = effectiveGroupFilter(
      all,
      ref.read(editorPresetBarProvider).groupFilter,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSave => presetNameOf(_name.text) != null && _groupValid;

  void _save() {
    final name = presetNameOf(_name.text);
    if (name == null || !_groupValid) return;
    final style = ref.read(editorToolProvider).currentPen;
    final repo = ref.read(core.penPresetRepositoryProvider);
    final group = _group;
    final pinned = _pinned;
    runPresetWrite(
      context,
      'creating a preset',
      () => repo.createPreset(
        name: name,
        style: style,
        group: group,
        pinned: pinned,
      ),
    );
    ref.read(editorPopupProvider.notifier).close();
  }

  @override
  Widget build(BuildContext context) => PopupPanelFrame(
    key: SavePresetDialog.panelKey,
    title: EditorStrings.saveAsPreset,
    width: 360,
    children: [
      PresetNameField(
        key: SavePresetDialog.nameFieldKey,
        controller: _name,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _save(),
      ),
      const SizedBox(height: 12),
      PresetGroupPicker(
        groups: _groups,
        initial: _group,
        onChanged: (group, valid) => setState(() {
          _group = group;
          _groupValid = valid;
        }),
      ),
      const SizedBox(height: 4),
      SwitchListTile(
        key: SavePresetDialog.pinnedKey,
        contentPadding: EdgeInsets.zero,
        title: const Text(EditorStrings.presetPinned),
        value: _pinned,
        onChanged: (v) => setState(() => _pinned = v),
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            key: SavePresetDialog.cancelKey,
            onPressed: () => ref.read(editorPopupProvider.notifier).close(),
            child: const Text(EditorStrings.cancel),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: SavePresetDialog.saveKey,
            onPressed: _canSave ? _save : null,
            child: const Text(EditorStrings.save),
          ),
        ],
      ),
    ],
  );
}
