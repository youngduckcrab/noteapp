// LibrarySettingsKeys (05-library 6.3.4, 8 L3; contract 7.2.9 key names,
// 7.4.6 scopes).
import 'package:feature_library/src/settings/library_settings_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';

void main() {
  final keys = LibrarySettingsKeys.all;

  test('names follow the CORE rule and the library. prefix, no duplicates', () {
    final rule = RegExp(r'^[a-z][a-zA-Z0-9_.]{0,63}$');
    for (final key in keys) {
      expect(rule.hasMatch(key.name), isTrue, reason: key.name);
      expect(key.name, startsWith('library.'));
    }
    expect(keys.map((k) => k.name).toSet(), hasLength(keys.length));
    expect(keys, hasLength(6));
  });

  test('view, sort, sidebar and expansion are per device', () {
    for (final key in [
      LibrarySettingsKeys.viewMode,
      LibrarySettingsKeys.sortField,
      LibrarySettingsKeys.sortDescending,
      LibrarySettingsKeys.sidebarVisible,
      LibrarySettingsKeys.expandedFolders,
    ]) {
      expect(key.scope, SettingScope.device, reason: key.name);
    }
  });

  test('the new note defaults are synced', () {
    expect(LibrarySettingsKeys.newNoteDefaults.scope, SettingScope.synced);
  });

  test('types and defaults', () {
    expect(LibrarySettingsKeys.viewMode.defaultValue, 'grid');
    expect(LibrarySettingsKeys.sortField.defaultValue, 'updatedAt');
    expect(LibrarySettingsKeys.sortDescending.defaultValue, isTrue);
    expect(LibrarySettingsKeys.sidebarVisible.defaultValue, isTrue);
    expect(
      LibrarySettingsKeys.expandedFolders,
      isA<SettingKey<List<String>>>(),
    );
    expect(LibrarySettingsKeys.expandedFolders.defaultValue, isEmpty);
    expect(
      LibrarySettingsKeys.newNoteDefaults,
      isA<SettingKey<Map<String, Object?>>>(),
    );
    expect(LibrarySettingsKeys.newNoteDefaults.defaultValue, isEmpty);
  });

  test('every key is accepted by the CORE settings repository', () async {
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final s = store.settings;
    await s.set(LibrarySettingsKeys.viewMode, 'list');
    await s.set(LibrarySettingsKeys.sortField, 'name');
    await s.set(LibrarySettingsKeys.sortDescending, false);
    await s.set(LibrarySettingsKeys.sidebarVisible, false);
    await s.set(LibrarySettingsKeys.expandedFolders, const ['a', 'b']);
    await s.set(LibrarySettingsKeys.newNoteDefaults, const {'size': 'letter'});
    final snapshot = await s.watchAll().first;
    expect(snapshot.get(LibrarySettingsKeys.viewMode), 'list');
    expect(snapshot.get(LibrarySettingsKeys.expandedFolders), ['a', 'b']);
    expect(snapshot.get(LibrarySettingsKeys.newNoteDefaults), {
      'size': 'letter',
    });
  });
}
