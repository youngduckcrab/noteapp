// lib/src/state/providers.dart — every LIBRARY provider (05-library 6.3.2).
// Riverpod 3.4.3 without code generation; name: == the variable name
// (contract 7.4.4). None of them has to be overridden by the app shell.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' show settingsSnapshotProvider;

import '../model/new_note_spec.dart';
import '../model/view_prefs.dart';
import '../settings/library_settings_keys.dart';
import 'prefs_notifier.dart';

/// View mode, sort and sidebar visibility (device settings, optimistic).
final libraryPrefsProvider =
    NotifierProvider<LibraryPrefsNotifier, LibraryViewPrefs>(
      LibraryPrefsNotifier.new,
      name: 'libraryPrefsProvider',
    );

/// NewNoteOptions.fromJson(snapshot.get(LibrarySettingsKeys.newNoteDefaults));
/// const NewNoteOptions() while the settings load or after a stream error.
final newNoteDefaultsProvider = Provider<NewNoteOptions>((ref) {
  final snapshot = ref.watch(settingsSnapshotProvider).value;
  if (snapshot == null) return const NewNoteOptions();
  return NewNoteOptions.fromJson(
    snapshot.get(LibrarySettingsKeys.newNoteDefaults),
  );
}, name: 'newNoteDefaultsProvider');
