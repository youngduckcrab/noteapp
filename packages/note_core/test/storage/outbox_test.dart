// CORE T7 — outbox records (6.10.1): one per write, merge rules, hints, local-only fields.
@TestOn('vm')
library;

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/outbox_writer.dart';
import 'package:note_core/src/storage/row_mappers.dart';
import 'package:test/test.dart';

import 'storage_support.dart';

void main() {
  late DriftNoteStore store;
  setUp(() async => store = await openStore());
  tearDown(() => store.close());

  Future<List<OutboxEntry>> outbox() => readOutbox(store.db);
  Future<void> ack() => store.db.delete(store.db.outbox).go();

  Future<void> write(SyncEntity e, Set<String> fields) =>
      store.queue.run((tx) => tx.putLocal(e, fields));

  test('every local write is recorded; a new entity is {*}', () async {
    await write(folder('f1'), const {kAllFields});
    await write(note('n1'), const {kAllFields});
    final entries = await outbox();
    expect([for (final e in entries) e.entityId], ['f1', 'n1']);
    expect(entries.first.seq < entries.last.seq, isTrue);
    expect(entries.first.rev, 1);
    expect(entries.first.op, OutboxOp.upsert);
    expect(entries.first.changedFields, {kAllFields});
    expect(entries.first.kind, EntityKind.folder);
    expect(entries.first.hlc.nodeId, kTestNode);
  });

  test(
    'merge: seq kept, rev + 1, fields united, hlc = newest, purge wins',
    () async {
      await write(folder('f1'), const {kAllFields});
      await ack();
      await write(folder('f1', name: 'a'), const {'name'});
      final first = (await outbox()).single;
      expect(first.changedFields, {'name'});
      await write(folder('f1', name: 'b'), const {'color', 'name'});
      final merged = (await outbox()).single;
      expect(merged.seq, first.seq);
      expect(merged.rev, 2);
      expect(merged.changedFields, {'color', 'name'});
      expect(merged.hlc > first.hlc, isTrue);
      expect(merged.enqueuedAt, first.enqueuedAt);

      await write(folder('f1', name: 'c'), const {kAllFields});
      expect((await outbox()).single.changedFields, {kAllFields});

      await store.queue.run(
        (tx) => tx.purge(const EntityRef(EntityKind.folder, 'f1')),
      );
      final purged = (await outbox()).single;
      expect(purged.seq, first.seq);
      expect(purged.rev, 4);
      expect(purged.op, OutboxOp.purge);
      expect(purged.changedFields, {kAllFields});
    },
  );

  test('a purge entry stays a purge when merged with an upsert', () async {
    await store.queue.run(
      (tx) => tx.purge(const EntityRef(EntityKind.note, 'n9')),
    );
    await write(note('n9'), const {'title'});
    final e = (await outbox()).single;
    expect(e.op, OutboxOp.purge);
    expect(e.changedFields, {kAllFields});
  });

  test(
    'local-only and meta fields are not recorded and keep the version',
    () async {
      await write(note('n1'), const {kAllFields});
      await ack();
      final before = await readVersionedRow(
        store.db,
        const EntityRef(EntityKind.note, 'n1'),
      );
      await write(note('n1', pageCount: 3), const {
        'pageCount',
        'firstPageId',
        'lastOpenedAt',
        'updatedAt',
      });
      expect(await outbox(), isEmpty);
      final after = await readVersionedRow(
        store.db,
        const EntityRef(EntityKind.note, 'n1'),
      );
      expect(after!.versions, before!.versions);
      expect((after.entity as Note).pageCount, 3);

      await write(note('n1', title: 'T'), const {
        'title',
        'updatedAt',
        'pageCount',
      });
      expect((await outbox()).single.changedFields, {'title'});

      expect(syncedFieldsOf(EntityKind.page, {'contentRevision', 'sortKey'}), {
        'sortKey',
      });
      expect(syncedFieldsOf(EntityKind.asset, {'hasLocalBytes'}), isEmpty);
      expect(syncedFieldsOf(EntityKind.setting, {'key', 'valueJson'}), {
        'valueJson',
      });
    },
  );

  test(
    'hints: noteId for page / stroke / recording, pageId for stroke',
    () async {
      await store.queue.run((tx) async {
        await tx.putLocal(note('n1'), const {kAllFields});
        await tx.putLocal(page('p1', 'n1'), const {kAllFields});
        await tx.putLocal(stroke('s1', 'p1'), const {kAllFields});
        await tx.putLocal(recording('r1', 'n1'), const {kAllFields});
        await tx.putLocal(folder('f1'), const {kAllFields});
      });
      // A stroke of a page written in an earlier commit (noteId from the page row).
      await write(stroke('s2', 'p1'), const {kAllFields});
      final byId = {for (final e in await outbox()) e.entityId: e};
      expect(byId['n1']!.noteId, isNull);
      expect(byId['f1']!.noteId, isNull);
      expect(byId['p1']!.noteId, 'n1');
      expect(byId['p1']!.pageId, isNull);
      expect(byId['s1']!.noteId, 'n1');
      expect(byId['s1']!.pageId, 'p1');
      expect(byId['s2']!.noteId, 'n1');
      expect(byId['s2']!.pageId, 'p1');
      expect(byId['r1']!.noteId, 'n1');
      // The stroke row keeps the denormalized note id.
      final rows = await store.db.select(store.db.strokes).get();
      expect({for (final r in rows) r.noteId}, {'n1'});
    },
  );

  test('remote writes are not recorded', () async {
    await store.queue.run(
      (tx) => tx.putRemote(
        folder('f1'),
        const EntityFieldVersions(Hlc(5, 0, '00000000000000bb')),
      ),
      origin: ChangeOrigin.remote,
    );
    expect(await outbox(), isEmpty);
  });
}
