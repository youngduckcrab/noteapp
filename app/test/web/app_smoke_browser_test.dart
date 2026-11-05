@TestOn('browser')
@Tags(['integration'])
library;

// Contract V6 smoke (docs/plans/01-infra.md 8.3 G2): V5 in Chrome with the
// real CORE web storage, the two files copied by tool/prepare_web_test.dart,
// and a database name + blob IndexedDB name of its own per run
// (INFRA-3-5). Skipped by default (app/dart_test.yaml); run in the
// integration stage with
// `ws test --platform chrome --run-skipped -t integration`.
//
// Written in I12 with steps 1–3 and 9 (+ deleteLocalNoteData after
// shutdown, INFRA-2-10); G2 adds steps 4–8.

import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/app/note_app.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/bootstrap/bootstrap_app.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/modules/core_module.dart';
import 'package:noteapp/src/modules/feature_wiring_module.dart';
import 'package:noteapp/src/modules/pdf_module.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:noteapp/src/web/web_platform.dart';

import '../support/contract_strings.dart';

/// One config per test run: its own SQLite DB and blob IndexedDB (8.3 'V6
/// 설정' — NoteStoreConfig has no copyWith).
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

void main() {
  testWidgets('V6: real modules on web storage → library banner per '
      'storageWarningOf', (tester) async {
    tester.view
      ..physicalSize = const Size(2064, 2752)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final run = '${DateTime.now().microsecondsSinceEpoch}';
    final web = createWebPlatform();
    final errorLog = AppErrorLog();
    late NoteStoreConfig config;
    late AppBootstrapper bootstrapper;
    await tester.pumpWidget(
      BootstrapApp(
        errorLog: errorLog,
        createBootstrapper: () => bootstrapper = AppBootstrapper(
          modules: [
            CoreModule(configFor: (ctx) => config = smokeConfigFor(ctx, run)),
            PdfModule(),
            FeatureWiringModule(),
          ],
          buildInfo: BuildInfo.local,
          runtimeInfo: RuntimeInfo.detect(web),
          web: web,
          errorLog: errorLog,
          ownerId: kLocalOwnerId,
        ),
      ),
    );
    for (var i = 0; i < 400 && find.byType(NoteApp).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byType(NoteApp), findsOneWidget, reason: '$errorLog');

    // 2–3. The banner follows the real web backend.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NoteApp)),
    );
    final store = container.read(noteStoreProvider);
    final warning = storageWarningOf(
      container.read(storageInfoProvider),
      store.persistenceStatus,
    );
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(
      find.text(ContractStrings.storageNotDurable),
      warning == StorageWarning.notDurable ? findsOneWidget : findsNothing,
    );
    expect(find.text(ContractStrings.storageWriteFailing), findsNothing);

    // 4–8: G2.

    // 9. Clean-up: close the store first, then drop both databases.
    await tester.runAsync(bootstrapper.shutdown);
    await tester.runAsync(() => deleteLocalNoteData(config));
  });
}
