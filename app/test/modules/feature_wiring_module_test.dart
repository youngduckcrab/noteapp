// FeatureWiringModule (docs/plans/01-infra.md 4.5.9, 9.1; contract 7.3.3
// rows owned by FeatureWiringModule): thumbnail renderer, PDF import /
// export slots, editor extensions, PDF render stats section — PDF parts only
// when the PDF module started. Containers hold the module overrides only
// (no test override of pdfRenderStatsProvider, INFRA-3-2 / C12-06).
// 2nd round (docs/plans/m5-7/01-infra.md 4.6.4, 6.7): contributions merged
// into the editor slots, image import outside FEATURE_MEDIA, dev overlay
// [pdf.render?, media?, recog.indexer?, search.index]; (R2-B8b, 6.12.3) the
// Pencil override of stylusExtrasProvider through an injected PencilPort.
// J9: a repeated menu item id → one record each, the later item dropped,
// then a debug assert.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        ValueListenable,
        ValueNotifier,
        debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:media_io/media_io.dart'
    show importImageForNote, supportedImageSources;
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/modules/core_module.dart';
import 'package:noteapp/src/modules/feature_wiring_module.dart';
import 'package:noteapp/src/modules/media_wiring.dart';
import 'package:noteapp/src/modules/pdf_module.dart';
import 'package:noteapp/src/modules/pdf_wiring.dart';
import 'package:noteapp/src/modules/pencil_wiring.dart';
import 'package:noteapp/src/modules/recognition_wiring.dart';
import 'package:noteapp/src/modules/search_wiring.dart';
import 'package:noteapp/src/pencil/pencil_stylus_extras.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pencil_bridge/pencil_bridge.dart';

import '../fakes/counting_note_store.dart';
import '../fakes/fake_app_module.dart';
import '../fakes/fake_native_paths.dart';
import '../fakes/fake_note_store_opener.dart';
import '../fakes/fake_pdf_actions.dart';
import '../fakes/fake_pencil_port.dart';
import '../fakes/fake_web_platform.dart';

/// Boots CoreModule (fake open), PdfModule (default arguments, or a failing
/// initialize) and [wiring]; returns a container with the overrides only.
Future<(ProviderContainer, BootstrapSuccess)> _boot(
  FeatureWiringModule wiring, {
  bool pdfFails = false,
  List<AppModule> between = const [],
  AppErrorLog? log,
}) async {
  final web = FakeWebPlatform();
  final store = CountingNoteStore();
  addTearDown(store.inner.close);
  final bootstrapper = AppBootstrapper(
    modules: [
      CoreModule(
        nativePaths: noNativePaths,
        open: fakeOpenNoteStore(store: store).call,
      ),
      if (pdfFails)
        PdfModule(initialize: () async => throw StateError('no pdfium'))
      else
        PdfModule(),
      ...between,
      wiring,
    ],
    buildInfo: BuildInfo.local,
    runtimeInfo: RuntimeInfo.detect(web),
    web: web,
    errorLog: log ?? AppErrorLog(),
    ownerId: kLocalOwnerId,
  );
  addTearDown(bootstrapper.shutdown);
  final success = await bootstrapper.run() as BootstrapSuccess;
  return (ProviderContainer.test(overrides: success.overrides), success);
}

final _importer = EditorImageImporter(
  sources: const {ImageImportSource.files, ImageImportSource.photos},
  pick: (context, source) async => null,
);

final class _FakeInkSearch implements LibraryInkSearch {
  @override
  final ValueListenable<LibraryInkSearchState> state = ValueNotifier(
    const LibraryInkSearchState(),
  );
  @override
  Future<void> turnOnAutoIndex() async {}
  @override
  Future<void> downloadModel({bool cellular = false}) async {}
  @override
  void searchOpened() {}
}

FeatureWiringModule _wiring(
  FakePdfActions pdf, {
  EditorImageImporter? importer,
  PencilPort pencil = const PencilPort(),
}) => FeatureWiringModule(
  importPdf: pdf.importPdf,
  exportPdf: pdf.exportPdf,
  moreMenuActions: pdf.moreMenuActions,
  addPageActions: pdf.addPageActions,
  pencil: pencil,
  imageImporter: () => importer,
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

    test('dev overlay: pdf.render whose lines read without an exception — '
        'the B4 zero stats, three lines — then search.index', () async {
      final (container, _) = await _boot(_wiring(FakePdfActions()));
      final sections = container.read(devOverlaySectionsProvider);
      expect(sections.map((s) => s.id), ['pdf.render', 'search.index']);
      final section = sections.first;
      expect(section.title, 'PDF 렌더');
      expect(section.lines.value, hasLength(3));
      expect(section.lines.value, formatPdfRenderStats(PdfRenderStats.zero));
    });

    test(
      'default arguments (the real pdf_io functions) build the same rows',
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
        expect(container.read(devOverlaySectionsProvider), hasLength(2));
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
    expect(container.read(devOverlaySectionsProvider).map((s) => s.id), [
      'search.index',
    ]);
    expect(moreMenuCalls, 0);
    expect(
      container.read(pageThumbnailRendererProvider),
      same(container.read(ink.inkPageThumbnailRendererProvider)),
    );
  });

  test('overrides(): feature package lists first, then the thumbnail '
      'renderer, the PDF rows, then the dev overlay (always)', () async {
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
    expect(withoutPdf.overrides().map((o) => o.origin), [
      ...origins.take(features.length + 1),
      devOverlaySectionsProvider,
    ]);

    // With an image importer: right after the editor extensions.
    final withImages = _wiring(FakePdfActions(), importer: _importer);
    await withImages.start(context(pdfOk: true));
    expect(withImages.overrides().map((o) => o.origin), [
      ...origins.take(features.length + 4),
      editorImageImporterProvider,
      devOverlaySectionsProvider,
    ]);
  });

  group('2nd round: contributions', () {
    EditorSelectionMenuItem selection(String id) => EditorSelectionMenuItem(
      id: id,
      label: id,
      icon: Icons.text_fields,
      onSelected: (context, s) async {},
    );
    EditorInsertMenuItem insert(String id) => EditorInsertMenuItem(
      id: id,
      label: id,
      icon: Icons.functions,
      onSelected: (context, s) async {},
    );
    Widget panel(BuildContext context, EditorPanelContext p) =>
        const SizedBox();

    FakeAppModule contributing(String id, ShellContribution contribution) =>
        FakeAppModule(
          id: id,
          critical: false,
          onStart: (c) => c.contribute(contribution),
        );

    test('none (PDF failed, no media / recognition): no editor extensions '
        'override at all', () async {
      final (container, success) = await _boot(
        _wiring(FakePdfActions()),
        pdfFails: true,
      );
      expect(
        success.overrides.map((o) => o.origin),
        isNot(contains(editorExtensionsProvider)),
      );
      expect(
        container.read(editorExtensionsProvider),
        const EditorExtensions(),
      );
    });

    test('one (media): the recording panel, even when PDF failed; the media '
        'dev section before search.index', () async {
      final (container, _) = await _boot(
        _wiring(FakePdfActions()),
        pdfFails: true,
        between: [
          contributing(
            'media',
            ShellContribution(
              moduleId: 'media',
              recordingPanel: panel,
              devOverlaySections: const [mediaDevOverlaySection],
            ),
          ),
        ],
      );
      final extensions = container.read(editorExtensionsProvider);
      expect(extensions.recordingPanel, panel);
      expect(extensions.moreMenuItems, isEmpty);
      expect(extensions.selectionMenuItems, isEmpty);
      expect(
        container.read(devOverlaySectionsProvider).map((s) => (s.id, s.title)),
        [('media', '녹음'), ('search.index', '검색 색인')],
      );
    });

    test('two (media, recognition) with PDF: items merged in module order, '
        'PDF menus kept; dev overlay [pdf.render, media, recog.indexer, '
        'search.index]', () async {
      final toText = selection('recog.toText');
      final toMath = selection('recog.toMath');
      final mathPad = insert('recog.mathPad');
      final (container, success) = await _boot(
        _wiring(
          FakePdfActions(
            moreMenuIds: ['pdf.export'],
            addPageIds: ['pdf.insert'],
          ),
        ),
        between: [
          contributing(
            'media',
            ShellContribution(
              moduleId: 'media',
              recordingPanel: panel,
              devOverlaySections: const [mediaDevOverlaySection],
            ),
          ),
          contributing(
            'recognition',
            ShellContribution(
              moduleId: 'recognition',
              selectionMenuItems: [toText, toMath],
              insertMenuItems: [mathPad],
              devOverlaySections: const [recognitionIndexerSection],
            ),
          ),
        ],
      );
      expect(success.contributions.map((c) => c.moduleId), [
        'media',
        'recognition',
      ]);
      final extensions = container.read(editorExtensionsProvider);
      expect(extensions.moreMenuItems.map((i) => i.id), ['pdf.export']);
      expect(extensions.addPageSources.map((i) => i.id), ['pdf.insert']);
      expect(extensions.selectionMenuItems, [same(toText), same(toMath)]);
      expect(extensions.insertMenuItems, [same(mathPad)]);
      expect(extensions.recordingPanel, panel);
      expect(extensions.appBarTrailing, isNull);
      expect(container.read(devOverlaySectionsProvider).map((s) => s.id), [
        'pdf.render',
        'media',
        'recog.indexer',
        'search.index',
      ]);
    });

    test('(handwriting search) a contribution\'s libraryInkSearch fills the '
        'library slot; without one it stays null', () async {
      final slot = _FakeInkSearch();
      final (withSlot, _) = await _boot(
        _wiring(FakePdfActions()),
        between: [
          contributing(
            'recognition',
            ShellContribution(
              moduleId: 'recognition',
              libraryInkSearch: (ref) => slot,
            ),
          ),
        ],
      );
      expect(withSlot.read(libraryInkSearchProvider), same(slot));

      final (without, _) = await _boot(_wiring(FakePdfActions()));
      expect(without.read(libraryInkSearchProvider), isNull);
    });

    group('a repeated menu item id (6.7 — merge rule)', () {
      List<AppModule> twoWithRepeats() => [
        contributing(
          'media',
          ShellContribution(
            moduleId: 'media',
            selectionMenuItems: [selection('shared.copy')],
            insertMenuItems: [insert('shared.pad')],
          ),
        ),
        contributing(
          'recognition',
          ShellContribution(
            moduleId: 'recognition',
            selectionMenuItems: [
              selection('recog.toText'),
              selection('shared.copy'),
            ],
            insertMenuItems: [insert('shared.pad'), insert('recog.mathPad')],
          ),
        ),
      ];

      test('release behaviour (assert off): one record per repeat, the later '
          'item dropped, the rest kept in module order', () async {
        FeatureWiringModule.debugAssertUniqueMenuIds = false;
        addTearDown(() => FeatureWiringModule.debugAssertUniqueMenuIds = true);
        final log = AppErrorLog();
        final (container, success) = await _boot(
          _wiring(FakePdfActions()),
          pdfFails: true,
          between: twoWithRepeats(),
          log: log,
        );
        expect(success.report.steps.last.outcome, StartupStepOutcome.ok);
        final extensions = container.read(editorExtensionsProvider);
        expect(extensions.selectionMenuItems.map((i) => i.id), [
          'shared.copy',
          'recog.toText',
        ]);
        expect(
          extensions.selectionMenuItems.first,
          same(success.contributions.first.selectionMenuItems.single),
          reason: 'the first one (media) stays',
        );
        expect(extensions.insertMenuItems.map((i) => i.id), [
          'shared.pad',
          'recog.mathPad',
        ]);
        final repeats = log.records
            .where((r) => r.summary.startsWith('duplicate'))
            .toList();
        expect(repeats.map((r) => (r.source, r.summary, r.details)), [
          (
            AppErrorSource.module,
            'duplicate selection menu item id shared.copy — the one of '
                'recognition is dropped',
            'first contributed by media',
          ),
          (
            AppErrorSource.module,
            'duplicate insert menu item id shared.pad — the one of '
                'recognition is dropped',
            'first contributed by media',
          ),
        ]);
      });

      test('debug builds: the assert fails the wiring start (after the '
          'records) — loud, and no editor slots from it', () async {
        final log = AppErrorLog();
        final (container, success) = await _boot(
          _wiring(FakePdfActions()),
          pdfFails: true,
          between: twoWithRepeats(),
          log: log,
        );
        expect(
          success.report.steps.last.outcome,
          StartupStepOutcome.failedNonCritical,
        );
        expect(
          log.records.where((r) => r.summary.startsWith('duplicate')),
          hasLength(2),
        );
        expect(
          log.records.last.summary,
          contains('Editor menu item ids must be unique'),
        );
        expect(
          container.read(editorExtensionsProvider),
          const EditorExtensions(),
        );
      });

      test('unique ids: no record', () async {
        final log = AppErrorLog();
        await _boot(
          _wiring(FakePdfActions()),
          pdfFails: true,
          between: [
            contributing(
              'recognition',
              ShellContribution(
                moduleId: 'recognition',
                selectionMenuItems: [selection('recog.toText')],
                insertMenuItems: [insert('recog.toText')],
              ),
            ),
          ],
          log: log,
        );
        expect(
          log.records.where((r) => r.summary.startsWith('duplicate')),
          isEmpty,
          reason: 'selection and insert are separate slots',
        );
      });
    });

    test('a contribution of a module that failed is not merged (only its '
        'fallback is)', () async {
      final (container, _) = await _boot(
        _wiring(FakePdfActions()),
        pdfFails: true,
        between: [
          FakeAppModule(
            id: 'recognition',
            critical: false,
            startError: StateError('no engine'),
            onStart: (c) => c.contribute(
              ShellContribution(
                moduleId: 'recognition',
                selectionMenuItems: [selection('recog.toText')],
              ),
            ),
          ),
          FakeAppModule(
            id: 'media',
            critical: false,
            startError: StateError('no mic'),
            fallback: ShellContribution(
              moduleId: 'media',
              recordingPanel: panel,
            ),
          ),
        ],
      );
      final extensions = container.read(editorExtensionsProvider);
      expect(extensions.selectionMenuItems, isEmpty);
      expect(extensions.recordingPanel, panel);
      expect(container.read(devOverlaySectionsProvider).map((s) => s.id), [
        'search.index',
      ]);
    });
  });

  group('2nd round: image import (outside FEATURE_MEDIA, D2-15)', () {
    test('the injected importer is wired even when media is off and PDF '
        'failed', () async {
      final (container, _) = await _boot(
        _wiring(FakePdfActions(), importer: _importer),
        pdfFails: true,
      );
      expect(container.read(editorImageImporterProvider), same(_importer));
    });

    test('media failed to start: the importer stays', () async {
      final (container, _) = await _boot(
        _wiring(FakePdfActions(), importer: _importer),
        between: [
          FakeAppModule(
            id: 'media',
            critical: false,
            startError: StateError('no mic'),
          ),
        ],
      );
      expect(container.read(editorImageImporterProvider), same(_importer));
    });

    test(
      'no sources (importer null) → no override, image insert hidden',
      () async {
        final (container, success) = await _boot(
          _wiring(FakePdfActions(), importer: null),
        );
        expect(
          success.overrides.map((o) => o.origin),
          isNot(contains(editorImageImporterProvider)),
        );
        expect(container.read(editorImageImporterProvider), isNull);
      },
    );

    test('the default: mediaImageImporterOrNull() — the real media_io '
        'sources (PDF T35b): android / iOS photos and camera → the override; '
        'a platform with no picker → no override', () async {
      // flutter_test runs as android unless told otherwise.
      expect(supportedImageSources(), {
        ImageImportSource.photos,
        ImageImportSource.camera,
      });
      final (container, _) = await _boot(FeatureWiringModule());
      final importer = container.read(editorImageImporterProvider);
      expect(importer, isNotNull);
      expect(importer!.sources, supportedImageSources());
      expect(importer.pick, importImageForNote);

      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        expect(supportedImageSources(), isEmpty);
        expect(mediaImageImporterOrNull(), isNull);
        final (off, _) = await _boot(FeatureWiringModule());
        expect(off.read(editorImageImporterProvider), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test(
      'an importer that throws → logged (source module), no override',
      () async {
        final log = AppErrorLog();
        final (container, success) = await _boot(
          FeatureWiringModule(
            importPdf: FakePdfActions().importPdf,
            imageImporter: () => throw StateError('picker broken'),
          ),
          log: log,
        );
        expect(success.report.steps.last.outcome, StartupStepOutcome.ok);
        expect(container.read(editorImageImporterProvider), isNull);
        expect(log.records.single.source, AppErrorSource.module);
        expect(log.records.single.summary, contains('picker broken'));
      },
    );
  });

  group('R2-B8b: Pencil (6.12.3, contract 7.3.3 stylusExtrasProvider row)', () {
    test('supported → PencilStylusExtrasSource with the capabilities read '
        'once at start; events carry the native timestamp', () async {
      final pencil = FakePencilPort(
        capabilities: () async => const PencilCapabilities(
          os: '17.5',
          squeeze: true,
          hover: true,
          roll: true,
          preferredTapAction: 'switchEraser',
        ),
      );
      final log = AppErrorLog();
      final (container, success) = await _boot(
        _wiring(FakePdfActions(), pencil: pencil),
        log: log,
      );
      expect(success.report.steps.last.outcome, StartupStepOutcome.ok);
      expect(pencil.capabilityCalls, 1);
      expect(log.records, isEmpty);
      expect(
        success.overrides.where((o) => o.origin == stylusExtrasProvider),
        hasLength(1),
      );

      final extras = container.read(stylusExtrasProvider);
      expect(extras, isA<PencilStylusExtrasSource>());
      expect(extras.isSupported, isTrue);
      // J13: the about section's line reads the start-time os (6.18).
      expect((extras as PencilStylusExtrasSource).os, '17.5');
      expect(extras.seen.value, (squeeze: false, roll: false));
      expect(
        extras.capabilities,
        const StylusCapabilities(
          doubleTap: true,
          squeeze: true,
          barrelRoll: true,
          hoverPose: true,
        ),
      );
      // Reading the slot again does not ask the pencil again.
      container.read(stylusExtrasProvider);
      expect(pencil.capabilityCalls, 1);

      final received = <StylusExtraEvent>[];
      final sub = extras.events.listen(received.add);
      const t = Duration(seconds: 7, microseconds: 5);
      pencil.controller.add(
        const PencilTap(t, preferredAction: 'switchPrevious'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(received, const [
        StylusDoubleTap(
          preferredAction: StylusPreferredAction.switchPrevious,
          timestamp: t,
        ),
      ]);
      await sub.cancel();
    });

    test('not supported (web, Android) → no override, the pencil is never '
        'asked', () async {
      final pencil = FakePencilPort(isSupported: false);
      final (container, success) = await _boot(
        _wiring(FakePdfActions(), pencil: pencil),
      );
      expect(
        success.overrides.map((o) => o.origin),
        isNot(contains(stylusExtrasProvider)),
      );
      expect(container.read(stylusExtrasProvider), isA<NoStylusExtras>());
      expect(pencil.capabilityCalls, 0);
      expect(pencil.eventReads, 0);
    });

    test('the default PencilPort on the test platform (not iOS) → no '
        'override', () async {
      expect(const PencilPort().isSupported, isFalse);
      final (container, success) = await _boot(_wiring(FakePdfActions()));
      expect(
        success.overrides.map((o) => o.origin),
        isNot(contains(stylusExtrasProvider)),
      );
      expect(container.read(stylusExtrasProvider).isSupported, isFalse);
    });

    test('capabilities throw (no plugin) → override with the fallback '
        '(double tap only) + 1 record', () async {
      final pencil = FakePencilPort(
        capabilities: () async =>
            throw MissingPluginException('No implementation found'),
      );
      final log = AppErrorLog();
      final (container, success) = await _boot(
        _wiring(FakePdfActions(), pencil: pencil),
        log: log,
      );
      expect(success.report.steps.last.outcome, StartupStepOutcome.ok);
      final extras = container.read(stylusExtrasProvider);
      expect(extras, isA<PencilStylusExtrasSource>());
      expect(
        extras.capabilities,
        stylusCapabilitiesOf(kPencilFallbackCapabilities),
      );
      expect(extras.capabilities, const StylusCapabilities(doubleTap: true));
      expect((extras as PencilStylusExtrasSource).os, '?');
      expect(log.records, hasLength(1));
      expect(log.records.single.source, AppErrorSource.module);
      expect(log.records.single.summary, contains('MissingPluginException'));
      expect(log.records.single.details, contains('double tap only'));
    });

    test('capabilities take longer than 500 ms → override with the fallback '
        '+ 1 record; the module still starts in time', () {
      fakeAsync((async) {
        final store = CountingNoteStore();
        final web = FakeWebPlatform();
        final log = AppErrorLog();
        final answer = Completer<PencilCapabilities>();
        final pencil = FakePencilPort(capabilities: () => answer.future);
        final bootstrapper = AppBootstrapper(
          modules: [
            CoreModule(
              nativePaths: noNativePaths,
              open: fakeOpenNoteStore(store: store).call,
            ),
            _wiring(FakePdfActions(), pencil: pencil),
          ],
          buildInfo: BuildInfo.local,
          runtimeInfo: RuntimeInfo.detect(web),
          web: web,
          errorLog: log,
          ownerId: kLocalOwnerId,
        );
        BootstrapSuccess? success;
        unawaited(
          bootstrapper.run().then((r) => success = r as BootstrapSuccess),
        );
        async.elapse(const Duration(milliseconds: 499));
        expect(success, isNull, reason: 'still waiting for the pencil');
        async.elapse(const Duration(milliseconds: 1));
        expect(success, isNotNull);
        expect(success!.report.steps.last.outcome, StartupStepOutcome.ok);
        expect(log.records, hasLength(1));
        expect(log.records.single.summary, startsWith('TimeoutException'));
        expect(log.records.single.details, contains('500 ms'));

        final container = ProviderContainer.test(overrides: success!.overrides);
        expect(
          container.read(stylusExtrasProvider).capabilities,
          const StylusCapabilities(doubleTap: true),
        );

        // A late answer changes nothing (capabilities are read once).
        answer.complete(const PencilCapabilities(os: '18.0', hover: true));
        async.flushMicrotasks();
        expect(
          container.read(stylusExtrasProvider).capabilities,
          const StylusCapabilities(doubleTap: true),
        );
        expect(pencil.capabilityCalls, 1);
        expect(log.records, hasLength(1));

        container.dispose();
        unawaited(bootstrapper.shutdown());
        unawaited(store.inner.close());
        async.elapse(const Duration(seconds: 1));
      });
    });
  });

  test('search.index lines follow the store status (CORE fake: no rebuild '
      'yet)', () async {
    final (container, _) = await _boot(_wiring(FakePdfActions()));
    final section = container
        .read(devOverlaySectionsProvider)
        .singleWhere((s) => s.id == 'search.index');
    expect(section.title, '검색 색인');
    await Future<void>.delayed(Duration.zero);
    expect(section.lines.value, hasLength(1));
    expect(section.lines.value.single, startsWith('대기 0 · '));
    expect(
      formatSearchIndexStatus(const SearchIndexStatus()).single,
      '대기 0 · 대기 · 마지막 재구축 없음',
    );
    expect(
      formatSearchIndexStatus(
        const SearchIndexStatus(pendingOwners: 3, rebuilding: true),
      ).single,
      '대기 3 · 재구축 중 · 마지막 재구축 없음',
    );
  });
}
