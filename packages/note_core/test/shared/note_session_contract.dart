// Shared body of the NoteSession contract (00-overview 7.2.8 N-1..N-6, CORE 9.1). Runs on
// createFakeNoteStore() now (test/session/note_session_contract_fake_test.dart) and on
// openTestNoteStore() from CORE T10 (+ N-7 there).
import 'dart:async';

import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

typedef StoreFactory = FutureOr<NoteStore> Function();

void defineNoteSessionContractTests(StoreFactory open) {
  late NoteStore store;
  late Note note;
  late NoteSession session;

  setUp(() async {
    store = await open();
    note = await store.library.createNote(
      title: 'contract',
      pages: const [PageDraft.blankA4, PageDraft.blankA4, PageDraft.blankA4],
    );
    session = await store.openSession(note.id);
  });

  tearDown(() async {
    if (!session.isClosed) await session.close();
    await store.close();
  });

  Stroke strokeOn(PageId pageId, {int seed = 0}) => StrokeFixtures.synthetic(
    pageId: pageId,
    ids: store.ids,
    seed: seed,
    createdAt: 1000 + seed,
  );

  group('N-1 synchronous apply + synchronous delivery', () {
    test(
      'listeners run before execute returns; state is new on return',
      () async {
        final page = session.pages.first;
        await session.openPage(page.id);
        final events = <String>[];
        final subs = [
          session
              .pageChanges(page.id)
              .listen((c) => events.add('page:${c.origin.name}')),
          session.pagesStream.listen((_) => events.add('pages')),
          session.historyStream.listen((_) => events.add('history')),
          session.noteStream.listen((_) => events.add('note')),
        ];
        // pageChanges delivers the `load` change right after listen.
        await Future<void>.value();
        expect(events, ['page:load']);
        events.clear();
        final s = strokeOn(page.id);
        final receipt = session.execute(
          AddStrokes(pageId: page.id, strokes: [s]),
        );
        // No await between execute and these checks.
        expect(events, containsAll(['page:local', 'pages', 'history']));
        expect(session.pageIfLoaded(page.id)!.strokeById(s.id), isNotNull);
        expect(session.history.undoDepth, 1);
        expect(session.history.canUndo, isTrue);
        expect(receipt.edit.insertedElementIds, [s.id]);
        await receipt.persisted;
        for (final sub in subs) {
          await sub.cancel();
        }
      },
    );

    test(
      'pagesStream: AddStrokes bumps contentRevision of that page only (v1.1)',
      () async {
        final pagesBefore = session.pages;
        final target = pagesBefore[1];
        await session.openPage(target.id);
        List<Page>? emitted;
        final sub = session.pagesStream.listen((p) => emitted = p);
        session.execute(
          AddStrokes(pageId: target.id, strokes: [strokeOn(target.id)]),
        );
        expect(emitted, isNotNull, reason: 'emitted inside execute');
        expect(emitted![1].id, target.id);
        expect(emitted![1].contentRevision, target.contentRevision + 1);
        expect(identical(emitted![0], pagesBefore[0]), isTrue);
        expect(identical(emitted![2], pagesBefore[2]), isTrue);
        expect(session.pages, emitted);
        expect(
          session.pageIfLoaded(target.id)!.page.contentRevision,
          target.contentRevision + 1,
        );
        await sub.cancel();
      },
    );

    test('the change carries added / removed / updated ids and keeps unchanged objects', () async {
      final page = session.pages.first;
      await session.openPage(page.id);
      final a = strokeOn(page.id, seed: 1);
      final b = strokeOn(page.id, seed: 2);
      session.execute(AddStrokes(pageId: page.id, strokes: [a, b]));
      final changes = <PageContentChange>[];
      final sub = session.pageChanges(page.id).listen(changes.add);
      final before = session.pageIfLoaded(page.id)!;
      session.execute(
        TransformElements(
          pageId: page.id,
          elementIds: [a.id],
          transform: Affine2.translation(1, 0),
        ),
      );
      session.execute(RemoveStrokes(pageId: page.id, strokeIds: [b.id]));
      expect(changes.map((c) => c.origin), [
        ChangeOrigin.load,
        ChangeOrigin.local,
        ChangeOrigin.local,
      ]);
      expect(changes[1].updated, {a.id});
      expect(changes[2].removed, {b.id});
      final after = session.pageIfLoaded(page.id)!;
      expect(after.revision, before.revision + 2);
      expect(after.strokes.map((s) => s.id), [a.id]);
      await sub.cancel();
    });
  });

  group('N-2 order and no re-entrancy', () {
    test('execute inside a listener throws StateError; only the outer command applies', () async {
      final page = session.pages.first;
      await session.openPage(page.id);
      Object? inner;
      final sub = session.historyStream.listen((_) {
        try {
          session.execute(
            AddStrokes(pageId: page.id, strokes: [strokeOn(page.id, seed: 9)]),
          );
        } on Object catch (e) {
          inner = e;
        }
      });
      session.execute(
        AddStrokes(pageId: page.id, strokes: [strokeOn(page.id, seed: 1)]),
      );
      expect(inner, isA<StateError>());
      expect(session.pageIfLoaded(page.id)!.strokeCount, 1);
      expect(session.history.undoDepth, 1);
      await sub.cancel();
    });

    test('a command deferred with scheduleMicrotask succeeds', () async {
      final page = session.pages.first;
      await session.openPage(page.id);
      final done = Completer<void>();
      var scheduled = false;
      final sub = session.historyStream.listen((_) {
        if (scheduled) return;
        scheduled = true;
        scheduleMicrotask(() {
          session.execute(
            AddStrokes(pageId: page.id, strokes: [strokeOn(page.id, seed: 9)]),
          );
          done.complete();
        });
      });
      session.execute(
        AddStrokes(pageId: page.id, strokes: [strokeOn(page.id, seed: 1)]),
      );
      await done.future;
      expect(session.pageIfLoaded(page.id)!.strokeCount, 2);
      await sub.cancel();
    });

    test(
      'undo() and executeAsync() change nothing before their first await',
      () async {
        final page = session.pages.first;
        await session.openPage(page.id);
        session.execute(
          AddStrokes(pageId: page.id, strokes: [strokeOn(page.id)]),
        );
        final undo = session.undo();
        expect(session.pageIfLoaded(page.id)!.strokeCount, 1);
        expect(session.history.undoDepth, 1);
        final result = await undo;
        expect(result.applied, isTrue);
        expect(session.pageIfLoaded(page.id)!.strokeCount, 0);
        final pagesBefore = session.pages;
        final insert = session.executeAsync(
          const InsertPages(drafts: [PageDraft.blankA4], position: PageAtEnd()),
        );
        expect(session.pages, same(pagesBefore));
        final receipt = await insert;
        expect(session.pages.length, pagesBefore.length + 1);
        expect(session.pages.last.id, receipt.edit.insertedPageIds.single);
      },
    );

    test('two consecutive executes apply and notify in call order', () async {
      final page = session.pages.first;
      await session.openPage(page.id);
      final order = <Set<ElementId>>[];
      final sub = session
          .pageChanges(page.id)
          .skip(1)
          .listen((c) => order.add(c.added));
      final a = strokeOn(page.id, seed: 1);
      final b = strokeOn(page.id, seed: 2);
      session
        ..execute(AddStrokes(pageId: page.id, strokes: [a]))
        ..execute(AddStrokes(pageId: page.id, strokes: [b]));
      expect(order, [
        {a.id},
        {b.id},
      ]);
      expect(session.history.undoDepth, 2);
      await sub.cancel();
    });
  });

  group('N-3 pages must be open for stroke commands', () {
    test('AddStrokes on a page that is not loaded → PageNotOpenException', () {
      final page = session.pages[2];
      expect(
        () => session.execute(
          AddStrokes(pageId: page.id, strokes: [strokeOn(page.id)]),
        ),
        throwsA(isA<PageNotOpenException>()),
      );
      expect(session.history.undoDepth, 0);
    });

    test(
      'executeAsync(DuplicatePages) opens the page, then unpins it',
      () async {
        final page = session.pages.first;
        final receipt = await session.executeAsync(
          DuplicatePages(pageIds: [page.id]),
        );
        expect(session.pages, hasLength(4));
        expect(session.pages[1].id, receipt.edit.insertedPageIds.single);
        // Unpinned: closing it again is a no-op, and it can be evicted later.
        session.closePage(page.id);
        expect(
          () => session.execute(const DeletePages(pageIds: [])),
          returnsNormally,
        );
      },
    );

    test('page commands work without loading', () {
      final receipt = session.execute(
        MovePages(
          pageIds: [session.pages.last.id],
          position: const PageAtStart(),
        ),
      );
      expect(receipt.edit.deltas, hasLength(1));
      expect(
        () => session.execute(
          DeletePages(pageIds: [for (final p in session.pages) p.id]),
        ),
        throwsA(isA<LastPageDeletionException>()),
      );
    });
  });

  group('N-4 read-only notes', () {
    test('trashed note: execute / executeAsync / undo / redo throw, nothing is written', () async {
      final page = session.pages.first;
      await session.openPage(page.id);
      session.execute(
        AddStrokes(pageId: page.id, strokes: [strokeOn(page.id)]),
      );
      await session.flush();
      final notes = <Note>[];
      final sub = session.noteStream.listen(notes.add);
      await store.library.trashItems([NoteRef(note.id)]);
      await store.flush();
      expect(session.isReadOnly, isTrue);
      expect(
        notes.last.isDeleted,
        isTrue,
        reason: 'noteStream announces the switch',
      );
      final pages = session.pages;
      final history = session.history;
      expect(
        () => session.execute(
          AddStrokes(pageId: page.id, strokes: [strokeOn(page.id, seed: 3)]),
        ),
        throwsA(isA<ReadOnlyNoteException>()),
      );
      await expectLater(
        session.executeAsync(
          const InsertPages(drafts: [PageDraft.blankA4], position: PageAtEnd()),
        ),
        throwsA(isA<ReadOnlyNoteException>()),
      );
      await expectLater(session.undo(), throwsA(isA<ReadOnlyNoteException>()));
      await expectLater(session.redo(), throwsA(isA<ReadOnlyNoteException>()));
      expect(session.pages, same(pages));
      expect(session.history, history);
      await store.flush();
      expect(store.persistenceStatus.pendingOps, 0);
      // Restored → writable again.
      await store.trash.restore([NoteRef(note.id)]);
      await store.flush();
      expect(session.isReadOnly, isFalse);
      await sub.cancel();
    });
  });

  group('N-5 one session per note, reference-counted', () {
    test(
      'openSession twice = same instance; close() releases one reference',
      () async {
        final again = await store.openSession(note.id);
        expect(identical(again, session), isTrue);
        await again.close();
        expect(session.isClosed, isFalse);
        session.execute(
          MovePages(
            pageIds: [session.pages.last.id],
            position: const PageAtStart(),
          ),
        );
        await session.close();
        expect(session.isClosed, isTrue);
        expect(
          () => session.execute(const DeletePages(pageIds: [])),
          throwsA(isA<SessionClosedException>()),
        );
        final reopened = await store.openSession(note.id);
        expect(identical(reopened, session), isFalse);
        session = reopened;
      },
    );
  });

  group('N-6 recent notes and missing notes', () {
    test('openSession marks the note opened (recent list)', () async {
      await store.flush();
      final recent = await store.library.watchRecentNotes().first;
      expect(recent.map((n) => n.id), contains(note.id));
      expect((await store.library.getNote(note.id))!.lastOpenedAt, isNotNull);
    });

    test('missing note → EntityNotFoundException', () async {
      await expectLater(
        store.openSession('no-such-note'),
        throwsA(isA<EntityNotFoundException>()),
      );
    });
  });
}
