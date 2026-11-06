// E-06: EditorSettingKeys (04-editor 6.14) — every key has the 'editor.'
// prefix and a valid CORE name, the scopes match the 6.14 table (device 4,
// synced 4, contract 7.4.6), and every key is a JSON map defaulting to {}.
// (v2) E2-01 adds editor.deviceState (device); E2-03 adds editor.toolOptions
// and editor.playback.preRollMs (synced) — the P-A end state of
// m5-7/04-editor 6.18: device 5, synced 6; all is List<SettingKey<Object?>>
// and preRollMs is the only integer key. (P-B) E2-10b adds editor.textDraft
// (device): device 6, synced 6.
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;

void main() {
  final all = EditorSettingKeys.all;

  test('all lists the twelve keys (6.14 + 6.18), each once', () {
    expect(all, isA<List<core.SettingKey<Object?>>>());
    expect(all, hasLength(12));
    expect({for (final k in all) k.name}, hasLength(12));
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
      'editor.deviceState': core.SettingScope.device,
      'editor.textDraft': core.SettingScope.device,
      'editor.settings.synced': core.SettingScope.synced,
      'editor.penStyles': core.SettingScope.synced,
      'editor.eraser': core.SettingScope.synced,
      'editor.colors': core.SettingScope.synced,
      'editor.toolOptions': core.SettingScope.synced,
      'editor.playback.preRollMs': core.SettingScope.synced,
    });
    expect(all.where((k) => k.scope == core.SettingScope.device), hasLength(6));
    expect(all.where((k) => k.scope == core.SettingScope.synced), hasLength(6));
  });

  test('every key but preRollMs is a JSON map with an empty default', () {
    for (final key in all) {
      if (identical(key, EditorSettingKeys.playbackPreRollMs)) continue;
      expect(key.defaultValue, isEmpty, reason: key.name);
      expect(key.decode({'v': 1, 'a': 2}), {'v': 1, 'a': 2});
      expect(() => key.decode('text'), throwsA(anything));
    }
  });

  test('preRollMs: the only integer key, default 1500', () {
    final ints = [
      for (final k in all)
        if (k is core.SettingKey<int>) k,
    ];
    expect(ints, [EditorSettingKeys.playbackPreRollMs]);
    final key = EditorSettingKeys.playbackPreRollMs;
    expect(key.defaultValue, 1500);
    expect(key.decode(2000), 2000);
  });

  test('the named keys are the ones in all', () {
    expect(all, [
      EditorSettingKeys.deviceSettings,
      EditorSettingKeys.toolSelection,
      EditorSettingKeys.viewport,
      EditorSettingKeys.presetBar,
      EditorSettingKeys.deviceState,
      EditorSettingKeys.textDraft,
      EditorSettingKeys.syncedSettings,
      EditorSettingKeys.penStyles,
      EditorSettingKeys.eraser,
      EditorSettingKeys.colors,
      EditorSettingKeys.toolOptions,
      EditorSettingKeys.playbackPreRollMs,
    ]);
  });
}
