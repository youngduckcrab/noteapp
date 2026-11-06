// tool/prepare_web_test.dart — media_io (m5-7/06-pdf 3.3, T30 — C2-39, 02-core 6.18.1).
//
// Runs CORE's `tool/prepare_web_test.dart --out test/web` from this package, which puts
// drift_worker.js and sqlite3.wasm next to the browser tests: test/web and test/media open the
// REAL web store with package:note_core/testing_web.dart openWebTestNoteStore (V16, V8). Both
// files are in .gitignore. `dart run tool/ws.dart test --platform chrome` runs this first.
//
//   cd packages/media_io && dart run tool/prepare_web_test.dart
import 'dart:io';
import 'dart:isolate';

Future<void> main(List<String> args) async {
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
    workingDirectory: _packageRoot().path,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) _fail('${script.path} --out test/web exited with $code');
}

/// packages/media_io, whether the script runs from there or from the workspace root.
Directory _packageRoot() {
  final script = File.fromUri(Platform.script);
  if (script.existsSync()) return script.parent.parent.absolute;
  for (final candidate in [Directory.current, Directory('packages/media_io')]) {
    if (File('${candidate.path}/tool/prepare_web_test.dart').existsSync()) {
      return candidate.absolute;
    }
  }
  _fail('run from packages/media_io');
}

Never _fail(String message) {
  stderr.writeln('prepare_web_test: $message');
  exit(1);
}
