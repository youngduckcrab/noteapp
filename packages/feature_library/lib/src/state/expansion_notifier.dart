// lib/src/state/expansion_notifier.dart — 05-library 6.3.3 / 6.5 (sidebar
// folders that are expanded; saved per device).
import 'dart:async' show Timer, unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart'
    show
        FolderId,
        FolderTree,
        SettingsRepository,
        folderTreeProvider,
        settingsRepositoryProvider;

import '../common/report_error.dart';
import '../settings/library_settings_keys.dart';

/// Expanded sidebar folders. The state set iterates from the least to the
/// most recently expanded folder.
class FolderExpansionNotifier extends Notifier<Set<FolderId>> {
  /// Saved ids at most (most recently expanded kept).
  static const int maxSaved = 500;

  /// Delay between the last change and the write.
  static const Duration saveDebounce = Duration(milliseconds: 500);

  late SettingsRepository _settings;
  FolderTree? _tree;
  Timer? _saveTimer;
  bool _loaded = false;
  bool _saveAfterLoad = false;

  /// Copy of state for ref.onDispose (state cannot be read there).
  Set<FolderId> _current = const {};

  /// Collapsed before the stored list arrived: not restored from it.
  final Set<FolderId> _collapsedBeforeLoad = {};

  /// Starts empty; loads LibrarySettingsKeys.expandedFolders once and merges it
  /// with anything expanded meanwhile.
  @override
  Set<FolderId> build() {
    _settings = ref.read(settingsRepositoryProvider);
    ref.listen(folderTreeProvider, (_, next) {
      final tree = next.value;
      if (tree != null) _tree = tree;
    }, fireImmediately: true);
    ref.onDispose(_flushOnDispose);
    unawaited(_load());
    return _current = const <FolderId>{};
  }

  void toggle(FolderId id) => state.contains(id) ? collapse(id) : expand(id);

  void expand(FolderId id) => expandAll([id]);

  void collapse(FolderId id) {
    if (!state.contains(id)) return;
    if (!_loaded) _collapsedBeforeLoad.add(id);
    _set({...state}..remove(id));
  }

  /// Reveal: expands every given id (ancestors of the current folder). Ids
  /// already expanded keep their place; nothing changes (and nothing is
  /// saved) when all of them are.
  void expandAll(Iterable<FolderId> ids) {
    final add = [
      for (final id in ids)
        if (!state.contains(id)) id,
    ];
    if (add.isEmpty) return;
    if (!_loaded) _collapsedBeforeLoad.removeAll(add);
    _set({...state, ...add});
  }

  // Persistence: 500 ms after the last change, writes ids that still exist in
  // the current FolderTree (if loaded), at most 500 (most recently expanded
  // kept). ref.onDispose writes immediately if a save is pending.

  Future<void> _load() async {
    List<String> stored;
    try {
      stored = await _settings.get(LibrarySettingsKeys.expandedFolders);
    } on Object catch (error, stack) {
      reportLibraryError(error, stack, 'loading library.sidebar.expanded');
      stored = const [];
    }
    if (!ref.mounted) return;
    _loaded = true;
    final merged = <FolderId>{
      for (final id in stored)
        if (!_collapsedBeforeLoad.contains(id)) id,
    };
    _collapsedBeforeLoad.clear();
    // Expanded meanwhile = more recent than anything stored.
    for (final id in state) {
      merged
        ..remove(id)
        ..add(id);
    }
    state = _current = merged;
    if (_saveAfterLoad) {
      _saveAfterLoad = false;
      _scheduleSave();
    }
  }

  void _set(Set<FolderId> next) {
    state = _current = next;
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDebounce, _save);
  }

  void _save() {
    _saveTimer = null;
    if (!_loaded) {
      // Writing now would drop the stored ids that have not arrived yet.
      _saveAfterLoad = true;
      return;
    }
    _write(_idsToSave(_current, _tree));
  }

  void _flushOnDispose() {
    final pending = _saveTimer != null || _saveAfterLoad;
    _saveTimer?.cancel();
    _saveTimer = null;
    // Before the load finished nothing the user did can be merged safely.
    if (pending && _loaded) _write(_idsToSave(_current, _tree));
  }

  void _write(List<FolderId> ids) {
    unawaited(
      _settings.set(LibrarySettingsKeys.expandedFolders, ids).catchError((
        Object error,
        StackTrace stack,
      ) {
        reportLibraryError(error, stack, 'saving library.sidebar.expanded');
      }),
    );
  }
}

/// Ids of [expanded] (least → most recent) that [tree] still has, the last
/// [FolderExpansionNotifier.maxSaved] of them. No tree yet → no filter.
List<FolderId> _idsToSave(Set<FolderId> expanded, FolderTree? tree) {
  final kept = [
    for (final id in expanded)
      if (tree == null || tree.byId(id) != null) id,
  ];
  final max = FolderExpansionNotifier.maxSaved;
  return kept.length <= max ? kept : kept.sublist(kept.length - max);
}
