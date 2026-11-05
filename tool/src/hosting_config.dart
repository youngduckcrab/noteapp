/// `ws hosting-config`: `app/firebase.json`, optionally with cross-origin
/// isolation headers for the `exp-wasm` experiment channel
/// (docs/plans/01-infra.md 6.12, contract 00-overview 7.4.9).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

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

/// Rule files of the M4 shape (6.12): `firestore.rules`, `firestore.indexes`
/// and `storage.rules`, relative to the directory of `firebase.json`.
const List<(String, String)> hostingRuleFileKeys = [
  ('firestore', 'rules'),
  ('firestore', 'indexes'),
  ('storage', 'rules'),
];

/// Problems of a default (not `--isolate`) Hosting configuration
/// (6.12 table, contract 7.4.9): `public` is `build/web`, every path is
/// rewritten to `/index.html`, `**` is `no-cache`, `**/*.wasm` is
/// `application/wasm`, there is no COOP / COEP header, and each referenced
/// rules / indexes file exists under [appDir]. Empty when fine.
List<String> hostingConfigProblems(
  Map<String, Object?> config, {
  required String appDir,
}) {
  final problems = <String>[];
  final hosting = config['hosting'];
  if (hosting is! Map<String, Object?>) return ['no `hosting` object'];
  if (hosting['public'] != 'build/web') {
    problems.add('hosting.public must be "build/web"');
  }
  final rewrites = hosting['rewrites'];
  final rewritesAll =
      rewrites is List &&
      rewrites.any(
        (r) =>
            r is Map &&
            r['source'] == '**' &&
            r['destination'] == '/index.html',
      );
  if (!rewritesAll) {
    problems.add('hosting.rewrites must send "**" to "/index.html"');
  }

  final headers = hosting['headers'];
  String? header(String source, String key) {
    if (headers is! List) return null;
    for (final entry in headers) {
      if (entry is! Map || entry['source'] != source) continue;
      final list = entry['headers'];
      if (list is! List) continue;
      for (final h in list) {
        if (h is Map && h['key'] == key) return '${h['value']}';
      }
    }
    return null;
  }

  if (header('**', 'Cache-Control') != 'no-cache') {
    problems.add('"**" needs Cache-Control: no-cache');
  }
  if (header('**/*.wasm', 'Content-Type') != 'application/wasm') {
    problems.add('"**/*.wasm" needs Content-Type: application/wasm');
  }
  if (headers is List) {
    for (final entry in headers) {
      final list = entry is Map ? entry['headers'] : null;
      if (list is! List) continue;
      for (final h in list) {
        if (h is Map && isolationHeaders.containsKey(h['key'])) {
          problems.add(
            '${h['key']} must not be in the default configuration '
            '(contract 7.4.9; only `ws hosting-config --isolate` adds it)',
          );
        }
      }
    }
  }

  for (final (section, key) in hostingRuleFileKeys) {
    final block = config[section];
    if (block is! Map || !block.containsKey(key)) continue;
    final path = block[key];
    if (path is! String || path.isEmpty) {
      problems.add('$section.$key must be a path');
      continue;
    }
    if (!File(p.normalize(p.join(appDir, path))).existsSync()) {
      problems.add('$section.$key: $path does not exist (relative to app/)');
    }
  }
  return problems;
}
