// finalizeWeb / ws finalize-web (docs/plans/01-infra.md 4.2, 6.11, 9.1).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../src/cli.dart';
import '../src/web_finalize.dart';
import 'support/fixture_workspace.dart';

void main() {
  late Directory dir;
  late String build;
  late String info;

  void write(String path, String text) => File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  Map<String, Object?> readJson(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

  void writeInfo(String channel) => write(
    info,
    jsonEncode({
      'APP_VERSION': '0.1.0',
      'APP_BUILD_NUMBER': '42',
      'APP_GIT_SHA': 'local',
      'APP_GIT_REF': 'main',
      'APP_CHANNEL': channel,
      'APP_BUILD_TIME': '2026-11-04T09:10:00Z',
    }),
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ws_finalize_');
    build = p.join(dir.path, 'app', 'build', 'web');
    info = p.join(dir.path, 'build', 'build_info.json');
    for (final name in [
      'index.html',
      'flutter.js',
      'favicon.png',
      'sqlite3.wasm',
    ]) {
      write(p.join(build, name), name);
    }
    write(
      p.join(build, 'flutter_bootstrap.js'),
      '/* custom */ _flutter.loader.load({config});',
    );
    write(p.join(build, 'main.dart.js'), 'x' * 2048);
    write(
      p.join(build, 'manifest.json'),
      jsonEncode({
        'name': '필기노트 (테스트)',
        'short_name': '필기노트',
        'start_url': '/',
      }),
    );
    writeInfo('live');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('live: copies the info, keeps the manifest, reports the size', () {
    final summary = p.join(dir.path, 'summary.md');
    final report = finalizeWeb(
      buildDir: build,
      infoFile: info,
      stepSummaryPath: summary,
    );
    expect(report.problems, isEmpty);
    expect(
      File(p.join(build, 'build_info.json')).readAsStringSync(),
      File(info).readAsStringSync(),
    );
    expect(readJson(p.join(build, 'manifest.json'))['name'], '필기노트 (테스트)');
    final sizeLine = report.lines.singleWhere(
      (l) => l.startsWith('main.dart.js: '),
    );
    expect(sizeLine, contains('2,048 B (0.00 MiB)'));
    expect(sizeLine, contains('gzipped'));
    expect(File(summary).readAsStringSync(), contains(sizeLine));
  });

  test('preview: renames the web app in manifest.json', () {
    writeInfo('preview');
    final report = finalizeWeb(buildDir: build, infoFile: info);
    expect(report.ok, isTrue);
    final manifest = readJson(p.join(build, 'manifest.json'));
    expect(manifest['name'], '필기노트 미리보기 (preview)');
    expect(manifest['short_name'], '노트β');
    expect(manifest['start_url'], '/');
  });

  test('missing required files and assets fail', () {
    File(p.join(build, 'flutter.js')).deleteSync();
    final report = finalizeWeb(
      buildDir: build,
      infoFile: info,
      extraRequiredFiles: const ['sqlite3.wasm', 'drift_worker.js'],
    );
    expect(report.problems, ['missing flutter.js', 'missing drift_worker.js']);
  });

  test('a service worker in flutter_bootstrap.js fails', () {
    write(
      p.join(build, 'flutter_bootstrap.js'),
      '_flutter.loader.load({serviceWorkerSettings: {serviceWorkerVersion: '
      '"1"}});',
    );
    final report = finalizeWeb(buildDir: build, infoFile: info);
    expect(report.problems.single, contains('serviceWorkerSettings'));
  });

  test('missing or broken build info fails', () {
    File(info).deleteSync();
    expect(
      finalizeWeb(buildDir: build, infoFile: info).problems,
      contains(contains('does not exist')),
    );
    write(info, '{"APP_CHANNEL": 1}');
    expect(
      finalizeWeb(buildDir: build, infoFile: info).problems.first,
      contains('JSON object of strings'),
    );
    write(info, 'not json');
    expect(
      finalizeWeb(buildDir: build, infoFile: info).problems.first,
      contains('not valid JSON'),
    );
  });

  test('formatBytes groups digits', () {
    expect(formatBytes(2471812), '2,471,812 B (2.36 MiB)');
    expect(formatBytes(999), '999 B (0.00 MiB)');
  });

  test('ws finalize-web exits 1 on problems and 0 when fine', () async {
    Future<(int, String)> run(Map<String, String> env) async {
      final out = StringBuffer();
      final code = await runWs(
        ['finalize-web', '--build-dir', 'app/build/web', '--info', info],
        context: WsContext(
          root: repoRoot,
          out: out,
          err: StringBuffer(),
          environment: env,
          workingDirectory: dir.path,
        ),
      );
      return (code, out.toString());
    }

    // The real repo may list web assets (I12); provide them.
    final summary = p.join(dir.path, 'step_summary.md');
    write(p.join(build, 'drift_worker.js'), '');
    final (code, out) = await run({'GITHUB_STEP_SUMMARY': summary});
    expect(code, 0, reason: out);
    expect(out, contains('ws finalize-web: ok'));
    expect(File(summary).readAsStringSync(), contains('main.dart.js'));

    File(p.join(build, 'index.html')).deleteSync();
    final (failed, failedOut) = await run({});
    expect(failed, 1);
    expect(failedOut, contains('finalize-web: missing index.html'));
  });
}
