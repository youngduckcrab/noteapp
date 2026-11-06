// CORE T32 — HandwritingRepository on SQLite (m5-7/02-core 6.9) beyond the shared body: the
// outbox ({*} for a new row, only the changed keys after, {deletedAt}, revive, noteId / pageId
// hints), watchPage emissions only for its row, put on a deleted page, the pages.ink_rev cache
// (6.9.3 — every stalePages case: no result + input, stroke add / transform / delete, highlighter
// / tape only, empty page, deleted pages, remote strokes, undo, after put, page order, cache
// writes with no outbox or ChangeBatch, cached pages not read again, a moved content_rev
// recomputes), notesWithStalePages (exact, recency, trash, owner, after the cache refresh) and
// update details (one transform call, a non-domain exception without a commit retry, the
// other jobs of the same commit kept).
@TestOn('vm')
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Value;
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/db/note_database.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing.dart'
    show StrokeFixtures, newerVersionWinsPolicy;
import 'package:test/test.dart';

import '../storage/storage_support.dart';
import '../sync/support/sync_support.dart';

void main() {
  late DriftNoteStore store;
  late int nowMs;
  late Note n;
  late List<PageId> pages;

  setUp(() async {
    nowMs = DateTime.utc(2026, 11, 6).millisecondsSinceEpoch;
    store = await openStore(
      clock: Clock(() => DateTime.fromMillisecondsSinceEpoch(nowMs)),
    );
    n = await store.library.createNote(
      title: '손글씨',
      pages: const [PageDraft.blankA4, PageDraft.blankA4, PageDraft.blankA4],
    );
    pages = [for (final p in await store.content.pagesOf(n.id)) p.id];
  });
  tearDown(() => store.close());

  /// Moves the store clock on (a stroke edit then gets a new updatedAt — 6.9.2).
  void tick() => nowMs += 1000;

  HandwritingRepository repo() => store.handwriting;

  HandwritingText result(
    PageId pageId, {
    String text = '회의록',
    String sourceRev = '0000000000000000',
    NoteId? noteId,
  }) => HandwritingText(
    noteId: noteId ?? n.id,
    pageId: pageId,
    engineId: 'fake/1:ko',
    sourceRev: sourceRev,
    lines: [
      HandwritingLine(
        text: text,
        rect: const PageRect(10, 10, 100, 30),
        strokeIds: const ['s1'],
        languageTag: 'ko',
      ),
    ],
    createdAt: 1,
  );

  Future<OutboxEntry?> entryOf(String id) async =>
      (await store.sync.pendingChanges(limit: 100000))
          .where((e) => e.entityId == id)
          .firstOrNull;

  Future<NoteSession> sessionOn(PageId pageId, {NoteId? noteId}) async {
    final s = await store.openSession(noteId ?? n.id);
    await s.openPage(pageId);
    return s;
  }

  /// Adds strokes of [tools] to [pageId]; returns the stored strokes of the page.
  Future<List<Stroke>> addStrokes(
    PageId pageId,
    List<PenTool> tools, {
    NoteId? noteId,
  }) async {
    tick();
    final s = await sessionOn(pageId, noteId: noteId);
    await s
        .execute(
          AddStrokes(
            pageId: pageId,
            strokes: [
              for (final (i, t) in tools.indexed)
                StrokeFixtures.synthetic(
                  pageId: pageId,
                  ids: store.ids,
                  seed: i,
                  tool: t,
                  createdAt: nowMs + i,
                ),
            ],
          ),
        )
        .persisted;
    final stored = s.pageIfLoaded(pageId)!.strokes;
    await s.close();
    return stored;
  }

  /// The sourceRev a recogniser would store for the page now.
  Future<String> revOf(PageId pageId) async {
    final content = await store.content.loadPage(pageId);
    return HandwritingText.sourceRevOf(
      content.strokes.where(HandwritingText.isRecognitionInput),
    );
  }

  Future<void> markFresh(PageId pageId) async =>
      repo().put(result(pageId, sourceRev: await revOf(pageId)));

  Future<PageRow> pageRow(PageId id) => (store.db.select(
    store.db.pages,
  )..where((t) => t.id.equals(id))).getSingle();

  group('writes', () {
    test('outbox: {*}, then the changed keys, {deletedAt}, a revive', () async {
      final id = HandwritingText.idFor(pages[0]);
      await repo().put(result(pages[0]));
      var e = (await entryOf(id))!;
      expect(e.changedFields, {kAllFields});
      expect(e.noteId, n.id);
      expect(e.pageId, pages[0]);
      await store.sync.acknowledge([e.ack]);

      tick();
      await repo().put(result(pages[0], text: '바뀜', sourceRev: '1' * 16));
      e = (await entryOf(id))!;
      expect(e.changedFields, {'lines', 'sourceRev'});
      await store.sync.acknowledge([e.ack]);

      tick();
      await repo().removeForPage(pages[0]);
      e = (await entryOf(id))!;
      expect(e.changedFields, {'deletedAt'});
      expect(e.op, OutboxOp.upsert);
      await store.sync.acknowledge([e.ack]);
      expect(await repo().forPage(pages[0]), isNull);

      tick();
      await repo().put(result(pages[0], text: '바뀜', sourceRev: '1' * 16));
      e = (await entryOf(id))!;
      expect(e.changedFields, {'deletedAt'}, reason: 'revived, same content');
      final revived = (await repo().forPage(pages[0]))!;
      expect(revived.deletedAt, isNull);
      expect(revived.updatedAt, nowMs);
      expect(revived.createdAt, 1);
    });

    test(
      'a page in the trash or deleted from its note still takes a result',
      () async {
        final s = await sessionOn(pages[2]);
        await s.execute(DeletePages(pageIds: [pages[2]])).persisted;
        await s.close();
        await repo().put(result(pages[2]));
        expect(await repo().forPage(pages[2]), isNotNull);
      },
    );

    test('watchPage emits for its own row only', () async {
      final seen = <String?>[];
      final sub = repo()
          .watchPage(pages[0])
          .listen((h) => seen.add(h?.lines.single.text));
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);
      await repo().put(result(pages[1]));
      await addStrokes(pages[0], [PenTool.ballpoint]);
      await repo().put(result(pages[0]));
      await repo().put(result(pages[0])); // unchanged: no write
      await repo().put(result(pages[0], text: '둘'));
      await Future<void>.delayed(Duration.zero);
      expect(seen, [null, '회의록', '둘']);
    });
  });

  group('update', () {
    test('the transform runs once per call', () async {
      var calls = 0;
      await repo().update(pages[0], (cur) {
        calls++;
        return result(pages[0]);
      });
      expect(calls, 1);
    });

    test('a transform exception is the call\'s: no commit retry, the other jobs of '
        'the commit kept', () async {
      final before = store.queue.debugTransactionCount;
      final other = repo().put(result(pages[1]));
      final failing = repo().update(
        pages[0],
        (_) => throw const FormatException('boom'),
      );
      final rename = store.library.renameNote(n.id, '같은 커밋');
      await expectLater(failing, throwsFormatException);
      await other;
      await rename;
      expect(store.queue.debugTransactionCount - before, 1);
      expect(store.persistenceStatus.consecutiveFailures, 0);
      expect(await repo().forPage(pages[1]), isNotNull);
      expect((await store.library.getNote(n.id))!.title, '같은 커밋');
      expect(await repo().forPage(pages[0]), isNull);
    });

    test('a library write from inside the transform is a StateError', () async {
      Object? error;
      await repo().update(pages[0], (_) {
        store.library.renameNote(n.id, 'x').catchError((Object e) => error = e);
        return null;
      });
      await Future<void>.delayed(Duration.zero);
      expect(error, isA<StateError>());
      expect((await store.library.getNote(n.id))!.title, '손글씨');
    });
  });

  group('stalePages (6.9.3)', () {
    test(
      'no result + input strokes; after put none; a new stroke again',
      () async {
        await addStrokes(pages[1], [PenTool.ballpoint]);
        expect(await repo().stalePages(n.id), [pages[1]]);
        await markFresh(pages[1]);
        expect(await repo().stalePages(n.id), isEmpty);
        await addStrokes(pages[1], [PenTool.fountain]);
        expect(await repo().stalePages(n.id), [pages[1]]);
      },
    );

    test(
      'a transformed or deleted input stroke makes the page stale',
      () async {
        final strokes = await addStrokes(pages[0], [
          PenTool.ballpoint,
          PenTool.pencil,
        ]);
        await markFresh(pages[0]);
        tick();
        var s = await sessionOn(pages[0]);
        await s
            .execute(
              TransformElements(
                pageId: pages[0],
                elementIds: [strokes.first.id],
                transform: Affine2.translation(5, 5),
              ),
            )
            .persisted;
        await s.close();
        expect(await repo().stalePages(n.id), [pages[0]]);
        await markFresh(pages[0]);
        tick();
        s = await sessionOn(pages[0]);
        await s
            .execute(
              RemoveStrokes(pageId: pages[0], strokeIds: [strokes.last.id]),
            )
            .persisted;
        await s.close();
        expect(await repo().stalePages(n.id), [pages[0]]);
      },
    );

    test('highlighter / tape / laser only and empty pages are never stale; a '
        'non-input stroke added to a fresh page keeps it fresh', () async {
      await addStrokes(pages[0], [PenTool.highlighter, PenTool.tape]);
      await addStrokes(pages[1], [PenTool.laser]);
      expect(await repo().stalePages(n.id), isEmpty);
      await addStrokes(pages[2], [PenTool.ballpoint]);
      await markFresh(pages[2]);
      await addStrokes(pages[2], [PenTool.highlighter]);
      expect(await repo().stalePages(n.id), isEmpty);
    });

    test('deleted pages are left out; page order follows the note', () async {
      for (final p in pages) {
        await addStrokes(p, [PenTool.ballpoint]);
      }
      final s = await store.openSession(n.id);
      await s
          .execute(
            MovePages(pageIds: [pages[2]], position: const PageAtStart()),
          )
          .persisted;
      await s.execute(DeletePages(pageIds: [pages[1]])).persisted;
      final order = [for (final p in s.pages) p.id];
      await s.close();
      expect(order, [pages[2], pages[0]]);
      expect(await repo().stalePages(n.id), order);
    });

    test('a remote stroke on a fresh page makes it stale', () async {
      await addStrokes(pages[0], [PenTool.ballpoint]);
      await markFresh(pages[0]);
      final remote = stroke('remote-stroke', pages[0]);
      await store.sync.applyRemote([
        upsert(remote, remoteAfter(store)),
      ], policy: newerVersionWinsPolicy);
      expect(await repo().stalePages(n.id), [pages[0]]);
      await markFresh(pages[0]);
      expect(await repo().stalePages(n.id), isEmpty);
    });

    test(
      'undo back to the recognised strokes makes the page fresh again',
      () async {
        await addStrokes(pages[0], [PenTool.ballpoint]);
        await markFresh(pages[0]);
        tick();
        final s = await sessionOn(pages[0]);
        await s
            .execute(
              AddStrokes(
                pageId: pages[0],
                strokes: [
                  StrokeFixtures.synthetic(
                    pageId: pages[0],
                    ids: store.ids,
                    seed: 9,
                    createdAt: nowMs,
                  ),
                ],
              ),
            )
            .persisted;
        expect(await repo().stalePages(n.id), [pages[0]]);
        tick();
        await s.undo();
        await s.flush();
        expect(await repo().stalePages(n.id), isEmpty);
        tick();
        await s.redo();
        await s.flush();
        expect(await repo().stalePages(n.id), [pages[0]]);
        await s.close();
      },
    );

    test('the cache: written without outbox or ChangeBatch, not read again, '
        'recomputed when content_rev moves', () async {
      await addStrokes(pages[0], [PenTool.ballpoint]);
      await addStrokes(pages[1], [PenTool.highlighter]);
      final outbox = (await store.sync.pendingChanges(limit: 100000)).length;
      final batches = <ChangeBatch>[];
      final sub = store.changes.listen(batches.add);
      addTearDown(sub.cancel);

      final refreshed0 = store.handwriting.debugInkRefreshedPages;
      expect(await repo().stalePages(n.id), [pages[0]]);
      expect(store.handwriting.debugInkRefreshedPages - refreshed0, 3);
      final row0 = await pageRow(pages[0]);
      expect(row0.inkRev, await revOf(pages[0]));
      expect(row0.inkRevAt, row0.contentRev);
      expect((await pageRow(pages[2])).inkRev, 'e3b0c44298fc1c14');
      await Future<void>.delayed(Duration.zero);
      expect(batches, isEmpty);
      expect((await store.sync.pendingChanges(limit: 100000)).length, outbox);

      // Fresh cache: no stroke rows read.
      expect(await repo().stalePages(n.id), [pages[0]]);
      expect(store.handwriting.debugInkRefreshedPages - refreshed0, 3);

      // The cache is trusted while content_rev stays …
      await (store.db.update(store.db.pages)
            ..where((t) => t.id.equals(pages[2])))
          .write(const PagesCompanion(inkRev: Value('ffffffffffffffff')));
      expect(await repo().stalePages(n.id), [pages[0], pages[2]]);
      // … and recomputed once it moves (one page read).
      await addStrokes(pages[2], [PenTool.highlighter]);
      expect(await repo().stalePages(n.id), [pages[0]]);
      expect(store.handwriting.debugInkRefreshedPages - refreshed0, 4);
    });

    test('the SQL-joined text is sourceRevOf\'s: mixed ASCII ids, updatedAt digits', () async {
      const ids = ['b', 'B', 'a-1', 'a_1', 'a1', '_x', '-y', 'Z9', '0', 'zz'];
      final v = remoteAfter(store);
      await store.sync.applyRemote([
        for (final (i, id) in ids.indexed)
          upsert(
            Stroke(
              id: id,
              pageId: pages[0],
              style: StrokeStyle.defaultsFor(
                i.isEven ? PenTool.ballpoint : PenTool.highlighter,
              ),
              points: stroke('p', pages[0]).points,
              createdAt: 7,
              updatedAt: 1000000000000 + i * 37,
            ),
            v,
          ),
      ], policy: newerVersionWinsPolicy);
      final rev = await revOf(pages[0]);
      expect(rev, isNot('e3b0c44298fc1c14'));
      expect(await repo().stalePages(n.id), [pages[0]]);
      expect((await pageRow(pages[0])).inkRev, rev);
      await repo().put(result(pages[0], sourceRev: rev));
      expect(await repo().stalePages(n.id), isEmpty);
    });

    test('a missing note, another owner\'s note: no pages', () async {
      await addStrokes(pages[0], [PenTool.ballpoint]);
      expect(await repo().stalePages('missing'), isEmpty);
      store.switchOwner('someone-else');
      expect(await repo().stalePages(n.id), isEmpty);
      expect(await repo().notesWithStalePages(), isEmpty);
    });
  });

  group('notesWithStalePages (6.9.3)', () {
    test(
      'exact, most recently updated first, trash out, cache-only after',
      () async {
        final b = await store.library.createNote(title: 'B');
        final c = await store.library.createNote(title: 'C');
        final bPage = (await store.content.pagesOf(b.id)).single.id;
        final cPage = (await store.content.pagesOf(c.id)).single.id;
        await addStrokes(pages[0], [PenTool.ballpoint]);
        await addStrokes(cPage, [PenTool.ballpoint], noteId: c.id);
        await addStrokes(bPage, [PenTool.highlighter], noteId: b.id);
        // n edited before c: c first. b has no input.
        expect(await repo().notesWithStalePages(), [c.id, n.id]);

        final refreshed = store.handwriting.debugInkRefreshedPages;
        expect(await repo().notesWithStalePages(), [c.id, n.id]);
        expect(
          store.handwriting.debugInkRefreshedPages,
          refreshed,
          reason: 'the cache is fresh: one query',
        );

        await store.library.trashItems([NoteRef(c.id)]);
        expect(await repo().notesWithStalePages(), [n.id]);
        await markFresh(pages[0]);
        expect(await repo().notesWithStalePages(), isEmpty);

        // A result that does not match any more (the page gained a stroke).
        await addStrokes(pages[0], [PenTool.pencil]);
        expect(await repo().notesWithStalePages(), [n.id]);
        // A result on a page without input is stale too.
        await repo().put(result(bPage, noteId: b.id));
        expect((await repo().notesWithStalePages()).toSet(), {n.id, b.id});
      },
    );
  });
}
