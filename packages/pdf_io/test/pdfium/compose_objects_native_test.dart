// Native compose backend v2 on real PDFium (m5-7/06-pdf 8.2 T22 — 6.1 E1–E4, 6.2.5, 6.2.6,
// 6.2.8): the shared object probes of test/support/compose_probes.dart (Chrome runs the same
// list in web/compose_objects_browser_test — T23) with the real NoteSans of ink_engine
// (rootBundle on the VM), plus the native bookkeeping: a job that loaded fonts and images
// frees everything on abort / finish (the worker's job map is empty).
@Tags(['pdfium'])
@TestOn('vm')
library;

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/compose/compose_backend_native.dart'
    show NativePdfComposeBackend, debugNativeComposeJobCount;
import 'package:pdf_io/testing.dart';

import '../support/compose_probes.dart';
import '../support/pdfium_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initPdfiumForTests);

  final engine = PdfrxEngine.shared();

  test('the VM probes embed the real NoteSans (two different files)', () async {
    final regular = await ink.InkFonts.noteSansBytes();
    final bold = await ink.InkFonts.noteSansBytes(bold: true);
    expect(regular.length, greaterThan(400000));
    expect(bold.length, greaterThan(400000));
    expect(regular.length, isNot(bold.length));
  });

  group('object probes', () {
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

    for (final probe in composeObjectProbes()) {
      test(probe.name, () => probe.body(ctx));
    }
  });

  group('native bookkeeping with objects', () {
    const plan = PdfComposePlan(
      sources: [],
      pages: [PdfComposeBlankPage(noteSize: ui.Size(300, 200))],
    );

    Future<List<PdfComposePageOps>> objectParts(ComposeProbeContext ctx) =>
        partsOf(ctx, 0, [
          imageAt(
            PdfJpegData(
              PdfObjectFixtures.jpegBaseline64x48,
              width: 64,
              height: 48,
            ),
            const ui.Rect.fromLTWH(10, 10, 64, 48),
          ),
          imageAt(
            halfAndHalf(8, 4, left: (0, 0, 255), right: (255, 0, 0)),
            const ui.Rect.fromLTWH(100, 10, 64, 32),
          ),
          textLine(
            '안녕 hello',
            frame: const core.ElementFrame(core.PageRect(10, 80, 290, 120)),
            baselineY: 24,
          ),
          textLine(
            '안녕',
            frame: const core.ElementFrame(core.PageRect(10, 130, 290, 170)),
            baselineY: 24,
            bold: true,
          ),
        ]);

    test(
      'abort after fonts, a JPEG and a bitmap → fonts and document freed',
      () async {
        final backend = NativePdfComposeBackend();
        final ctx = ComposeProbeContext(backend: backend, engine: engine);
        final job = await backend.begin(plan);
        await job.addPages(await objectParts(ctx));
        expect(await debugNativeComposeJobCount(), 1);
        await job.abort();
        expect(await debugNativeComposeJobCount(), 0);
        expect(backend.openJobCount, 0);
        await backend.dispose();
      },
    );

    test('finish after the same parts → a PDF, job freed', () async {
      final backend = NativePdfComposeBackend();
      final ctx = ComposeProbeContext(backend: backend, engine: engine);
      final bytes = await ctx.compose(plan, await objectParts(ctx));
      expect(await debugNativeComposeJobCount(), 0);
      final objects = ProbePdfObjects(bytes);
      expect(objects.images, hasLength(2));
      expect(objects.fontFiles, 2);
      final out = await ctx.open(bytes);
      expect(
        (await out.text(0)).replaceAll(RegExp(r'\s+'), ' ').trim(),
        '안녕 hello 안녕',
      );
      await ctx.dispose();
      await backend.dispose();
    });

    test('a failed part (unknown font) keeps the job until abort', () async {
      final backend = NativePdfComposeBackend();
      final ctx = ComposeProbeContext(backend: backend, engine: engine);
      final job = await backend.begin(plan);
      await job.addPages(await objectParts(ctx));
      // The same fonts again: already loaded in this job → exportFailed, job still open.
      await expectLater(
        job.addPages(await objectParts(ctx)),
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
  });
}
