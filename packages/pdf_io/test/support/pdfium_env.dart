// Real PDFium for VM tests (06-pdf 8 T2, 9.1, 6.1 V3). VM only (dart:io): never import this
// from test/web/.
//
// V3: pdfrxFlutterInitialize() needs Pdfrx.cacheDirectoryPath set first (path_provider has no
// plugin in `flutter test`), and Pdfrx.pdfiumModulePath must point at the libpdfium.so the
// pdfium_dart build hook made ("Native assets file not found" otherwise).
import 'dart:io';

import 'package:pdfrx/pdfrx.dart' as rx;

bool _initialized = false;

/// Call from setUpAll in every test/pdfium/ test. Idempotent.
Future<void> initPdfiumForTests() async {
  if (_initialized) return;
  rx.Pdfrx.cacheDirectoryPath ??= Directory.systemTemp
      .createTempSync('pdf_io_pdfrx_')
      .path;
  rx.Pdfrx.pdfiumModulePath = findLibPdfium();
  await rx.pdfrxFlutterInitialize();
  _initialized = true;
}

/// PDFIUM_PATH, else build/native_assets/linux/libpdfium.so (package or workspace root),
/// else .dart_tool/hooks_runner/shared/pdfium_dart/build/*/linux-x64/libpdfium.so.
String findLibPdfium() {
  final fromEnv = Platform.environment['PDFIUM_PATH'];
  if (fromEnv != null && fromEnv.isNotEmpty) {
    if (File(fromEnv).existsSync()) return File(fromEnv).absolute.path;
    throw StateError('PDFIUM_PATH=$fromEnv does not exist');
  }
  final roots = <Directory>[Directory.current.absolute];
  // The workspace root holds .dart_tool/ for every member (pub workspace).
  var dir = Directory.current.absolute;
  for (var i = 0; i < 4; i++) {
    dir = dir.parent;
    roots.add(dir);
  }
  for (final root in roots) {
    final built = File('${root.path}/build/native_assets/linux/libpdfium.so');
    if (built.existsSync()) return built.path;
  }
  for (final root in roots) {
    final hooks = Directory(
      '${root.path}/.dart_tool/hooks_runner/shared/pdfium_dart/build',
    );
    if (!hooks.existsSync()) continue;
    for (final build in hooks.listSync().whereType<Directory>()) {
      final lib = File('${build.path}/linux-x64/libpdfium.so');
      if (lib.existsSync()) return lib.path;
    }
  }
  throw StateError(
    'libpdfium.so not found. Run `flutter test` once in packages/pdf_io so the '
    'pdfium_dart build hook downloads PDFium (network + gcc), or set PDFIUM_PATH.',
  );
}
