// V11 on the VM (m5-7/06-pdf 8.3 4-a; 8.2 T29 — PDF-M14): the 1차 real wiring
// (support/real_wiring.dart — openTestNoteStore, pdfIoOverrides(), INK's thumbnail renderer,
// real PDFium, the native compose backend, InkEngineVectorizer) exports a note with the four
// object kinds, an image page, a dashed stroke and tape; the scenario and its assertions are in
// support/v11_scenario.dart (the Chrome run, web/export_objects_v11_browser_test.dart, is the
// same). Integration stage only (`ws test --run-skipped -t integration --package pdf_io`).
@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/testing_vm.dart' as core_vm;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/compose/compose_backend_native.dart'
    show debugNativeComposeJobCount;

import '../support/compose_probes.dart';
import '../support/export_world.dart' show captureFlutterErrors;
import '../support/pdfium_env.dart';
import '../support/real_wiring.dart';
import '../support/v11_scenario.dart';

Future<Uint8List> _inflate(Uint8List data) async =>
    Uint8List.fromList(zlib.decode(data));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RealWiring app;
  late ComposeProbeContext out;
  late List<FlutterErrorDetails> reports;

  setUpAll(() async {
    await initPdfiumForTests();
    await PdfrxEngine.shared().ensureInitialized();
  });

  setUp(() async {
    reports = captureFlutterErrors();
    app = RealWiring(await core_vm.openTestNoteStore());
    out = ComposeProbeContext(
      backend: app.read(pdfComposeBackendProvider),
      engine: PdfrxEngine.shared(),
    );
  });

  tearDown(() async {
    await out.dispose();
    await app.close();
    expect(await debugNativeComposeJobCount(), 0);
    expect(reports, isEmpty, reason: 'no reported PDF errors');
  });

  test(
    'V11: objects, image page, dashed stroke and tape → text, image objects, '
    'one formula raster, dash pieces and one cover in the PDF',
    () => runV11Scenario(app, out: out, inflate: _inflate),
  );
}
