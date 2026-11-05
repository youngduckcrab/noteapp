// lib/src/state/prefs_notifier.dart — 05-library 6.3.3. The view settings are
// the one optimistic state of the screen (6.3.1): set at once, then saved.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart'
    show
        LibrarySortField,
        SettingsRepository,
        settingsRepositoryProvider,
        settingsSnapshotProvider;

import '../common/report_error.dart';
import '../model/view_prefs.dart';
import '../settings/library_settings_keys.dart';

class LibraryPrefsNotifier extends Notifier<LibraryViewPrefs> {
  /// Watches settingsSnapshotProvider; while loading (or after a stream
  /// error) returns the defaults with isLoaded == false.
  @override
  LibraryViewPrefs build() {
    final snapshot = ref.watch(settingsSnapshotProvider).value;
    return snapshot == null
        ? const LibraryViewPrefs()
        : LibraryViewPrefs.fromSnapshot(snapshot);
  }

  /// Sets state immediately, then SettingsRepository.set (errors reported,
  /// state kept).
  Future<void> setViewMode(LibraryViewMode mode) {
    state = state.copyWith(viewMode: mode);
    return _save('saving library.viewMode', (settings) {
      return [settings.set(LibrarySettingsKeys.viewMode, mode.name)];
    });
  }

  /// LibrarySort.select; field and direction are written together (one
  /// commit, so no snapshot with only one of them changed).
  Future<void> selectSort(LibrarySortField field) {
    final sort = state.sort.select(field);
    state = state.copyWith(sort: sort);
    return _save('saving library.sortField', (settings) {
      return [
        settings.set(LibrarySettingsKeys.sortField, sort.field.name),
        settings.set(LibrarySettingsKeys.sortDescending, sort.descending),
      ];
    });
  }

  Future<void> setSidebarVisible(bool visible) {
    state = state.copyWith(sidebarVisible: visible);
    return _save('saving library.sidebar.visible', (settings) {
      return [settings.set(LibrarySettingsKeys.sidebarVisible, visible)];
    });
  }

  Future<void> _save(
    String context,
    List<Future<void>> Function(SettingsRepository settings) writes,
  ) async {
    try {
      await Future.wait(writes(ref.read(settingsRepositoryProvider)));
    } on Object catch (error, stack) {
      reportLibraryError(error, stack, context);
    }
  }
}
