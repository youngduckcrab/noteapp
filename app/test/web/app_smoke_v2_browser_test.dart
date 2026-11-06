@TestOn('browser')
@Tags(['integration'])
library;

// Contract V6 v2 smoke (docs/plans/m5-7/01-infra.md 8.2 J19, 9.1; contract
// 7.7 V6 v2.1, 7.4.6 v2.1): the V5 v2 steps of
// test/integration/app_smoke_v2_test.dart in Chrome on the web runtime
// (dart2js — no dart:io at run time) with the real CORE web storage of its
// own per run, the five real modules and the fakes of
// test/support/smoke_v2_fakes.dart (module injection arguments only). The
// web runtime calls no dart:io and no native-only plugin: the error log
// stays empty and no record mentions MissingPluginException. The InkFonts
// test font is installed first (C23-07 — the editor lays text out with
// InkTextLayout). Skipped by default (app/dart_test.yaml); run with
// `ws test --platform chrome --run-skipped -t integration --package noteapp`.

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/testing.dart' show useInkTestFonts;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/modules/core_module.dart';
import 'package:noteapp/src/modules/media_wiring.dart';

import '../support/smoke_scenario.dart';
import '../support/smoke_v2_fakes.dart';

/// Own SQLite DB and blob IndexedDB per run (1st round V6 '설정').
NoteStoreConfig _configFor(AppModuleContext context, String run) =>
    NoteStoreConfig(
      databaseName: 'noteapp_smoke2_$run',
      ownerId: context.ownerId,
      web: WebStorageConfig(
        sqlite3WasmPath: context.web.resolveAppUrl('sqlite3.wasm'),
        driftWorkerPath: context.web.resolveAppUrl('drift_worker.js'),
        blobDatabaseName: 'noteapp_smoke2_${run}_blobs',
      ),
    );

void main() {
  setUpAll(useInkTestFonts);

  testWidgets('V6 v2 (J19): five real modules on web storage → the 7.3.3 '
      'rows once → the four slots → the 1st round flow → a search hit opens '
      'at its page and rect; no plugin error', (tester) async {
    expect(kIsWeb, isTrue);
    final run = '${DateTime.now().microsecondsSinceEpoch}';
    NoteStoreConfig? config;
    final fakes = SmokeV2Fakes();
    final app = await bootSmokeV2App(
      tester,
      fakes,
      CoreModule(configFor: (ctx) => config = _configFor(ctx, run)),
    );
    try {
      expectContractOverridesV2(app, fakes);
      expect(config!.databaseName, 'noteapp_smoke2_$run');

      // The four slots.
      final c = app.container;
      final extensions = c.read(editorExtensionsProvider);
      expect(c.read(editorImageImporterProvider), same(fakes.importer));
      expect(extensions.recordingPanel, same(mediaRecordingPanel));
      expect([
        for (final i in extensions.selectionMenuItems) i.id,
      ], realRecognitionSelectionIds());
      expect([
        for (final i in extensions.insertMenuItems) i.id,
      ], realRecognitionInsertIds());
      expect(
        [for (final s in c.read(devOverlaySectionsProvider)) s.id],
        ['pdf.render', 'media', 'recog.indexer', 'search.index'],
      );
      expect(
        featureRows(app, fakes),
        expectedFeatureRows(app.success.features),
      );

      // The 1st round flow; the banner follows the real web backend.
      final info = c.read(storageInfoProvider);
      final warning = storageWarningOf(info, app.store.persistenceStatus);
      debugPrint('V6 v2: backend ${info.backend}, warning $warning');
      final noteId = await runSmokeScenario(
        tester,
        app,
        banner: warning == StorageWarning.notDurable
            ? findsOneWidget
            : findsNothing,
        trace: (step) => debugPrint('V6 v2: step $step'),
      );
      final pageId = await settle(
        tester,
        'the pages of $noteId',
        () async => (await app.store.content.pagesOf(noteId)).first.id,
      );

      // 9. A search hit (LibraryScreen.onOpenNoteAt) → the page and the rect.
      const hit = Rect.fromLTRB(40.04, 60, 180.25, 96.5);
      const kept = Rect.fromLTRB(40, 60, 180.3, 96.5);
      tester.widget<LibraryScreen>(find.byType(LibraryScreen)).onOpenNoteAt!(
        noteId,
        pageId,
        hit,
      );
      await pumpUntil(
        tester,
        () => find.byType(EditorScreen).evaluate().isNotEmpty,
        reason: 'the editor at the hit',
      );
      final editor = tester.widget<EditorScreen>(find.byType(EditorScreen));
      expect(editor.initialPageId, pageId);
      expect(editor.initialFocusRectPt, kept);
      await letRealTimePass(tester);
      await tester.tap(iconButtonLabeled(SmokeLabels.back));
      await pumpUntil(
        tester,
        () => find.byType(EditorScreen).evaluate().isEmpty,
        reason: 'back in the library after the hit',
      );

      expectNoMissingPlugin(app.errorLog);
      expect(app.errorLog.totalCount, 0, reason: '${app.errorLog}');
    } finally {
      // Close the store first, then drop both databases of this run.
      await app.shutdown(tester);
      if (config case final config?) {
        await tester.runAsync(() => deleteLocalNoteData(config));
      }
    }
  });
}
