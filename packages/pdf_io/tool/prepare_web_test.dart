// Copies the pdfrx wasm assets and pdf_io's compose extension into test/web/pdfium/ for
// `flutter test --platform chrome test/web` (06-pdf 9.1, PDF-M2, V11). No network: the files
// come from the pub cache. `dart run tool/ws.dart test --platform chrome` runs this first.
//
//   cd packages/pdf_io && dart run tool/prepare_web_test.dart
//
// Fails when the pdfrx pdfium.wasm is not the build the compose extension was checked
// against (V17: pdfium-binaries chromium/7811) — a pdfrx upgrade must re-run T14's probes.
// Files already up to date are skipped.
//
// (2차, m5-7/06-pdf 3.1 — C2-39, 02-core 6.18.1) Then runs CORE's
// `tool/prepare_web_test.dart --out test/web`, which puts drift_worker.js and sqlite3.wasm next
// to the browser tests, so test/web can open the real web store (package:note_core/
// testing_web.dart openWebTestNoteStore — V11 Chrome). Both files are in .gitignore.
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// V17: SHA-256 of pdfrx 2.11.0 assets/pdfium.wasm (= chromium/7811 lib/pdfium.wasm).
const String expectedWasmSha256 =
    '5b2cbb18e9dc361dae375e971c7e75f7306d39b7749ad4fced475579e6a549df';

const List<String> pdfrxAssets = [
  'pdfium.wasm',
  'pdfium_worker.js',
  'pdfium_client.js',
];

Future<void> main(List<String> args) async {
  final packageRoot = _packageRoot();
  final pdfrxLib = await Isolate.resolvePackageUri(Uri.parse('package:pdfrx/'));
  if (pdfrxLib == null) {
    _fail('package:pdfrx is not resolvable — run `flutter pub get` first.');
  }
  // package:pdfrx/ → <pdfrx>/lib/; the assets live in <pdfrx>/assets/.
  final pdfrxRoot = Directory.fromUri(pdfrxLib).parent;
  final sources = <String, File>{
    for (final name in pdfrxAssets)
      name: File('${pdfrxRoot.path}/assets/$name'),
    'pdf_io_compose_ext.js': File(
      '${packageRoot.path}/web/pdf_io_compose_ext.js',
    ),
  };
  for (final entry in sources.entries) {
    if (!entry.value.existsSync()) _fail('missing ${entry.value.path}');
  }

  final wasmSha = _sha256(sources['pdfium.wasm']!);
  if (wasmSha != expectedWasmSha256) {
    _fail(
      'pdfrx pdfium.wasm sha256 is $wasmSha, expected $expectedWasmSha256 '
      '(chromium/7811, V17). The pdfrx version changed: re-check the compose '
      'extension (06-pdf T14) before updating expectedWasmSha256.',
    );
  }

  final out = Directory('${packageRoot.path}/test/web/pdfium')
    ..createSync(recursive: true);
  var copied = 0;
  for (final entry in sources.entries) {
    final target = File('${out.path}/${entry.key}');
    final sourceSha = _sha256(entry.value);
    if (target.existsSync() && _sha256(target) == sourceSha) continue;
    entry.value.copySync(target.path);
    if (_sha256(target) != sourceSha) _fail('copy of ${entry.key} differs');
    copied++;
  }
  stdout.writeln(
    'prepare_web_test: ${sources.length} files in ${out.path} '
    '($copied copied, ${sources.length - copied} up to date)',
  );

  await runCoreWebTestPrepare(packageRoot);
}

/// Runs note_core's tool/prepare_web_test.dart with `--out test/web` from [packageRoot]
/// (C2-39): drift_worker.js and sqlite3.wasm for openWebTestNoteStore. Fails when it fails.
Future<void> runCoreWebTestPrepare(Directory packageRoot) async {
  final coreLib = await Isolate.resolvePackageUri(
    Uri.parse('package:note_core/'),
  );
  if (coreLib == null) {
    _fail('package:note_core is not resolvable — run `flutter pub get` first.');
  }
  // package:note_core/ → <note_core>/lib/; the script is <note_core>/tool/.
  final script = File(
    '${Directory.fromUri(coreLib).parent.path}/tool/prepare_web_test.dart',
  );
  if (!script.existsSync()) _fail('missing ${script.path}');
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['run', script.path, '--out', 'test/web'],
    workingDirectory: packageRoot.path,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) _fail('${script.path} --out test/web exited with $code');
}

/// packages/pdf_io, whether the script runs from there or from the workspace root.
Directory _packageRoot() {
  final script = File.fromUri(Platform.script);
  if (script.existsSync()) return script.parent.parent.absolute;
  for (final candidate in [Directory.current, Directory('packages/pdf_io')]) {
    if (File('${candidate.path}/tool/prepare_web_test.dart').existsSync()) {
      return candidate.absolute;
    }
  }
  _fail('run from packages/pdf_io');
}

String _sha256(File file) => sha256.convert(file.readAsBytesSync()).toString();

Never _fail(String message) {
  stderr.writeln('prepare_web_test: $message');
  exit(1);
}
