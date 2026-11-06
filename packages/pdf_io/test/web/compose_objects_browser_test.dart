@TestOn('browser')
library;

// Web compose backend v2 in Chrome (m5-7/06-pdf 8.2 T23 — 6.2.5–6.2.7): the compose Worker
// (pdfrx pdfium_worker.js + web/pdf_io_compose_ext.js v2, own pdfium.wasm) runs the SAME
// object probes as the native backend (test/support/compose_probes.dart
// composeObjectProbes — T22) with the INK test font (setUpAll(useInkTestFonts): every probe
// sentence is inside its characters, C23-07), plus the worker side of v2: a pdfrx worker
// without Pdfium.addFunction → engineUnavailable, a job that loaded fonts and images is freed
// by abort / finish, RGBA is transferred and JPEG / font bytes stay usable. Uses the files
// tool/prepare_web_test.dart copied to test/web/pdfium/ (9.1).
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/compose/compose_backend_browser.dart'
    show BrowserPdfComposeBackend;
import 'package:pdf_io/testing.dart';
import 'package:web/web.dart' as web;

import '../support/compose_probes.dart';

const PdfIoConfig _config = PdfIoConfig(
  pdfiumWasmModulesUrl: 'pdfium/',
  composeExtensionUrl: 'pdfium/pdf_io_compose_ext.js',
);

const PdfComposePlan _blank = PdfComposePlan(
  sources: [],
  pages: [PdfComposeBlankPage(noteSize: ui.Size(300, 200))],
);

/// A blob: script that runs [prelude], loads the real extension, then runs [epilogue].
String _wrappedExtension(String prelude, String epilogue) {
  final real = Uri.parse(web.document.baseURI)
      .resolve(_config.composeExtensionUrl)
      .toString();
  final source = '$prelude\nimportScripts(${jsonEncode(real)});\n$epilogue';
  return web.URL.createObjectURL(
    web.Blob(
      <JSAny>[source.toJS].toJS,
      web.BlobPropertyBag(type: 'application/javascript'),
    ),
  );
}

void main() {
  final engine = PdfrxEngine.shared();

  setUpAll(() async {
    await ink.useInkTestFonts();
    engine.configure(_config);
    await engine.ensureInitialized();
  });

  group('object probes', () {
    // One worker for all probes (each worker instantiates its own pdfium.wasm).
    final backend = BrowserPdfComposeBackend(_config);
    late ComposeProbeContext ctx;

    setUp(() => ctx = ComposeProbeContext(backend: backend, engine: engine));

    tearDown(() async {
      await ctx.dispose();
      expect(backend.openJobCount, 0, reason: 'a probe left a job open');
      expect(await backend.debugWorkerJobCount(), 0);
    });

    tearDownAll(backend.dispose);

    for (final probe in composeObjectProbes()) {
      test(probe.name, () => probe.body(ctx));
    }
  });

  group('web backend v2', () {
    Future<List<PdfComposePageOps>> objectParts(
      ComposeProbeContext ctx, {
      PdfRgbaData? rgba,
      Uint8List? jpeg,
    }) => partsOf(ctx, 0, [
      imageAt(
        PdfJpegData(
          jpeg ?? PdfObjectFixtures.jpegBaseline64x48,
          width: 64,
          height: 48,
        ),
        const ui.Rect.fromLTWH(10, 10, 64, 48),
      ),
      imageAt(
        rgba ?? halfAndHalf(8, 4, left: (0, 0, 255), right: (255, 0, 0)),
        const ui.Rect.fromLTWH(100, 10, 64, 32),
      ),
      textLine(
        '안녕 hello',
        frame: const core.ElementFrame(core.PageRect(10, 80, 290, 120)),
        baselineY: 24,
      ),
    ]);

    test(
      'a pdfrx worker without Pdfium.addFunction → engineUnavailable',
      () async {
        // Hidden only while the extension loads: pdfrx's own start-up needs it afterwards.
        final url = _wrappedExtension(
          'const pdfioSaved = Pdfium.addFunction; Pdfium.addFunction = undefined;',
          'Pdfium.addFunction = pdfioSaved;',
        );
        addTearDown(() => web.URL.revokeObjectURL(url));
        final backend = BrowserPdfComposeBackend(
          PdfIoConfig(
            pdfiumWasmModulesUrl: 'pdfium/',
            composeExtensionUrl: url,
          ),
        );
        addTearDown(backend.dispose);
        await expectLater(
          backend.begin(_blank),
          throwsA(
            isA<PdfIoException>()
                .having((e) => e.code, 'code', PdfErrorCode.engineUnavailable)
                .having(
                  (e) => e.detail,
                  'detail',
                  contains('pdfio-incompatible-pdfrx'),
                ),
          ),
        );
        expect(backend.openJobCount, 0);
      },
    );

    test(
      'abort after fonts, a JPEG and a bitmap frees the worker job',
      () async {
        final backend = BrowserPdfComposeBackend(_config);
        addTearDown(backend.dispose);
        final ctx = ComposeProbeContext(backend: backend, engine: engine);
        final job = await backend.begin(_blank);
        await job.addPages(await objectParts(ctx));
        expect(await backend.debugWorkerJobCount(), 1);
        await job.abort();
        expect(await backend.debugWorkerJobCount(), 0);
        expect(backend.openJobCount, 0);
      },
    );

    test(
      'RGBA is transferred; JPEG and font bytes stay usable after sending',
      () async {
        final backend = BrowserPdfComposeBackend(_config);
        addTearDown(backend.dispose);
        final ctx = ComposeProbeContext(backend: backend, engine: engine);
        addTearDown(ctx.dispose);
        final rgba = halfAndHalf(8, 4, left: (0, 0, 255), right: (255, 0, 0));
        final jpeg = PdfObjectFixtures.jpegBaseline64x48;
        final font = await ctx.fontBytes();
        final fontLength = font.length;
        final bytes = await ctx.compose(
          _blank,
          await objectParts(ctx, rgba: rgba, jpeg: jpeg),
        );
        expect(rgba.rgba.lengthInBytes, 0, reason: 'RGBA buffer detached');
        expect(jpeg.length, greaterThan(0), reason: 'JPEG bytes kept');
        expect(font.length, fontLength, reason: 'font bytes kept');
        expect(
          (await ink.InkFonts.noteSansBytes()).length,
          fontLength,
          reason: "INK's cached font bytes are not detached",
        );
        final objects = ProbePdfObjects(bytes);
        expect(objects.images, hasLength(2));
        expect(objects.fontFiles, 1);
        final out = await ctx.open(bytes);
        expect((await out.text(0)).replaceAll(' ', ' ').trim(), '안녕 hello');
      },
    );

    test('finish after the same parts → a PDF, the worker job freed', () async {
      final backend = BrowserPdfComposeBackend(_config);
      addTearDown(backend.dispose);
      final ctx = ComposeProbeContext(backend: backend, engine: engine);
      addTearDown(ctx.dispose);
      final bytes = await ctx.compose(_blank, await objectParts(ctx));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(await backend.debugWorkerJobCount(), 0);
      expect(backend.openJobCount, 0);
    });
  });
}
