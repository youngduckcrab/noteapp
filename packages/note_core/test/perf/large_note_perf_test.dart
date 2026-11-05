// CORE T18 — 9.1 budgets on a 100,000-stroke note (500 pages x 200 strokes x 100
// points, seeded with seedSyntheticNote, file database): the seed time (record only)
// and openSession of that note after reopening (page metadata only, < 200 ms).
@TestOn('vm')
@Tags(['perf'])
library;

import 'package:note_core/dev_tools.dart';
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

import 'perf_support.dart';

void main() {
  test('100,000-stroke note: seed (record), openSession < 200 ms', () async {
    final path = await tempDatabasePath('large');
    final seeding = await openTestNoteStore(filePath: path);
    final (noteId, seedTime) = await timed(() async {
      final id = await seedSyntheticNote(
        seeding,
        title: 'large',
        pages: 500,
        strokesPerPage: 200,
        pointsPerStroke: 100,
      );
      await seeding.flush();
      return id;
    });
    await seeding.close();
    record('seed 100,000 strokes (500 x 200, 100 points)', seedTime);

    final store = await openFileStore(path);
    // Warm the code paths on another (small) note first.
    final warm = await store.library.createNote(title: 'warm-up');
    await (await store.openSession(warm.id)).close();

    final (session, openTime) = await timed(() => store.openSession(noteId));
    expect(session.pages, hasLength(500));
    expect(session.pageIfLoaded(session.pages.first.id), isNull);
    record(
      'openSession of the 100,000-stroke note',
      openTime,
      budget: const Duration(milliseconds: 200),
    );
    await session.close();
  }, timeout: const Timeout(Duration(minutes: 20)));
}
