@TestOn('browser')
library;

// Foundation step B4 on the web (dart2js, Chrome = CanvasKit): the whole public surface
// compiles for the web (barrel + testing.dart, browser halves of the conditional exports),
// the B4 provider reads of contract 7.6 B4 work, and the B4 pure calculations give the
// same results as on the VM (contract 7.4.8: dart2js number differences).
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

bool _equal(Object a, Object b) => a == b;

void main() {
  test('pdfIoOverrides() container: builders and stats read on the web', () {
    final container = ProviderContainer(overrides: pdfIoOverrides());
    addTearDown(container.dispose);
    final builders = container.read(ink.pageBackgroundBuildersProvider);
    expect(builders, hasLength(2));
    expect((builders.first as PdfBackgroundLayerBuilder).isPaperOnly, isTrue);
    expect(builders.last, isA<ink.TemplateBackgroundLayerBuilder>());
    expect(container.read(pdfRenderStatsProvider).value, PdfRenderStats.zero);
  });

  testWidgets('paperOnly build fills pageSize × viewScale', (tester) async {
    const builder = PdfBackgroundLayerBuilder.paperOnly();
    const ctx = ink.PageBackgroundContext(
      pageId: 'p1',
      pageSize: Size(200, 100),
      background: ink.InkBackgroundSpec(
        kind: ink.InkBackgroundKind.pdf,
        assetId: 'a',
        pdfPageIndex: 0,
      ),
      viewScale: 1.5,
      ancestorScale: 2,
      devicePixelRatio: 2,
      isScaling: false,
    );
    const key = Key('background');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: KeyedSubtree(
            key: key,
            child: Builder(builder: (context) => builder.build(context, ctx)),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(key)), const Size(300, 150));
    expect(
      await builder.renderStill(
        ctx.background,
        pageSize: ctx.pageSize,
        pixelSize: const Size(60, 30),
      ),
      isNull,
    );
  });

  test('web defaults and browser halves of the conditional exports', () {
    expect(
      const PdfIoConfig().effectiveRenderBudget,
      const PdfRenderBudget.web(),
    );
    expect(const PdfRenderBudget.web().totalBytes, 112 * 1024 * 1024);
    // B4 placeholders of the browser files (PDF T14 / T16).
    expect(
      () => createPlatformComposeBackend(const PdfIoConfig()),
      throwsUnimplementedError,
    );
    expect(createPlatformOutputSink, throwsUnimplementedError);
    expect(const NoIncomingPdfFiles().incoming, emitsDone);
    expect(pdfEditorMoreMenuActions(), isEmpty);
    expect(pdfEditorAddPageSources(), isEmpty);
    expect(const PdfFixturePage().rotate, 0);
  });

  test('PdfPageFit gives the VM numbers', () {
    final fit = PdfPageFit(
      notePageSize: const ui.Size(72, 72),
      pdfPageSize: const ui.Size(50, 50),
    );
    expect(fit.k, closeTo(1.44, 1e-9));
    final r = fit.pdfToNote(const ui.Rect.fromLTWH(10, 10, 5, 5));
    expect(r.left, closeTo(14.4, 1e-9));
    expect(r.width, closeTo(7.2, 1e-9));
    final letter = PdfPageFit(
      notePageSize: const ui.Size(595.2756, 841.8898),
      pdfPageSize: const ui.Size(612, 792),
    );
    expect(letter.oy, closeTo(35.767, 1e-3));
    expect(letter.noteToPdfMatrix()[5], closeTo(-letter.oy / letter.k, 1e-9));
  });

  test('value equality holds under dart2js', () {
    expect(
      _equal(
        const PdfJobIdle<PdfImportResult>(),
        const PdfJobIdle<PdfExportResult>(),
      ),
      isFalse,
    );
    expect(
      PdfIoException(PdfErrorCode.busy, cause: Object()),
      const PdfIoException(PdfErrorCode.busy),
    );
    expect(
      const PdfProgress(PdfJobPhase.composing, done: 1, total: 2).hashCode,
      const PdfProgress(PdfJobPhase.composing, done: 1, total: 2).hashCode,
    );
  });
}
