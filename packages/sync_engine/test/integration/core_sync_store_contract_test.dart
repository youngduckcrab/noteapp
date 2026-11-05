// T16 (integration stage, contract 7.7 step 5 v1.2 — C12-05 "SyncStore 계약 스위트 C-01~C-25
// (CoreSyncLocalStore(openTestNoteStore))"): the shared suite of
// test/contract/sync_store_contract.dart against real CORE through CoreSyncLocalStore, with
// the real-CORE-only checks (5.1.4): C-21 reopening the same file (realCore: true) and C-15's
// open session history (remote and repair writes stay out of undo; the session sees them as
// remote changes). Write retries (S-20) need CORE fault hooks that openTestNoteStore does not
// take: the integration stage checks them with CORE's own fault tests (5.1.2).
@Tags(['integration'])
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';

import '../contract/sync_store_contract.dart';
import 'support/core_store_driver.dart';

void main() {
  syncStoreContract(
    'CoreSyncLocalStore(openTestNoteStore)',
    CoreStoreDriver.open,
    realCore: true,
  );

  group('real CORE only', () {
    late ContractClock clock;
    late CoreStoreDriver d;

    setUp(() async {
      clock = ContractClock(kContractStart);
      d = await CoreStoreDriver.open(
        deviceNodeId: kContractNode,
        clock: clock.clock,
      );
      addTearDown(d.close);
    });

    test('C-15 an open session: remote and repair writes are not undo steps; '
        'its own stroke stays the only one', () async {
      final store = d.core.store;
      final n = await d.createNote('a');
      final page = (await d.activePageIds(n)).single;
      final session = await store.openSession(n);
      addTearDown(session.close);
      await session.openPage(page);
      final stroke = StrokeFixtures.synthetic(
        pageId: page,
        ids: store.ids,
        seed: 1,
        createdAt: clock.millis,
      );
      session.execute(AddStrokes(pageId: page, strokes: [stroke]));
      await session.flush();
      expect(session.history.undoDepth, 1);

      clock.advance(const Duration(seconds: 1));
      final row = (await d.sync.readVersioned([EntityRef(EntityKind.note, n)]))
          .single!;
      await d.sync.applyRemote([
        remoteOf(
          row.entity,
          set: {'title': 'remote'},
          versions: EntityFieldVersions(
            Hlc(
              clock.now.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
              0,
              kRemoteNode,
            ),
          ),
        ),
      ], policy: take);
      final after = (await d.sync.readVersioned([
        EntityRef(EntityKind.note, n),
      ])).single!;
      await d.sync.commitRepairs([
        (entity: after.entity, fields: const {'folderId', 'sortKey'}),
      ]);
      await pumpEventQueue();
      expect(session.note.title, 'remote');
      expect(session.history.undoDepth, 1);

      await session.undo();
      await session.flush();
      final content = await store.content.loadPage(page);
      expect(content.strokes, isEmpty);
      expect((await store.library.getNote(n))!.title, 'remote');
    });
  });
}
