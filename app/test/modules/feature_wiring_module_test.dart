// FeatureWiringModule (docs/plans/01-infra.md 4.5.9, 9.1; contract 7.3.3
// rows owned by FeatureWiringModule): thumbnail renderer, PDF import /
// export slots, editor extensions, PDF render stats section — PDF parts only
// when the PDF module started. Containers hold the module overrides only
// (no test override of pdfRenderStatsProvider, INFRA-3-2 / C12-06).
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/modules/core_module.dart';
import 'package:noteapp/src/modules/feature_wiring_module.dart';
import 'package:noteapp/src/modules/pdf_module.dart';
import 'package:noteapp/src/modules/pdf_wiring.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:pdf_io/pdf_io.dart';

import '../fakes/counting_note_store.dart';
import '../fakes/fake_note_store_opener.dart';
import '../fakes/fake_pdf_actions.dart';
import '../fakes/fake_web_platform.dart';

/// Boots CoreModule (fake open), PdfModule (default arguments, or a failing
/// initialize) and [wiring]; returns a container with the overrides only.
Future<(ProviderContainer, BootstrapSuccess)> _boot(
  FeatureWiringModule wiring, {
  bool pdfFails = false,
}) async {
  final web = FakeWebPlatform();
  final store = CountingNoteStore();
  addTearDown(store.inner.close);
  final bootstrapper = AppBootstrapper(
    modules: [
      CoreModule(open: fakeOpenNoteStore(store: store).call),
      if (pdfFails)
        PdfModule(initialize: () async => throw StateError('no pdfium'))
      else
        PdfModule(),
      wiring,
    ],
    buildInfo: BuildInfo.local,
    runtimeInfo: RuntimeInfo.detect(web),
    web: web,
    errorLog: AppErrorLog(),
    ownerId: kLocalOwnerId,
  );
  addTearDown(bootstrapper.shutdown);
  final success = await bootstrapper.run() as BootstrapSuccess;
  return (ProviderContainer.test(overrides: success.overrides), success);
}

FeatureWiringModule _wiring(FakePdfActions pdf) => FeatureWiringModule(
  importPdf: pdf.importPdf,
  exportPdf: pdf.exportPdf,
  moreMenuActions: pdf.moreMenuActions,
  addPageActions: pdf.addPageActions,
);

void main() {
  test('id, label, non-critical, 1 s timeout', () {
    final module = FeatureWiringModule();
    expect(FeatureWiringModule.moduleId, 'featureWiring');
    expect(module.id, 'featureWiring');
    expect(module.label, '화면 연결 중');
    expect(module.critical, isFalse);
    expect(module.startTimeout, const Duration(seconds: 1));
  });

  group('PDF started', () {
    test('thumbnail renderer is INK’s instance; the import / export slots '
        'are the injected functions', () async {
      final pdf = FakePdfActions();
      final (container, success) = await _boot(_wiring(pdf));
      expect(
        success.report.steps.map((s) => s.outcome),
        everyElement(StartupStepOutcome.ok),
      );

      final renderer = container.read(pageThumbnailRendererProvider);
      expect(renderer, isNotNull);
      expect(
        renderer,
        same(container.read(ink.inkPageThumbnailRendererProvider)),
      );
      expect(
        identical(
          container.read(libraryPdfImportActionProvider),
          pdf.importPdf,
        ),
        isTrue,
      );
      expect(
        identical(
          container.read(libraryPdfExportActionProvider),
          pdf.exportPdf,
        ),
        isTrue,
      );
    });

    test('editor extensions: menu ids in the fake actions’ order, no app '
        'bar trailing', () async {
      final pdf = FakePdfActions(
        moreMenuIds: ['pdf.export', 'pdf.share', 'pdf.print', 'pdf.search'],
        addPageIds: ['pdf.insert'],
      );
      final (container, _) = await _boot(_wiring(pdf));
      final extensions = container.read(editorExtensionsProvider);
      expect(extensions.moreMenuItems.map((i) => i.id), [
        'pdf.export',
        'pdf.share',
        'pdf.print',
        'pdf.search',
      ]);
      expect(extensions.addPageSources.map((i) => i.id), ['pdf.insert']);
      expect(extensions.appBarTrailing, isNull);
    });

    test('dev overlay: one pdf.render section whose lines read without an '
        'exception — the B4 zero stats, three lines', () async {
      final (container, _) = await _boot(_wiring(FakePdfActions()));
      final sections = container.read(devOverlaySectionsProvider);
      expect(sections.map((s) => s.id), ['pdf.render']);
      final section = sections.single;
      expect(section.title, 'PDF 렌더');
      expect(section.lines.value, hasLength(3));
      expect(section.lines.value, formatPdfRenderStats(PdfRenderStats.zero));
    });

    test(
      'default arguments (pdf_io B4 functions) build the same rows',
      () async {
        final (container, _) = await _boot(FeatureWiringModule());
        expect(
          identical(
            container.read(libraryPdfImportActionProvider),
            importPdfAsNewNote,
          ),
          isTrue,
        );
        expect(
          identical(
            container.read(libraryPdfExportActionProvider),
            exportNotesAsPdf,
          ),
          isTrue,
        );
        final extensions = container.read(editorExtensionsProvider);
        expect(
          extensions.moreMenuItems.map((i) => i.id),
          pdfEditorMoreMenuActions().map((a) => a.id),
        );
        expect(
          extensions.addPageSources.map((i) => i.id),
          pdfEditorAddPageSources().map((a) => a.id),
        );
        expect(container.read(devOverlaySectionsProvider), hasLength(1));
      },
    );
  });

  test('PDF failed: no PDF slots (defaults), the thumbnail renderer is still '
      'wired', () async {
    final pdf = FakePdfActions();
    var moreMenuCalls = 0;
    final (container, success) = await _boot(
      FeatureWiringModule(
        importPdf: pdf.importPdf,
        exportPdf: pdf.exportPdf,
        moreMenuActions: () {
          moreMenuCalls++;
          return pdf.moreMenuActions();
        },
        addPageActions: pdf.addPageActions,
      ),
      pdfFails: true,
    );
    expect(success.report.steps.map((s) => s.outcome), [
      StartupStepOutcome.ok,
      StartupStepOutcome.failedNonCritical,
      StartupStepOutcome.ok,
    ]);
    expect(container.read(libraryPdfImportActionProvider), isNull);
    expect(container.read(libraryPdfExportActionProvider), isNull);
    final extensions = container.read(editorExtensionsProvider);
    expect(extensions.moreMenuItems, isEmpty);
    expect(extensions.addPageSources, isEmpty);
    expect(container.read(devOverlaySectionsProvider), isEmpty);
    expect(moreMenuCalls, 0);
    expect(
      container.read(pageThumbnailRendererProvider),
      same(container.read(ink.inkPageThumbnailRendererProvider)),
    );
  });

  test('overrides(): feature package lists first, then the thumbnail '
      'renderer, then the four PDF rows', () async {
    AppModuleContext context({required bool pdfOk}) {
      final web = FakeWebPlatform();
      final ctx = AppModuleContext(
        buildInfo: BuildInfo.local,
        runtimeInfo: RuntimeInfo.detect(web),
        web: web,
        ownerId: kLocalOwnerId,
        errorLog: AppErrorLog(),
      );
      if (pdfOk) ctx.recordOutcome(PdfModule.moduleId, StartupStepOutcome.ok);
      return ctx;
    }

    final features = <Override>[
      ...featureEditorOverrides(),
      ...featureLibraryOverrides(),
    ];
    final origins = [
      for (final o in features) o.origin,
      pageThumbnailRendererProvider,
      libraryPdfImportActionProvider,
      libraryPdfExportActionProvider,
      editorExtensionsProvider,
      devOverlaySectionsProvider,
    ];

    final withPdf = _wiring(FakePdfActions());
    await withPdf.start(context(pdfOk: true));
    expect(withPdf.overrides().map((o) => o.origin), origins);

    final withoutPdf = _wiring(FakePdfActions());
    await withoutPdf.start(context(pdfOk: false));
    expect(
      withoutPdf.overrides().map((o) => o.origin),
      origins.take(features.length + 1),
    );
  });
}
