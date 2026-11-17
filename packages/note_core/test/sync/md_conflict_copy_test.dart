// (v2.17-md, C217M-07 L2, m5-7/08-markdown 5.3, MD-T08 store half) SyncStore
// .keepMarkdownConflictCopy on the SQLite store: when a received MD 문서 body would replace
// (or be replaced by) an unsent local text, the losing text is kept as a conflict copy; the
// cases that are NOT concurrent edits (same text, a re-delivered or older version, this
// device's own record, nothing unsent) make no copy; a copy is never rewritten; an autosave
// between the engine's pre-pass and the apply loses neither text.
@TestOn('vm')
library;

import 'package:clock/clock.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing.dart';
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

const String kOther = 'ffffffffffffffff';

void main() {
  late DriftNoteStore store;
  late DateTime now;
  late Note note;
  late FolderId folderId;

  setUp(() async {
    now = DateTime.utc(2026, 11, 17, 9, 30);
    store = await openTestNoteStore(
      clock: Clock(() => now),
      seedDefaultPenPresets: false,
    ) as DriftNoteStore;
    folderId = (await store.library.createFolder(name: '수업')).id;
    note = await store.markdown.create(
      folderId: folderId,
      title: '강의 노트',
      text: '처음',
    );
    // The create is uploaded: nothing pending, base = the uploaded version.
    final entries = await store.sync.pendingChanges();
    final body = entries.singleWhere((e) => e.kind == EntityKind.markdown);
    await store.sync.acknowledge([
      for (final e in entries)
        e == body
            ? OutboxAck(
                e.seq,
                e.rev,
                uploadedTextVersion: (await store.markdown.get(note.id))!
                    .textVersion,
              )
            : e.ack,
    ]);
  });
  tearDown(() => store.close());

  Future<MarkdownDoc> doc(NoteId id) async => (await store.markdown.get(id))!;

  /// A local, unsent edit.
  Future<void> editLocally(String text) async {
    final d = await doc(note.id);
    await store.markdown.saveText(note.id, text, baseVersion: d.textVersion);
  }

  /// A record of another device's text, [ahead] ms after this device's clock.
  ({MarkdownText body, EntityFieldVersions versions}) remote(
    String text, {
    int ahead = 1000,
    String node = kOther,
  }) {
    final last = store.queue.hlc.last;
    final v = Hlc(last.millis + ahead, 0, node);
    return (
      body: MarkdownText(
        noteId: note.id,
        text: text,
        createdAt: note.createdAt,
        updatedAt: last.millis + ahead,
        version: v,
      ),
      versions: EntityFieldVersions(v),
    );
  }

  Future<void> apply(({MarkdownText body, EntityFieldVersions versions}) r) =>
      store.sync.applyRemote([
        RemoteUpsert(r.body, r.versions),
      ], policy: newerVersionWinsPolicy);

  Future<List<Note>> folderNotes() async =>
      (await store.library.watchListing(LibraryQuery(folderId: folderId)).first)
          .notes;

  test('1. concurrent edit, the received text wins: the local text is kept '
      'byte for byte in a copy', () async {
    await editLocally('내 글\r\n');
    final r = remote('다른 기기 글');
    final copyId = await store.sync.keepMarkdownConflictCopy(
      r.body,
      r.versions,
    );
    expect(copyId, isNotNull);
    await apply(r);
    expect((await doc(note.id)).text, '다른 기기 글');
    final copy = await doc(copyId!);
    expect(copy.text, '내 글\r\n');
    expect(copy.note.folderId, folderId);
    expect(copy.note.title, '강의 노트 (충돌 사본 2026-11-17 09:30)');
    expect(await folderNotes(), hasLength(2));
    // The copy is a local write: it goes to the other devices too.
    final pending = await store.sync.pendingChanges();
    expect(
      pending.map((e) => (e.kind, e.entityId)),
      contains((EntityKind.markdown, MarkdownText.idFor(copyId))),
    );
  });

  test('1b. concurrent edit, the local text wins (newer): the received text is '
      'kept, the local text uploads', () async {
    final r = remote('다른 기기 글', ahead: 1);
    now = now.add(const Duration(seconds: 5));
    await editLocally('내 글 (더 새로움)');
    final copyId = await store.sync.keepMarkdownConflictCopy(
      r.body,
      r.versions,
    );
    await apply(r);
    expect((await doc(note.id)).text, '내 글 (더 새로움)');
    expect((await doc(copyId!)).text, '다른 기기 글');
  });

  test('2. the same text: no copy', () async {
    await editLocally('같은 글');
    final r = remote('같은 글');
    expect(
      await store.sync.keepMarkdownConflictCopy(r.body, r.versions),
      isNull,
    );
    expect(await folderNotes(), hasLength(1));
  });

  test(
    '3. a re-delivered / older version (≤ base_text_version): no copy',
    () async {
      // The other device's text arrives and is applied: base = its version.
      final first = remote('받은 글');
      await apply(first);
      await editLocally('그 뒤 내 글');
      // The same record again (compaction snapshot, held record released).
      expect(
        await store.sync.keepMarkdownConflictCopy(first.body, first.versions),
        isNull,
      );
      expect(await folderNotes(), hasLength(1));
    },
  );

  test("4. this device's own record coming back: no copy", () async {
    await editLocally('내 글');
    final own = remote('예전 내 글', node: store.sync.deviceNodeId);
    expect(
      await store.sync.keepMarkdownConflictCopy(own.body, own.versions),
      isNull,
    );
  });

  test(
    '5. nothing unsent here: no copy (the received text simply wins)',
    () async {
      final r = remote('받은 글');
      expect(
        await store.sync.keepMarkdownConflictCopy(r.body, r.versions),
        isNull,
      );
      await apply(r);
      expect((await doc(note.id)).text, '받은 글');
      expect(await folderNotes(), hasLength(1));
    },
  );

  Future<List<String>> allTexts() async => [
    for (final r
        in await store.db.customSelect('SELECT text FROM md_docs').get())
      r.read<String>('text'),
  ];

  test('6. a copy is never rewritten: a second conflict within 10 minutes '
      'makes a new copy; the same losing text reuses the copy', () async {
    await editLocally('내 글 1');
    final r1 = remote('남 글 1');
    final copy1 = await store.sync.keepMarkdownConflictCopy(
      r1.body,
      r1.versions,
    );
    await apply(r1);
    now = now.add(const Duration(minutes: 3));
    await editLocally('내 글 2');
    final r2 = remote('남 글 2');
    final copy2 = await store.sync.keepMarkdownConflictCopy(
      r2.body,
      r2.versions,
    );
    expect(copy2, isNot(copy1));
    expect((await doc(copy1!)).text, '내 글 1');
    expect((await doc(copy2!)).text, '내 글 2');
    await apply(r2);
    expect(await folderNotes(), hasLength(3));
    // The same losing text again within the window: the copy that holds it is reused.
    now = now.add(const Duration(minutes: 1));
    await editLocally('내 글 2');
    final r3 = remote('남 글 3');
    expect(
      await store.sync.keepMarkdownConflictCopy(r3.body, r3.versions),
      copy2,
    );
    await apply(r3);
    expect(await folderNotes(), hasLength(3));
    // ... but not after 10 minutes, and not when that copy is in the trash.
    now = now.add(const Duration(minutes: 11));
    await editLocally('내 글 2');
    final r4 = remote('남 글 4');
    final copy4 = await store.sync.keepMarkdownConflictCopy(
      r4.body,
      r4.versions,
    );
    expect(copy4, isNot(copy2));
    await apply(r4);
    await store.library.trashItems([NoteRef(copy4!)]);
    await editLocally('내 글 2');
    final r5 = remote('남 글 5');
    final copy5 = await store.sync.keepMarkdownConflictCopy(
      r5.body,
      r5.versions,
    );
    expect(copy5, isNot(copy4));
  });

  test('6b. what the user wrote into a copy is never overwritten by a later '
      'conflict (review finding)', () async {
    await editLocally('로컬1');
    final r1 = remote('원격1');
    final c1 = await store.sync.keepMarkdownConflictCopy(r1.body, r1.versions);
    await apply(r1);
    final copy = await doc(c1!);
    await store.markdown.saveText(
      c1,
      '로컬1 + 사본에서 쓴 중요한 내용',
      baseVersion: copy.textVersion,
    );
    now = now.add(const Duration(minutes: 3));
    await editLocally('로컬2');
    final r2 = remote('원격2');
    final c2 = await store.sync.keepMarkdownConflictCopy(r2.body, r2.versions);
    await apply(r2);
    expect(c2, isNot(c1));
    expect((await doc(c1)).text, '로컬1 + 사본에서 쓴 중요한 내용');
    expect(await allTexts(), containsAll(['원격2', '로컬2']));
  });

  test('6c. two received texts that lose in a row are both kept', () async {
    final r1 = remote('원격1', ahead: 1);
    now = now.add(const Duration(seconds: 5));
    await editLocally('로컬1');
    await store.sync.keepMarkdownConflictCopy(r1.body, r1.versions);
    await apply(r1);
    final r2 = remote('원격2 (원격1과 별개)', ahead: 1);
    now = now.add(const Duration(seconds: 5));
    await editLocally('로컬2');
    await store.sync.keepMarkdownConflictCopy(r2.body, r2.versions);
    await apply(r2);
    expect(await allTexts(), unorderedEquals(['로컬2', '원격1', '원격2 (원격1과 별개)']));
  });

  group(
    '7. an autosave between the pre-pass and the apply (review finding)',
    () {
      test(
        'local newer after the autosave: the received text is kept too',
        () async {
          await editLocally('로컬1');
          final r = remote('원격 중요', ahead: 1);
          final c = await store.sync.keepMarkdownConflictCopy(
            r.body,
            r.versions,
          );
          expect((await doc(c!)).text, '로컬1');
          now = now.add(const Duration(seconds: 2));
          await editLocally('로컬1 더 씀');
          final batches = <ChangeBatch>[];
          final sub = store.changes.listen(batches.add);
          await apply(r);
          await sub.cancel();
          // The body is a remote change; the copy made inside the apply a local one.
          expect([
            for (final b in batches)
              for (final c in b.changes)
                if (c.kind == EntityKind.note) (b.origin, c.id == note.id),
          ], contains((ChangeOrigin.local, false)));
          expect((await doc(note.id)).text, '로컬1 더 씀');
          expect(
            await allTexts(),
            unorderedEquals(['로컬1 더 씀', '로컬1', '원격 중요']),
          );
          // The copy made inside the apply is a local write: it uploads.
          final pending = await store.sync.pendingChanges();
          expect(
            pending.where((e) => e.kind == EntityKind.markdown),
            hasLength(3),
          );
        },
      );

      test(
        'received text still newer: the autosaved text is kept too',
        () async {
          await editLocally('로컬1');
          final r = remote('원격', ahead: 60000);
          await store.sync.keepMarkdownConflictCopy(r.body, r.versions);
          await editLocally('로컬1 더 씀');
          await apply(r);
          expect((await doc(note.id)).text, '원격');
          expect(await allTexts(), containsAll(['로컬1', '로컬1 더 씀']));
        },
      );

      test(
        'an unsent edit that appears only after the pre-pass is kept',
        () async {
          final r = remote('원격', ahead: 60000);
          expect(
            await store.sync.keepMarkdownConflictCopy(r.body, r.versions),
            isNull,
          );
          await editLocally('사이에 쓴 글');
          await apply(r);
          expect((await doc(note.id)).text, '원격');
          expect(await allTexts(), contains('사이에 쓴 글'));
        },
      );

      test('no autosave: the apply makes no second copy', () async {
        await editLocally('로컬1');
        final r = remote('원격');
        await store.sync.keepMarkdownConflictCopy(r.body, r.versions);
        await apply(r);
        expect(await allTexts(), unorderedEquals(['원격', '로컬1']));
        final kv = await store.db
            .customSelect("SELECT key FROM kv WHERE key LIKE 'md.guarded.%'")
            .get();
        expect(kv, isEmpty);
      });

      test(
        'an apply without the pre-pass still keeps the losing text',
        () async {
          await editLocally('로컬1');
          await apply(remote('원격'));
          expect(await allTexts(), unorderedEquals(['원격', '로컬1']));
        },
      );
    },
  );

  test('base_text_version: after a copy it is the received version (one '
      'divergence, one copy)', () async {
    await editLocally('내 글');
    final r = remote('남 글');
    await store.sync.keepMarkdownConflictCopy(r.body, r.versions);
    // Asked again for the same record before it was applied: nothing new.
    expect(
      await store.sync.keepMarkdownConflictCopy(r.body, r.versions),
      isNull,
    );
  });
}
