// CORE T28 — the sync window with the DB v2 kinds (m5-7/02-core 6.13, 8.2): pendingChanges,
// readVersioned, applyRemote (every decision) and commitRepairs for page objects and
// handwriting results; a remote object or handwriting result written to an existing page
// raises its content_rev once per call (thumbnails, ink_rev cache — 6.9.3); a remote object
// moves its note's updatedAt like a stroke, a handwriting result (derived, as the local put —
// 6.9.4) does not; both list the note as affected.
@TestOn('vm')
library;

import 'dart:async';

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../storage/storage_support.dart';
import 'support/sync_support.dart';

void main() {
  late DriftNoteStore store;
  late List<ChangeBatch> batches;
  late StreamSubscription<ChangeBatch> sub;

  setUp(() async {
    store = await openStore();
    batches = [];
    sub = store.changes.listen(batches.add);
  });
  tearDown(() async {
    await sub.cancel();
    await store.close();
  });

  SyncStore sync() => store.sync;

  Future<VersionedEntity?> read(EntityKind kind, String id) async =>
      (await sync().readVersioned([EntityRef(kind, id)])).single;

  Future<List<OutboxEntry>> pending() => sync().pendingChanges(limit: 100000);

  Future<void> ackAll() async =>
      sync().acknowledge([for (final e in await pending()) e.ack]);

  Future<int> contentRev(PageId id) async =>
      ((await read(EntityKind.page, id))!.entity as Page).contentRevision;

  HandwritingText handwriting(
    PageId pageId,
    NoteId noteId, {
    int at = 1,
    String text = '회의록',
  }) => HandwritingText(
    noteId: noteId,
    pageId: pageId,
    engineId: 'fake/1:ko',
    sourceRev: '0123456789abcdef',
    lines: [
      HandwritingLine(
        text: text,
        alternatives: const [],
        rect: const PageRect(10, 10, 100, 40),
        strokeIds: const ['s1'],
        languageTag: 'ko',
      ),
    ],
    createdAt: at,
    updatedAt: at,
  );

  /// A note with its first page, outbox acknowledged.
  Future<({Note note, PageId pageId})> seeded() async {
    final n = await store.library.createNote(title: 'n');
    await ackAll();
    final stored = (await store.library.getNote(n.id))!;
    return (note: stored, pageId: stored.firstPageId!);
  }

  Future<void> local(SyncEntity e, Set<String> fields) =>
      store.queue.run((tx) => tx.putLocal(e, fields));

  group('outbox and reads', () {
    test(
      'pendingChanges lists the new kinds with hints; acknowledge clears',
      () async {
        final s = await seeded();
        await local(
          PageObjectFixtures.shape(pageId: s.pageId, id: 'o1'),
          const {kAllFields},
        );
        await local(handwriting(s.pageId, s.note.id), const {kAllFields});
        final entries = await pending();
        expect(
          [for (final e in entries) e.kind],
          [EntityKind.pageObject, EntityKind.handwriting],
        );
        for (final e in entries) {
          expect((e.noteId, e.pageId), (s.note.id, s.pageId));
        }
        final snaps = await sync().readVersioned([
          for (final e in entries) e.ref,
        ]);
        expect(snaps[0]!.entity, isA<ShapeObject>());
        expect(snaps[1]!.entity, isA<HandwritingText>());
        expect(snaps[0]!.entity.version, entries[0].hlc);
        await ackAll();
        expect(await pending(), isEmpty);
      },
    );

    test('readVersioned: mixed kinds in order, missing rows null', () async {
      final s = await seeded();
      final text = PageObjectFixtures.textBox(pageId: s.pageId, id: 'o1');
      final hw = handwriting(s.pageId, s.note.id);
      await local(text, const {kAllFields});
      await local(hw, const {kAllFields});
      await local(text.copyWith(text: 'two'), const {'text'});
      final got = await sync().readVersioned([
        EntityRef(EntityKind.handwriting, hw.id),
        const EntityRef(EntityKind.pageObject, 'missing'),
        const EntityRef(EntityKind.pageObject, 'o1'),
        EntityRef(EntityKind.note, s.note.id),
        EntityRef(EntityKind.handwriting, HandwritingText.idFor('nope')),
      ]);
      expect(got[0]!.entity.id, hw.id);
      expect(got[1], isNull);
      final o = got[2]!;
      expect((o.entity as TextBoxObject).text, 'two');
      expect(o.versions.overrides.keys, ['text'], reason: 'field versions');
      expect(o.entity.version, o.versions.max);
      expect(got[3]!.entity, isA<Note>());
      expect(got[4], isNull);
    });
  });

  group('applyRemote', () {
    test('a new object on an existing page: taken, content_rev + 1 once, note updatedAt', () async {
      final s = await seeded();
      final rev = await contentRev(s.pageId);
      final later = s.note.updatedAt + 5000;
      final report = await sync().applyRemote([
        upsert(
          PageObjectFixtures.textBox(
            pageId: s.pageId,
            id: 'o1',
            createdAt: later,
          ),
          remoteAfter(store),
        ),
        upsert(
          PageObjectFixtures.math(pageId: s.pageId, id: 'o2'),
          remoteAfter(store),
        ),
      ], policy: newerVersionWinsPolicy);
      expect(report.taken, 2);
      expect(report.affectedNoteIds, {s.note.id});
      expect(await contentRev(s.pageId), rev + 1, reason: 'once per call');
      expect((await store.library.getNote(s.note.id))!.updatedAt, later);
      expect(await pending(), isEmpty, reason: 'remote writes: no outbox');
      await pumpEventQueue();
      final c = {for (final x in batches.last.changes) x.id: x};
      expect((c['o1']!.noteId, c['o1']!.pageId), (s.note.id, s.pageId));
      expect(c[s.note.id], isNotNull, reason: 'the derived note change');
    });

    test(
      'a remote change and a remote delete of an object bump content_rev',
      () async {
        final s = await seeded();
        final o = PageObjectFixtures.shape(pageId: s.pageId, id: 'o1');
        await local(o, const {kAllFields});
        await ackAll();
        final rev = await contentRev(s.pageId);
        await sync().applyRemote([
          upsert(o.copyWithMeta(updatedAt: 7), remoteAfter(store)),
        ], policy: newerVersionWinsPolicy);
        expect(await contentRev(s.pageId), rev + 1);
        await sync().applyRemote([
          upsert(
            o.copyWithMeta(updatedAt: 8, deletedAt: 8),
            remoteAfter(store),
          ),
        ], policy: newerVersionWinsPolicy);
        expect(await contentRev(s.pageId), rev + 2);
        final back = (await read(EntityKind.pageObject, 'o1'))!.entity;
        expect(back.isDeleted, isTrue);
      },
    );

    test('an object with its new page: the page starts at 0', () async {
      final n = await store.library.createNote(title: 'n');
      final report = await sync().applyRemote([
        upsert(page('p9', n.id), remoteAfter(store)),
        upsert(
          PageObjectFixtures.image(pageId: 'p9', assetId: 'c' * 64, id: 'o1'),
          remoteAfter(store),
        ),
      ], policy: newerVersionWinsPolicy);
      expect(report.taken, 2);
      expect(await contentRev('p9'), 0, reason: 'a new page row');
      final row = await store.db.select(store.db.pageObjects).getSingle();
      expect((row.noteId, row.assetId), (n.id, 'c' * 64));
    });

    test(
      'an orphan object: stored, no content_rev, no affected note',
      () async {
        final report = await sync().applyRemote([
          upsert(
            PageObjectFixtures.shape(pageId: 'nowhere', id: 'o1'),
            remoteAfter(store),
          ),
        ], policy: newerVersionWinsPolicy);
        expect(report.taken, 1);
        expect(report.affectedNoteIds, isEmpty);
        expect(await read(EntityKind.pageObject, 'o1'), isNotNull);
      },
    );

    test(
      'a remote handwriting result: content_rev + 1, note updatedAt kept',
      () async {
        final s = await seeded();
        final rev = await contentRev(s.pageId);
        final report = await sync().applyRemote([
          upsert(
            handwriting(s.pageId, s.note.id, at: s.note.updatedAt + 9000),
            remoteAfter(store),
          ),
        ], policy: newerVersionWinsPolicy);
        expect(report.taken, 1);
        expect(report.affectedNoteIds, {s.note.id});
        expect(await contentRev(s.pageId), rev + 1);
        expect(
          (await store.library.getNote(s.note.id))!.updatedAt,
          s.note.updatedAt,
          reason: 'a derived result does not reorder the library',
        );
        final hw = (await read(
          EntityKind.handwriting,
          HandwritingText.idFor(s.pageId),
        ))!;
        expect((hw.entity as HandwritingText).lines.single.text, '회의록');
      },
    );

    test(
      'KeepLocal: rows, content_rev and pending entries unchanged',
      () async {
        final s = await seeded();
        final o = PageObjectFixtures.textBox(pageId: s.pageId, id: 'o1');
        await local(o, const {kAllFields});
        final before = (await read(EntityKind.pageObject, 'o1'))!;
        final rev = await contentRev(s.pageId);
        final entries = await pending();
        final report = await sync().applyRemote([
          upsert(o.copyWith(text: 'remote'), remoteAfter(store)),
        ], policy: RecordingPolicy.always(const KeepLocal()).call);
        expect(report.kept, 1);
        expect(await read(EntityKind.pageObject, 'o1'), before);
        expect(await contentRev(s.pageId), rev);
        expect(await pending(), entries);
      },
    );

    test(
      'TakeRemote(dropPendingLocal) of an object drops its pending entry',
      () async {
        final s = await seeded();
        final o = PageObjectFixtures.textBox(pageId: s.pageId, id: 'o1');
        await local(o, const {kAllFields});
        await sync().applyRemote(
          [upsert(o.copyWith(text: 'remote'), remoteAfter(store))],
          policy: RecordingPolicy.always(
            const TakeRemote(dropPendingLocal: true),
          ).call,
        );
        expect(await pending(), isEmpty);
        final back = (await read(EntityKind.pageObject, 'o1'))!.entity;
        expect((back as TextBoxObject).text, 'remote');
      },
    );

    test('the policy sees the stored object and its pending fields', () async {
      final s = await seeded();
      final o = PageObjectFixtures.textBox(pageId: s.pageId, id: 'o1');
      await local(o, const {kAllFields});
      await ackAll();
      await local(o.copyWith(text: 'mine'), const {'text'});
      final policy = RecordingPolicy.always(const KeepLocal());
      await sync().applyRemote([
        upsert(o.copyWith(text: 'theirs'), remoteAfter(store)),
      ], policy: policy.call);
      final call = policy.calls.single;
      expect((call.local!.entity as TextBoxObject).text, 'mine');
      expect((call.remote.entity as TextBoxObject).text, 'theirs');
      expect(call.pending, {'text'});
    });

    test('an UnknownObject is applied and read back key for key', () async {
      final s = await seeded();
      final u = PageObjectFixtures.unknown(pageId: s.pageId, id: 'u1');
      final v = remoteAfter(store);
      await sync().applyRemote([upsert(u, v)], policy: newerVersionWinsPolicy);
      final back = (await read(EntityKind.pageObject, 'u1'))!;
      expect(back.entity, isA<UnknownObject>());
      expect(back.entity.toJson(), {...u.toJson(), 'version': v.toString()});
      expect(back.versions, EntityFieldVersions(v));
    });
  });

  group('commitRepairs', () {
    test('an object field restamped; other fields and versions stay; content_rev + 1', () async {
      final s = await seeded();
      final o = PageObjectFixtures.textBox(pageId: s.pageId, id: 'o1');
      await local(o, const {kAllFields});
      await ackAll();
      final before = (await read(EntityKind.pageObject, 'o1'))!;
      final rev = await contentRev(s.pageId);
      await sync().commitRepairs([
        (
          entity: o.copyWith(
            text: 'repaired',
            frame: const ElementFrame(PageRect(0, 0, 10, 10)),
          ),
          fields: {'text'},
        ),
      ]);
      final after = (await read(EntityKind.pageObject, 'o1'))!;
      final t = after.entity as TextBoxObject;
      expect(t.text, 'repaired');
      expect(t.frame, o.frame, reason: 'frame is not in fields');
      expect(after.versions.of('text') > before.versions.max, isTrue);
      expect(after.versions.of('frame'), before.versions.of('frame'));
      expect(await contentRev(s.pageId), rev + 1);
      final e = (await pending()).single;
      expect(e.changedFields, {'text'});
      expect((e.noteId, e.pageId), (s.note.id, s.pageId));
    });

    test('a handwriting repair of a missing row writes it whole', () async {
      final s = await seeded();
      final hw = handwriting(s.pageId, s.note.id);
      await sync().commitRepairs([
        (entity: hw, fields: {'lines'}),
      ]);
      final back = (await read(EntityKind.handwriting, hw.id))!;
      expect((back.entity as HandwritingText).lines, hw.lines);
      expect(back.versions.overrides, isEmpty);
      final e = (await pending()).single;
      expect(e.changedFields, {kAllFields});
    });
  });
}
