// Copies the committed web assets next to the Chrome tests
// (docs/plans/01-infra.md 3.4, 4.2 `ws test --platform chrome` step 1):
// web/sqlite3.wasm and web/drift_worker.js → test/web/, so that the V6 smoke
// (app_smoke_browser_test.dart) can open CORE's web storage from the test
// page. The copies are git-ignored (app/.gitignore).
//
// Usage (from app/): dart run tool/prepare_web_test.dart
import 'dart:io';

/// Files copied from `web/` to `test/web/` (tool/web_assets.yaml).
const List<String> webTestAssets = ['sqlite3.wasm', 'drift_worker.js'];

/// Copies [webTestAssets] from `<appDir>/web/` to `<appDir>/test/web/`.
/// Returns the copied target paths. Throws [FileSystemException] when a
/// source is missing (run `dart run tool/ws.dart web-assets fetch` from the
/// workspace root).
List<String> prepareWebTest(String appDir) {
  final target = Directory('$appDir/test/web')..createSync(recursive: true);
  return [
    for (final name in webTestAssets)
      File('$appDir/web/$name').copySync('${target.path}/$name').path,
  ];
}

void main(List<String> args) {
  try {
    for (final path in prepareWebTest(Directory.current.path)) {
      stdout.writeln('prepare_web_test: copied $path');
    }
  } on FileSystemException catch (e) {
    stderr.writeln('prepare_web_test: ${e.message} (${e.path})');
    exitCode = 1;
  }
}
