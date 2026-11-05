@TestOn('browser')
@Tags(['integration'])
library;

// Contract V6 smoke (docs/plans/01-infra.md 8.3 G2): the V5 scenario in
// Chrome on the web runtime (dart2js — no dart:io at run time) with the real
// CORE web storage, the two files copied by tool/prepare_web_test.dart, and a
// database name + blob IndexedDB name of its own per run (8.3 'V6 설정',
// INFRA-3-5). Steps 3–8 are shared with V5 (test/support/smoke_scenario.dart).
// The banner assertions follow the real web backend (storageWarningOf).
// Skipped by default (app/dart_test.yaml); run in the integration stage with
// `ws test --platform chrome --run-skipped -t integration`.

import 'dart:js_interop';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/modules/core_module.dart';

import 'package:web/web.dart' as html;

import '../support/smoke_scenario.dart';

/// One config per test run: its own SQLite DB and blob IndexedDB (8.3 'V6
/// 설정' — NoteStoreConfig has no copyWith). Absolute URLs as in production
/// (resolveAppUrl = document.baseURI — the test page sits next to the two
/// copied files).
NoteStoreConfig smokeConfigFor(AppModuleContext context, String n) =>
    NoteStoreConfig(
      databaseName: 'noteapp_smoke_$n',
      ownerId: context.ownerId,
      web: WebStorageConfig(
        sqlite3WasmPath: context.web.resolveAppUrl('sqlite3.wasm'),
        driftWorkerPath: context.web.resolveAppUrl('drift_worker.js'),
        blobDatabaseName: 'noteapp_smoke_${n}_blobs',
      ),
    );

/// Names of this origin's IndexedDB databases that belong to run [n].
Future<List<String>> _databasesOf(String n) async {
  final infos = await html.window.indexedDB.databases().toDart;
  return [
    for (final info in infos.toDart)
      if (info.name.contains('noteapp_smoke_$n')) info.name,
  ];
}

void main() {
  testWidgets('V6: real modules on web storage → library → new note → one '
      'stroke → undo / redo → close → reopen keeps it; banners per '
      'storageWarningOf', (tester) async {
    expect(kIsWeb, isTrue);
    final run = '${DateTime.now().microsecondsSinceEpoch}';
    NoteStoreConfig? config;
    NoteId? noteId;

    // 1. Real modules; CORE on the web storage of this run.
    final opening = Stopwatch()..start();
    final app = await bootSmokeApp(
      tester,
      CoreModule(configFor: (ctx) => config = smokeConfigFor(ctx, run)),
    );
    opening.stop();
    // Measured, not asserted (8.3 G2: first openNoteStore time in Chrome).
    debugPrint(
      'V6: bootstrap to the library in ${opening.elapsedMilliseconds} ms '
      '(core step ${app.success.report.steps.first.elapsed.inMilliseconds} '
      'ms)',
    );
    try {
      expectContractOverrides(app);
      expect(config!.databaseName, 'noteapp_smoke_$run');
      expect(config!.web.blobDatabaseName, 'noteapp_smoke_${run}_blobs');
      expect(Uri.parse(config!.web.sqlite3WasmPath).isAbsolute, isTrue);

      // 2. The banner follows the real web backend.
      final info = app.container.read(storageInfoProvider);
      final warning = storageWarningOf(info, app.store.persistenceStatus);
      debugPrint('V6: backend ${info.backend}, warning $warning');
      expect(info.backend, isNot(StorageBackend.nativeMemory));
      expect(info.backend, isNot(StorageBackend.nativeFile));
      expect(warning, isNot(StorageWarning.writeFailing));

      // 3–8. notDurable → the sentence once on each screen, null → nowhere.
      noteId = await runSmokeScenario(
        tester,
        app,
        banner: warning == StorageWarning.notDurable
            ? findsOneWidget
            : findsNothing,
        trace: (step) => debugPrint('V6: step $step'),
      );
      expect(app.errorLog.totalCount, 0, reason: '${app.errorLog}');
    } finally {
      // 9. Clean-up: close the store first (CORE 6.18 — StateError while a
      //    store with this config is open), then drop both databases.
      await app.shutdown(tester);
      final before = await tester.runAsync(() => _databasesOf(run));
      debugPrint('V6: IndexedDB databases of this run: $before');
      await tester.runAsync(() => deleteLocalNoteData(config!));
    }

    // The data is gone (INFRA-2-10 — both databases): no IndexedDB database
    // of this run is left, and the same config opens a new, empty database.
    expect(await tester.runAsync(() => _databasesOf(run)), isEmpty);
    final again = (await tester.runAsync(() => openNoteStore(config!)))!;
    try {
      final note = await tester.runAsync<Note?>(
        () => again.library.getNote(noteId!),
      );
      expect(note, isNull);
    } finally {
      await tester.runAsync(again.close);
      await tester.runAsync(() => deleteLocalNoteData(config!));
    }
    expect(await tester.runAsync(() => _databasesOf(run)), isEmpty);
  });
}
