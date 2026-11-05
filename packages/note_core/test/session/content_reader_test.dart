// CORE T10 — NoteContentReader of the SQLite store (4.5): reads outside sessions
// (PDF export, thumbnails). getPage: active page → value, deleted / missing → null.
@TestOn('vm')
library;

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../storage/storage_support.dart';

void main() {
  late DriftNoteStore store;
  late NoteContentReader reader;
  setUp(() async {
    store = await openStore();
    reader = store.content;
  });
  tearDown(() => store.close());

  test('getPage: active page → value (with the local contentRevision), deleted '
      'or missing → null', () async {
    final note = await store.library.createNote(
      title: 'n',
      pages: const [PageDraft.blankA4, PageDraft.blankA4],
    );
    final session = await store.openSession(note.id);
    addTearDown(session.close);
    final pages = session.pages;
    await session.openPage(pages[0].id);
    await session
        .execute(
          AddStrokes(
            pageId: pages[0].id,
            strokes: [
              StrokeFixtures.synthetic(pageId: pages[0].id, ids: store.ids),
            ],
          ),
        )
        .persisted;
    final active = (await reader.getPage(pages[0].id))!;
    expect(active.id, pages[0].id);
    expect(active.noteId, note.id);
    expect(active.contentRevision, 1);
    await session.execute(DeletePages(pageIds: [pages[1].id])).persisted;
    expect(await reader.getPage(pages[1].id), isNull);
    expect(await reader.getPage('no-such-page'), isNull);
  });

  test('pagesOf: active pages in order; loadPage: committed strokes', () async {
    final note = await store.library.createNote(
      title: 'n',
      pages: const [PageDraft.blankA4, PageDraft.blankA4, PageDraft.blankA4],
    );
    final session = await store.openSession(note.id);
    addTearDown(session.close);
    final ids = [for (final p in session.pages) p.id];
    await session
        .execute(MovePages(pageIds: [ids[2]], position: const PageAtStart()))
        .persisted;
    expect(
      [for (final p in await reader.pagesOf(note.id)) p.id],
      [ids[2], ids[0], ids[1]],
    );
    await session.openPage(ids[0]);
    final strokes = [
      for (var i = 0; i < 3; i++)
        StrokeFixtures.synthetic(
          pageId: ids[0],
          ids: store.ids,
          seed: i,
          createdAt: 10 + i,
        ),
    ];
    await session
        .execute(AddStrokes(pageId: ids[0], strokes: strokes))
        .persisted;
    final content = await reader.loadPage(ids[0]);
    expect(
      [for (final s in content.strokes) s.id],
      [for (final s in strokes) s.id],
    );
    expect(content.page.id, ids[0]);
    expect((await reader.loadPage(ids[1])).strokes, isEmpty);
  });
}
