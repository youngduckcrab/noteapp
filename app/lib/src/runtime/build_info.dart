/// Compile-time build metadata (docs/plans/01-infra.md 4.5.1, 6.11).
library;

import 'package:flutter/foundation.dart';

/// Where a build is served from.
enum BuildChannel { local, preview, live, experiment }

/// Compile-time build metadata.
///
/// Injected with `--dart-define-from-file=build/build_info.json`; the same
/// JSON file is served as `/build_info.json` for update detection (6.11).
@immutable
final class BuildInfo {
  const BuildInfo({
    required this.version,
    required this.buildNumber,
    required this.gitSha,
    required this.gitRef,
    required this.channel,
    this.builtAt,
  });

  /// Reads APP_VERSION, APP_BUILD_NUMBER, APP_GIT_SHA, APP_GIT_REF,
  /// APP_CHANNEL, APP_BUILD_TIME via String.fromEnvironment.
  /// Missing or malformed values fall back to [local] field by field.
  factory BuildInfo.fromEnvironment() => _fromValues(const {
    _versionKey: String.fromEnvironment(_versionKey),
    _buildNumberKey: String.fromEnvironment(_buildNumberKey),
    _gitShaKey: String.fromEnvironment(_gitShaKey),
    _gitRefKey: String.fromEnvironment(_gitRefKey),
    _channelKey: String.fromEnvironment(_channelKey),
    _buildTimeKey: String.fromEnvironment(_buildTimeKey),
  });

  /// Parses the same keys (APP_*) from a decoded build_info.json map.
  /// Throws [FormatException] when APP_GIT_SHA is missing.
  factory BuildInfo.fromJson(Map<String, Object?> json) {
    final sha = json[_gitShaKey];
    if (sha is! String || sha.trim().isEmpty) {
      throw const FormatException('build_info.json has no APP_GIT_SHA');
    }
    return _fromValues({
      for (final key in _keys)
        key: switch (json[key]) {
          final String s => s,
          final num n => '$n',
          _ => null,
        },
    });
  }

  /// Used by `flutter run`, tests and builds without defines.
  static const BuildInfo local = BuildInfo(
    version: '0.0.0',
    buildNumber: 0,
    gitSha: 'local',
    gitRef: 'local',
    channel: BuildChannel.local,
  );

  final String version;
  final int buildNumber;
  final String gitSha;
  final String gitRef;
  final BuildChannel channel;
  final DateTime? builtAt;

  bool get isLocal => gitSha == local.gitSha;

  /// First 7 characters of [gitSha], or `local`.
  String get shortSha => isLocal
      ? local.gitSha
      : gitSha.length > 7
      ? gitSha.substring(0, 7)
      : gitSha;

  /// e.g. `0.1.0 (#42 · a1b2c3d · main)`.
  String get displayLabel => '$version (#$buildNumber · $shortSha · $gitRef)';

  Map<String, String> toJson() => {
    _versionKey: version,
    _buildNumberKey: '$buildNumber',
    _gitShaKey: gitSha,
    _gitRefKey: gitRef,
    _channelKey: channel.name,
    if (builtAt != null) _buildTimeKey: _formatTime(builtAt!),
  };

  @override
  bool operator ==(Object other) =>
      other is BuildInfo &&
      other.version == version &&
      other.buildNumber == buildNumber &&
      other.gitSha == gitSha &&
      other.gitRef == gitRef &&
      other.channel == channel &&
      other.builtAt == builtAt;

  @override
  int get hashCode =>
      Object.hash(version, buildNumber, gitSha, gitRef, channel, builtAt);

  @override
  String toString() => 'BuildInfo($displayLabel, ${channel.name})';
}

const String _versionKey = 'APP_VERSION';
const String _buildNumberKey = 'APP_BUILD_NUMBER';
const String _gitShaKey = 'APP_GIT_SHA';
const String _gitRefKey = 'APP_GIT_REF';
const String _channelKey = 'APP_CHANNEL';
const String _buildTimeKey = 'APP_BUILD_TIME';

const List<String> _keys = [
  _versionKey,
  _buildNumberKey,
  _gitShaKey,
  _gitRefKey,
  _channelKey,
  _buildTimeKey,
];

final RegExp _digits = RegExp(r'^\d{1,9}$');

BuildInfo _fromValues(Map<String, String?> values) {
  String? text(String key) {
    final value = values[key]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  final number = text(_buildNumberKey);
  final channel = text(_channelKey);
  final time = text(_buildTimeKey);
  return BuildInfo(
    version: text(_versionKey) ?? BuildInfo.local.version,
    buildNumber: number != null && _digits.hasMatch(number)
        ? int.parse(number)
        : BuildInfo.local.buildNumber,
    gitSha: text(_gitShaKey) ?? BuildInfo.local.gitSha,
    gitRef: text(_gitRefKey) ?? BuildInfo.local.gitRef,
    channel: BuildChannel.values.firstWhere(
      (c) => c.name == channel,
      orElse: () => BuildInfo.local.channel,
    ),
    builtAt: time == null ? null : DateTime.tryParse(time)?.toUtc(),
  );
}

/// `2026-11-04T09:10:00Z` (UTC, whole seconds) — the format `ws build-info`
/// writes.
String _formatTime(DateTime time) {
  final utc = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-'
      '${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:'
      '${two(utc.second)}Z';
}
