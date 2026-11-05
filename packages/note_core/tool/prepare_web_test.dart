// tool/prepare_web_test.dart — CORE T16 (docs/plans/02-core.md 9.1, contract
// 00-overview 7.4.8): puts the two web assets the browser tests load next to them
// in test/web/ (both are in the package .gitignore):
//
//   drift_worker.js  copied from the resolved drift package (pub cache)
//   sqlite3.wasm     the sqlite3 3.8.0 release asset, sha256-checked
//
// sqlite3.wasm is cached in .dart_tool/note_core_web_test/ and never downloaded
// twice. Before downloading, the copy shipped in the drift package (its devtools
// extension carries the same release file) is used when its sha256 matches. The
// tests themselves never use the network.
//
// Run from packages/note_core: dart run tool/prepare_web_test.dart
// (`dart run tool/ws.dart test --platform chrome` runs it first).
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

const _sqliteUrl =
    'https://github.com/simolus3/sqlite3.dart/releases/download/'
    'sqlite3-3.8.0/sqlite3.wasm';
const _sqliteSha256 =
    'efd308be92a34f3aa15f289a37f213b0230fd80888a1364326ee29579d892d37';
const _workerSha256 =
    'a54b81412d4c4ab56653bb9e4c02912b0820bb37e2bba00722ddef4d78083d4a';

Future<void> main() async {
  final package = _packageDir();
  final webDir = Directory('${package.path}/test/web');
  final cacheDir = Directory('${package.path}/.dart_tool/note_core_web_test');
  await cacheDir.create(recursive: true);

  final drift = await _driftPackageDir();

  // drift_worker.js — the file of the drift version this workspace resolves.
  final worker = File('${drift.path}/drift_worker.js');
  if (!worker.existsSync()) {
    _fail('drift_worker.js not found in ${drift.path}');
  }
  _check(await worker.readAsBytes(), _workerSha256, worker.path);
  await _install(worker, File('${webDir.path}/drift_worker.js'));

  // sqlite3.wasm — cache, then the drift package copy, then the release URL.
  final cached = File('${cacheDir.path}/sqlite3-3.8.0.wasm');
  if (!(cached.existsSync() && _matches(cached, _sqliteSha256))) {
    final bundled = File('${drift.path}/extension/devtools/build/sqlite3.wasm');
    if (bundled.existsSync() && _matches(bundled, _sqliteSha256)) {
      await bundled.copy(cached.path);
      stdout.writeln('sqlite3.wasm: taken from ${bundled.path}');
    } else {
      final bytes = await _download(Uri.parse(_sqliteUrl));
      _check(bytes, _sqliteSha256, _sqliteUrl);
      await cached.writeAsBytes(bytes, flush: true);
      stdout.writeln('sqlite3.wasm: downloaded from $_sqliteUrl');
    }
  }
  await _install(cached, File('${webDir.path}/sqlite3.wasm'));
  stdout.writeln('test/web: drift_worker.js and sqlite3.wasm are ready');
}

/// packages/note_core: the parent of this script's tool/ directory, else the
/// working directory.
Directory _packageDir() {
  if (Platform.script.isScheme('file')) {
    final dir = File.fromUri(Platform.script).parent.parent;
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/test/web').existsSync()) {
      return dir;
    }
  }
  return Directory.current;
}

Future<Directory> _driftPackageDir() async {
  final lib = await Isolate.resolvePackageUri(
    Uri.parse('package:drift/drift.dart'),
  );
  if (lib == null || !lib.isScheme('file')) {
    _fail('package:drift could not be resolved (run `flutter pub get`)');
  }
  return File.fromUri(lib).parent.parent;
}

bool _matches(File file, String sha256Hex) =>
    sha256.convert(file.readAsBytesSync()).toString() == sha256Hex;

void _check(List<int> bytes, String sha256Hex, String source) {
  final actual = sha256.convert(bytes).toString();
  if (actual != sha256Hex) {
    _fail('sha256 of $source is $actual, expected $sha256Hex');
  }
}

/// Copies [from] to [to] unless [to] already has the same bytes.
Future<void> _install(File from, File to) async {
  if (to.existsSync() && to.lengthSync() == from.lengthSync()) {
    final a = sha256.convert(await from.readAsBytes());
    final b = sha256.convert(await to.readAsBytes());
    if (a == b) return;
  }
  await from.copy(to.path);
}

Future<List<int>> _download(Uri url) async {
  final client = HttpClient()
    ..findProxy = HttpClient.findProxyFromEnvironment
    ..connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.getUrl(url);
    final response = await request.close().timeout(const Duration(minutes: 2));
    if (response.statusCode != HttpStatus.ok) {
      _fail('GET $url: HTTP ${response.statusCode}');
    }
    final bytes = <int>[];
    await response.timeout(const Duration(minutes: 2)).forEach(bytes.addAll);
    return bytes;
  } finally {
    client.close(force: true);
  }
}

Never _fail(String message) {
  stderr.writeln('prepare_web_test: $message');
  exit(1);
}
