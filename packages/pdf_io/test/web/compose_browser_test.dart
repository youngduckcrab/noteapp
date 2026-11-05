@TestOn('browser')
library;

// Web compose backend in Chrome (06-pdf 6.11.6, 8 T14): the compose Worker (pdfrx
// pdfium_worker.js + web/pdf_io_compose_ext.js, own pdfium.wasm 7811) runs the SAME probes
// as the native backend (test/support/compose_probes.dart, VM PDFium 8125) and the output
// is checked by reopening it with pdfrx wasm. Plus the worker bookkeeping: an incompatible
// or missing extension → engineUnavailable, abort frees the job, an abort without answer
// stops the worker, the idle shutdown (short timeout instead of fake time — the Worker is
// real). Uses the files tool/prepare_web_test.dart copied to test/web/pdfium/ (9.1).
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
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
  pages: [PdfComposeBlankPage(noteSize: ui.Size(200, 100))],
);

Matcher _code(PdfErrorCode code) =>
    isA<PdfIoException>().having((e) => e.code, 'code', code);

/// A blob: script that runs [prelude], loads the real extension, then runs [epilogue].
String _wrappedExtension({String prelude = '', String epilogue = ''}) {
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

/// Polls [done] (no timing assertion: the bound only stops a broken test).
Future<void> _eventually(bool Function() done) async {
  for (var i = 0; i < 600 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  final engine = PdfrxEngine.shared();

  setUpAll(() async {
    engine.configure(_config);
    await engine.ensureInitialized();
  });

  group('probes', () {
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

    for (final probe in composeProbes()) {
      test(probe.name, () => probe.body(ctx));
    }
  });

  group('web backend', () {
    test('createPlatformComposeBackend gives the Worker backend', () async {
      final backend = createPlatformComposeBackend(_config);
      expect(backend, isA<BrowserPdfComposeBackend>());
      expect(backend.isSupported, isTrue);
      expect((backend as BrowserPdfComposeBackend).hasWorker, isFalse);
      await backend.dispose();
    });

    test('abort frees the worker job; dispose stops the worker', () async {
      final backend = BrowserPdfComposeBackend(_config);
      final job = await backend.begin(_blank);
      await job.addPages([
        markerOps(0, const [ui.Rect.fromLTWH(10, 10, 20, 20)]),
      ]);
      expect(await backend.debugWorkerJobCount(), 1);
      expect(backend.openJobCount, 1);
      await job.abort();
      expect(await backend.debugWorkerJobCount(), 0);
      expect(backend.openJobCount, 0);
      final open = await backend.begin(_blank);
      expect(await backend.debugWorkerJobCount(), 1);
      await backend.dispose();
      expect(backend.hasWorker, isFalse);
      expect(() => open.addPages(const []), throwsStateError);
      expect(() => backend.begin(_blank), throwsStateError);
    });

    test('incompatible pdfrx worker → engineUnavailable', () async {
      // encodePdf missing: the extension's compatibility check fails.
      final url = _wrappedExtension(prelude: 'encodePdf = undefined;');
      addTearDown(() => web.URL.revokeObjectURL(url));
      final backend = BrowserPdfComposeBackend(
        PdfIoConfig(pdfiumWasmModulesUrl: 'pdfium/', composeExtensionUrl: url),
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
    });

    test('missing extension script → engineUnavailable', () async {
      final backend = BrowserPdfComposeBackend(
        const PdfIoConfig(
          pdfiumWasmModulesUrl: 'pdfium/',
          composeExtensionUrl: 'pdfium/no_such_extension.js',
        ),
      );
      addTearDown(backend.dispose);
      await expectLater(
        backend.begin(_blank),
        throwsA(_code(PdfErrorCode.engineUnavailable)),
      );
    });

    test('an abort without answer stops the worker; the next begin starts a new one', () async {
      // The abort command busy-waits 3 s; the backend gives up after 100 ms.
      final url = _wrappedExtension(
        epilogue:
            'functions.pdfioComposeAbort = function () {'
            ' const end = Date.now() + 3000; while (Date.now() < end) {} return {}; };',
      );
      addTearDown(() => web.URL.revokeObjectURL(url));
      final backend = BrowserPdfComposeBackend(
        PdfIoConfig(pdfiumWasmModulesUrl: 'pdfium/', composeExtensionUrl: url),
        abortTimeout: const Duration(milliseconds: 100),
      );
      addTearDown(backend.dispose);
      final job = await backend.begin(_blank);
      expect(backend.hasWorker, isTrue);
      await job.abort();
      expect(backend.hasWorker, isFalse);
      expect(backend.openJobCount, 0);
      final again = await backend.begin(_blank);
      expect(backend.hasWorker, isTrue);
      final bytes = await again.finish();
      expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
    });

    test(
      'idle shutdown after the last job; begin starts a new worker',
      () async {
        final backend = BrowserPdfComposeBackend(
          _config,
          idleTimeout: const Duration(milliseconds: 200),
        );
        addTearDown(backend.dispose);
        final first = await backend.begin(_blank);
        expect(backend.hasWorker, isTrue);
        await first.finish();
        await _eventually(() => !backend.hasWorker);
        expect(backend.hasWorker, isFalse);
        final second = await backend.begin(_blank);
        expect(backend.hasWorker, isTrue);
        // An open job keeps the worker.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(backend.hasWorker, isTrue);
        final bytes = await second.finish();
        expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
      },
    );

    test(
      'source bytes stay usable after begin (no transfer of caller data)',
      () async {
        final backend = BrowserPdfComposeBackend(_config);
        addTearDown(backend.dispose);
        final bytes = onePage(const PdfFixturePage(width: 100, height: 100));
        final length = bytes.length;
        final job = await backend.begin(
          PdfComposePlan(
            sources: [sourceOf(bytes)],
            pages: [sourcePage(0, 0, const ui.Size(100, 100))],
          ),
        );
        expect(bytes.length, length);
        await job.abort();
      },
    );
  });
}
