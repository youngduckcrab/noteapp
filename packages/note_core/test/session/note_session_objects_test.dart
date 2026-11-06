// CORE T27 — page objects in the note sessions of the SQLite store (m5-7/02-core 6.5) beyond
// the shared object contract: lazy loading reads only the opened page's objects, unchanged
// objects keep their instances (K-4), local object edits bump the page revision and write
// page_objects rows with outbox hints, remote object changes reach a loaded page as
// PageContentChange(remote) without touching the history (N-7), a queued session write wins,
// a reopened session starts with an empty history (C15-04 — CORE-F4), and createNote writes
// the drafts' objects (6.4.1).
@TestOn('vm')
library;

import 'dart:async';

import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor;
import 'package:drift/native.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/outbox_writer.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../storage/storage_support.dart';
import '../sync/support/sync_support.dart';

/// Records the arguments of every SELECT on the page_objects table.
final class _ObjectQueries extends QueryInterceptor {
  final List<List<Object?>> args = [];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('"page_objects"')) this.args.add(args);
    return executor.runSelect(statement, args);
  }
}

const _remoteNode = 'ffffffffffffffff';
var _remoteMs = 1893456000000; // 2030: after every local stamp of these tests

EntityFieldVersions _remoteVersions() =>
    EntityFieldVersions(Hlc(_remoteMs++, 0, _remoteNode));

/// The internal remote write path (applyRemote / commitRepairs, CORE T14 / T28).
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

  /// One object of each known type and an unknown one, on [pageId] (createdAt 10..14).
  List<PageObject> objectsOn(PageId pageId, String prefix) => [
    PageObjectFixtures.shape(
      pageId: pageId,
      id: '$prefix-shape',
      createdAt: 10,
    ),
    PageObjectFixtures.textBox(
      pageId: pageId,
      id: '$prefix-text',
      createdAt: 11,
    ),
    PageObjectFixtures.math(pageId: pageId, id: '$prefix-math', createdAt: 12),
    PageObjectFixtures.image(
      pageId: pageId,
      id: '$prefix-image',
      assetId: 'asset-1',
      createdAt: 13,
    ),
    PageObjectFixtures.unknown(pageId: pageId, id: '$prefix-unknown'),
  ];

  Future<void> add(PageId pageId, List<PageObject> objects) =>
      session.execute(AddObjects(pageId: pageId, objects: objects)).persisted;

  PageContent loaded(PageId pageId) => session.pageIfLoaded(pageId)!;

  group('lazy loading', () {
    test('openSession and openPage query only the objects of the opened page; '
        'the other pages stay unloaded', () async {
      final queries = _ObjectQueries();
      await openWith(executor: NativeDatabase.memory().interceptWith(queries));
      final pages = session.pages;
      for (final p in pages) {
        await session.openPage(p.id);
        await add(p.id, objectsOn(p.id, p.id));
      }
      await session.close();
      queries.args.clear();

      session = await store.openSession(note.id);
      expect(queries.args, isEmpty, reason: 'opening reads no object');
      final content = await session.openPage(pages[1].id);
      expect(content.objects.map((o) => o.pageId).toSet(), {pages[1].id});
      expect(content.objects, hasLength(5));
      final queried = {for (final a in queries.args) ...a};
      expect(queried, contains(pages[1].id));
      expect(queried, isNot(contains(pages[0].id)));
      expect(queried, isNot(contains(pages[2].id)));
      expect(session.pageIfLoaded(pages[0].id), isNull);
      expect(session.pageIfLoaded(pages[2].id), isNull);
    });

    test('a reopened session reads every type back in Stroke.compareOrder, '
        'versions = rows; its history is empty (C15-04)', () async {
      await openWith();
      final page = session.pages.first;
      await session.openPage(page.id);
      final objects = objectsOn(page.id, 'o');
      await add(page.id, objects.reversed.toList());
      final before = loaded(page.id).objects;
      expect(session.history.canUndo, isTrue);
      await session.close();

      session = await store.openSession(note.id);
      expect(session.history.canUndo, isFalse);
      expect(session.history.canRedo, isFalse);
      final content = await session.openPage(page.id);
      // createdAt 1 (the unknown fixture) first, then 10..14.
      expect(content.objects.map((o) => o.id), [
        'o-unknown',
        'o-shape',
        'o-text',
        'o-math',
        'o-image',
      ]);
      for (final o in content.objects) {
        final mine = before.singleWhere((b) => b.id == o.id);
        expect(o, mine, reason: o.id);
        expect(o.toJson(), mine.toJson(), reason: o.id);
      }
      final unknown = content.objectById('o-unknown')! as UnknownObject;
      expect(unknown.rawJson['payload'], {
        'fixture': true,
        'items': [1, 2, 3],
      });
    });
  });

  test('unchanged objects and strokes keep their instances across local and '
      'remote edits (K-4)', () async {
    await openWith();
    final page = session.pages.first;
    await session.openPage(page.id);
    await add(page.id, objectsOn(page.id, 'o'));
    final stroke = StrokeFixtures.synthetic(pageId: page.id, ids: store.ids);
    await session
        .execute(AddStrokes(pageId: page.id, strokes: [stroke]))
        .persisted;
    final first = loaded(page.id);

    final text = first.objectById('o-text')! as TextBoxObject;
    await session
        .execute(
          UpdateObjects(
            pageId: page.id,
            objects: [text.copyWith(text: '바뀜')],
          ),
        )
        .persisted;
    final second = loaded(page.id);
    expect(second.objectById('o-text'), isNot(same(text)));
    for (final id in ['o-shape', 'o-math', 'o-image', 'o-unknown']) {
      expect(second.objectById(id), same(first.objectById(id)), reason: id);
    }
    expect(second.strokeById(stroke.id), same(first.strokeById(stroke.id)));

    final shape = second.objectById('o-shape')! as ShapeObject;
    await _putRemote(store, [
      shape.copyWith(style: shape.style.copyWith(strokeWidth: 5)),
    ]);
    final third = loaded(page.id);
    expect((third.objectById('o-shape')! as ShapeObject).style.strokeWidth, 5);
    for (final id in ['o-text', 'o-math', 'o-image', 'o-unknown']) {
      expect(third.objectById(id), same(second.objectById(id)), reason: id);
    }
    expect(third.strokeById(stroke.id), same(first.strokeById(stroke.id)));
  });

  group('session writes', () {
    test('an object edit bumps the page revision (memory and row); rows carry '
        'note_id; the outbox has noteId and pageId', () async {
      await openWith();
      final page = session.pages.first;
      await session.openPage(page.id);
      final rev = session.pages.first.contentRevision;
      await add(page.id, [
        PageObjectFixtures.textBox(pageId: page.id, id: 't1'),
      ]);
      expect(session.pages.first.contentRevision, rev + 1);
      expect(loaded(page.id).revision, 1);
      expect((await store.content.getPage(page.id))!.contentRevision, rev + 1);
      final row = await (store.db.select(
        store.db.pageObjects,
      )..where((t) => t.id.equals('t1'))).getSingle();
      expect(row.noteId, note.id);
      expect(row.pageId, page.id);
      expect(row.type, 'text');
      final entry = (await readOutbox(store.db))
          .singleWhere((e) => e.entityId == 't1');
      expect((entry.noteId, entry.pageId), (note.id, page.id));
      expect(entry.changedFields, {kAllFields});

      await store.db.delete(store.db.outbox).go();
      await session
          .execute(RemoveElements(pageId: page.id, elementIds: ['t1']))
          .persisted;
      expect(session.pages.first.contentRevision, rev + 2);
      final removed = (await readOutbox(store.db)).single;
      expect(removed.changedFields, {'deletedAt'});
      expect((removed.noteId, removed.pageId), (note.id, page.id));
      expect((await store.content.loadPage(page.id)).objects, isEmpty);
    });

    test('one command of strokes and objects is one commit and one ChangeBatch '
        '(C-11)', () async {
      await openWith();
      final page = session.pages.first;
      await session.openPage(page.id);
      final batches = <ChangeBatch>[];
      final sub = store.changes.listen(batches.add);
      addTearDown(sub.cancel);
      final before = store.queue.debugTransactionCount;
      await session
          .execute(
            CompositeCommand([
              AddStrokes(
                pageId: page.id,
                strokes: [
                  StrokeFixtures.synthetic(pageId: page.id, ids: store.ids),
                ],
              ),
              AddObjects(pageId: page.id, objects: objectsOn(page.id, 'c')),
            ]),
          )
          .persisted;
      expect(store.queue.debugTransactionCount, before + 1);
      await Future<void>.delayed(Duration.zero);
      final kinds = {
        for (final b in batches)
          for (final c in b.changes) c.kind,
      };
      expect(batches, hasLength(1));
      // The page's contentRevision is a local value (no page change); the note's derived
      // values are.
      expect(kinds, {
        EntityKind.stroke,
        EntityKind.pageObject,
        EntityKind.note,
      });
      final objectChanges = batches.single.changes.where(
        (c) => c.kind == EntityKind.pageObject,
      );
      expect(objectChanges, hasLength(5));
      for (final c in objectChanges) {
        expect((c.noteId, c.pageId), (note.id, page.id), reason: c.id);
      }
    });
  });

  group('remote changes (N-7)', () {
    test(
      'a remote update and a remote deletion of loaded objects: '
      'PageContentChange(remote), revisions + 1, history unchanged',
      () async {
        await openWith();
        final page = session.pages.first;
        await session.openPage(page.id);
        await add(page.id, objectsOn(page.id, 'o'));
        final changes = <PageContentChange>[];
        final pageLists = <List<Page>>[];
        final subs = [
          session.pageChanges(page.id).listen(changes.add),
          session.pagesStream.listen(pageLists.add),
        ];
        addTearDown(() async {
          for (final s in subs) {
            await s.cancel();
          }
        });
        await Future<void>.delayed(Duration.zero);
        changes.clear();
        final history = session.history;
        final rev = session.pages.first.contentRevision;
        final storedRev = (await store.content.getPage(page.id))!
            .contentRevision;
        final content = loaded(page.id);
        final text = content.objectById('o-text')! as TextBoxObject;
        final math = content.objectById('o-math')!;
        // Through SyncStore.applyRemote: the remote writer raises the row's content_rev
        // once per call (CORE T28).
        final report = await store.sync.applyRemote([
          upsert(text.copyWith(text: 'remote'), remoteAfter(store)),
          upsert(
            math.copyWithMeta(deletedAt: 5, updatedAt: 5),
            remoteAfter(store),
          ),
        ], policy: newerVersionWinsPolicy);
        expect(report.taken, 2);
        final change = changes.single;
        expect(change.origin, ChangeOrigin.remote);
        expect(change.updated, {'o-text'});
        expect(change.removed, {'o-math'});
        expect(change.added, isEmpty);
        expect(
          (change.content.objectById('o-text')! as TextBoxObject).text,
          'remote',
        );
        expect(change.content.objectById('o-math'), isNull);
        expect(change.content.objects, hasLength(4));
        expect(change.content.revision, content.revision + 1);
        expect(session.pages.first.contentRevision, rev + 1);
        expect(pageLists.last.first.contentRevision, rev + 1);
        // The row: content_rev + 1.
        expect(
          (await store.content.getPage(page.id))!.contentRevision,
          storedRev + 1,
        );
        expect(session.history, history);
      },
    );

    test(
      'a remote object on a page that is not loaded bumps its revision only',
      () async {
        await openWith();
        final page = session.pages[2];
        final rev = page.contentRevision;
        final changes = <PageContentChange>[];
        final sub = session.pageChanges(page.id).listen(changes.add);
        addTearDown(sub.cancel);
        await _putRemote(store, [
          PageObjectFixtures.math(pageId: page.id, id: 'far'),
        ]);
        expect(session.pageIfLoaded(page.id), isNull);
        expect(changes, isEmpty);
        expect(session.pages[2].contentRevision, rev + 1);
        final content = await session.openPage(page.id);
        expect(content.objectById('far'), isA<MathObject>());
      },
    );

    test(
      'a remote object of another note does not reach the session',
      () async {
        await openWith();
        final page = session.pages.first;
        await session.openPage(page.id);
        final other = await store.library.createNote(title: 'other');
        final otherPage = (await store.content.pagesOf(other.id)).single;
        final changes = <PageContentChange>[];
        final sub = session.pageChanges(page.id).listen(changes.add);
        addTearDown(sub.cancel);
        await Future<void>.delayed(Duration.zero);
        changes.clear();
        final rev = session.pages.first.contentRevision;
        await _putRemote(store, [
          PageObjectFixtures.textBox(pageId: otherPage.id, id: 'elsewhere'),
        ]);
        expect(changes, isEmpty);
        expect(session.pages.first.contentRevision, rev);
        expect(loaded(page.id).objectById('elsewhere'), isNull);
      },
    );

    test('a session write still queued wins over a remote write of the same '
        'object committed before it', () async {
      await openWith();
      final page = session.pages.first;
      await session.openPage(page.id);
      await add(page.id, [
        PageObjectFixtures.textBox(pageId: page.id, id: 't1'),
      ]);
      final mine = loaded(page.id).objectById('t1')! as TextBoxObject;
      // The remote job commits alone while the session's update waits behind it.
      final gate = Completer<void>();
      final remote = store.queue.run((tx) async {
        await gate.future;
        await tx.putRemote(mine.copyWith(text: 'remote'), _remoteVersions());
      }, origin: ChangeOrigin.remote);
      await Future<void>.delayed(Duration.zero);
      final update = session.execute(
        UpdateObjects(
          pageId: page.id,
          objects: [mine.copyWith(text: 'mine')],
        ),
      );
      gate.complete();
      await Future.wait([remote, update.persisted]);
      final shown = loaded(page.id).objectById('t1')! as TextBoxObject;
      final stored =
          (await store.content.loadPage(page.id)).objectById('t1')!
              as TextBoxObject;
      expect(shown.text, 'mine');
      expect(stored.text, 'mine');
    });

    test('a remote orphan object adopted with its page reaches the session '
        'when the page is opened', () async {
      await openWith(pages: 1);
      final last = session.pages.last;
      final orphan = PageObjectFixtures.shape(
        pageId: 'remote-page',
        id: 'orphan',
      );
      await _putRemote(store, [orphan]); // no page row yet
      await _putRemote(store, [
        Page(
          id: 'remote-page',
          noteId: note.id,
          sortKey: '${last.sortKey}V',
          size: PageSize.a4Portrait,
          background: const BlankBackground(),
          createdAt: 1,
          updatedAt: 1,
        ),
      ]);
      expect(session.pages.map((p) => p.id), contains('remote-page'));
      final content = await session.openPage('remote-page');
      expect(content.objectById('orphan'), isA<ShapeObject>());
    });
  });

  group('createNote with PageDraft.objects (6.4.1)', () {
    test('new ids, the original createdAt, normalized; rows and outbox carry '
        'the note', () async {
      await openWith(pages: 1);
      await session.close();
      final drafts = [
        PageDraft(
          size: PageSize.a4Portrait,
          background: const BlankBackground(),
          objects: [
            PageObjectFixtures.shape(
              pageId: 'ignored',
              id: 'src-shape',
              createdAt: 42,
            ).copyWith(
              style: const ShapeStyle(
                strokeColorArgb: 0x801A1A1A, // alpha → 0xFF
                strokeWidth: 99, // → 30
              ),
            ),
            PageObjectFixtures.unknown(pageId: 'ignored', id: 'src-unknown'),
          ],
        ),
      ];
      await store.db.delete(store.db.outbox).go();
      final created = await store.library.createNote(
        title: 'with objects',
        pages: drafts,
      );
      session = await store.openSession(created.id);
      final pageId = session.pages.single.id;
      final content = await session.openPage(pageId);
      expect(content.objects, hasLength(2));
      final shape = content.objects.whereType<ShapeObject>().single;
      final unknown = content.objects.whereType<UnknownObject>().single;
      expect(shape.id, isNot('src-shape'));
      expect(unknown.id, isNot('src-unknown'));
      expect(shape.pageId, pageId);
      expect(unknown.pageId, pageId);
      expect(shape.createdAt, 42);
      expect(shape.style.strokeColorArgb, 0xFF1A1A1A);
      expect(shape.style.strokeWidth, 30);
      expect(shape.version, isNotNull);
      expect(unknown.rawJson['payload'], {
        'fixture': true,
        'items': [1, 2, 3],
      });
      for (final o in content.objects) {
        final row = await (store.db.select(
          store.db.pageObjects,
        )..where((t) => t.id.equals(o.id))).getSingle();
        expect(row.noteId, created.id, reason: o.id);
      }
      final entries = (await readOutbox(store.db))
          .where((e) => e.kind == EntityKind.pageObject)
          .toList();
      expect(entries, hasLength(2));
      for (final e in entries) {
        expect((e.noteId, e.pageId), (created.id, pageId));
        expect(e.changedFields, {kAllFields});
      }
    });

    test('a draft over the object limits throws before any write', () async {
      await openWith(pages: 1);
      Future<int> rows() async =>
          (await store.db.select(store.db.notes).get()).length;
      final notes = await rows();
      final tooMany = PageDraft(
        size: PageSize.a4Portrait,
        background: const BlankBackground(),
        objects: [
          for (var i = 0; i <= PageObjectLimits.maxObjectsPerPage; i++)
            PageObjectFixtures.textBox(pageId: 'x', id: 'x$i'),
        ],
      );
      final longText = PageDraft(
        size: PageSize.a4Portrait,
        background: const BlankBackground(),
        objects: [
          PageObjectFixtures.textBox(
            pageId: 'x',
            text: 'a' * (PageObjectLimits.maxTextLength + 1),
          ),
        ],
      );
      for (final d in [tooMany, longText]) {
        await expectLater(
          store.library.createNote(title: 'x', pages: [PageDraft.blankA4, d]),
          throwsArgumentError,
        );
      }
      expect(await rows(), notes);
    });
  });
}
