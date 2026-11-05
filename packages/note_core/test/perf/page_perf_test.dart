// CORE T18 — 9.1 budgets on dense pages (file database): openPage of a 2,000-stroke
// page (query + decode, < 300 ms) and execute(AddStrokes, 1 stroke) on a 5,000-stroke
// page (in-memory update, mean < 2 ms).
@TestOn('vm')
@Tags(['perf'])
library;

import 'package:note_core/dev_tools.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import 'perf_support.dart';

void main() {
  test('openPage of a 2,000-stroke page < 300 ms', () async {
    final store = await openFileStore(await tempDatabasePath('page2k'));
    final noteId = await seedSyntheticNote(
      store,
      pages: 2,
      strokesPerPage: 2000,
    );
    await store.flush();
    final runs = <Duration>[];
    for (var r = 0; r < 3; r++) {
      // A new session each time: nothing of the note is cached.
      final session = await store.openSession(noteId);
      final pageId = session.pages[r.isEven ? 0 : 1].id;
      final (content, time) = await timed(() => session.openPage(pageId));
      expect(content.strokeCount, 2000);
      runs.add(time);
      session.closePage(pageId);
      await session.close();
    }
    record(
      'openPage 2,000 strokes (median of 3)',
      median(runs),
      budget: const Duration(milliseconds: 300),
      note: 'runs ${[for (final r in runs) ms(r)]}',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test(
    'execute(AddStrokes 1 stroke) on a 5,000-stroke page: mean < 2 ms',
    () async {
      final store = await openFileStore(await tempDatabasePath('page5k'));
      final noteId = await seedSyntheticNote(
        store,
        pages: 1,
        strokesPerPage: 5000,
      );
      final session = await store.openSession(noteId);
      addTearDown(session.close);
      final pageId = session.pages.single.id;
      await session.openPage(pageId);
      final strokes = [
        for (var i = 0; i < 120; i++)
          StrokeFixtures.synthetic(
            pageId: pageId,
            ids: store.ids,
            seed: 100000 + i,
          ),
      ];
      final times = <Duration>[];
      for (var i = 0; i < strokes.length; i++) {
        final sw = Stopwatch()..start();
        session.execute(AddStrokes(pageId: pageId, strokes: [strokes[i]]));
        sw.stop();
        if (i >= 20) times.add(sw.elapsed); // the first 20 warm up
        // Let the write queue commit in between, as while drawing.
        await Future<void>.delayed(Duration.zero);
      }
      expect(session.pageIfLoaded(pageId)!.strokeCount, 5120);
      record(
        'execute AddStrokes(1) on 5,000 strokes (mean of 100)',
        mean(times),
        budget: const Duration(milliseconds: 2),
        note: 'median ${ms(median(times))} ms',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
