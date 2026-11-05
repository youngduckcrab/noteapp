import 'dart:convert';

import 'package:note_core/note_core.dart';
import 'package:note_core/src/repo/settings_internal.dart';
import 'package:test/test.dart';

/// Stores [value] like the repository does (JSON text) and reads it back.
T _roundTrip<T>(SettingKey<T> key, T value) =>
    SettingsSnapshot({key.name: jsonDecode(jsonEncode(key.encode(value)))})
        .get(key);

void main() {
  test('typed keys encode / decode', () {
    expect(_roundTrip(SettingKey.boolean('editor.a', false), true), isTrue);
    expect(_roundTrip(SettingKey.integer('editor.b', 0), 42), 42);
    expect(_roundTrip(SettingKey.number('editor.c', 0), 2.5), 2.5);
    expect(_roundTrip(SettingKey.string('editor.d', ''), '펜'), '펜');
    expect(_roundTrip(SettingKey.intList('editor.e', const []), [1, 2]), [
      1,
      2,
    ]);
    expect(
      _roundTrip(SettingKey.stringList('editor.f', const []), ['a', 'b']),
      ['a', 'b'],
    );
    expect(
      _roundTrip(SettingKey.jsonMap('editor.g'), {
        'k': [1, 'x'],
        'n': null,
      }),
      {
        'k': [1, 'x'],
        'n': null,
      },
    );
  });

  test('scope defaults to synced', () {
    expect(SettingKey.boolean('editor.a', false).scope, SettingScope.synced);
    expect(
      SettingKey.boolean('editor.a', false, scope: SettingScope.device).scope,
      SettingScope.device,
    );
    expect(SettingKey.jsonMap('editor.g').defaultValue, isEmpty);
  });

  test('missing or undecodable values give the default', () {
    final snap = SettingsSnapshot(const {
      'editor.a': 'not a bool',
      'editor.b': 1.5,
      'editor.e': [1, 'x'],
      'editor.f': [1],
      'editor.g': [1, 2],
      'editor.c': 3,
    });
    expect(snap.get(SettingKey.boolean('editor.a', true)), isTrue);
    expect(snap.get(SettingKey.integer('editor.b', 7)), 7);
    expect(snap.get(SettingKey.intList('editor.e', const [9])), [9]);
    expect(snap.get(SettingKey.stringList('editor.f', const ['d'])), ['d']);
    expect(
      snap.get(SettingKey.jsonMap('editor.g', defaultValue: const {'d': 1})),
      {'d': 1},
    );
    expect(
      snap.get(SettingKey.number('editor.c', 0)),
      3.0,
      reason: 'integers are accepted',
    );
    expect(snap.get(SettingKey.string('editor.missing', 'def')), 'def');
  });

  test('custom key', () {
    final key = SettingKey<Duration>(
      'editor.delay',
      defaultValue: Duration.zero,
      encode: (d) => d.inMilliseconds,
      decode: (j) => Duration(milliseconds: j! as int),
    );
    expect(
      _roundTrip(key, const Duration(seconds: 2)),
      const Duration(seconds: 2),
    );
    expect(decodeSetting(key, 'bad'), Duration.zero);
  });

  test("names: pattern, and 'sync.' is reserved", () {
    checkSettingKeyName('editor.penOnlyMode');
    checkSettingKeyName('library.view_mode2');
    expect(() => checkSettingKeyName('sync.cursor'), throwsArgumentError);
    expect(() => checkSettingKeyName('Editor.x'), throwsArgumentError);
    expect(() => checkSettingKeyName(''), throwsArgumentError);
    expect(() => checkSettingKeyName('a${'b' * 64}'), throwsArgumentError);
    expect(() => checkSettingKeyName('editor-x'), throwsArgumentError);
  });

  test('snapshot equality is deep', () {
    expect(
      const SettingsSnapshot({
        'a': [1, 2],
      }),
      SettingsSnapshot({
        'a': [1, 2],
      }),
    );
  });
}
