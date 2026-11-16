// lib/src/state/preset_bar.dart — 04-editor 6.10; stored form 6.14.
//
// The preset bar's group filter (device setting editor.presetBar) and the
// views of CORE's preset list it shows. EDITOR defines no presets provider of
// its own: the list is core.penPresetsProvider and every write goes straight
// to core.penPresetRepositoryProvider (contract X3, 04-editor 5.1.5).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

import 'debounced_writer.dart';
import 'settings/editor_setting_keys.dart';

/// Debounce of editor.presetBar (6.14: '변경 500ms 뒤').
const Duration _writeDelay = Duration(milliseconds: 500);

@immutable
class PresetBarState {
  const PresetBarState({this.groupFilter});
  final String? groupFilter; // null = all groups

  /// {"v":1,"group":null} (6.14).
  Map<String, Object?> toJson() => {'v': 1, 'group': groupFilter};

  /// Unknown `v` reads the known fields. A `group` that is not a non-blank
  /// string is the default (all groups) and is named in [invalidFields].
  factory PresetBarState.fromJson(
    Map<String, Object?> json, {
    List<String>? invalidFields,
  }) {
    final raw = json['group'];
    if (raw == null) return const PresetBarState();
    if (raw is String && raw.trim().isNotEmpty) {
      return PresetBarState(groupFilter: raw);
    }
    invalidFields?.add('group');
    return const PresetBarState();
  }

  @override
  bool operator ==(Object other) =>
      other is PresetBarState && other.groupFilter == groupFilter;

  @override
  int get hashCode => Object.hash(PresetBarState, groupFilter);

  @override
  String toString() => 'PresetBarState(groupFilter: $groupFilter)';
}

/// Global. Persists EditorSettingKeys.presetBar (device — contract 7.4.6 '프리셋 바 필터').
///
/// Same load rules as the other EDITOR notifiers: build() returns the default
/// synchronously and the stored value replaces it after the load (a change
/// made before the load completes wins); settings.watch brings values written
/// elsewhere (own echo ignored); an invalid stored value is the default and is
/// reported once per load (library 'feature_editor').
class PresetBarNotifier extends Notifier<PresetBarState> {
  late DebouncedSettingWriter _writer;
  StreamSubscription<Map<String, Object?>>? _remote;
  int _generation = 0;

  @override
  PresetBarState build() {
    final settings = ref.watch(core.settingsRepositoryProvider);
    final generation = ++_generation;
    final writer = _writer = DebouncedSettingWriter(
      settings: settings,
      key: EditorSettingKeys.presetBar,
      delay: _writeDelay,
    );
    ref.onDispose(() {
      _generation++;
      writer.dispose();
      unawaited(_remote?.cancel());
      _remote = null;
    });
    unawaited(_load(settings, generation));
    return const PresetBarState();
  }

  /// null = all groups. A blank name is all groups.
  void setGroupFilter(String? group) {
    final next = PresetBarState(
      groupFilter: group == null || group.trim().isEmpty ? null : group,
    );
    if (next == state) return;
    state = next;
    final json = next.toJson();
    _writer.schedule(() => json);
  }

  /// Writes a pending debounced value now (EditorCommands.flushAll, 6.17).
  Future<void> flush() => _writer.flush();

  Future<void> _load(core.SettingsRepository settings, int generation) async {
    Map<String, Object?> json = const {};
    try {
      json = await settings.get(EditorSettingKeys.presetBar);
    } on Object catch (error, stack) {
      _report(error, stack, 'while loading the preset bar filter');
    }
    if (generation != _generation) return; // rebuilt or disposed meanwhile
    final invalid = <String>[];
    final loaded = PresetBarState.fromJson(json, invalidFields: invalid);
    if (invalid.isNotEmpty) {
      _report(
        FormatException(
          'Invalid preset bar setting replaced by the default: '
          '${invalid.map((f) => '${EditorSettingKeys.presetBar.name}.$f').join(', ')}',
        ),
        null,
        'while loading the preset bar filter',
      );
    }
    if (!_writer.isPending) state = loaded;
    _remote = settings
        .watch(EditorSettingKeys.presetBar)
        .listen(
          _onRemote,
          onError: (Object error, StackTrace stack) =>
              _report(error, stack, 'while watching the preset bar filter'),
        );
  }

  void _onRemote(Map<String, Object?> json) {
    if (_writer.isOwnEcho(json) || _writer.isPending) return;
    final next = PresetBarState.fromJson(json);
    if (next != state) state = next;
  }

  void _report(Object error, StackTrace? stack, String context) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'feature_editor',
        context: ErrorDescription(context),
      ),
    );
  }
}

final editorPresetBarProvider =
    NotifierProvider<PresetBarNotifier, PresetBarState>(
      PresetBarNotifier.new,
      name: 'editorPresetBarProvider',
    );

/// The filter that applies to [all]: [groupFilter] when some active preset
/// still has that group, otherwise null (all groups) — a filter whose group
/// was renamed or deleted (here or on another device) does not leave the bar
/// empty. The stored filter is kept.
String? effectiveGroupFilter(List<core.PenPreset> all, String? groupFilter) {
  if (groupFilter == null) return null;
  return all.any((p) => p.group == groupFilter) ? groupFilter : null;
}

/// pinned && (filter == null || group == filter), in CORE order (sortKey, id).
/// Source: core.penPresetsProvider (EDITOR does not define a presets provider).
final editorVisiblePresetsProvider = Provider<AsyncValue<List<core.PenPreset>>>(
  (ref) {
    final presets = ref.watch(core.penPresetsProvider);
    final filter = ref.watch(
      editorPresetBarProvider.select((s) => s.groupFilter),
    );
    return presets.whenData((all) {
      final group = effectiveGroupFilter(all, filter);
      return List<core.PenPreset>.unmodifiable([
        for (final p in all)
          if (p.pinned && (group == null || p.group == group)) p,
      ]);
    });
  },
  name: 'editorVisiblePresetsProvider',
);

/// Distinct non-null groups, sorted (Korean collation not required).
final editorPresetGroupsProvider = Provider<List<String>>((ref) {
  final all = ref.watch(core.penPresetsProvider).value ?? const [];
  final groups = {
    for (final p in all)
      if (p.group != null) p.group!,
  }.toList()..sort();
  return List<String>.unmodifiable(groups);
}, name: 'editorPresetGroupsProvider');

/// [all] in the order of [order] when one is set (ids not in it keep their
/// relative order after the listed ones — the reorderPresets rule).
List<core.PenPreset> presetsInOrder(
  List<core.PenPreset> all,
  List<String>? order,
) {
  if (order == null) return all;
  final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
  final indexed = [for (var i = 0; i < all.length; i++) (i, all[i])];
  indexed.sort((a, b) {
    final ra = rank[a.$2.id] ?? order.length + a.$1;
    final rb = rank[b.$2.id] ?? order.length + b.$1;
    return ra.compareTo(rb);
  });
  return [for (final (_, p) in indexed) p];
}

abstract final class PresetOrdering {
  /// The bar shows a subset (pinned + group filter). Moves one item inside the subset
  /// (onReorderItem semantics: newIndex is the final index after removal) and returns
  /// the FULL active id order for core.PenPresetRepository.reorderPresets: walk [all]
  /// (CORE order), replacing subset members in sequence with the reordered subset.
  ///
  /// Subset ids that are not in [all] are dropped first (CORE would ignore
  /// them). Throws a RangeError when [oldIndex] or [newIndex] is outside the
  /// subset.
  static List<String> reorderSubset({
    required List<core.PenPreset> all,
    required List<String> subsetIds,
    required int oldIndex,
    required int newIndex,
  }) {
    RangeError.checkValidIndex(oldIndex, subsetIds, 'oldIndex');
    RangeError.checkValidIndex(newIndex, subsetIds, 'newIndex');
    final reordered = [...subsetIds];
    reordered.insert(newIndex, reordered.removeAt(oldIndex));
    final known = {for (final p in all) p.id};
    final subset = [
      for (final id in reordered)
        if (known.contains(id)) id,
    ];
    final members = subset.toSet();
    var next = 0;
    return List<String>.unmodifiable([
      for (final p in all) members.contains(p.id) ? subset[next++] : p.id,
    ]);
  }
}

/// (v2.15-ui, m5-7/04-editor 23) Most pens the tray holds.
const int kTrayMaxPens = 8;

/// (v2.15-ui) The pen tray's pens: the pinned presets (the same stored
/// presets and pinned flag the preset row showed — nothing migrates) in CORE
/// order, at most [kTrayMaxPens]. The tray has no group menu, so the stored
/// group filter (editor.presetBar) does not apply: a filter set on the old
/// row must not hide pens with no way to bring them back.
final editorTrayPresetsProvider = Provider<AsyncValue<List<core.PenPreset>>>((
  ref,
) {
  final presets = ref.watch(core.penPresetsProvider);
  return presets.whenData(
    (all) => List<core.PenPreset>.unmodifiable(
      all.where((p) => p.pinned).take(kTrayMaxPens),
    ),
  );
}, name: 'editorTrayPresetsProvider');

/// (v2.15-ui) The number of pinned presets (the tray's limit counts them
/// all, also those past [kTrayMaxPens] from the old row).
final editorPinnedCountProvider = Provider<int>((ref) {
  final all = ref.watch(core.penPresetsProvider).value ?? const [];
  return all.where((p) => p.pinned).length;
}, name: 'editorPinnedCountProvider');
