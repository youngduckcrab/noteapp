@Tags(['integration'])
@TestOn('browser')
library;

// V11 in Chrome (m5-7/06-pdf 8.3 4-b; 8.2 T29 — PDF-M12, PDF-M14): the same scenario as the VM
// run (test/support/v11_scenario.dart) on CORE's REAL web store (note_core/testing_web.dart
// openWebTestNoteStore — IndexedDB + the drift web worker; tool/prepare_web_test.dart puts
// sqlite3.wasm and drift_worker.js next to the test page), the real INK and the compose Worker
// (pdfium.wasm + pdf_io_compose_ext.js from test/web/pdfium/). setUpAll(useInkTestFonts): the text
// box sentence is inside the test font's characters (C23-07). Content streams are inflated by
// the browser (DecompressionStream). Integration stage only (`ws test --run-skipped -t
// integration --platform chrome --package pdf_io`); until CORE T26/T27 and INK T42 the scenario
// skips itself at run time. The store has a unique name and is deleted at the start and the end.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/testing.dart' as ink;
import 'package:note_core/testing_web.dart' as core_web;
import 'package:pdf_io/pdf_io.dart';
import 'package:web/web.dart' as web;

import '../support/compose_probes.dart';
import '../support/real_wiring.dart';
import '../support/v11_scenario.dart';

const PdfIoConfig _config = PdfIoConfig(
  warmUpOnStart: false,
  pdfiumWasmModulesUrl: 'pdfium/',
  composeExtensionUrl: 'pdfium/pdf_io_compose_ext.js',
);

/// zlib data → bytes, by the browser's DecompressionStream('deflate') (RFC 1950).
Future<Uint8List> _inflate(Uint8List data) async {
  final inflater = web.DecompressionStream('deflate');
  final stream = web.Blob(<JSAny>[data.toJS].toJS).stream().pipeThrough(
    web.ReadableWritablePair(
      readable: inflater.readable,
      writable: inflater.writable,
    ),
  );
  final buffer = await web.Response(stream).arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

void main() {
  final name = 'pdf_v11_${DateTime.now().microsecondsSinceEpoch}';
  late RealWiring app;
  late ComposeProbeContext out;

  setUpAll(() async {
    await ink.useInkTestFonts();
    PdfrxEngine.shared().configure(_config);
    await PdfrxEngine.shared().ensureInitialized();
    await core_web.deleteWebTestNoteStore(name);
  });

  setUp(() async {
    app = RealWiring(
      await core_web.openWebTestNoteStore(name),
      config: _config,
    );
    out = ComposeProbeContext(
      backend: app.read(pdfComposeBackendProvider),
      engine: PdfrxEngine.shared(),
    );
  });

  tearDown(() async {
    await out.dispose();
    await app.close();
    await core_web.deleteWebTestNoteStore(name);
  });

  test(
    'V11 (Chrome, real web store): objects, image page, dashed stroke and tape → '
    'text, image objects, one formula raster, dash pieces and one cover',
    () => runV11Scenario(app, out: out, inflate: _inflate),
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('the browser inflater reads what PDFium deflated', () async {
    // zlib of 'q 0 0 m 1 1 l S Q' (level 9) — the inflater the scenario uses.
    final zlib = Uint8List.fromList(const [
      120, 218, 43, 84, 48, 0, 194, 92, 5, 67, 32, 204, 81, 8, 86, 8, 4, 0, //
      32, 247, 3, 177,
    ]);
    expect(String.fromCharCodes(await _inflate(zlib)), 'q 0 0 m 1 1 l S Q');
  });
}
