// CORE T18 — 9.1 budget: one stroke enqueued → committed on a file database (WAL,
// synchronous = NORMAL), median < 30 ms. (v2, m5-7 T35) The store is the one openNoteStore
// gives the native app: both native paths (file database in the background isolate + file
// blobs, 6.15.3).
@TestOn('vm')
@Tags(['perf'])
library;

import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import 'perf_support.dart';

void main() {
  test('one stroke enqueue → commit (file database): median < 30 ms', () async {
    final store = await openNativeFileStore('commit');
    final note = await store.library.createNote(title: 'commit');
    final session = await store.openSession(note.id);
    addTearDown(session.close);
    final pageId = session.pages.single.id;
    await session.openPage(pageId);
    final times = <Duration>[];
    final latencies = <Duration>[];
    for (var i = 0; i < 60; i++) {
      final stroke = StrokeFixtures.synthetic(
        pageId: pageId,
        ids: store.ids,
        seed: i,
      );
      final sw = Stopwatch()..start();
      session.execute(AddStrokes(pageId: pageId, strokes: [stroke]));
      await store.flush();
      sw.stop();
      if (i < 10) continue; // warm-up
      times.add(sw.elapsed);
      latencies.add(store.persistenceStatus.lastCommitLatency!);
    }
    record(
      'stroke enqueue → commit (median of 50)',
      median(times),
      budget: const Duration(milliseconds: 30),
      note:
          'PersistenceStatus.lastCommitLatency median '
          '${ms(median(latencies))} ms',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
