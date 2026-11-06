// Shared body (m5-7/02-core 6.5, 6.4.2 — N-1..N-6 with page objects): synchronous apply,
// PageContentChange ids of strokes AND objects, re-entry, page not open, read-only, a shared
// session, reload after reopen, NoteContentReader.loadPage objects. The fake store runs it now
// (test/session/object_session_contract_fake_test.dart); the real store from CORE T27.
// Web-safe.
import 'dart:async';

import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

void defineObjectSessionContract(FutureOr<NoteStore> Function() open) {
  late NoteStore store;
  late Note note;
  late NoteSession session;
  late PageId pageId;

  setUp(() async {
    store = await open();
    note = await store.library.createNote(
      title: 'objects',
      pages: const [PageDraft.blankA4, PageDraft.blankA4],
    );
    session = await store.openSession(note.id);
    pageId = session.pages.first.id;
    await session.openPage(pageId);
  });

  tearDown(() async {
    if (!session.isClosed) await session.close();
    await store.close();
  });

  TextBoxObject text(String id, {String body = '회의록', int createdAt = 2}) =>
      TextBoxObject(
        id: id,
        pageId: pageId,
        frame: const ElementFrame(PageRect(10, 10, 210, 50)),
        text: body,
        style: const TextBoxStyle(),
        createdAt: createdAt,
      );

  test('N-1: applied synchronously; the change names the object ids', () async {
    final changes = <PageContentChange>[];
    final sub = session.pageChanges(pageId).listen(changes.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(Duration.zero); // the load change
    changes.clear();
    final stroke = StrokeFixtures.synthetic(pageId: pageId, ids: store.ids);
    final receipt = session.execute(
      CompositeCommand([
        AddStrokes(pageId: pageId, strokes: [stroke]),
        AddObjects(pageId: pageId, objects: [text('t1')]),
      ]),
    );
    // Before any await: memory and the change event.
    final content = session.pageIfLoaded(pageId)!;
    expect(content.objectById('t1'), isA<TextBoxObject>());
    expect(content.elementById(stroke.id), isA<Stroke>());
    expect(changes.single.added, {'t1', stroke.id});
    expect(changes.single.origin, ChangeOrigin.local);
    expect(receipt.edit.insertedElementIds, [stroke.id, 't1']);
    await receipt.persisted;

    session.execute(
      UpdateObjects(
        pageId: pageId,
        objects: [text('t1', body: '바뀜')],
      ),
    );
    expect(changes.last.updated, {'t1'});
    session.execute(RemoveElements(pageId: pageId, elementIds: ['t1']));
    expect(changes.last.removed, {'t1'});
    expect(session.pageIfLoaded(pageId)!.objects, isEmpty);
    await session.undo();
    expect(changes.last.added, {'t1'});
    expect(changes.last.origin, ChangeOrigin.undo);
  });

  test('N-2: execute from a listener is a StateError', () async {
    Object? error;
    final sub = session.pageChanges(pageId).listen((c) {
      if (c.origin != ChangeOrigin.local) return;
      try {
        session.execute(AddObjects(pageId: pageId, objects: [text('t3')]));
      } on StateError catch (e) {
        error = e;
      }
    });
    addTearDown(sub.cancel);
    await session
        .execute(AddObjects(pageId: pageId, objects: [text('t2')]))
        .persisted;
    expect(error, isA<StateError>());
    expect(session.pageIfLoaded(pageId)!.objectById('t3'), isNull);
  });

  test('N-3: a page that is not open', () {
    final other = session.pages.last.id;
    expect(
      () => session.execute(
        AddObjects(
          pageId: other,
          objects: [text('x').copyTo(id: 'x', pageId: other, createdAt: 1)],
        ),
      ),
      throwsA(isA<PageNotOpenException>()),
    );
  });

  test('N-4: a trashed note is read-only', () async {
    await store.library.trashItems([NoteRef(note.id)]);
    await Future<void>.delayed(Duration.zero);
    expect(session.isReadOnly, isTrue);
    expect(
      () => session.execute(AddObjects(pageId: pageId, objects: [text('t4')])),
      throwsA(isA<ReadOnlyNoteException>()),
    );
  });

  test('N-5: a second openSession shares the objects', () async {
    await session
        .execute(AddObjects(pageId: pageId, objects: [text('t5')]))
        .persisted;
    final again = await store.openSession(note.id);
    expect(again.pageIfLoaded(pageId)!.objectById('t5'), isNotNull);
    await again.close();
  });

  test(
    'reopen and the content reader: objects come back from the store',
    () async {
      await session
          .execute(
            AddObjects(
              pageId: pageId,
              objects: [
                text('late', createdAt: 9),
                text('early', createdAt: 1),
              ],
            ),
          )
          .persisted;
      await session.close();
      final reopened = await store.openSession(note.id);
      addTearDown(reopened.close);
      final content = await reopened.openPage(pageId);
      expect(content.objects.map((o) => o.id), ['early', 'late']);
      expect(content.objects.first.version, isNotNull);
      final read = await store.content.loadPage(pageId);
      expect(read.objects.map((o) => o.id), ['early', 'late']);
      expect(read.objectById('late'), content.objectById('late'));
    },
  );

  test(
    'PageDraft.copyOf + InsertPages and DuplicatePages copy the objects',
    () async {
      await session
          .execute(
            AddObjects(pageId: pageId, objects: [text('src', createdAt: 7)]),
          )
          .persisted;
      final draft = PageDraft.copyOf(session.pageIfLoaded(pageId)!);
      expect(draft.objects.single.id, 'src');
      final inserted = session.execute(
        InsertPages(drafts: [draft], position: const PageAtEnd()),
      );
      await inserted.persisted;
      final newPage = inserted.edit.insertedPageIds.single;
      final copy = (await session.openPage(newPage)).objects.single;
      expect(copy.id, isNot('src'));
      expect(copy.createdAt, 7);
      expect((copy as TextBoxObject).text, '회의록');
      final dup = session.execute(DuplicatePages(pageIds: [pageId]));
      await dup.persisted;
      final dupPage = dup.edit.insertedPageIds.single;
      expect((await session.openPage(dupPage)).objects.single.createdAt, 7);
    },
  );
}
