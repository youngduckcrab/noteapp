// CORE T10 — the shared NoteSession contract (N-1..N-6) on the SQLite store
// (openTestNoteStore), plus N-7: remote changes reach an open session. More N-7
// cases (deletions, pages, queued local writes, undo) are in note_session_test.dart.
@TestOn('vm')
library;

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing.dart';
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

import '../shared/note_session_contract.dart';

Future<NoteStore> _open() => openTestNoteStore(
  ids: SequentialIdGenerator(),
  deviceNodeId: '00000000000000aa',
  seedDefaultPenPresets: false,
);

void main() {
  defineNoteSessionContractTests(_open);

  group('N-7 remote changes', () {
    test(
      'a committed remote stroke updates the loaded page '
      '(PageContentChange origin remote), pagesStream and not the history',
      () async {
        final store = await _open() as DriftNoteStore;
        addTearDown(store.close);
        final note = await store.library.createNote(title: 'n');
        final session = await store.openSession(note.id);
        addTearDown(session.close);
        final page = session.pages.single;
        await session.openPage(page.id);
        final changes = <PageContentChange>[];
        final lists = <List<Page>>[];
        final subs = [
          session.pageChanges(page.id).listen(changes.add),
          session.pagesStream.listen(lists.add),
        ];
        await Future<void>.value();
        changes.clear();
        final remote = StrokeFixtures.synthetic(
          pageId: page.id,
          ids: store.ids,
        );
        // The internal path of SyncStore.applyRemote (CORE T14).
        await store.queue.run(
          (tx) => tx.putRemote(
            remote,
            EntityFieldVersions(Hlc(1893456000000, 0, 'ffffffffffffffff')),
          ),
          origin: ChangeOrigin.remote,
        );
        expect(changes.single.origin, ChangeOrigin.remote);
        expect(changes.single.added, {remote.id});
        expect(session.pageIfLoaded(page.id)!.strokeById(remote.id), isNotNull);
        expect(lists.single.single.contentRevision, page.contentRevision + 1);
        expect(session.history.canUndo, isFalse);
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
  });
}
