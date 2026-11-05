/// `ws build-info`: writes `build_info.json`, the `--dart-define-from-file`
/// input of the web build and the file the app polls for new versions
/// (docs/plans/01-infra.md 4.5.1, 6.11).
library;

import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// The channels of `BuildInfo.channel` (app `BuildChannel`).
const List<String> buildChannels = ['live', 'preview', 'experiment', 'local'];

/// Invalid input for `ws build-info` (usage error, exit code 2).
final class BuildInfoException implements Exception {
  const BuildInfoException(this.message);

  final String message;

  @override
  String toString() => 'BuildInfoException: $message';
}

final RegExp _version = RegExp(r'^\d+\.\d+\.\d+$');
final RegExp _sha = RegExp(r'^[0-9a-f]{40}$');
final RegExp _digits = RegExp(r'^\d+$');

/// The build info values (every value a string):
/// `APP_VERSION`, `APP_BUILD_NUMBER`, `APP_GIT_SHA`, `APP_GIT_REF`,
/// `APP_CHANNEL`, `APP_BUILD_TIME`.
///
/// `GITHUB_SHA`, `GITHUB_REF_NAME` and `GITHUB_RUN_NUMBER` come from
/// [environment]; when they are missing the values are `local`, `local` and
/// `0`. Throws [BuildInfoException] for an unknown [channel], a [version]
/// that is not `x.y.z`, a `GITHUB_SHA` that is not 40 lowercase hex digits or
/// a `GITHUB_RUN_NUMBER` that is not a number.
Map<String, String> buildInfoValues({
  required String channel,
  required String version,
  required Map<String, String> environment,
  required DateTime now,
}) {
  if (!buildChannels.contains(channel)) {
    throw BuildInfoException(
      'unknown channel `$channel` (one of ${buildChannels.join(', ')})',
    );
  }
  if (!_version.hasMatch(version)) {
    throw BuildInfoException('version `$version` is not x.y.z');
  }
  String? env(String key) {
    final value = environment[key]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  final sha = env('GITHUB_SHA');
  if (sha != null && !_sha.hasMatch(sha)) {
    throw BuildInfoException(
      'GITHUB_SHA `$sha` is not 40 lowercase hex digits',
    );
  }
  final number = env('GITHUB_RUN_NUMBER');
  if (number != null && !_digits.hasMatch(number)) {
    throw BuildInfoException('GITHUB_RUN_NUMBER `$number` is not a number');
  }
  return {
    'APP_VERSION': version,
    'APP_BUILD_NUMBER': number ?? '0',
    'APP_GIT_SHA': sha ?? 'local',
    'APP_GIT_REF': env('GITHUB_REF_NAME') ?? 'local',
    'APP_CHANNEL': channel,
    'APP_BUILD_TIME': formatBuildTime(now),
  };
}

/// `2026-11-04T09:10:00Z` (UTC, whole seconds).
String formatBuildTime(DateTime time) {
  final utc = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-'
      '${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:'
      '${two(utc.second)}Z';
}

/// The `x.y.z` part of the `version:` of the pubspec at [pubspecPath]
/// (`0.1.0+1` → `0.1.0`). Throws [BuildInfoException].
String appVersionFromPubspec(String pubspecPath) {
  final file = File(pubspecPath);
  if (!file.existsSync()) {
    throw BuildInfoException('$pubspecPath not found (pass --version)');
  }
  final Object? yaml;
  try {
    yaml = loadYaml(file.readAsStringSync());
  } on YamlException catch (e) {
    throw BuildInfoException('cannot parse $pubspecPath: ${e.message}');
  }
  final version = yaml is YamlMap ? yaml['version'] : null;
  if (version == null) {
    throw BuildInfoException('$pubspecPath has no `version:` (pass --version)');
  }
  return '$version'.split('+').first;
}

/// The JSON text written to the `--out` file.
String encodeBuildInfo(Map<String, String> values) =>
    '${const JsonEncoder.withIndent('  ').convert(values)}\n';
