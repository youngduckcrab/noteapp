// lib/src/settings/recognition_settings_keys.dart — (internal) the recog.*
// settings (m5-7/05-library 4.4.3; names, scopes and defaults are contract
// m5-7/00-overview 7.4.4 v2.1, CP-L9). CORE SettingKey factories only.
// There is no 'recognition on' key — the whole feature is FEATURE_RECOGNITION
// (the app shell leaves recognitionOverrides() out).
import 'package:note_core/note_core.dart' show SettingKey, SettingScope;

abstract final class RecognitionSettingsKeys {
  /// 'ko' | 'en' — conversion sheet default and the indexer's model. Unknown value → 'ko'.
  static final SettingKey<String> language = SettingKey.string(
    'recog.language',
    'ko',
    scope: SettingScope.synced,
  );

  /// G-3 / D15: external math engine consent (contract key and default).
  static final SettingKey<bool> mathConsent = SettingKey.boolean(
    'recog.mathConsent',
    false,
    scope: SettingScope.synced,
  );

  /// U16: automatic recognition for search (default off).
  static final SettingKey<bool> autoIndex = SettingKey.boolean(
    'recog.autoIndex',
    false,
    scope: SettingScope.device,
  );

  /// Download models on Wi-Fi only (Android enforces; iOS asks first — 6.7.4).
  static final SettingKey<bool> modelWifiOnly = SettingKey.boolean(
    'recog.modelWifiOnly',
    true,
    scope: SettingScope.device,
  );

  /// Every recog.* key (tests, the settings section).
  static final List<SettingKey<Object>> all = [
    language,
    mathConsent,
    autoIndex,
    modelWifiOnly,
  ];
}

/// The recognition languages (BCP-47 tags of the ML Kit models).
const List<String> kRecognitionLanguages = ['ko', 'en'];

/// [value] of recog.language as a supported tag: 'ko' | 'en'; anything else
/// → 'ko' (4.4.3).
String recognitionLanguageOf(String value) =>
    kRecognitionLanguages.contains(value) ? value : 'ko';
