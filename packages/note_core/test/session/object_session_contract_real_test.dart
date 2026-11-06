// CORE T27 — the object session contract (m5-7/02-core 6.5, the T23a shared body) on the
// SQLite store (openTestNoteStore), plus N-7: a committed remote page object reaches an open
// session (PageContentChange origin remote, not in the history). More cases are in
// note_session_objects_test.dart.
@TestOn('vm')
library;

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing.dart';
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

import '../shared/object_session_contract.dart';

Future<NoteStore> _open() => openTestNoteStore(
  ids: SequentialIdGenerator(),
  deviceNodeId: '00000000000000aa',
  seedDefaultPenPresets: false,
);

void main() {
  defineObjectSessionContract(_open);

  test('N-7: a committed remote object updates the loaded page '
      '(origin remote), pagesStream and not the history', () async {
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
    addTearDown(() async {
      for (final s in subs) {
        await s.cancel();
      }
    });
    await Future<void>.value();
    changes.clear();
    final remote = PageObjectFixtures.textBox(pageId: page.id, id: 'remote-t');
    // The internal path of SyncStore.applyRemote (CORE T14 / T28).
    await store.queue.run(
      (tx) => tx.putRemote(
        remote,
        EntityFieldVersions(Hlc(1893456000000, 0, 'ffffffffffffffff')),
      ),
      origin: ChangeOrigin.remote,
    );
    expect(changes.single.origin, ChangeOrigin.remote);
    expect(changes.single.added, {'remote-t'});
    final content = session.pageIfLoaded(page.id)!;
    expect(content.objectById('remote-t'), isA<TextBoxObject>());
    expect(content.revision, 1);
    expect(lists.single.single.contentRevision, page.contentRevision + 1);
    expect(session.history.canUndo, isFalse);
  });
}
