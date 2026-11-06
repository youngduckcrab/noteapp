// Integration stage (CORE I-2, progress log 'content_rev 경합' — T32 note): a session's local
// write and a remote write on the same page, queued in that order of arrival — the remote job
// first (its stroke not yet seen by the session), then the local stroke the session numbered
// from its memory. Two content changes must give two content_rev steps, so a thumbnail or an
// ink_rev cache taken between them is not mistaken for the final state.
@TestOn('vm')
library;

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../storage/storage_support.dart';
import '../sync/support/sync_support.dart';

void main() {
  late DriftNoteStore store;

  setUp(() async => store = await openStore());
  tearDown(() => store.close());

  Future<int> storedRev(PageId page) async =>
      (await store.content.getPage(page))!.contentRevision;

  test('a remote stroke queued before a local one: two content_rev steps, '
      'the session and the row agree', () async {
    final note = await store.library.createNote(
      title: 'race',
      pages: const [PageDraft.blankA4],
    );
    final page = (await store.content.pagesOf(note.id)).single.id;
    final session = await store.openSession(note.id);
    await session.openPage(page);
    await session
        .execute(AddStrokes(pageId: page, strokes: [stroke('l1', page)]))
        .persisted;
    final before = await storedRev(page);

    // The remote job enters the write queue first; the session has not seen it when it
    // numbers its local stroke.
    final remote = store.sync.applyRemote([
      upsert(stroke('r1', page), remoteAfter(store)),
    ], policy: newerVersionWinsPolicy);
    final local = session
        .execute(AddStrokes(pageId: page, strokes: [stroke('l2', page)]))
        .persisted;
    expect((await remote).taken, 1);
    await local;
    await store.flush();

    expect(await storedRev(page), before + 2);
    expect(
      session.pages.singleWhere((p) => p.id == page).contentRevision,
      await storedRev(page),
    );
    final content = await store.content.loadPage(page);
    expect(content.strokes.map((s) => s.id).toSet(), {'l1', 'l2', 'r1'});
    await session.close();
  });

  test(
    'without a race the local write numbers as before (session value)',
    () async {
      final note = await store.library.createNote(
        title: 'plain',
        pages: const [PageDraft.blankA4],
      );
      final page = (await store.content.pagesOf(note.id)).single.id;
      final session = await store.openSession(note.id);
      await session.openPage(page);
      final start = await storedRev(page);
      for (var i = 0; i < 3; i++) {
        await session
            .execute(AddStrokes(pageId: page, strokes: [stroke('s$i', page)]))
            .persisted;
      }
      expect(await storedRev(page), start + 3);
      expect(
        session.pages.singleWhere((p) => p.id == page).contentRevision,
        start + 3,
      );
      await session.close();
    },
  );
}
