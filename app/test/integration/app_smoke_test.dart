@Tags(['integration'])
library;

// Contract V5 smoke (docs/plans/01-infra.md 8.3 G2 'V5 스모크 단계'): the
// real modules over the real CORE (in memory), INK and feature packages.
// Skipped by default (app/dart_test.yaml); run in the integration stage with
// `ws test --run-skipped -t integration`.
//
// Written in I12 with steps 1–3 and 9; G2 adds steps 4–8 (new note →
// editor banner → one stylus stroke → reopen → undo) once the real screens
// are merged and their labels are known.

import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/app/note_app.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/bootstrap/bootstrap_app.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/modules/core_module.dart';
import 'package:noteapp/src/modules/feature_wiring_module.dart';
import 'package:noteapp/src/modules/pdf_module.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:noteapp/src/web/web_platform.dart';

import '../support/contract_strings.dart';

void main() {
  testWidgets('V5: real modules → library with the notDurable banner', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(2064, 2752)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // 1. Real modules; CORE in memory (nativeMemory → notDurable).
    final web = createWebPlatform();
    final errorLog = AppErrorLog();
    late AppBootstrapper bootstrapper;
    await tester.pumpWidget(
      BootstrapApp(
        errorLog: errorLog,
        createBootstrapper: () => bootstrapper = AppBootstrapper(
          modules: [
            CoreModule(configFor: (_) => const NoteStoreConfig(inMemory: true)),
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
    // CORE opens on real I/O: let real time pass until the app shows.
    for (var i = 0; i < 200 && find.byType(NoteApp).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byType(NoteApp), findsOneWidget, reason: '$errorLog');
    final success = await bootstrapper.run();
    expect(success, isA<BootstrapSuccess>());
    final origins = [
      for (final o in (success as BootstrapSuccess).overrides) o.origin,
    ];
    expect(origins.toSet(), hasLength(origins.length));

    // 2. In-memory CORE: nativeMemory → notDurable.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NoteApp)),
    );
    final store = container.read(noteStoreProvider);
    final info = container.read(storageInfoProvider);
    expect(info.backend, StorageBackend.nativeMemory);
    expect(
      storageWarningOf(info, store.persistenceStatus),
      StorageWarning.notDurable,
    );

    // 3. Library banner, before its close button is pressed.
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.text(ContractStrings.storageNotDurable), findsOneWidget);

    // 4–8: G2.

    // 9. Clean-up.
    await tester.runAsync(bootstrapper.shutdown);
  });
}
