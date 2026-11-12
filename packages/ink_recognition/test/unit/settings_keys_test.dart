// RecognitionSettingsKeys (m5-7/05-library 4.4.3, 8.2 L2-07; contract 7.4.4
// v2.1 — CP-L9): the four contract recog.* keys + recog.mathOnDevice (the
// on-device math engine, device scope), their scopes and defaults, CORE's
// name rule, and the language fallback.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/src/settings/recognition_settings_keys.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';

void main() {
  test('five keys, recog. prefix, CORE name rule, no duplicates', () {
    final keys = RecognitionSettingsKeys.all;
    expect(keys.map((k) => k.name), [
      'recog.language',
      'recog.mathConsent',
      'recog.autoIndex',
      'recog.modelWifiOnly',
      'recog.mathOnDevice',
    ]);
    final rule = RegExp(r'^[a-z][a-zA-Z0-9_.]{0,63}$');
    for (final key in keys) {
      expect(rule.hasMatch(key.name), isTrue, reason: key.name);
      expect(key.name, startsWith('recog.'));
    }
    expect(keys.map((k) => k.name).toSet(), hasLength(5));
  });

  test('scopes and defaults (contract 7.4.4)', () {
    expect(RecognitionSettingsKeys.language, isA<SettingKey<String>>());
    expect(RecognitionSettingsKeys.language.scope, SettingScope.synced);
    expect(RecognitionSettingsKeys.language.defaultValue, 'ko');
    expect(RecognitionSettingsKeys.mathConsent, isA<SettingKey<bool>>());
    expect(RecognitionSettingsKeys.mathConsent.scope, SettingScope.synced);
    expect(RecognitionSettingsKeys.mathConsent.defaultValue, isFalse);
    expect(RecognitionSettingsKeys.autoIndex, isA<SettingKey<bool>>());
    expect(RecognitionSettingsKeys.autoIndex.scope, SettingScope.device);
    expect(RecognitionSettingsKeys.autoIndex.defaultValue, isFalse);
    expect(RecognitionSettingsKeys.modelWifiOnly, isA<SettingKey<bool>>());
    expect(RecognitionSettingsKeys.modelWifiOnly.scope, SettingScope.device);
    expect(RecognitionSettingsKeys.modelWifiOnly.defaultValue, isTrue);
    expect(RecognitionSettingsKeys.mathOnDevice, isA<SettingKey<bool>>());
    expect(RecognitionSettingsKeys.mathOnDevice.scope, SettingScope.device);
    expect(RecognitionSettingsKeys.mathOnDevice.defaultValue, isFalse);
  });

  test(
    'the CORE settings repository takes every key and reads it back',
    () async {
      final store = createFakeNoteStore();
      addTearDown(store.close);
      final s = store.settings;
      expect(await s.get(RecognitionSettingsKeys.language), 'ko');
      expect(await s.get(RecognitionSettingsKeys.mathConsent), isFalse);
      await s.set(RecognitionSettingsKeys.language, 'en');
      await s.set(RecognitionSettingsKeys.mathConsent, true);
      await s.set(RecognitionSettingsKeys.autoIndex, true);
      await s.set(RecognitionSettingsKeys.modelWifiOnly, false);
      expect(await s.get(RecognitionSettingsKeys.language), 'en');
      expect(await s.get(RecognitionSettingsKeys.mathConsent), isTrue);
      expect(await s.get(RecognitionSettingsKeys.autoIndex), isTrue);
      expect(await s.get(RecognitionSettingsKeys.modelWifiOnly), isFalse);
    },
  );

  test("an unknown language value reads as 'ko'", () {
    expect(recognitionLanguageOf('ko'), 'ko');
    expect(recognitionLanguageOf('en'), 'en');
    expect(recognitionLanguageOf('ja'), 'ko');
    expect(recognitionLanguageOf(''), 'ko');
    expect(kRecognitionLanguages, ['ko', 'en']);
  });
}
