// Native compose backend on real PDFium (06-pdf 6.11.3–6.11.7, 8 T13): the shared probes
// of test/support/compose_probes.dart (the web backend runs the same list in T14), plus
// the native job bookkeeping — the worker isolate's job map is empty after finish, abort,
// a failed begin and dispose.
@Tags(['pdfium'])
@TestOn('vm')
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/compose/compose_backend_native.dart'
    show NativePdfComposeBackend, debugNativeComposeJobCount;

import '../support/compose_probes.dart';
import '../support/pdfium_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initPdfiumForTests);

  final engine = PdfrxEngine.shared();

  group('probes', () {
    late NativePdfComposeBackend backend;
    late ComposeProbeContext ctx;

    setUp(() {
      backend = NativePdfComposeBackend();
      ctx = ComposeProbeContext(backend: backend, engine: engine);
    });

    tearDown(() async {
      await ctx.dispose();
      expect(backend.openJobCount, 0, reason: 'a probe left a job open');
      await backend.dispose();
      expect(await debugNativeComposeJobCount(), 0);
    });

    for (final probe in composeProbes()) {
      test(probe.name, () => probe.body(ctx));
    }
  });

  group('native backend', () {
    const blank = PdfComposePlan(
      sources: [],
      pages: [PdfComposeBlankPage(noteSize: ui.Size(200, 100))],
    );

    test('createPlatformComposeBackend gives the FFI backend', () async {
      final backend = createPlatformComposeBackend(const PdfIoConfig());
      expect(backend, isA<NativePdfComposeBackend>());
      expect(backend.isSupported, isTrue);
      await backend.dispose();
    });

    test('abort frees the worker job (job map empty)', () async {
      final backend = NativePdfComposeBackend();
      final job = await backend.begin(blank);
      await job.addPages([
        markerOps(0, const [ui.Rect.fromLTWH(10, 10, 20, 20)]),
      ]);
      expect(await debugNativeComposeJobCount(), 1);
      expect(backend.openJobCount, 1);
      await job.abort();
      expect(await debugNativeComposeJobCount(), 0);
      expect(backend.openJobCount, 0);
      await backend.dispose();
    });

    test('finish frees the worker job', () async {
      final backend = NativePdfComposeBackend();
      final job = await backend.begin(blank);
      final bytes = await job.finish();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(await debugNativeComposeJobCount(), 0);
      expect(backend.openJobCount, 0);
      await backend.dispose();
    });

    test('a failed begin leaves no job behind', () async {
      final backend = NativePdfComposeBackend();
      await expectLater(
        backend.begin(
          PdfComposePlan(
            sources: [
              PdfComposeSource(
                assetId: 'bad',
                bytes: Uint8List.fromList(List.filled(64, 0x41)),
              ),
            ],
            pages: const [
              PdfComposeSourcePage(
                sourceIndex: 0,
                pdfPageIndex: 0,
                noteSize: ui.Size(100, 100),
              ),
            ],
          ),
        ),
        throwsA(
          isA<PdfIoException>().having(
            (e) => e.code,
            'code',
            PdfErrorCode.exportFailed,
          ),
        ),
      );
      expect(await debugNativeComposeJobCount(), 0);
      await backend.dispose();
    });

    test('a failed addPages keeps the job until abort', () async {
      final backend = NativePdfComposeBackend();
      final job = await backend.begin(blank);
      final bad = PdfComposePageOps(
        outputIndex: 0,
        verbs: Uint8List.fromList(const [1, 7]), // lineTo before moveTo
        coords: Float32List.fromList(const [1, 1, 0]),
        paints: Float32List(10),
      );
      await expectLater(
        job.addPages([bad]),
        throwsA(
          isA<PdfIoException>().having(
            (e) => e.code,
            'code',
            PdfErrorCode.exportFailed,
          ),
        ),
      );
      expect(await debugNativeComposeJobCount(), 1);
      await job.abort();
      expect(await debugNativeComposeJobCount(), 0);
      await backend.dispose();
    });

    test(
      'dispose aborts open jobs; begin afterwards is a StateError',
      () async {
        final backend = NativePdfComposeBackend();
        await backend.begin(blank);
        await backend.begin(blank);
        expect(await debugNativeComposeJobCount(), 2);
        await backend.dispose();
        expect(await debugNativeComposeJobCount(), 0);
        expect(() => backend.begin(blank), throwsStateError);
      },
    );

    test('plan errors are ArgumentErrors before the worker', () async {
      final backend = NativePdfComposeBackend();
      expect(
        () => backend.begin(const PdfComposePlan(sources: [], pages: [])),
        throwsArgumentError,
      );
      expect(
        () => backend.begin(
          const PdfComposePlan(
            sources: [],
            pages: [
              PdfComposeSourcePage(
                sourceIndex: 0,
                pdfPageIndex: 0,
                noteSize: ui.Size(100, 100),
              ),
            ],
          ),
        ),
        throwsArgumentError,
      );
      final job = await backend.begin(blank);
      expect(
        () => job.addPages([
          markerOps(1, const [ui.Rect.fromLTWH(0, 0, 1, 1)]),
        ]),
        throwsArgumentError,
      );
      await job.abort();
      await backend.dispose();
    });

    test('engine start failure → engineUnavailable', () async {
      final backend = NativePdfComposeBackend(
        ensureEngine: () async => throw StateError('no wasm'),
      );
      await expectLater(
        backend.begin(blank),
        throwsA(
          isA<PdfIoException>().having(
            (e) => e.code,
            'code',
            PdfErrorCode.engineUnavailable,
          ),
        ),
      );
      await backend.dispose();
    });
  });
}
