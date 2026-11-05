/// `ws hosting-config`: `app/firebase.json`, optionally with cross-origin
/// isolation headers for the `exp-wasm` experiment channel
/// (docs/plans/01-infra.md 6.12, contract 00-overview 7.4.9).
library;

import 'dart:convert';

/// Repo-relative path of the Hosting configuration.
const String hostingConfigPath = 'app/firebase.json';

/// Headers added by `--isolate` (never part of the default configuration).
const Map<String, String> isolationHeaders = {
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Embedder-Policy': 'require-corp',
};

/// Thrown when the configuration is not the expected JSON shape.
final class HostingConfigException implements Exception {
  const HostingConfigException(this.message);

  final String message;

  @override
  String toString() => 'HostingConfigException: $message';
}

/// Parses `firebase.json` text. Throws [HostingConfigException].
Map<String, Object?> parseHostingConfig(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException catch (e) {
    throw HostingConfigException('not valid JSON: ${e.message}');
  }
  if (json is! Map<String, Object?> || json['hosting'] is! Map) {
    throw const HostingConfigException('no `hosting` object');
  }
  return json;
}

/// A copy of [config] whose `hosting.headers` entry for source `**` also has
/// [isolationHeaders] (the entry is created when missing; existing values
/// of the same keys are replaced).
Map<String, Object?> isolatedHostingConfig(Map<String, Object?> config) {
  final copy = jsonDecode(jsonEncode(config)) as Map<String, Object?>;
  final hosting = copy['hosting']! as Map<String, Object?>;
  final headers = (hosting['headers'] as List<Object?>?) ?? <Object?>[];
  hosting['headers'] = headers;
  Map<String, Object?>? all;
  for (final entry in headers) {
    if (entry is Map<String, Object?> && entry['source'] == '**') {
      all = entry;
      break;
    }
  }
  if (all == null) {
    all = <String, Object?>{'source': '**', 'headers': <Object?>[]};
    headers.insert(0, all);
  }
  final list = (all['headers'] as List<Object?>?) ?? <Object?>[];
  all['headers'] = list;
  list.removeWhere((h) => h is Map && isolationHeaders.containsKey(h['key']));
  isolationHeaders.forEach((key, value) {
    list.add(<String, Object?>{'key': key, 'value': value});
  });
  return copy;
}

/// Pretty JSON text of [config].
String encodeHostingConfig(Map<String, Object?> config) =>
    '${const JsonEncoder.withIndent('  ').convert(config)}\n';
