// CORE T7 — ChangeBatch after each commit with EntityChange hints, local and remote
// (4.8.1, 6.10.3, contract 7.2.10 v1.1 / v1.2).
@TestOn('vm')
library;

import 'dart:async';

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/change_bus.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/row_mappers.dart';
import 'package:test/test.dart';

import 'storage_support.dart';

const Hlc _r1 = Hlc(10, 0, '00000000000000bb');
const Hlc _r2 = Hlc(20, 0, '00000000000000bb');

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

  Map<String, EntityChange> byId(ChangeBatch b) => {
    for (final c in b.changes) c.id: c,
  };

  test('a local batch carries noteId / pageId hints', () async {
    await store.queue.run((tx) async {
      await tx.putLocal(note('n1'), const {kAllFields});
      await tx.putLocal(page('p1', 'n1'), const {kAllFields});
      await tx.putLocal(stroke('s1', 'p1'), const {kAllFields});
      await tx.putLocal(recording('r1', 'n1'), const {kAllFields});
    });
    await pumpEventQueue();
    final b = batches.single;
    expect(b.origin, ChangeOrigin.local);
    final c = byId(b);
    expect(c['n1']!.kind, EntityKind.note);
    expect(c['p1']!.noteId, 'n1');
    expect(c['s1']!.noteId, 'n1');
    expect(c['s1']!.pageId, 'p1');
    expect(c['r1']!.noteId, 'n1');
  });

  test(
    'a remote batch carries the same hints; a stroke gets its page\'s note',
    () async {
      await store.queue.run((tx) async {
        await tx.putRemote(page('p1', 'n1'), const EntityFieldVersions(_r1));
        await tx.putRemote(stroke('s1', 'p1'), const EntityFieldVersions(_r1));
        await tx.putRemote(
          recording('r1', 'n1'),
          const EntityFieldVersions(_r1),
        );
      }, origin: ChangeOrigin.remote);
      // A remote stroke of a page stored by an earlier commit.
      await store.queue.run(
        (tx) =>
            tx.putRemote(stroke('s2', 'p1'), const EntityFieldVersions(_r2)),
        origin: ChangeOrigin.remote,
      );
      await pumpEventQueue();
      expect(batches, hasLength(2));
      expect(batches.every((b) => b.origin == ChangeOrigin.remote), isTrue);
      final c = byId(batches.first);
      expect(c['p1']!.noteId, 'n1');
      expect(c['s1']!.noteId, 'n1');
      expect(c['s1']!.pageId, 'p1');
      expect(c['r1']!.noteId, 'n1');
      final s2 = batches.last.changes.single;
      expect((s2.id, s2.noteId, s2.pageId), ('s2', 'n1', 'p1'));
      // Remote versions are stored as given and advance the HLC.
      final row = await readVersionedRow(
        store.db,
        const EntityRef(EntityKind.stroke, 's2'),
      );
      expect(row!.versions, const EntityFieldVersions(_r2));
      expect(store.hlc.last > _r2, isTrue);
    },
  );

  test(
    'an orphan stroke is listed with the commit that brings its page',
    () async {
      await store.queue.run(
        (tx) => tx.putRemote(
          stroke('s1', 'p1', deletedAt: 5),
          const EntityFieldVersions(_r1),
        ),
        origin: ChangeOrigin.remote,
      );
      await store.queue.run(
        (tx) =>
            tx.putRemote(stroke('s2', 'p1'), const EntityFieldVersions(_r1)),
        origin: ChangeOrigin.remote,
      );
      await pumpEventQueue();
      expect(batches, isEmpty);
      final orphanRows = await store.db.select(store.db.strokes).get();
      expect({for (final r in orphanRows) r.noteId}, {''});

      await store.queue.run(
        (tx) => tx.putRemote(page('p1', 'n1'), const EntityFieldVersions(_r2)),
        origin: ChangeOrigin.remote,
      );
      await pumpEventQueue();
      final b = batches.single;
      final c = byId(b);
      expect(c.keys.toSet(), {'p1', 's1', 's2'});
      expect(
        (c['s1']!.noteId, c['s1']!.pageId, c['s1']!.deleted),
        ('n1', 'p1', true),
      );
      expect((c['s2']!.noteId, c['s2']!.pageId), ('n1', 'p1'));
      final rows = await store.db.select(store.db.strokes).get();
      expect({for (final r in rows) r.noteId}, {'n1'});
    },
  );

  test('one batch per origin of a commit; repeated changes collapse', () async {
    final gate = Completer<void>();
    final hold = store.queue.run((tx) => gate.future);
    await pumpEventQueue(times: 5);
    final writes = [
      store.queue.run((tx) => tx.putLocal(folder('f1'), const {kAllFields})),
      store.queue.run(
        (tx) => tx.putLocal(folder('f1', name: 'x'), const {'name'}),
      ),
      store.queue.run(
        (tx) => tx.putRemote(folder('f2'), const EntityFieldVersions(_r1)),
        origin: ChangeOrigin.remote,
      ),
      store.queue.run((tx) => tx.putLocal(folder('f3'), const {kAllFields})),
    ];
    gate.complete();
    await Future.wait([hold, ...writes]);
    await pumpEventQueue();
    expect(
      [for (final b in batches) b.origin],
      [ChangeOrigin.local, ChangeOrigin.remote, ChangeOrigin.local],
    );
    expect([for (final c in batches.first.changes) c.id], ['f1']);
    expect(batches.map((b) => b.committedAt).toSet(), hasLength(1));
  });

  test('a job that fails with a domain error publishes nothing', () async {
    await expectLater(
      store.queue.run((tx) async {
        await tx.putLocal(folder('f1'), const {kAllFields});
        throw ArgumentError('bad');
      }),
      throwsArgumentError,
    );
    await pumpEventQueue();
    expect(batches, isEmpty);
  });

  test('batchesOf drops empty jobs', () {
    expect(batchesOf([(ChangeOrigin.local, const [])], 1), isEmpty);
  });
}
