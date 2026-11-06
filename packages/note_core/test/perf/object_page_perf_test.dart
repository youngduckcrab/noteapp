// CORE T37 — PF-1 and PF-2 (m5-7/02-core 6.19) on a file database: openPage of a page with
// 2,000 page objects and 2,000 strokes (query + decode of both, ≤ 400 ms — the 1st-round
// 2,000-stroke budget of 300 ms plus the objects) and execute(UpdateObjects, 1 object) on a
// page with 2,000 objects (in-memory update, mean ≤ 2 ms).
@TestOn('vm')
@Tags(['perf'])
library;

import 'package:note_core/dev_tools.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import 'perf_support.dart';

/// 2,000 objects in a 40 × 50 grid on an A4 page: shapes of every kind, text boxes, math
/// and unknown objects (the four JSON shapes of the page_objects rows).
List<PageObject> _objects(PageId pageId, {int count = 2000}) => [
  for (var i = 0; i < count; i++)
    () {
      final x = 10.0 + (i % 40) * 14;
      final y = 10.0 + (i ~/ 40) * 16;
      final rect = PageRect(x, y, x + 12, y + 14);
      return switch (i % 4) {
        0 => PageObjectFixtures.shape(
          pageId: pageId,
          kind: ShapeKind.values[(i ~/ 4) % ShapeKind.values.length],
          rect: rect,
          createdAt: 1 + i,
        ),
        1 => PageObjectFixtures.textBox(
          pageId: pageId,
          text: '텍스트 $i text',
          rect: rect,
          createdAt: 1 + i,
        ),
        2 => PageObjectFixtures.math(
          pageId: pageId,
          latex: '\\frac{$i}{b}',
          rect: rect,
          createdAt: 1 + i,
        ),
        _ => PageObjectFixtures.unknown(pageId: pageId, rect: rect),
      };
    }(),
];

/// A note of [pages] pages with 2,000 strokes each; every page also gets [objects] objects
/// (written through a session, committed and flushed).
Future<NoteId> _seed(
  NoteStore store, {
  int pages = 1,
  int objects = 2000,
}) async {
  final noteId = await seedSyntheticNote(
    store,
    pages: pages,
    strokesPerPage: 2000,
  );
  final session = await store.openSession(noteId);
  for (final page in session.pages) {
    await session.openPage(page.id);
    final receipt = session.execute(
      AddObjects(
        pageId: page.id,
        objects: _objects(page.id, count: objects),
      ),
    );
    await receipt.persisted;
    session.closePage(page.id);
  }
  await session.close();
  await store.flush();
  return noteId;
}

void main() {
  test(
    'PF-1: openPage of a page with 2,000 objects + 2,000 strokes ≤ 400 ms',
    () async {
      final store = await openFileStore(await tempDatabasePath('pf1'));
      final noteId = await _seed(store, pages: 2);
      final runs = <Duration>[];
      for (var r = 0; r < 3; r++) {
        // A new session each time: nothing of the note is cached.
        final session = await store.openSession(noteId);
        final pageId = session.pages[r.isEven ? 0 : 1].id;
        final (content, time) = await timed(() => session.openPage(pageId));
        expect(content.strokeCount, 2000);
        expect(content.objects, hasLength(2000));
        runs.add(time);
        session.closePage(pageId);
        await session.close();
      }
      record(
        'PF-1 openPage 2,000 objects + 2,000 strokes (median of 3)',
        median(runs),
        budget: const Duration(milliseconds: 400),
        note: 'runs ${[for (final r in runs) ms(r)]}',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('PF-2: execute(UpdateObjects 1 object) on a page with 2,000 objects: mean ≤ 2 ms', () async {
    final store = await openFileStore(await tempDatabasePath('pf2'));
    final noteId = await _seed(store);
    final session = await store.openSession(noteId);
    addTearDown(session.close);
    final pageId = session.pages.single.id;
    final content = await session.openPage(pageId);
    final boxes = content.objects.whereType<TextBoxObject>().toList();
    expect(boxes, hasLength(500));
    final times = <Duration>[];
    for (var i = 0; i < 120; i++) {
      final box = boxes[i % boxes.length];
      final edited = box.copyWith(text: '${box.text} · $i');
      final sw = Stopwatch()..start();
      session.execute(UpdateObjects(pageId: pageId, objects: [edited]));
      sw.stop();
      if (i >= 20) times.add(sw.elapsed); // the first 20 warm up
      // Let the write queue commit in between, as while typing.
      await Future<void>.delayed(Duration.zero);
    }
    final after = session.pageIfLoaded(pageId)!;
    expect(after.objects, hasLength(2000));
    expect(
      (after.objectById(boxes[119 % boxes.length].id)! as TextBoxObject).text,
      endsWith('· 119'),
    );
    await store.flush();
    record(
      'PF-2 execute UpdateObjects(1) on 2,000 objects (mean of 100)',
      mean(times),
      budget: const Duration(milliseconds: 2),
      note: 'median ${ms(median(times))} ms',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
