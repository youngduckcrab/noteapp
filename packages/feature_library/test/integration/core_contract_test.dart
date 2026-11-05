// Real-CORE contract test (05-library 8 L21, LIBRARY-S4; contract 7.7 step
// 5). Integration stage only: dart_test.yaml skips the `integration` tag;
// run with `ws test --run-skipped -t integration`. Written ahead during the
// concurrent stage, when openTestNoteStore was still B2's UnimplementedError
// — the integration stage runs it and tunes runAsync where real drift timers
// need it (11절, LIBRARY-2-6).
//  ① the shared scenarios without fault injection (needsFaults == false) on
//    openTestNoteStore(storageInfo: nativeFile) — no banner, same layout as
//    the fake; the store is opened and closed inside tester.runAsync.
//  ② the default openTestNoteStore() (memory = nativeMemory) shows the
//    notDurable banner without any write (contract 7.2.12, 7.6 C11-12).
@Tags(['integration'])
@TestOn('vm')
library;

import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/ui/banners/storage_warning_banner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing_vm.dart';

import '../shared/library_scenarios.dart';
import '../support/fake_library_backend.dart';
import '../support/library_test_harness.dart';

void main() {
  /// Opens real CORE inside runAsync (its drift timers live outside the fake
  /// time zone).
  Future<FakeLibraryBackend> open(
    WidgetTester tester, {
    StorageInfo? storageInfo,
  }) async => (await tester.runAsync(
    () => FakeLibraryBackend.overStore(
      (clock) => openTestNoteStore(clock: clock, storageInfo: storageInfo),
    ),
  ))!;

  /// The screen first (its CORE subscriptions end), then store.close().
  Future<void> close(WidgetTester tester, FakeLibraryBackend backend) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(backend.dispose);
  }

  group('shared scenarios on real CORE (nativeFile)', () {
    for (final scenario in libraryScenarios.where((s) => !s.needsFaults)) {
      testWidgets(scenario.name, (tester) async {
        final backend = await open(
          tester,
          storageInfo: const StorageInfo(backend: StorageBackend.nativeFile),
        );
        expect(backend.faults, isNull);
        try {
          await scenario.body(tester, LibraryTestHarness(backend));
        } finally {
          await close(tester, backend);
        }
      });
    }
  });

  testWidgets('default openTestNoteStore(): notDurable banner, no write', (
    tester,
  ) async {
    final backend = await open(tester);
    try {
      await LibraryTestHarness(backend).pump(tester);
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(StorageWarningBanner),
          matching: find.text(LibraryStrings.storageNotDurable),
        ),
        findsOneWidget,
      );
      expect(backend.calls, isEmpty);
    } finally {
      await close(tester, backend);
    }
  });
}
