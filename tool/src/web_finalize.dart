/// `ws finalize-web`: last step after `flutter build web`
/// (docs/plans/01-infra.md 4.2, 6.9, 6.11).
///
/// 1. copies the build info JSON to `<build>/build_info.json` (the compiled
///    defines and the served file come from the same file);
/// 2. on a non-live channel renames the web app in `manifest.json`;
/// 3. checks that the required files exist and that `flutter_bootstrap.js`
///    registers no service worker;
/// 4. reports the size of `main.dart.js` (also to `GITHUB_STEP_SUMMARY`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Files every finalized web build must contain (relative to the build
/// directory); the web assets of `tool/web_assets.yaml` are added by the
/// caller.
const List<String> requiredWebBuildFiles = [
  'index.html',
  'flutter.js',
  'flutter_bootstrap.js',
  'main.dart.js',
  'manifest.json',
  'favicon.png',
  'build_info.json',
];

/// Web app names on non-live channels (6.9 manifest table).
String previewAppName(String channel) => '필기노트 미리보기 ($channel)';

/// Short web app name on non-live channels.
const String previewShortName = '노트β';

/// The outcome of [finalizeWeb].
final class FinalizeReport {
  FinalizeReport({required this.problems, required this.lines});

  /// Reasons the build is not deployable (exit code 1 when not empty).
  final List<String> problems;

  /// Informational lines (channel, manifest change, `main.dart.js` size).
  final List<String> lines;

  bool get ok => problems.isEmpty;
}

/// Finalizes the web build in [buildDir] with the build info file
/// [infoFile]. [extraRequiredFiles] are checked like
/// [requiredWebBuildFiles]. When [stepSummaryPath] is given the size report
/// is appended to it as Markdown.
FinalizeReport finalizeWeb({
  required String buildDir,
  required String infoFile,
  List<String> extraRequiredFiles = const [],
  String? stepSummaryPath,
}) {
  final problems = <String>[];
  final lines = <String>[];
  final build = Directory(buildDir);
  if (!build.existsSync()) {
    return FinalizeReport(
      problems: ['build directory $buildDir does not exist'],
      lines: lines,
    );
  }

  // 1. build info
  final info = File(infoFile);
  String? channel;
  if (!info.existsSync()) {
    problems.add('build info $infoFile does not exist');
  } else {
    final text = info.readAsStringSync();
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, Object?> ||
          json.values.any((v) => v is! String)) {
        problems.add('$infoFile is not a JSON object of strings');
      } else {
        channel = json['APP_CHANNEL'] as String?;
        if (channel == null) problems.add('$infoFile has no APP_CHANNEL');
        File(p.join(buildDir, 'build_info.json')).writeAsStringSync(text);
        lines.add('build_info.json copied (channel ${channel ?? '?'})');
      }
    } on FormatException catch (e) {
      problems.add('$infoFile is not valid JSON: ${e.message}');
    }
  }

  // 2. manifest name on non-live channels
  final manifest = File(p.join(buildDir, 'manifest.json'));
  if (channel != null && channel != 'live' && manifest.existsSync()) {
    try {
      final json = jsonDecode(manifest.readAsStringSync());
      if (json is Map<String, Object?>) {
        json['name'] = previewAppName(channel);
        json['short_name'] = previewShortName;
        manifest.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(json)}\n',
        );
        lines.add(
          'manifest.json renamed to "${previewAppName(channel)}" / '
          '"$previewShortName"',
        );
      } else {
        problems.add('manifest.json is not a JSON object');
      }
    } on FormatException catch (e) {
      problems.add('manifest.json is not valid JSON: ${e.message}');
    }
  }

  // 3. required files, no service worker
  for (final name in [...requiredWebBuildFiles, ...extraRequiredFiles]) {
    if (!File(p.join(buildDir, name)).existsSync()) {
      problems.add('missing $name');
    }
  }
  final bootstrap = File(p.join(buildDir, 'flutter_bootstrap.js'));
  if (bootstrap.existsSync() &&
      bootstrapAppScript(bootstrap.readAsStringSync())
          .contains('serviceWorkerSettings')) {
    problems.add(
      'flutter_bootstrap.js passes serviceWorkerSettings: the app must not '
      'register a service worker (6.11)',
    );
  }

  // 4. main.dart.js size
  final mainJs = File(p.join(buildDir, 'main.dart.js'));
  if (mainJs.existsSync()) {
    final bytes = mainJs.readAsBytesSync();
    final gzipped = gzip.encode(bytes).length;
    final line =
        'main.dart.js: ${formatBytes(bytes.length)} '
        '(${formatBytes(gzipped)} gzipped)';
    lines.add(line);
    if (stepSummaryPath != null) {
      File(stepSummaryPath).writeAsStringSync(
        '### Web build\n\n'
        '- channel: ${channel ?? '?'}\n'
        '- $line\n',
        mode: FileMode.append,
      );
    }
  }
  return FinalizeReport(problems: problems, lines: lines);
}

/// `2,471,812 B (2.36 MiB)`.
String formatBytes(int bytes) {
  final digits = '$bytes';
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  final mib = (bytes / (1024 * 1024)).toStringAsFixed(2);
  return '$grouped B ($mib MiB)';
}

/// The app's own part of a built `flutter_bootstrap.js`: the text after the
/// `_flutter.buildConfig = …` line that `{{flutter_build_config}}` expands
/// to. The `{{flutter_js}}` loader above it names `serviceWorkerSettings` in
/// its own `load()` signature, so only this part is checked. Without that
/// line (not a template build) the whole text.
String bootstrapAppScript(String text) {
  const marker = '_flutter.buildConfig = ';
  final at = text.lastIndexOf(marker);
  if (at < 0) return text;
  final lineEnd = text.indexOf('\n', at);
  return lineEnd < 0 ? '' : text.substring(lineEnd + 1);
}
