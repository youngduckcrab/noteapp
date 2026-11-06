// lib/src/providers.dart — media_io internals (m5-7/06-pdf 4.4, 4.6). Not exported.
import 'package:note_core/note_core.dart' as core;

/// The media.* setting keys (contract 7.4.4 prefix, 06-pdf 4.6).
abstract final class MediaSettingKeys {
  /// The recording consent notice was shown on this device (7.4.4: device).
  static final core.SettingKey<bool> consentShown = core.SettingKey.boolean(
    'media.consentShown',
    false,
    scope: core.SettingScope.device,
  );

  /// Last playback speed (applied on the next open).
  static final core.SettingKey<double> playbackSpeed = core.SettingKey.number(
    'media.playbackSpeed',
    1.0,
    scope: core.SettingScope.device,
  );

  /// (v2.1) Recovery attempts per draft {draftId: n} (6.10.3).
  static final core.SettingKey<Map<String, Object?>> recoverAttempts =
      core.SettingKey.jsonMap(
        'media.recoverAttempts',
        scope: core.SettingScope.device,
      );

  /// Recording bit rate (bps); 0 = not set → MediaIoConfig.bitRate (4.6).
  static final core.SettingKey<int> bitRate = core.SettingKey.integer(
    'media.bitRate',
    0,
  );
}
