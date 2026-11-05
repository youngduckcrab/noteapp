// CORE T10 — note sessions of the SQLite store beyond the shared contract (6.14): lazy
// page loading, the page cache (LRU 8, pins), rows / outbox / ChangeBatch of session
// writes, read-only openings, and remote changes reaching an open session (N-7).
@TestOn('vm')
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor;
import 'package:drift/native.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/outbox_writer.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../storage/storage_support.dart';

/// Records the arguments of every SELECT on the strokes table.
final class _StrokeQueries extends QueryInterceptor {
  final List<List<Object?>> args = [];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('"strokes"')) this.args.add(args);
    return executor.runSelect(statement, args);
  }
}

const _remoteNode = 'ffffffffffffffff';
var _remoteMs = 1893456000000; // 2030: after every local stamp of these tests

EntityFieldVersions _remoteVersions() =>
    EntityFieldVersions(Hlc(_remoteMs++, 0, _remoteNode));

/// The internal remote write path (applyRemote / commitRepairs, CORE T14).
Future<void> _putRemote(DriftNoteStore store, List<SyncEntity> entities) =>
    store.queue.run((tx) async {
      for (final e in entities) {
        await tx.putRemote(e, _remoteVersions());
      }
    }, origin: ChangeOrigin.remote);

void main() {
  late DriftNoteStore store;
  late Note note;
  late NoteSession session;

  Future<void> openWith({QueryExecutor? executor, int pages = 3}) async {
    store = executor == null
        ? await openStore()
        : await DriftNoteStore.open(
            executor: executor,
            storageInfo: const StorageInfo(
              backend: StorageBackend.nativeMemory,
            ),
            config: NoteStoreConfig(
              inMemory: true,
              seedDefaultPenPresets: false,
              idGenerator: SequentialIdGenerator(),
            ),
            deviceNodeId: kTestNode,
          );
    note = await store.library.createNote(
      title: 'n',
      pages: [for (var i = 0; i < pages; i++) PageDraft.blankA4],
    );
    session = await store.openSession(note.id);
  }

  tearDown(() async {
    if (!session.isClosed) await session.close();
    await store.close();
  });

  Stroke strokeOn(PageId pageId, {int seed = 0}) => StrokeFixtures.synthetic(
    pageId: pageId,
    ids: store.ids,
    seed: seed,
    pointCount: 20,
    createdAt: 1000 + seed,
  );

  Future<List<Stroke>> addStrokes(PageId pageId, int count) async {
    final strokes = [for (var i = 0; i < count; i++) strokeOn(pageId, seed: i)];
    await session
        .execute(AddStrokes(pageId: pageId, strokes: strokes))
        .persisted;
    return strokes;
  }

  group('lazy loading', () {
    test(
      'openSession and openPage query only the strokes of the opened page',
      () async {
        final queries = _StrokeQueries();
        await openWith(
          executor: NativeDatabase.memory().interceptWith(queries),
        );
        final pages = session.pages;
        await session.openPage(pages[1].id);
        await addStrokes(pages[1].id, 2);
        await session.close();
        queries.args.clear();

        session = await store.openSession(note.id);
        expect(queries.args, isEmpty, reason: 'opening reads no stroke');
        final content = await session.openPage(pages[1].id);
        expect(content.strokes, hasLength(2));
        expect(queries.args, isNotEmpty);
        final queried = {for (final a in queries.args) ...a};
        expect(queried, contains(pages[1].id));
        expect(queried, isNot(contains(pages[0].id)));
        expect(queried, isNot(contains(pages[2].id)));
      },
    );

    test('a reopened session reads the committed strokes in order', () async {
      await openWith();
      final page = session.pages.first;
      await session.openPage(page.id);
      final added = await addStrokes(page.id, 3);
      await session.close();
      session = await store.openSession(note.id);
      final content = await session.openPage(page.id);
      expect(
        [for (final s in content.strokes) s.id],
        [for (final s in added) s.id],
      );
      expect(
        content.strokes.first.points.contentEquals(added.first.points),
        isTrue,
      );
    });
  });

  group('page cache', () {
    test('unpinned pages: LRU of 8', () async {
      await openWith(pages: 10);
      final ids = [for (final p in session.pages) p.id];
      for (final id in ids) {
        await session.openPage(id);
        session.closePage(id);
      }
      expect(session.pageIfLoaded(ids[0]), isNull);
      expect(session.pageIfLoaded(ids[1]), isNull);
      for (final id in ids.skip(2)) {
        expect(session.pageIfLoaded(id), isNotNull, reason: id);
      }
      // Using page 2 again makes page 3 the least recently used.
      await session.openPage(ids[2]);
      session.closePage(ids[2]);
      await session.openPage(ids[0]);
      session.closePage(ids[0]);
      expect(session.pageIfLoaded(ids[3]), isNull);
      expect(session.pageIfLoaded(ids[2]), isNotNull);
    });

    test('pinned pages stay loaded beyond 8', () async {
      await openWith(pages: 10);
      final ids = [for (final p in session.pages) p.id];
      for (final id in ids) {
        await session.openPage(id);
      }
      for (final id in ids) {
        expect(session.pageIfLoaded(id), isNotNull);
      }
      session.closePage(ids[0]);
      session.closePage(ids[1]);
      session.closePage(ids[2]);
      expect(session.pageIfLoaded(ids[0]), isNotNull, reason: '3 unpinned ≤ 8');
    });

    test('maxCachedPages from the options', () async {
      await openWith(pages: 4);
      await session.close();
      session = await store.openSession(
        note.id,
        options: const NoteSessionOptions(maxCachedPages: 1),
      );
      final ids = [for (final p in session.pages) p.id];
      for (final id in ids) {
        await session.openPage(id);
        session.closePage(id);
      }
      expect(
        [for (final id in ids) session.pageIfLoaded(id) != null],
        [false, false, false, true],
      );
    });
  });

  test(
    'deleting every page: LastPageDeletionException, nothing changes',
    () async {
      await openWith(pages: 2);
      final pages = session.pages;
      expect(
        () => session.execute(
          DeletePages(pageIds: [for (final p in pages) p.id]),
        ),
        throwsA(isA<LastPageDeletionException>()),
      );
      expect(session.pages, same(pages));
    },
  );

  test('unchanged strokes keep their objects across edits (K-4)', () async {
    await openWith();
    final page = session.pages.first;
    await session.openPage(page.id);
    await addStrokes(page.id, 3);
    final before = session.pageIfLoaded(page.id)!.strokes;
    final extra = strokeOn(page.id, seed: 9);
    session.execute(AddStrokes(pageId: page.id, strokes: [extra]));
    final after = session.pageIfLoaded(page.id)!.strokes;
    expect(after, hasLength(4));
    for (var i = 0; i < 3; i++) {
      expect(identical(after[i], before[i]), isTrue);
    }
    session.execute(
      RestyleStrokes(
        pageId: page.id,
        strokeIds: [before[1].id],
        patch: const StrokeStylePatch(colorArgb: 0xFFFF0000),
      ),
    );
    final restyled = session.pageIfLoaded(page.id)!.strokes;
    expect(identical(restyled[0], before[0]), isTrue);
    expect(identical(restyled[1], before[1]), isFalse);
    expect(identical(restyled[2], before[2]), isTrue);
    await session.flush();
  });

  group('session writes', () {
    test(
      'rows and outbox carry the versions of the session (memory = rows)',
      () async {
        await openWith();
        final page = session.pages.first;
        await session.openPage(page.id);
        await store.db.delete(store.db.outbox).go();
        final s = strokeOn(page.id);
        final receipt = session.execute(
          AddStrokes(pageId: page.id, strokes: [s]),
        );
        await receipt.persisted;
        final inMemory = session.pageIfLoaded(page.id)!.strokeById(s.id)!;
        final stored = await store.content.loadPage(page.id);
        expect(stored.strokes.single.version, inMemory.version);
        expect(stored.strokes.single.points.contentEquals(s.points), isTrue);
        final entry = (await readOutbox(store.db)).single;
        expect(entry.kind, EntityKind.stroke);
        expect(entry.entityId, s.id);
        expect(entry.noteId, note.id);
        expect(entry.pageId, page.id);
        expect(entry.hlc, inMemory.version);
      },
    );

    test('local values: page contentRevision, note updatedAt / pageCount / '
        'firstPageId (C-9), no outbox for them', () async {
      final clock = _SteppingClock();
      store = await openStore(clock: clock);
      note = await store.library.createNote(title: 'n');
      session = await store.openSession(note.id);
      final page = session.pages.single;
      await session.openPage(page.id);
      await store.flush();
      await store.db.delete(store.db.outbox).go();
      final batches = <ChangeBatch>[];
      final sub = store.changes.listen(batches.add);
      addTearDown(sub.cancel);
      await session
          .execute(AddStrokes(pageId: page.id, strokes: [strokeOn(page.id)]))
          .persisted;
      final storedPage = (await store.content.getPage(page.id))!;
      expect(storedPage.contentRevision, 1);
      expect(storedPage.contentRevision, session.pages.single.contentRevision);
      final storedNote = (await store.library.getNote(note.id))!;
      expect(storedNote.updatedAt, session.note.updatedAt);
      expect(storedNote.updatedAt, greaterThan(note.updatedAt));
      expect(storedNote.version, note.version, reason: 'local value only');
      expect(
        [for (final e in await readOutbox(store.db)) e.kind],
        [EntityKind.stroke],
      );
      // A page inserted at the start becomes the first page.
      await session.executeAsync(
        const InsertPages(drafts: [PageDraft.blankA4], position: PageAtStart()),
      );
      await session.flush();
      final after = (await store.library.getNote(note.id))!;
      expect(after.pageCount, 2);
      expect(after.firstPageId, session.pages.first.id);
      await Future<void>.delayed(Duration.zero);
      expect(batches.first.origin, ChangeOrigin.local);
      expect(
        batches.first.changes.map((c) => c.kind),
        containsAll([EntityKind.stroke, EntityKind.note]),
      );
    });

    test('undo / redo are written with their origins', () async {
      await openWith();
      final page = session.pages.first;
      await session.openPage(page.id);
      final origins = <ChangeOrigin>[];
      final sub = store.changes.listen((b) => origins.add(b.origin));
      addTearDown(sub.cancel);
      await addStrokes(page.id, 1);
      await session.undo();
      await session.flush();
      expect((await store.content.loadPage(page.id)).strokes, isEmpty);
      await session.redo();
      await session.flush();
      expect((await store.content.loadPage(page.id)).strokes, hasLength(1));
      await Future<void>.delayed(Duration.zero);
      expect(origins, [
        ChangeOrigin.local,
        ChangeOrigin.undo,
        ChangeOrigin.redo,
      ]);
    });
  });

  group('read-only openings (N-4)', () {
    test('a trashed note opens read-only', () async {
      await openWith();
      await session.close();
      await store.library.trashItems([NoteRef(note.id)]);
      session = await store.openSession(note.id);
      expect(session.isReadOnly, isTrue);
    });

    test('a note of a newer schema opens read-only', () async {
      await openWith();
      await session.close();
      final newer = Note.fromJson({
        ...(await store.library.getNote(note.id))!.toJson(),
        'schemaVersion': kNoteSchemaVersion + 1,
      });
      await _putRemote(store, [newer]);
      session = await store.openSession(note.id);
      expect(session.note.requiresNewerApp, isTrue);
      expect(session.isReadOnly, isTrue);
    });

    test('a note of another owner is not found', () async {
      await openWith();
      final other = Note.fromJson({
        ...note.toJson(),
        'id': 'other-owner-note',
        'ownerId': 'someone',
      });
      await _putRemote(store, [other]);
      await expectLater(
        store.openSession('other-owner-note'),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('concurrent openSession calls share one session', () async {
      await openWith();
      await session.close();
      final both = await Future.wait([
        store.openSession(note.id),
        store.openSession(note.id),
      ]);
      expect(identical(both[0], both[1]), isTrue);
      await both[0].close();
      expect(both[1].isClosed, isFalse);
      session = both[1];
    });
  });

  group('remote changes (N-7)', () {
    test('a remote stroke on a loaded page: PageContentChange(remote), '
        'contentRevision + 1, not in the history', () async {
      await openWith();
      final page = session.pages.first;
      await session.openPage(page.id);
      await addStrokes(page.id, 1);
      final changes = <PageContentChange>[];
      final pageLists = <List<Page>>[];
      final subs = [
        session.pageChanges(page.id).listen(changes.add),
        session.pagesStream.listen(pageLists.add),
      ];
      await Future<void>.delayed(Duration.zero);
      changes.clear();
      final history = session.history;
      final rev = session.pages.first.contentRevision;
      final remote = strokeOn(page.id, seed: 7);
      await _putRemote(store, [remote]);
      expect(changes, hasLength(1));
      expect(changes.single.origin, ChangeOrigin.remote);
      expect(changes.single.added, {remote.id});
      expect(changes.single.content.strokeById(remote.id), isNotNull);
      expect(session.pages.first.contentRevision, rev + 1);
      expect(pageLists.last.first.contentRevision, rev + 1);
      expect(session.history, history);
      for (final s in subs) {
        await s.cancel();
      }
    });

    test('a remote deletion and a remote update of loaded strokes', () async {
      await openWith();
      final page = session.pages.first;
      await session.openPage(page.id);
      final strokes = await addStrokes(page.id, 2);
      final changes = <PageContentChange>[];
      final sub = session.pageChanges(page.id).listen(changes.add);
      await Future<void>.delayed(Duration.zero);
      changes.clear();
      final content = session.pageIfLoaded(page.id)!;
      final first = content.strokeById(strokes[0].id)!;
      final second = content.strokeById(strokes[1].id)!;
      await _putRemote(store, [
        first.copyWith(deletedAt: 5),
        second.copyWith(style: second.style.copyWith(width: 9)),
      ]);
      final change = changes.single;
      expect(change.removed, {first.id});
      expect(change.updated, {second.id});
      expect(change.content.strokes.single.style.width, 9);
      await sub.cancel();
    });

    test(
      'a remote stroke on a page that is not loaded bumps its revision only',
      () async {
        await openWith();
        final page = session.pages[2];
        final rev = page.contentRevision;
        await _putRemote(store, [strokeOn(page.id)]);
        expect(session.pageIfLoaded(page.id), isNull);
        expect(session.pages[2].contentRevision, rev + 1);
        final content = await session.openPage(page.id);
        expect(content.strokes, hasLength(1));
      },
    );

    test(
      'remote pages: a new page joins the list, a deleted one leaves it; the '
      'note row (title) reaches noteStream',
      () async {
        await openWith();
        final notes = <Note>[];
        final sub = session.noteStream.listen(notes.add);
        final last = session.pages.last;
        final added = Page(
          id: 'remote-page',
          noteId: note.id,
          sortKey: '${last.sortKey}V',
          size: PageSize.a4Portrait,
          background: const BlankBackground(),
          createdAt: 1,
          updatedAt: 1,
        );
        await _putRemote(store, [
          added,
          session.pages.first.copyWith(deletedAt: 3),
          (await store.library.getNote(note.id))!.copyWith(title: 'renamed'),
        ]);
        expect(
          [for (final p in session.pages) p.id],
          [
            ...[for (final p in session.pages) p.id].take(2),
            'remote-page',
          ],
        );
        expect(session.pages, hasLength(3));
        expect(session.pages.last.id, 'remote-page');
        expect(session.note.title, 'renamed');
        expect(session.note.pageCount, 3);
        expect(notes.last.title, 'renamed');
        await sub.cancel();
      },
    );

    test('a session write still queued wins over a remote write of the same '
        'stroke committed before it', () async {
      await openWith();
      final page = session.pages.first;
      await session.openPage(page.id);
      final strokes = await addStrokes(page.id, 1);
      final mine = session.pageIfLoaded(page.id)!.strokeById(strokes[0].id)!;
      // The remote job commits alone while the session's restyle waits behind it.
      final gate = Completer<void>();
      final remote = store.queue.run((tx) async {
        await gate.future;
        await tx.putRemote(
          mine.copyWith(style: mine.style.copyWith(width: 2)),
          _remoteVersions(),
        );
      }, origin: ChangeOrigin.remote);
      await Future<void>.delayed(Duration.zero);
      final restyle = session.execute(
        RestyleStrokes(
          pageId: page.id,
          strokeIds: [mine.id],
          patch: const StrokeStylePatch(width: 7),
        ),
      );
      final before = store.queue.debugTransactionCount;
      gate.complete();
      await Future.wait([remote, restyle.persisted]);
      expect(store.queue.debugTransactionCount, before + 1);
      final shown = session.pageIfLoaded(page.id)!.strokeById(mine.id)!;
      final stored = (await store.content.loadPage(page.id))
          .strokeById(mine.id)!;
      expect(shown.style.width, 7);
      expect(stored.style.width, 7);
    });

    test('undo skips a stroke changed remotely since (6.7.3)', () async {
      await openWith();
      final page = session.pages.first;
      await session.openPage(page.id);
      final strokes = await addStrokes(page.id, 2);
      final s0 = session.pageIfLoaded(page.id)!.strokeById(strokes[0].id)!;
      await _putRemote(store, [
        s0.copyWith(style: s0.style.copyWith(width: 4)),
      ]);
      final result = await session.undo();
      await session.flush();
      expect(result.skippedEntities, 1);
      final content = session.pageIfLoaded(page.id)!;
      expect(content.strokeById(strokes[0].id), isNotNull);
      expect(content.strokeById(strokes[1].id), isNull);
    });
  });
}

/// A clock that moves 1 ms forward on every read.
final class _SteppingClock extends Clock {
  _SteppingClock() : super(_next);
  static var _ms = 1793750400000;
  static DateTime _next() =>
      DateTime.fromMillisecondsSinceEpoch(_ms++, isUtc: true);
}
