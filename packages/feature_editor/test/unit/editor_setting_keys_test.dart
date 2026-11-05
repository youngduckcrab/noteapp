// E-06: EditorSettingKeys (04-editor 6.14) — every key has the 'editor.'
// prefix and a valid CORE name, the scopes match the 6.14 table (device 4,
// synced 4, contract 7.4.6), and every key is a JSON map defaulting to {}.
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;

void main() {
  final all = EditorSettingKeys.all;

  test('all lists the eight keys of 6.14, each once', () {
    expect(all, hasLength(8));
    expect({for (final k in all) k.name}, hasLength(8));
  });

  test("names: 'editor.' prefix and the CORE name rule", () {
    final rule = RegExp(r'^[a-z][a-zA-Z0-9_.]{0,63}$');
    for (final key in all) {
      expect(key.name, startsWith('editor.'), reason: key.name);
      expect(rule.hasMatch(key.name), isTrue, reason: key.name);
      expect(key.name, isNot(startsWith('sync.')));
    }
  });

  test('scopes = 6.14 table (contract 7.4.6 v1.1)', () {
    final scopes = {for (final k in all) k.name: k.scope};
    expect(scopes, {
      'editor.settings.device': core.SettingScope.device,
      'editor.toolSelection': core.SettingScope.device,
      'editor.viewport': core.SettingScope.device,
      'editor.presetBar': core.SettingScope.device,
      'editor.settings.synced': core.SettingScope.synced,
      'editor.penStyles': core.SettingScope.synced,
      'editor.eraser': core.SettingScope.synced,
      'editor.colors': core.SettingScope.synced,
    });
    expect(all.where((k) => k.scope == core.SettingScope.device), hasLength(4));
    expect(all.where((k) => k.scope == core.SettingScope.synced), hasLength(4));
  });

  test('every key is a JSON map with an empty default', () {
    for (final key in all) {
      expect(key.defaultValue, isEmpty);
      expect(key.decode({'v': 1, 'a': 2}), {'v': 1, 'a': 2});
      expect(() => key.decode('text'), throwsA(anything));
    }
  });

  test('the named keys are the ones in all', () {
    expect(all, [
      EditorSettingKeys.deviceSettings,
      EditorSettingKeys.toolSelection,
      EditorSettingKeys.viewport,
      EditorSettingKeys.presetBar,
      EditorSettingKeys.syncedSettings,
      EditorSettingKeys.penStyles,
      EditorSettingKeys.eraser,
      EditorSettingKeys.colors,
    ]);
  });
}
