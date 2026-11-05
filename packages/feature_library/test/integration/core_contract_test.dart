// Real-CORE contract test (05-library 8 L21, LIBRARY-S4; contract 7.7 step
// 5). Integration stage only: dart_test.yaml skips the `integration` tag;
// run with `ws test --run-skipped -t integration`. Written ahead during the
// concurrent stage, when openTestNoteStore was still B2's UnimplementedError;
// the integration stage ran it on the merged CORE and only had to change how
// the store is closed (close() below — 11절, LIBRARY-2-6).
//  ① the shared scenarios without fault injection (needsFaults == false) on
//    openTestNoteStore(storageInfo: nativeFile) — no banner, same layout as
//    the fake; the store is opened inside tester.runAsync and closed by
//    close() (fake time and real event-loop turns in turn).
//  ② the default openTestNoteStore() (memory = nativeMemory) shows the
//    notDurable banner without any write (contract 7.2.12, 7.6 C11-12).
@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:async';

import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/ui/banners/storage_warning_banner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing_vm.dart';

import '../shared/library_scenarios.dart';
import '../support/fake_library_backend.dart';
import '../support/library_test_harness.dart';

/// Fake-time / real-loop turns close() may take before the test fails.
const int _closeTurns = 500;

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
  ///
  /// Real CORE keeps page thumbnails in an in-memory IndexedDB (idb_shim over
  /// sembast) whose work waits on zero / 100 µs timers in the zone that
  /// started it, and on locks held by work of the other zone. A thumbnail read
  /// a cover started in the fake-async zone can still wait on such a timer
  /// after pumpAndSettle, and store.close() waits for every cache operation:
  /// inside runAsync alone it never finished (the 200-character copy
  /// scenario). So close() starts in the test zone and the test alternates
  /// fake time and real event-loop turns until it has finished — bounded, as
  /// in EDITOR E-21 — which also leaves no fake timer behind.
  Future<void> close(WidgetTester tester, FakeLibraryBackend backend) async {
    await tester.pumpWidget(const SizedBox());
    var done = false;
    Object? error;
    StackTrace? stack;
    unawaited(
      backend.dispose().then<void>(
        (_) => done = true,
        onError: (Object e, StackTrace s) =>
            (error, stack, done) = (e, s, true),
      ),
    );
    for (var i = 0; i < _closeTurns && !done; i++) {
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    if (error case final e?) Error.throwWithStackTrace(e, stack!);
    expect(done, isTrue, reason: 'store.close() did not finish');
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
