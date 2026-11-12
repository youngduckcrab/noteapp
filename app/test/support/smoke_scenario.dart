// The contract V5 / V6 smoke scenario (docs/plans/01-infra.md 8.3 'V5 스모크
// 단계', contract 7.7 V5 · V6), shared by the VM test
// (test/integration/app_smoke_test.dart, in-memory CORE) and the Chrome test
// (test/web/app_smoke_browser_test.dart, CORE web storage). Each test builds
// its own CoreModule and decides the expected banner; everything else runs
// here, through the production screens:
//
//   boot the real modules → every 7.3.3 override present once and real →
//   library (banner) → '새 노트' → editor (banner) → one stylus stroke →
//   undo → empty page → redo → back → library → open the note again → the
//   stroke is kept, the new session starts with an empty history.
//
// Controls are found by their visible label or accessibility label (never by
// a position or a package's private key); stroke positions come from the
// page view's rect, so banner and toolbar heights do not matter. Stroke
// counts are read from the store (CORE NoteContentReader after flush,
// contract 7.2.9), not from the screen structure.
//
// Web-safe: no dart:io, no package:web.
library;

import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter/gestures.dart'
    show
        PointerAddedEvent,
        PointerDeviceKind,
        PointerDownEvent,
        PointerMoveEvent,
        PointerRemovedEvent,
        PointerUpEvent,
        kPrimaryButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:media_io/media_io.dart'
    show importImageForNote, supportedImageSources;
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/app/note_app.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/bootstrap/bootstrap_app.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/features/app_features.dart';
import 'package:noteapp/src/modules/core_module.dart';
import 'package:noteapp/src/modules/feature_wiring_module.dart';
import 'package:noteapp/src/modules/pdf_module.dart';
import 'package:noteapp/src/providers.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:noteapp/src/settings/settings_sections.dart';
import 'package:noteapp/src/web/web_platform.dart';
import 'package:pdf_io/pdf_io.dart';

import 'contract_strings.dart';

/// Labels of the feature screens the smoke drives: user-visible texts
/// (LIBRARY 05-library 6.12 new note flow) and accessibility labels (EDITOR
/// 04-editor 6.9.1 — toolbar icon buttons have no tooltip but a
/// semanticLabel), as a user or a screen reader finds them. The packages keep
/// their string constants under src/, so the app spells them out here; a
/// renamed label fails the smoke loudly.
abstract final class SmokeLabels {
  /// LIBRARY: the empty home's '새 노트' button.
  static const String newNote = '새 노트';

  /// LIBRARY: the new note dialog's confirm button.
  static const String create = '만들기';

  /// LIBRARY: the title the new note dialog proposes for the first note.
  static const String untitledNote = '제목 없는 노트';

  /// EDITOR toolbar: back (flush, then onClose).
  static const String back = '뒤로';

  /// EDITOR toolbar: undo / redo.
  static const String undo = '되돌리기';
  static const String redo = '다시 실행';
}

/// What one smoke run started; [shutdown] is step 9.
final class SmokeApp {
  SmokeApp._(this.bootstrapper, this.success, this.container, this.errorLog);

  final AppBootstrapper bootstrapper;
  final BootstrapSuccess success;
  final ProviderContainer container;
  final AppErrorLog errorLog;

  NoteStore get store => container.read(noteStoreProvider);

  /// Closes the modules in reverse order (CoreModule.stop = store.close()).
  Future<void> shutdown(WidgetTester tester) =>
      settle(tester, 'the shutdown', bootstrapper.shutdown);
}

/// Step 1: iPad Pro 13" portrait (1032 × 1376, DPR 2), BootstrapApp with
/// [core], the real PdfModule() and FeatureWiringModule() (production
/// arguments), the production screens (appScreenBuildersProvider is not
/// overridden) — until the LibraryScreen shows.
Future<SmokeApp> bootSmokeApp(WidgetTester tester, CoreModule core) =>
    bootSmokeAppWith(
      tester,
      modules: [core, PdfModule(), FeatureWiringModule()],
    );

/// [bootSmokeApp] with any module list and build switches (2nd round —
/// docs/plans/m5-7/01-infra.md 9.1: the five modules of
/// test/support/smoke_v2_fakes.dart, [features] = the build's switches as
/// AppBootstrapper.features, V15).
Future<SmokeApp> bootSmokeAppWith(
  WidgetTester tester, {
  required List<AppModule> modules,
  AppFeatures features = AppFeatures.all,
}) async {
  tester.view
    ..physicalSize = const Size(2064, 2752)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  final web = createWebPlatform();
  final errorLog = AppErrorLog();
  late AppBootstrapper bootstrapper;
  await tester.pumpWidget(
    BootstrapApp(
      errorLog: errorLog,
      createBootstrapper: () => bootstrapper = AppBootstrapper(
        modules: modules,
        buildInfo: BuildInfo.local,
        runtimeInfo: RuntimeInfo.detect(web),
        web: web,
        errorLog: errorLog,
        ownerId: kLocalOwnerId,
        features: features,
      ),
    ),
  );
  await pumpUntil(
    tester,
    () => find.byType(LibraryScreen).evaluate().isNotEmpty,
    reason: 'the library after the bootstrap ($errorLog)',
  );
  final result = await bootstrapper.run();
  expect(result, isA<BootstrapSuccess>(), reason: '$errorLog');
  final container = ProviderScope.containerOf(
    tester.element(find.byType(NoteApp)),
  );
  return SmokeApp._(
    bootstrapper,
    result as BootstrapSuccess,
    container,
    errorLog,
  );
}

/// Step 1 (contract 7.3.3, V5 '7.3.3 표의 override가 모두 실제 구현이고
/// 중복이 없음'): every module started; the root overrides are exactly the
/// 7.3.3 '이번' rows + the shell rows (+ whatever featureEditorOverrides() /
/// featureLibraryOverrides() return — empty today), each provider once; and
/// each value is the real implementation.
void expectContractOverrides(SmokeApp app) {
  expect(
    {for (final s in app.success.report.steps) s.id: s.outcome},
    {
      CoreModule.moduleId: StartupStepOutcome.ok,
      PdfModule.moduleId: StartupStepOutcome.ok,
      FeatureWiringModule.moduleId: StartupStepOutcome.ok,
    },
  );

  final origins = [for (final o in app.success.overrides) o.origin];
  expect(origins.toSet(), hasLength(origins.length), reason: 'duplicates');
  expect(origins.toSet(), <Object>{
    // 7.3.3 '이번' rows.
    noteStoreProvider, // CoreModule
    ink.pageBackgroundBuildersProvider, // PdfModule → pdfIoOverrides()
    pdfIoConfigProvider,
    pageThumbnailRendererProvider, // FeatureWiringModule
    libraryPdfImportActionProvider,
    libraryPdfExportActionProvider,
    editorExtensionsProvider,
    devOverlaySectionsProvider,
    // 7.3.3 '셸 provider' row (BootstrapApp / AppBootstrapper, 01-infra 6.4).
    buildInfoProvider,
    webPlatformProvider,
    runtimeInfoProvider,
    appErrorLogProvider,
    startupReportProvider,
    appBootstrapperProvider,
    // 2nd round shell rows (m5-7/01-infra 4.6.1 · 4.6.7).
    appFeaturesProvider,
    shellContributionsProvider,
    // 2nd round D2-15: FeatureWiringModule's image importer, outside
    // FEATURE_MEDIA — present whenever media_io offers a source on this
    // platform (android in flutter_test, every browser).
    if (supportedImageSources().isNotEmpty) editorImageImporterProvider,
    // The packages' own lists, added by FeatureWiringModule (4.5.9).
    for (final o in featureEditorOverrides()) o.origin,
    for (final o in featureLibraryOverrides()) o.origin,
  });

  final c = app.container;
  // PDF: the PDF background builder first, then INK's default list
  // (contract v2.2 7.3.3 — [pdf, image, template]).
  expect(c.read(ink.pageBackgroundBuildersProvider), [
    isA<PdfBackgroundLayerBuilder>(),
    isA<ink.ImageBackgroundLayerBuilder>(),
    isA<ink.TemplateBackgroundLayerBuilder>(),
  ]);
  expect(c.read(pdfIoConfigProvider), const PdfIoConfig());
  // FeatureWiringModule rows.
  expect(
    c.read(pageThumbnailRendererProvider),
    same(c.read(ink.inkPageThumbnailRendererProvider)),
  );
  expect(
    identical(c.read(libraryPdfImportActionProvider), importPdfAsNewNote),
    isTrue,
  );
  expect(
    identical(c.read(libraryPdfExportActionProvider), exportNotesAsPdf),
    isTrue,
  );
  final extensions = c.read(editorExtensionsProvider);
  expect(
    extensions.moreMenuItems.map((i) => i.id),
    pdfEditorMoreMenuActions().map((a) => a.id),
  );
  expect(
    extensions.addPageSources.map((i) => i.id),
    pdfEditorAddPageSources().map((a) => a.id),
  );
  final importer = c.read(editorImageImporterProvider);
  if (supportedImageSources().isEmpty) {
    expect(importer, isNull);
  } else {
    expect(importer!.sources, supportedImageSources());
    expect(importer.pick, importImageForNote);
  }
  final sections = c.read(devOverlaySectionsProvider);
  // 2nd round S2-4: search.index is always last.
  expect(sections.map((s) => s.id), ['pdf.render', 'search.index']);
  expect(sections.first.lines.value, hasLength(3));
}

/// Steps 3–8 on the production screens. [banner] is the expected match count
/// of the notDurable sentence on each screen (findsOneWidget / findsNothing);
/// the writeFailing sentence never shows (no failure is injected). [trace]
/// gets the step about to run (a hang then shows where). Returns the note id.
Future<NoteId> runSmokeScenario(
  WidgetTester tester,
  SmokeApp app, {
  required Matcher banner,
  void Function(String step)? trace,
}) async {
  final store = app.store;
  final log = trace ?? (_) {};

  log('3 library banner');
  // 3. Library banner, before its close button is pressed (the banner is not
  //    closed — that is LIBRARY's own test).
  await pumpUntil(
    tester,
    () => find.text(SmokeLabels.newNote).evaluate().isNotEmpty,
    reason: "the empty home's '${SmokeLabels.newNote}'",
  );
  expect(find.byType(LibraryScreen), findsOneWidget);
  expect(find.text(ContractStrings.storageNotDurable), banner);
  expect(find.text(ContractStrings.storageWriteFailing), findsNothing);

  log('4 new note');
  // 4. New note: '새 노트' → the dialog's '만들기' → EditorScreen.
  await tester.tap(find.text(SmokeLabels.newNote));
  await pumpUntil(
    tester,
    () => find.text(SmokeLabels.create).evaluate().isNotEmpty,
    reason: 'the new note dialog',
  );
  await tester.tap(find.text(SmokeLabels.create));
  await pumpUntil(
    tester,
    () => find.byType(ink.InkPageView).evaluate().isNotEmpty,
    reason: 'the editor of the new note',
  );
  expect(find.byType(EditorScreen), findsOneWidget);
  final noteId = tester.widget<EditorScreen>(find.byType(EditorScreen)).noteId;
  expect(
    (await _getNote(tester, store, noteId))?.title,
    SmokeLabels.untitledNote,
  );
  expect(await strokesOnFirstPage(tester, store, noteId), isEmpty);

  log('5 editor banner');
  // 5. Editor banner: the same sentence (the library route below is
  //    Offstage, which the default finder skips).
  expect(find.text(ContractStrings.storageNotDurable), banner);
  expect(find.text(ContractStrings.storageWriteFailing), findsNothing);

  log('6 stroke');
  // 6. One synthetic stylus stroke in the middle of the first page view.
  final page = _visible(
    tester,
    tester.getRect(find.byType(ink.InkPageView).first),
  );
  await stylusStroke(tester, strokePathIn(page));
  await pumpUntil(
    tester,
    () => _enabled(tester, SmokeLabels.undo),
    reason: 'one undo step after the stroke',
  );
  final drawn = await strokesOnFirstPage(tester, store, noteId);
  expect(drawn, hasLength(1));
  final strokeId = drawn.single.id;
  // Screen → page mapping: the path spans the middle 40 % of the page view's
  // width, so the stroke spans about 40 % of the page's width, centred.
  final pageWidth = await _firstPageWidth(tester, store, noteId);
  final b = drawn.single.bounds;
  expect((b.right - b.left) / pageWidth, closeTo(0.4, 0.05));
  expect((b.left + b.right) / 2 / pageWidth, closeTo(0.5, 0.05));

  log('8 undo / redo');
  // 8. Undo (toolbar) → an empty page in the store; redo brings the same
  //    stroke back. Done before closing (01-infra 8.3 'G2 실행 순서'): the
  //    session's history closes with the editor (02-core 6.16
  //    noteSessionProvider, '재진입 시 빈 히스토리'), so the stroke of a
  //    closed session cannot be undone after reopening.
  await tester.tap(iconButtonLabeled(SmokeLabels.undo));
  await pumpUntil(
    tester,
    () =>
        !_enabled(tester, SmokeLabels.undo) &&
        _enabled(tester, SmokeLabels.redo),
    reason: 'the undo applied',
  );
  expect(await strokesOnFirstPage(tester, store, noteId), isEmpty);
  await tester.tap(iconButtonLabeled(SmokeLabels.redo));
  await pumpUntil(
    tester,
    () =>
        _enabled(tester, SmokeLabels.undo) &&
        !_enabled(tester, SmokeLabels.redo),
    reason: 'the redo applied',
  );
  expect(
    [for (final s in await strokesOnFirstPage(tester, store, noteId)) s.id],
    [strokeId],
  );

  log('7 close and reopen');
  // 7. Back (flush, then onClose) → library → the note's tile by its title →
  //    the editor again: the stroke is kept; the new session has no history.
  await tester.tap(iconButtonLabeled(SmokeLabels.back));
  await pumpUntil(
    tester,
    () =>
        find.byType(EditorScreen).evaluate().isEmpty &&
        find.byType(LibraryScreen).evaluate().isNotEmpty,
    reason: 'back in the library',
  );
  expect(store.persistenceStatus.pendingOps, 0);
  await pumpUntil(
    tester,
    () => find.text(SmokeLabels.untitledNote).evaluate().isNotEmpty,
    reason: "the note's tile",
  );
  expect(find.text(SmokeLabels.untitledNote), findsOneWidget);
  await tester.tap(find.text(SmokeLabels.untitledNote));
  await pumpUntil(
    tester,
    () => find.byType(ink.InkPageView).evaluate().isNotEmpty,
    reason: 'the editor opened again',
  );
  expect(tester.widget<EditorScreen>(find.byType(EditorScreen)).noteId, noteId);
  await letRealTimePass(tester);
  expect(
    [for (final s in await strokesOnFirstPage(tester, store, noteId)) s.id],
    [strokeId],
  );
  expect(_enabled(tester, SmokeLabels.undo), isFalse);
  expect(find.text(ContractStrings.storageNotDurable), banner);

  log('leave the editor');
  // Leave the editor so that no session stays open during shutdown.
  await tester.tap(iconButtonLabeled(SmokeLabels.back));
  await pumpUntil(
    tester,
    () => find.byType(EditorScreen).evaluate().isEmpty,
    reason: 'back in the library (2)',
  );
  log('done');
  return noteId;
}

/// The strokes of [noteId]'s first page as committed: NoteStore.flush(), then
/// NoteContentReader.pagesOf / loadPage (contract 7.2.9).
Future<List<Stroke>> strokesOnFirstPage(
  WidgetTester tester,
  NoteStore store,
  NoteId noteId,
) => settle(tester, 'the first page of $noteId', () async {
  await store.flush();
  final pages = await store.content.pagesOf(noteId);
  final content = await store.content.loadPage(pages.first.id);
  return content.strokes;
});

/// The width (pt) of [id]'s first page.
Future<double> _firstPageWidth(
  WidgetTester tester,
  NoteStore store,
  NoteId id,
) => settle(
  tester,
  'the pages of $id',
  () async => (await store.content.pagesOf(id)).first.size.width,
);

Future<Note?> _getNote(WidgetTester tester, NoteStore store, NoteId id) =>
    settle(tester, 'note $id', () => store.library.getNote(id));

/// Runs [operation] on the app's store and pumps (with real time passing)
/// until it completes; returns its value or rethrows its error.
///
/// Not tester.runAsync(operation): the store was opened by the bootstrapper
/// inside the widget test's fake-async zone, so on the web its Web Worker
/// replies are handled in that zone and only run when the test pumps — an
/// operation awaited inside runAsync (where nothing pumps) never completes.
Future<T> settle<T>(
  WidgetTester tester,
  String what,
  Future<T> Function() operation,
) async {
  late T value;
  Object? error;
  StackTrace? stackTrace;
  var done = false;
  unawaited(
    operation().then(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object e, StackTrace s) {
        error = e;
        stackTrace = s;
        done = true;
      },
    ),
  );
  await pumpUntil(tester, () => done, reason: what);
  if (error case final e?) Error.throwWithStackTrace(e, stackTrace!);
  return value;
}

/// [rect] clipped to the logical screen.
Rect _visible(WidgetTester tester, Rect rect) => rect.intersect(
  Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio,
);

bool _enabled(WidgetTester tester, String label) =>
    tester.widget<IconButton>(iconButtonLabeled(label)).onPressed != null;

/// The IconButton whose icon carries [label] as its semantic label (EDITOR
/// toolbar buttons have no tooltip, 04-editor 6.9.1). Onstage only.
Finder iconButtonLabeled(String label) => find.ancestor(
  of: find.byWidgetPredicate((w) => w is Icon && w.semanticLabel == label),
  matching: find.byType(IconButton),
);

/// Pumps frames until [done] holds, letting real time pass in between (the
/// real CORE opens, writes and reads outside the fake-async zone — drift on
/// the VM, a Web Worker in Chrome). Fails with [reason] after [maxTries]
/// (no wall-clock assertion: the limit only stops a hang).
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  required String reason,
  int maxTries = 600,
  Duration step = const Duration(milliseconds: 25),
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (done()) return;
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(done(), isTrue, reason: 'gave up waiting for $reason');
}

/// Lets real time pass [times] × [step] with a frame after each (pending
/// real I/O settles; nothing is asserted).
Future<void> letRealTimePass(
  WidgetTester tester, {
  int times = 10,
  Duration step = const Duration(milliseconds: 25),
}) async {
  for (var i = 0; i < times; i++) {
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// The stroke path inside [page]: a gentle zigzag through the middle, from
/// 20 % of the width left of the centre to 20 % right of it (8.3 V5 step 6).
List<Offset> strokePathIn(Rect page) {
  final c = page.center;
  final half = page.width * 0.2;
  const steps = 12;
  return [
    for (var i = 0; i <= steps; i++)
      Offset(
        c.dx - half + 2 * half * i / steps,
        c.dy + (i.isEven ? 0 : page.height * 0.01),
      ),
  ];
}

int _nextEventPointer = 70000;

/// One synthetic Apple Pencil stroke through [points]: the device is added,
/// then down, a move every [interval] (event timestamps and fake time
/// advance together), up and removed — raw PointerEvents with pressure, as
/// the engine sends them.
Future<void> stylusStroke(
  WidgetTester tester,
  List<Offset> points, {
  int device = 7,
  Duration interval = const Duration(milliseconds: 8),
}) async {
  var now = const Duration(seconds: 1);
  final pointer = _nextEventPointer++;
  await tester.sendEventToBinding(
    PointerAddedEvent(
      timeStamp: now,
      device: device,
      kind: PointerDeviceKind.stylus,
      position: points.first,
    ),
  );
  await tester.sendEventToBinding(
    PointerDownEvent(
      timeStamp: now,
      pointer: pointer,
      device: device,
      kind: PointerDeviceKind.stylus,
      position: points.first,
      buttons: kPrimaryButton,
      pressure: 0.5,
      pressureMin: 0,
      pressureMax: 1,
    ),
  );
  var last = points.first;
  for (final p in points.skip(1)) {
    now += interval;
    await tester.pump(interval);
    await tester.sendEventToBinding(
      PointerMoveEvent(
        timeStamp: now,
        pointer: pointer,
        device: device,
        kind: PointerDeviceKind.stylus,
        position: p,
        delta: p - last,
        buttons: kPrimaryButton,
        pressure: 0.5,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    last = p;
  }
  now += interval;
  await tester.pump(interval);
  await tester.sendEventToBinding(
    PointerUpEvent(
      timeStamp: now,
      pointer: pointer,
      device: device,
      kind: PointerDeviceKind.stylus,
      position: last,
      pressureMin: 0,
      pressureMax: 1,
    ),
  );
  await tester.sendEventToBinding(
    PointerRemovedEvent(
      timeStamp: now,
      device: device,
      kind: PointerDeviceKind.stylus,
      position: last,
    ),
  );
  await tester.pump();
}
