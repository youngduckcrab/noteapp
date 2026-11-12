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
//  ③ (v2, 05-library 8.3 L2-I2) the '노트 내용' group on real CORE: the same
//    seed (seedContentHits — text boxes, math, handwriting, a pdf unit) on the
//    fake and on openTestNoteStore() gives the same hits in the same order
//    (source, page, snippet, match range, rects) and the same note groups
//    (groupContentHits), for queries that reach every source.
@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:async';

import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/model/content_hits.dart';
import 'package:feature_library/src/ui/banners/storage_warning_banner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing_vm.dart';

import '../shared/library_scenarios.dart';
import '../support/fake_library_backend.dart';
import '../support/fixtures.dart';
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

  group('(v2) L2-I2 content search on real CORE = fake', () {
    /// Queries that together reach every source of seedContentHits.
    const queries = ['회의', 'frac', '정리', '예산', '분기 회의', '할 일'];

    /// A hit with ids replaced by note title and 1-based page index (ids are
    /// store-generated); score is left out (it only orders — CP-14).
    Future<List<String>> describe(NoteStore store, String query) async {
      final result = await store.library.searchLibrary(query);
      final titles = <NoteId, String>{};
      final pageIndex = <PageId, int>{};
      Future<void> know(NoteId id) async {
        if (titles.containsKey(id)) return;
        titles[id] = (await store.library.getNote(id))!.title;
        for (final (i, p) in (await store.content.pagesOf(id)).indexed) {
          pageIndex[p.id] = i + 1;
        }
      }

      final out = <String>[];
      for (final g in groupContentHits(result.pages)) {
        await know(g.noteId);
        out.add('group ${titles[g.noteId]}');
        for (final h in g.hits) {
          expect(h.noteId, g.noteId);
          out.add(
            '  p${pageIndex[h.pageId]} ${h.source.name} "${h.snippet}" '
            '${h.matchRange} '
            '${[for (final r in h.rects) '(${r.left},${r.top},${r.right},${r.bottom})']}',
          );
        }
      }
      return out;
    }

    test('same hits, same order, same groups', () async {
      final fake = FakeLibraryBackend();
      final real = await FakeLibraryBackend.overStore(
        (clock) => openTestNoteStore(
          clock: clock,
          storageInfo: const StorageInfo(backend: StorageBackend.nativeFile),
        ),
      );
      try {
        await seedContentHits(fake);
        await seedContentHits(real);
        final sources = <SearchSource>{};
        for (final q in queries) {
          final want = await describe(fake.store, q);
          final got = await describe(real.store, q);
          expect(want, isNotEmpty, reason: q);
          expect(got, want, reason: 'query "$q"');
          final result = await real.store.library.searchLibrary(q);
          sources.addAll(result.pages.map((h) => h.source));
        }
        // Every content source was compared at least once.
        expect(sources, {
          SearchSource.text,
          SearchSource.math,
          SearchSource.ink,
          SearchSource.pdf,
        });
      } finally {
        await fake.dispose();
        await real.dispose();
      }
    });
  });
}
