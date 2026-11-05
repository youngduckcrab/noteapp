@Tags(['integration'])
library;

// Contract V5 smoke (docs/plans/01-infra.md 8.3 G2 'V5 스모크 단계' 1–9): the
// real modules over the real CORE (in memory), INK, PDF and feature packages,
// through the production screens. Steps 3–8 are shared with the Chrome V6
// test (test/support/smoke_scenario.dart). Skipped by default
// (app/dart_test.yaml); run in the integration stage with
// `ws test --run-skipped -t integration`.

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/modules/core_module.dart';

import '../support/smoke_scenario.dart';

void main() {
  testWidgets('V5: real modules → library → new note → one stroke → undo / '
      'redo → close → reopen keeps it; same banner on both screens', (
    tester,
  ) async {
    // 1. Real modules; CORE in memory. Every 7.3.3 override once, real.
    final app = await bootSmokeApp(
      tester,
      CoreModule(configFor: (_) => const NoteStoreConfig(inMemory: true)),
    );
    expectContractOverrides(app);

    // 2. In-memory CORE: nativeMemory → notDurable (contract 7.2.12 v1.1).
    final info = app.container.read(storageInfoProvider);
    expect(info.backend, StorageBackend.nativeMemory);
    expect(
      storageWarningOf(info, app.store.persistenceStatus),
      StorageWarning.notDurable,
    );

    // 3–8. Both screens show the fixed notDurable sentence once.
    await runSmokeScenario(tester, app, banner: findsOneWidget);
    expect(app.errorLog.totalCount, 0, reason: '${app.errorLog}');

    // 9. Clean-up.
    await app.shutdown(tester);
  });
}
