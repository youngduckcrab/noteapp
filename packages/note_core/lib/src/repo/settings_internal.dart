// Internal helpers of the settings repositories (CORE 4.5). Not exported.
import 'settings_repository.dart';

/// [SettingKey.defaultValue] when [json] is null or [SettingKey.decode] throws.
T decodeSetting<T>(SettingKey<T> key, Object? json) {
  if (json == null) return key.defaultValue;
  try {
    return key.decode(json);
  } on Object {
    return key.defaultValue;
  }
}

final RegExp _settingName = RegExp(r'^[a-z][a-zA-Z0-9_.]{0,63}$');

/// Repository-side check of a key name (a const constructor cannot validate, CORE 4.5).
void checkSettingKeyName(String name) {
  if (!_settingName.hasMatch(name)) {
    throw ArgumentError.value(name, 'name', 'invalid setting key name');
  }
  if (name.startsWith('sync.')) {
    throw ArgumentError.value(
      name,
      'name',
      "'sync.' is reserved for the SYNC meta KV",
    );
  }
}
