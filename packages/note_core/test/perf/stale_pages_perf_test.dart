// CORE T32 — m5-7/02-core 6.19 PF-6 and PF-11 (6.9.3, file database, no covering index):
// PF-6: stalePages of a 20-page × 1,000-stroke note — the first call (every page's ink_rev
// computed) ≤ 150 ms, then with one changed page ≤ 10 ms (median).
// PF-11: a 100,000-stroke library (50 notes × 100 pages × 20 strokes; 3 of the notes with long
// strokes — about 5 % of the strokes with ~6 KB points) after reopening: the first catch-up
// (notesWithStalePages + stalePages of every listed note) ≤ 1.5 s, then notesWithStalePages
// ≤ 30 ms (median). Over budget → re-check 6.9.3 (the covering index).
@TestOn('vm')
@Tags(['perf'])
library;

import 'package:note_core/dev_tools.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart' show StrokeFixtures;
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

import 'perf_support.dart';

void main() {
  test(
    'PF-6: stalePages 20 × 1,000 strokes — first ≤ 150 ms, one page ≤ 10 ms',
    () async {
      final path = await tempDatabasePath('stale6');
      final seeding = await openTestNoteStore(filePath: path);
      final (noteId, seedTime) = await timed(
        () => seedSyntheticNote(
          seeding,
          title: 'pf6',
          pages: 20,
          strokesPerPage: 1000,
          pointsPerStroke: 60,
        ),
      );
      await seeding.close();
      record('PF-6 seed 20 × 1,000 strokes (60 points)', seedTime);

      final store = await openFileStore(path);
      // Warm the code paths (the SQL join and the hash of a full page) on another note first.
      final warm = await seedSyntheticNote(
        store,
        title: 'warm-up',
        pages: 2,
        strokesPerPage: 1000,
        pointsPerStroke: 10,
      );
      await store.handwriting.stalePages(warm);

      final (first, firstTime) = await timed(
        () => store.handwriting.stalePages(noteId),
      );
      expect(first, hasLength(20));
      record(
        'PF-6 first stalePages (20 pages, 20,000 strokes)',
        firstTime,
        budget: const Duration(milliseconds: 150),
      );

      final (_, cachedTime) = await timed(
        () => store.handwriting.stalePages(noteId),
      );
      record('PF-6 stalePages, cache fresh', cachedTime);

      final session = await store.openSession(noteId);
      final pageId = session.pages[7].id;
      await session.openPage(pageId);
      final times = <Duration>[];
      for (var i = 0; i < 9; i++) {
        await session
            .execute(
              AddStrokes(
                pageId: pageId,
                strokes: [
                  StrokeFixtures.synthetic(
                    pageId: pageId,
                    ids: store.ids,
                    seed: 500 + i,
                    createdAt: i,
                  ),
                ],
              ),
            )
            .persisted;
        final (stale, t) = await timed(
          () => store.handwriting.stalePages(noteId),
        );
        expect(stale, hasLength(20));
        times.add(t);
      }
      await session.close();
      record(
        'PF-6 stalePages with one changed page (median of 9)',
        median(times),
        budget: const Duration(milliseconds: 10),
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'PF-11: 100,000-stroke library — catch-up ≤ 1.5 s, then ≤ 30 ms',
    () async {
      final path = await tempDatabasePath('stale11');
      final seeding = await openTestNoteStore(filePath: path);
      final sw = Stopwatch()..start();
      for (var i = 0; i < 50; i++) {
        await seedSyntheticNote(
          seeding,
          title: 'pf11-$i',
          pages: 100,
          strokesPerPage: 20,
          // Notes 0–2: long strokes (~6 KB of points, overflow pages), the rest short.
          pointsPerStroke: i < 3 ? 1200 : 40,
          seed: i + 1,
        );
      }
      await seeding.flush();
      sw.stop();
      await seeding.close();
      record('PF-11 seed 50 × 100 pages × 20 strokes', sw.elapsed);

      // Warm the code paths on another (in-memory) store first.
      final warmStore = await openTestNoteStore();
      final warm = await seedSyntheticNote(
        warmStore,
        title: 'warm-up',
        pages: 3,
        strokesPerPage: 1000,
        pointsPerStroke: 10,
      );
      await warmStore.handwriting.notesWithStalePages();
      await warmStore.handwriting.stalePages(warm);
      await warmStore.close();

      final store = await openFileStore(path);
      final (caught, catchUp) = await timed(() async {
        final notes = await store.handwriting.notesWithStalePages();
        var pages = 0;
        for (final n in notes) {
          pages += (await store.handwriting.stalePages(n)).length;
        }
        return (notes.length, pages);
      });
      expect(caught, (50, 5000));
      record(
        'PF-11 first catch-up (notesWithStalePages + 50 × stalePages)',
        catchUp,
        budget: const Duration(milliseconds: 1500),
      );

      final times = <Duration>[];
      for (var i = 0; i < 9; i++) {
        final (notes, t) = await timed(
          () => store.handwriting.notesWithStalePages(),
        );
        expect(notes, hasLength(50));
        times.add(t);
      }
      record(
        'PF-11 notesWithStalePages after the catch-up (median of 9)',
        median(times),
        budget: const Duration(milliseconds: 30),
      );
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
