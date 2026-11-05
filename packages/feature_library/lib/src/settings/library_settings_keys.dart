// lib/src/settings/library_settings_keys.dart — 05-library 6.3.4. Declared
// only with CORE's SettingKey factories (contract 7.2.9, LIBRARY-S5). Scopes
// follow contract 7.4.6: view, sort, sidebar and expansion are per device;
// the new note defaults are synced.
import 'package:note_core/note_core.dart' show SettingKey, SettingScope;

abstract final class LibrarySettingsKeys {
  /// 'grid' | 'list' (LibraryViewMode.name). Device-local: screen size
  /// differs per device.
  static final SettingKey<String> viewMode = SettingKey.string(
    'library.viewMode',
    'grid',
    scope: SettingScope.device,
  );

  /// LibrarySortField.name ('name' | 'createdAt' | 'updatedAt' | 'custom').
  static final SettingKey<String> sortField = SettingKey.string(
    'library.sortField',
    'updatedAt',
    scope: SettingScope.device,
  );
  static final SettingKey<bool> sortDescending = SettingKey.boolean(
    'library.sortDescending',
    true,
    scope: SettingScope.device,
  );
  static final SettingKey<bool> sidebarVisible = SettingKey.boolean(
    'library.sidebar.visible',
    true,
    scope: SettingScope.device,
  );

  /// Expanded sidebar folder ids (at most 500, most recently expanded kept).
  static final SettingKey<List<String>> expandedFolders = SettingKey.stringList(
    'library.sidebar.expanded',
    const [],
    scope: SettingScope.device,
  );

  /// New note dialog defaults = '기본 속지' setting (NewNoteOptions.toJson()).
  /// Synced.
  static final SettingKey<Map<String, Object?>> newNoteDefaults =
      SettingKey.jsonMap('library.newNote.defaults');

  /// Every key above (settings_keys_test: names, scopes, uniqueness).
  static List<SettingKey<Object?>> get all => [
    viewMode,
    sortField,
    sortDescending,
    sidebarVisible,
    expandedFolders,
    newNoteDefaults,
  ];
}
