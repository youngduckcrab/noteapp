@Tags(['integration'])
library;

// Contract V5 v2 smoke (docs/plans/m5-7/01-infra.md 8.2 J19, 9.1 '앱 스모크
// v2 단계'; contract 7.7 V5 v2.1): the five real modules over the real CORE
// (in memory), INK, PDF and feature packages, through the production
// screens. The fakes go in only through the module injection arguments
// (test/support/smoke_v2_fakes.dart). This file holds the steps that run
// before the areas' 2nd round code is merged (9.1 table 'J19'):
//
//   1  start: five modules ok, the 7.3.3 rows each once, audio rows from
//      MediaModule and recognition rows from RecognitionModule;
//   ·  the four editor slots: image import (1), recording panel (2),
//      selection (3) and insert (4) menu items — the provider values;
//   ·  the 1st round V5 flow on top of the five modules (new note → stroke
//      → undo / redo → close → reopen);
//   9  routing: the library's onOpenNoteAt → `?page=&focus=` → the editor
//      gets the page and the rect.
//
// H3 (integration stage, every area merged) adds steps 2–8 and 10 on a
// second note (test/support/smoke_v2_scenario.dart — stroke, text box '안녕
// hello', rectangle, image (slot 1), lasso → 90° → colour → cut → paste,
// undo chain → redo → close → reopen, recording panel (slot 2) with the fake
// recorder and 3 strokes → stop, playback focus and a finger tap seek,
// slots 3 · 4 with the real recognition items, the export counts) and step 9
// through the library search UI ('안녕' → the content hit → `?page=&focus=`).
// Skipped by default (app/dart_test.yaml); run with
// `ws test --run-skipped -t integration --package noteapp`.

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/modules/core_module.dart';
import 'package:noteapp/src/modules/media_wiring.dart';
import 'package:noteapp/src/routing/app_routes.dart';
import 'package:noteapp/src/settings/settings_sections.dart';
import 'package:pdf_io/pdf_io.dart';

import '../fakes/fake_native_paths.dart';
import '../support/smoke_scenario.dart';
import '../support/smoke_v2_fakes.dart';
import '../support/smoke_v2_scenario.dart';

String _location(WidgetTester tester) =>
    (tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
            as GoRouter)
        .state
        .uri
        .toString();

void main() {
  testWidgets('V5 v2 (J19): five real modules → the 7.3.3 rows once → the '
      'four slots → the 1st round flow → a search hit opens at its page and '
      'rect', (tester) async {
    final fakes = SmokeV2Fakes();
    final app = await bootSmokeV2App(
      tester,
      fakes,
      CoreModule(
        nativePaths: noNativePaths,
        configFor: (_) => const NoteStoreConfig(inMemory: true),
      ),
    );

    // 1. Start: every module ok, each override once and from its module.
    expectContractOverridesV2(app, fakes);
    expect(
      {for (final t in app.success.idleTasks) t.id},
      {
        'pdf.searchIndexer',
        'media.leaveGuard',
        'media.recoverDrafts',
        'recognition.indexer',
      },
    );
    expect(
      [for (final c in app.success.contributions) c.moduleId],
      ['media', 'recognition'],
    );

    // The four slots (contract 7.3.3 v2 rows of FeatureWiringModule).
    final c = app.container;
    final extensions = c.read(editorExtensionsProvider);
    // 1 — image import: the importer FeatureWiringModule got, outside
    //     FEATURE_MEDIA (D17).
    expect(c.read(editorImageImporterProvider), same(fakes.importer));
    expect(
      c.read(editorImageImporterProvider)!.sources,
      SmokeV2Fakes.imageSources,
    );
    // 2 — recording panel: MediaModule's contribution.
    expect(extensions.recordingPanel, same(mediaRecordingPanel));
    // 3 · 4 — the recognition actions, converted (6.7 '자리 변환'). Empty on
    //     the R2-B6 surface; LIBRARY's actions are merged now (H3).
    expect(realRecognitionSelectionIds(), isNotEmpty);
    expect(realRecognitionInsertIds(), isNotEmpty);
    expect([
      for (final i in extensions.selectionMenuItems) i.id,
    ], realRecognitionSelectionIds());
    expect([
      for (final i in extensions.insertMenuItems) i.id,
    ], realRecognitionInsertIds());
    // PDF's own rows stay.
    expect(
      [for (final i in extensions.moreMenuItems) i.id],
      [for (final a in pdfEditorMoreMenuActions()) a.id],
    );
    expect(
      [for (final i in extensions.addPageSources) i.id],
      [for (final a in pdfEditorAddPageSources()) a.id],
    );
    // Developer overlay: PDF first, then the contributions in module order,
    // search.index last (S2-4).
    expect(
      [for (final s in c.read(devOverlaySectionsProvider)) s.id],
      ['pdf.render', 'media', 'recog.indexer', 'search.index'],
    );
    // Settings: the recognition section sits with the contributed ones,
    // before the developer sections (S2-9).
    final settings = [for (final s in c.read(settingsSectionsProvider)) s.id];
    expect(settings, contains('recog.settings'));
    expect(
      settings.indexOf('recog.settings'),
      lessThan(settings.indexOf('editor.developer')),
    );
    // The V15 rows of the all-on start (feature_switch_test compares the
    // other seven combinations against these).
    expect(featureRows(app, fakes), expectedFeatureRows(app.success.features));

    // The 1st round V5 flow on the five modules.
    final noteId = await runSmokeScenario(tester, app, banner: findsOneWidget);
    final pageId = await settle(
      tester,
      'the pages of $noteId',
      () async => (await app.store.content.pagesOf(noteId)).first.id,
    );

    // 9. Routing (7.3.3: the router joins LibraryScreen.onOpenNoteAt to
    //    AppRoutes.note(noteId, pageId:, focus:)): what a search hit calls.
    const hit = Rect.fromLTRB(40.04, 60, 180.25, 96.5);
    const kept = Rect.fromLTRB(40, 60, 180.3, 96.5); // 0.1 pt in the address
    expect(find.byType(LibraryScreen), findsOneWidget);
    final library = tester.widget<LibraryScreen>(find.byType(LibraryScreen));
    expect(library.onOpenNoteAt, isNotNull);
    library.onOpenNoteAt!(noteId, pageId, hit);
    await pumpUntil(
      tester,
      () => find.byType(EditorScreen).evaluate().isNotEmpty,
      reason: 'the editor at the hit',
    );
    final editor = tester.widget<EditorScreen>(find.byType(EditorScreen));
    expect(editor.noteId, noteId);
    expect(editor.initialPageId, pageId);
    expect(editor.initialFocusRectPt, kept);
    expect(
      _location(tester),
      AppRoutes.note(noteId, pageId: pageId, focus: kept),
    );
    await letRealTimePass(tester);
    await tester.tap(iconButtonLabeled(SmokeLabels.back));
    await pumpUntil(
      tester,
      () => find.byType(EditorScreen).evaluate().isEmpty,
      reason: 'back in the library after the hit',
    );
    expect(_location(tester), AppRoutes.library);

    // H3: steps 2–8 and 10 on a second note, then step 9 through the search
    //     UI on its text box.
    final steps = <String>[];
    final v2 = await runSmokeV2Scenario(
      tester,
      app,
      fakes,
      trace: (s) {
        steps.add(s);
        debugPrint('V5 v2 step: $s');
      },
    );
    await runSearchStep(tester, app, v2.noteId, '안녕');
    final searched = tester.widget<EditorScreen>(find.byType(EditorScreen));
    final box = v2.page.objects.whereType<TextBoxObject>().single.bounds;
    final flash = searched.initialFocusRectPt!;
    expect(searched.initialPageId, v2.page.page.id);
    expect(flash.left, greaterThanOrEqualTo(box.left - 1));
    expect(flash.right, lessThanOrEqualTo(box.right + 1));
    expect(flash.top, greaterThanOrEqualTo(box.top - 1));
    expect(flash.bottom, lessThanOrEqualTo(box.bottom + 1));
    expect(
      _location(tester),
      AppRoutes.note(
        v2.noteId,
        pageId: searched.initialPageId,
        focus: searched.initialFocusRectPt,
      ),
    );
    await tester.tap(iconButtonLabeled(SmokeLabels.back));
    await pumpUntil(
      tester,
      () => find.byType(EditorScreen).evaluate().isEmpty,
      reason: 'back in the library after the search hit',
    );

    expect(app.errorLog.totalCount, 0, reason: '${app.errorLog} $steps');
    await app.shutdown(tester);
  });
}
