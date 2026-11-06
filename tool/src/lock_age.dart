/// `ws lock-age` (docs/plans/m5-7/01-infra.md 4.2, 8.2 J20, Q8 — P-C): the
/// 14-day publication rule of the workspace lock (6.1, contract 7.5) checked
/// by machine. Every `hosted` entry of `pubspec.lock` that is new or has
/// another version than at `--since <git-ref>` is looked up on its hosted
/// server's API (`<url>/api/packages/<name>`); a version published fewer
/// than `--min-days` calendar days (UTC) before `--now` is a violation. A
/// version that cannot be read (network error, server error, a version the
/// API does not list, an unreadable answer) is a warning: the check never
/// fails on the network (exit 0 unless a violation was seen).
library;

import 'dart:convert';

import 'package:yaml/yaml.dart';

/// Reads [url]; `null` when the answer is not there (network error,
/// non-200). Same shape as the `web-assets fetch` downloader.
typedef LockAgeFetch = Future<List<int>?> Function(Uri url);

/// The default `--min-days` (01-infra 6.1: 14 days since publication).
const int defaultLockAgeMinDays = 14;

/// A `hosted` package of a pubspec.lock.
final class LockedHostedPackage {
  const LockedHostedPackage({
    required this.name,
    required this.version,
    required this.url,
  });

  final String name;
  final String version;

  /// The hosted server (`description.url`, e.g. `https://pub.dev`).
  final String url;

  /// `<url>/api/packages/<name>`.
  Uri get apiUri {
    final base = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    return Uri.parse('$base/api/packages/${Uri.encodeComponent(name)}');
  }

  @override
  bool operator ==(Object other) =>
      other is LockedHostedPackage &&
      other.name == name &&
      other.version == version &&
      other.url == url;

  @override
  int get hashCode => Object.hash(name, version, url);

  @override
  String toString() => '$name $version';
}

/// A pubspec.lock that cannot be read.
final class LockAgeException implements Exception {
  const LockAgeException(this.message);

  final String message;

  @override
  String toString() => 'LockAgeException: $message';
}

/// The `hosted` entries of [lockText] by name. Other sources (sdk, path,
/// git) are left out. Throws [LockAgeException] on a file that is not a
/// pubspec.lock.
Map<String, LockedHostedPackage> parseHostedPackages(
  String lockText, {
  String source = 'pubspec.lock',
}) {
  final Object? doc;
  try {
    doc = loadYaml(lockText);
  } on YamlException catch (e) {
    throw LockAgeException('$source is not YAML: ${e.message}');
  }
  if (doc is! YamlMap) throw LockAgeException('$source is not a map');
  final packages = doc['packages'];
  if (packages == null) return const {};
  if (packages is! YamlMap) {
    throw LockAgeException('$source: `packages` is not a map');
  }
  final result = <String, LockedHostedPackage>{};
  for (final MapEntry(:key, :value) in packages.entries) {
    if (value is! YamlMap || value['source'] != 'hosted') continue;
    final description = value['description'];
    final version = value['version'];
    if (description is! YamlMap || version is! String) {
      throw LockAgeException('$source: hosted entry `$key` has no version');
    }
    final url = description['url'];
    result['$key'] = LockedHostedPackage(
      name: '${description['name'] ?? key}',
      version: version,
      url: url is String && url.isNotEmpty ? url : 'https://pub.dev',
    );
  }
  return result;
}

/// The hosted packages of [after] that [before] does not have, or has with
/// another version or server, in name order. [before] null = no lock at the
/// base (every hosted entry is new).
List<LockedHostedPackage> changedHostedPackages(String? before, String after) {
  final old = before == null
      ? const <String, LockedHostedPackage>{}
      : parseHostedPackages(before, source: 'pubspec.lock at the base');
  final now = parseHostedPackages(after);
  return [
    for (final name in now.keys.toList()..sort())
      if (old[name] != now[name]) now[name]!,
  ];
}

/// The `published` time of [version] in a package API answer
/// (`{"versions": [{"version": "1.2.3", "published": "…"}, …]}`); null when
/// the answer is not that shape or does not list the version.
DateTime? publishedOf(String apiJson, String version) {
  final Object? doc;
  try {
    doc = jsonDecode(apiJson);
  } on FormatException {
    return null;
  }
  if (doc is! Map) return null;
  final versions = doc['versions'];
  if (versions is! List) return null;
  for (final entry in versions) {
    if (entry is Map && entry['version'] == version) {
      final published = entry['published'];
      return published is String ? DateTime.tryParse(published) : null;
    }
  }
  return null;
}

/// Whole calendar days (UTC) from [published] to [now].
int calendarDaysBetween(DateTime published, DateTime now) {
  DateTime day(DateTime t) {
    final u = t.toUtc();
    return DateTime.utc(u.year, u.month, u.day);
  }

  return day(now).difference(day(published)).inDays;
}

enum LockAgeOutcome {
  /// Published at least min-days ago.
  ok,

  /// Published fewer than min-days ago (violation, exit 1).
  tooNew,

  /// Could not be read (warning, exit stays 0).
  unknown,
}

/// The check of one changed package.
final class LockAgeEntry {
  const LockAgeEntry({
    required this.package,
    required this.outcome,
    this.published,
    this.days,
    this.detail = '',
  });

  final LockedHostedPackage package;
  final LockAgeOutcome outcome;
  final DateTime? published;
  final int? days;

  /// Why the outcome is unknown.
  final String detail;
}

/// What `ws lock-age` found.
final class LockAgeReport {
  const LockAgeReport({
    required this.entries,
    required this.minDays,
    required this.now,
    this.baseWarning,
  });

  final List<LockAgeEntry> entries;
  final int minDays;
  final DateTime now;

  /// Set when the base could not be read (then nothing was compared).
  final String? baseWarning;

  Iterable<LockAgeEntry> get violations =>
      entries.where((e) => e.outcome == LockAgeOutcome.tooNew);

  Iterable<LockAgeEntry> get warnings =>
      entries.where((e) => e.outcome == LockAgeOutcome.unknown);

  int get warningCount => warnings.length + (baseWarning == null ? 0 : 1);

  /// A Markdown table, the warning / violation lines, then the last line
  /// `ws lock-age: N violation(s), M warning(s)`.
  String format({required String since}) {
    final out = StringBuffer();
    final today = _date(now);
    if (baseWarning case final warning?) {
      out.writeln('warning: $warning — nothing compared');
    } else if (entries.isEmpty) {
      out.writeln('No hosted package is new or changed since $since.');
    } else {
      out
        ..writeln(
          '${entries.length} hosted package(s) new or changed since $since '
          '(rule: published at least $minDays day(s) before $today):',
        )
        ..writeln()
        ..writeln('| package | version | published | days | result |')
        ..writeln('|---|---|---|---:|---|');
      for (final e in entries) {
        final published = e.published == null ? '?' : _date(e.published!);
        final result = switch (e.outcome) {
          LockAgeOutcome.ok => 'ok',
          LockAgeOutcome.tooNew => 'too new',
          LockAgeOutcome.unknown => 'unknown',
        };
        out.writeln(
          '| ${e.package.name} | ${e.package.version} | $published | '
          '${e.days ?? '?'} | $result |',
        );
      }
      out.writeln();
      for (final e in violations) {
        out.writeln(
          'violation: ${e.package.name} ${e.package.version} was published '
          '${_date(e.published!)}, ${e.days} day(s) before $today '
          '(< $minDays)',
        );
      }
      for (final e in warnings) {
        out.writeln(
          'warning: ${e.package.name} ${e.package.version}: ${e.detail}',
        );
      }
    }
    out.writeln(
      'ws lock-age: ${violations.length} violation(s), $warningCount '
      'warning(s)',
    );
    return '$out';
  }
}

String _date(DateTime t) => t.toUtc().toIso8601String().substring(0, 10);

/// Checks every hosted package of [lock] that is new or changed against
/// [baseLock] (null = no lock at the base). One API request per package
/// name, in name order.
Future<LockAgeReport> checkLockAge({
  required String? baseLock,
  required String lock,
  required LockAgeFetch fetch,
  required DateTime now,
  int minDays = defaultLockAgeMinDays,
}) async {
  final entries = <LockAgeEntry>[];
  for (final package in changedHostedPackages(baseLock, lock)) {
    final List<int>? body;
    try {
      body = await fetch(package.apiUri);
    } on Object catch (e) {
      entries.add(
        LockAgeEntry(
          package: package,
          outcome: LockAgeOutcome.unknown,
          detail: 'could not read ${package.apiUri} ($e)',
        ),
      );
      continue;
    }
    if (body == null) {
      entries.add(
        LockAgeEntry(
          package: package,
          outcome: LockAgeOutcome.unknown,
          detail: 'could not read ${package.apiUri}',
        ),
      );
      continue;
    }
    final published = publishedOf(
      utf8.decode(body, allowMalformed: true),
      package.version,
    );
    if (published == null) {
      entries.add(
        LockAgeEntry(
          package: package,
          outcome: LockAgeOutcome.unknown,
          detail: '${package.apiUri} does not give the publication time',
        ),
      );
      continue;
    }
    final days = calendarDaysBetween(published, now);
    entries.add(
      LockAgeEntry(
        package: package,
        outcome: days < minDays ? LockAgeOutcome.tooNew : LockAgeOutcome.ok,
        published: published,
        days: days,
      ),
    );
  }
  return LockAgeReport(entries: entries, minDays: minDays, now: now);
}
