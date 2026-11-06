// CORE T10 — NoteContentReader of the SQLite store (4.5): reads outside sessions
// (PDF export, thumbnails). getPage: active page → value, deleted / missing → null. (v2.0,
// CORE T27) loadPage fills objects: active ones of that page, Stroke.compareOrder
// (m5-7/02-core 6.5).
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

  test('(v2.0) loadPage: the committed active objects of that page in '
      'Stroke.compareOrder, next to its strokes', () async {
    final note = await store.library.createNote(
      title: 'n',
      pages: const [PageDraft.blankA4, PageDraft.blankA4],
    );
    final session = await store.openSession(note.id);
    addTearDown(session.close);
    final ids = [for (final p in session.pages) p.id];
    for (final id in ids) {
      await session.openPage(id);
    }
    await session
        .execute(
          CompositeCommand([
            AddStrokes(
              pageId: ids[0],
              strokes: [
                StrokeFixtures.synthetic(pageId: ids[0], ids: store.ids),
              ],
            ),
            AddObjects(
              pageId: ids[0],
              objects: [
                PageObjectFixtures.math(pageId: ids[0], id: 'm', createdAt: 30),
                PageObjectFixtures.textBox(
                  pageId: ids[0],
                  id: 't',
                  createdAt: 20,
                ),
                PageObjectFixtures.shape(
                  pageId: ids[0],
                  id: 's',
                  createdAt: 20,
                ),
                PageObjectFixtures.unknown(pageId: ids[0], id: 'u'),
              ],
            ),
            AddObjects(
              pageId: ids[1],
              objects: [PageObjectFixtures.shape(pageId: ids[1], id: 'other')],
            ),
          ]),
        )
        .persisted;
    await session
        .execute(RemoveElements(pageId: ids[0], elementIds: ['m']))
        .persisted;
    final content = await reader.loadPage(ids[0]);
    // createdAt, then id (Stroke.compareOrder): u (1), s (20), t (20).
    expect([for (final o in content.objects) o.id], ['u', 's', 't']);
    expect(content.strokes, hasLength(1));
    expect(content.objectById('other'), isNull);
    expect(content.objectById('m'), isNull);
    final shown = session.pageIfLoaded(ids[0])!;
    for (final o in content.objects) {
      expect(o, shown.objectById(o.id), reason: o.id);
      expect(o.version, shown.objectById(o.id)!.version, reason: o.id);
    }
    expect(
      [for (final o in (await reader.loadPage(ids[1])).objects) o.id],
      ['other'],
    );
  });
}
