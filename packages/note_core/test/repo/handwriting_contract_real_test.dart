// The handwriting contract (m5-7/02-core 6.9) on the real SQLite store (CORE T32) — the same
// body as test/repo/handwriting_contract_fake_test.dart — plus race case 3 of 6.9.4, which
// needs the remote path: a remote result that arrives while the indexer recognises (between
// its forPage and its update) is what the update transform gets (G-4).
@TestOn('vm')
library;

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing.dart' show newerVersionWinsPolicy;
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

import '../shared/handwriting_contract.dart';
import '../storage/storage_support.dart';
import '../sync/support/sync_support.dart';

void main() {
  group('shared body', () => defineHandwritingContract(openTestNoteStore));

  group('6.9.4 race case 3 (remote)', () {
    late DriftNoteStore store;
    late Note note;
    late PageId pageId;

    setUp(() async {
      store = await openStore();
      note = await store.library.createNote(title: '경합');
      pageId = (await store.content.pagesOf(note.id)).single.id;
    });
    tearDown(() => store.close());

    HandwritingText result(String text, {int createdAt = 1}) => HandwritingText(
      noteId: note.id,
      pageId: pageId,
      engineId: 'fake/1:ko',
      sourceRev: '0000000000000000',
      lines: [
        HandwritingLine(
          text: text,
          rect: const PageRect(10, 10, 100, 30),
          strokeIds: const ['s1'],
          languageTag: 'ko',
        ),
      ],
      createdAt: createdAt,
    );

    test(
      'a remote result between forPage and update is the transform input',
      () async {
        await store.handwriting.put(result('local A'));
        // The indexer: read, then recognise (await) …
        final seenByIndexer = await store.handwriting.forPage(pageId);
        expect(seenByIndexer!.lines.single.text, 'local A');
        // … meanwhile a remote result B arrives.
        final remote = result('remote B', createdAt: 2);
        final report = await store.sync.applyRemote([
          upsert(remote, remoteAfter(store)),
        ], policy: newerVersionWinsPolicy);
        expect(report.taken, 1);
        HandwritingText? got;
        final stored = await store.handwriting.update(pageId, (cur) {
          got = cur;
          return cur!.copyWith(
            lines: [
              ...cur.lines,
              cur.lines.single.copyWith(text: 'merged'),
            ],
          );
        });
        expect(got!.lines.single.text, 'remote B', reason: 'not local A');
        expect([for (final l in stored!.lines) l.text], ['remote B', 'merged']);
        expect(await store.handwriting.forPage(pageId), stored);
      },
    );

    test(
      'an applyRemote queued before an update (no await) is seen by it',
      () async {
        final remote = store.sync.applyRemote([
          upsert(result('remote B'), remoteAfter(store)),
        ], policy: newerVersionWinsPolicy);
        HandwritingText? got;
        final up = store.handwriting.update(pageId, (cur) {
          got = cur;
          return null;
        });
        await remote;
        expect((await up)!.lines.single.text, 'remote B');
        expect(got!.lines.single.text, 'remote B');
      },
    );
  });
}
