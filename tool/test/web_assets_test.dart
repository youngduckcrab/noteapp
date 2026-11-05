// tool/web_assets.yaml, ws web-assets verify|fetch
// (docs/plans/01-infra.md 4.3, 9.1, contract 00-overview 7.4.9).
// fetch is tested against a local HTTP server only (no network).

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../src/cli.dart';
import '../src/web_assets.dart';
import 'support/fixture_workspace.dart';

void main() {
  test('sha256 is computed in process (package:crypto)', () {
    expect(
      sha256Hex('abc'.codeUnits),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  group('parse', () {
    test('fields, line numbers and defaults', () {
      final manifest = WebAssetsManifest.parse('''
assets:
  - path: sqlite3.wasm               # relative to app/web/
    url: https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.8.0/sqlite3.wasm
    bytes: 758619
    sha256: efd308be92a34f3aa15f289a37f213b0230fd80888a1364326ee29579d892d37
    owner: CORE
    reason: drift web database
  - path: drift_worker.js
    url: https://github.com/simolus3/drift/releases/download/drift-2.35.3/drift_worker.js
    bytes: 361829
    sha256: a54b81412d4c4ab56653bb9e4c02912b0820bb37e2bba00722ddef4d78083d4a
    owner: CORE
    reason: drift web worker
''');
      expect(manifest.assets.map((a) => a.path), [
        'sqlite3.wasm',
        'drift_worker.js',
      ]);
      expect(manifest.assets.first.bytes, 758619);
      expect(manifest.assets.first.line, 2);
      expect(manifest.assets.last.line, 8);
      expect(manifest.assets.last.url.host, 'github.com');
      expect(manifest.assets.last.owner, 'CORE');
    });

    test('malformed entries are rejected', () {
      final valid =
          '    url: https://example.invalid/x\n'
          '    bytes: 1\n'
          '    sha256: ${'0' * 64}\n'
          '    owner: CORE\n'
          '    reason: r\n';
      for (final text in [
        'assets: 1',
        'nope: []',
        'assets:\n  - 1\n',
        'assets:\n  - path: x\n',
        'assets:\n  - path: /abs\n$valid',
        'assets:\n  - path: ../up\n$valid',
        'assets:\n  - path: x\n$valid  - path: x\n$valid',
        'assets:\n  - path: x\n${valid.replaceFirst('1', '-1')}',
        'assets:\n  - path: x\n${valid.replaceFirst('0' * 64, 'ABC')}',
        'assets:\n  - path: x\n${valid.replaceFirst('https://example.invalid/x', 'x')}',
        'assets: [',
      ]) {
        expect(
          () => WebAssetsManifest.parse(text),
          throwsA(isA<WebAssetsFormatException>()),
          reason: text,
        );
      }
    });

    test('loadIfExists returns null for a missing file', () {
      expect(WebAssetsManifest.loadIfExists('/nonexistent/x.yaml'), isNull);
    });
  });

  group('verify and fetch', () {
    late Directory dir;
    late HttpServer server;
    final served = <String, List<int>>{};
    final requests = <String>[];
    const good = 'sqlite wasm bytes';
    const worker = 'drift worker bytes';

    WebAssetsManifest manifest() => WebAssetsManifest.parse('''
assets:
  - path: sqlite3.wasm
    url: http://127.0.0.1:${server.port}/sqlite3.wasm
    bytes: ${good.length}
    sha256: ${sha256Hex(good.codeUnits)}
    owner: CORE
    reason: test
  - path: sub/drift_worker.js
    url: http://127.0.0.1:${server.port}/drift_worker.js
    bytes: ${worker.length}
    sha256: ${sha256Hex(worker.codeUnits)}
    owner: CORE
    reason: test
''');

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('ws_assets_');
      served
        ..clear()
        ..['/sqlite3.wasm'] = good.codeUnits
        ..['/drift_worker.js'] = worker.codeUnits;
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add(request.uri.path);
        final body = served[request.uri.path];
        if (body == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.add(body);
        }
        await request.response.close();
      });
    });
    tearDown(() async {
      await server.close(force: true);
      dir.deleteSync(recursive: true);
    });

    void write(String path, String text) => File(p.join(dir.path, path))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);

    test('verify: missing, size mismatch, sha mismatch, fine', () {
      var problems = verifyWebAssets(manifest(), dir.path);
      expect(problems.map((e) => e.message), [
        'file is missing',
        'file is missing',
      ]);
      write('sqlite3.wasm', '$good!');
      write('sub/drift_worker.js', worker.replaceFirst('d', 'D'));
      problems = verifyWebAssets(manifest(), dir.path);
      expect(problems.first.message, contains('expected ${good.length}'));
      expect(problems.last.message, contains('sha256 is'));
      write('sqlite3.wasm', good);
      write('sub/drift_worker.js', worker);
      expect(verifyWebAssets(manifest(), dir.path), isEmpty);
    });

    test('fetch writes only matching downloads, skips valid files', () async {
      served['/drift_worker.js'] = 'tampered bytes!!!!'.codeUnits;
      var results = await fetchWebAssets(manifest(), dir.path);
      expect(results.map((r) => r.outcome), [
        FetchOutcome.written,
        FetchOutcome.mismatch,
      ]);
      expect(File(p.join(dir.path, 'sqlite3.wasm')).readAsStringSync(), good);
      expect(
        File(p.join(dir.path, 'sub/drift_worker.js')).existsSync(),
        isFalse,
      );

      served['/drift_worker.js'] = worker.codeUnits;
      requests.clear();
      results = await fetchWebAssets(manifest(), dir.path);
      expect(results.map((r) => r.outcome), [
        FetchOutcome.alreadyValid,
        FetchOutcome.written,
      ]);
      expect(requests, ['/drift_worker.js']);
      expect(verifyWebAssets(manifest(), dir.path), isEmpty);
    });

    test('a failed download is reported and nothing is written', () async {
      served.remove('/sqlite3.wasm');
      final results = await fetchWebAssets(manifest(), dir.path);
      expect(results.first.outcome, FetchOutcome.downloadFailed);
      expect(results.first.isFailure, isTrue);
      expect(File(p.join(dir.path, 'sqlite3.wasm')).existsSync(), isFalse);
    });

    test('ws web-assets verify / fetch exit codes', () async {
      final fixture = FixtureWorkspace.clean();
      addTearDown(fixture.dispose);
      Future<(int, String)> ws(List<String> args) async {
        final out = StringBuffer();
        final code = await runWs(
          args,
          context: WsContext(root: fixture.root, out: out, err: StringBuffer()),
        );
        return (code, out.toString());
      }

      expect((await ws(['web-assets', 'verify'])).$1, environmentExitCode);
      final yaml = File(p.join(dir.path, 'm.yaml'))
        ..writeAsStringSync('''
assets:
  - path: sqlite3.wasm
    url: http://127.0.0.1:${server.port}/sqlite3.wasm
    bytes: ${good.length}
    sha256: ${sha256Hex(good.codeUnits)}
    owner: CORE
    reason: test
''');
      fixture.write('tool/web_assets.yaml', yaml.readAsStringSync());
      final (verifyCode, verifyOut) = await ws(['web-assets', 'verify']);
      expect(verifyCode, 1);
      expect(verifyOut, contains('app/web/sqlite3.wasm: file is missing'));
      final (fetchCode, fetchOut) = await ws(['web-assets', 'fetch']);
      expect(fetchCode, 0, reason: fetchOut);
      expect((await ws(['web-assets', 'verify'])).$1, 0);
      expect((await ws(['web-assets'])).$1, usageExitCode);
      expect((await ws(['web-assets', 'nope'])).$1, usageExitCode);
    });
  });

  group('the committed tool/web_assets.yaml', () {
    late WebAssetsManifest manifest;

    setUpAll(() {
      manifest = WebAssetsManifest.loadIfExists(
        p.join(repoRoot, webAssetsManifestPath),
      )!;
    });

    test('has exactly the two contract 7.4.9 items', () {
      expect(
        [
          for (final a in manifest.assets)
            (a.path, '${a.url}', a.bytes, a.sha256, a.owner),
        ],
        [
          (
            'sqlite3.wasm',
            'https://github.com/simolus3/sqlite3.dart/releases/download/'
                'sqlite3-3.8.0/sqlite3.wasm',
            758619,
            'efd308be92a34f3aa15f289a37f213b0230fd80888a1364326ee29579d892d37',
            'CORE',
          ),
          (
            'drift_worker.js',
            'https://github.com/simolus3/drift/releases/download/'
                'drift-2.35.3/drift_worker.js',
            361829,
            'a54b81412d4c4ab56653bb9e4c02912b0820bb37e2bba00722ddef4d78083d4a',
            'CORE',
          ),
        ],
      );
    });

    test('the committed app/web files verify (size and sha256)', () {
      expect(
        verifyWebAssets(manifest, p.join(repoRoot, 'app', 'web')),
        isEmpty,
      );
    });

    test('ws web-assets verify exits 0 on the repository', () async {
      final out = StringBuffer();
      final code = await runWs([
        'web-assets',
        'verify',
      ], context: WsContext(root: repoRoot, out: out, err: StringBuffer()));
      expect(code, 0, reason: '$out');
    });
  });
}
