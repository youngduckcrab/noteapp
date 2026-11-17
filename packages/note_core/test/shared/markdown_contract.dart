// (v2.17-md, m5-7/08-markdown 12.1, MD-T02 · MD-T03 · MD-T05) The shared contract of
// MarkdownRepository: the fake store (test/repo/fake_markdown_test.dart) and the SQLite store
// (test/repo/markdown_contract_real_test.dart) pass the same cases. Store-specific situations
// (a body that has not arrived yet, another device's text) come through [MarkdownTestHooks].
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:note_core/note_core.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

/// How a store simulates the sync situations of an MD 문서.
typedef MarkdownTestHooks = ({
  Future<void> Function(NoteStore store, NoteId noteId) removeBody,
  Future<Hlc> Function(NoteStore store, NoteId noteId, String text) remoteText,
});

void defineMarkdownContract(
  FutureOr<NoteStore> Function(Clock clock) open,
  MarkdownTestHooks hooks,
) {
  late NoteStore store;
  late MarkdownRepository md;
  var now = DateTime.utc(2026, 11, 17, 9, 30);

  setUp(() async {
    now = DateTime.utc(2026, 11, 17, 9, 30);
    store = await open(Clock(() => now));
    md = store.markdown;
  });
  tearDown(() => store.close());

  Future<MarkdownDoc> doc(NoteId id) async => (await md.get(id))!;

  test(
    'create: an MD note without pages, listed with the notes, in recent',
    () async {
      final folder = await store.library.createFolder(name: '폴더');
      final note = await md.create(
        folderId: folder.id,
        title: '  회의록 ',
        text: '# 제목\r\n',
      );
      expect(note.isMarkdown, isTrue);
      expect(note.schemaVersion, kMarkdownNoteSchemaVersion);
      expect(note.title, '회의록');
      expect(note.pageCount, 0);
      expect(note.firstPageId, isNull);
      final listing = await store.library
          .watchListing(LibraryQuery(folderId: folder.id))
          .first;
      expect(listing.notes.map((n) => n.id), [note.id]);
      final d = await doc(note.id);
      expect(d.text, '# 제목\r\n');
      expect(d.bodyPresent, isTrue);
      expect(d.textVersion, isNotNull);
      expect(d.isReadOnly, isFalse);
      expect(await md.preview(note.id), '제목');
      await store.library.markOpened(note.id);
      final recent = await store.library.watchRecentNotes().first;
      expect(recent.map((n) => n.id), contains(note.id));
    },
  );

  test('create validation: title, folder, size — nothing written', () async {
    expect(() => md.create(title: '  '), throwsArgumentError);
    expect(
      () => md.create(folderId: 'nope', title: 'x'),
      throwsA(isA<EntityNotFoundException>()),
    );
    expect(
      () => md.create(title: 'x', text: 'a' * 400001),
      throwsA(isA<MarkdownTooLargeException>()),
    );
    final listing = await store.library
        .watchListing(const LibraryQuery())
        .first;
    expect(listing.notes, isEmpty);
  });

  test('saveText: saved / unchanged, updatedAt bumped, watch emits', () async {
    final note = await md.create(title: 'a', text: 'one');
    final first = await doc(note.id);
    final events = <MarkdownDoc?>[];
    final sub = md.watch(note.id).listen(events.add);
    await pumpEventQueue();
    now = now.add(const Duration(minutes: 1));
    final r = await md.saveText(note.id, 'two', baseVersion: first.textVersion);
    expect(r.outcome, MarkdownSaveOutcome.saved);
    expect(r.conflictCopyId, isNull);
    expect(r.textVersion! > first.textVersion!, isTrue);
    final after = await doc(note.id);
    expect(after.text, 'two');
    expect(after.textVersion, r.textVersion);
    expect(after.note.updatedAt, greaterThan(note.updatedAt));
    final same = await md.saveText(note.id, 'two', baseVersion: r.textVersion);
    expect(same.outcome, MarkdownSaveOutcome.unchanged);
    expect(same.textVersion, r.textVersion);
    await pumpEventQueue();
    expect(events.map((e) => e?.text), ['one', 'two']);
    await sub.cancel();
  });

  test(
    'saveText with a stale base keeps the stored text as a conflict copy',
    () async {
      final folder = await store.library.createFolder(name: 'f');
      final note = await md.create(
        folderId: folder.id,
        title: '문서',
        text: 'base',
      );
      final loaded = await doc(note.id);
      // Another device's text arrives while the editor still holds its buffer.
      final remote = await hooks.remoteText(store, note.id, 'theirs');
      expect((await doc(note.id)).textVersion, remote);
      final r = await md.saveText(
        note.id,
        'mine',
        baseVersion: loaded.textVersion,
      );
      expect(r.outcome, MarkdownSaveOutcome.savedWithConflictCopy);
      expect((await doc(note.id)).text, 'mine');
      final copy = await doc(r.conflictCopyId!);
      expect(copy.text, 'theirs');
      expect(copy.note.folderId, folder.id);
      expect(copy.note.title, '문서 (충돌 사본 2026-11-17 09:30)');
      // Saving again from the new base is a plain save.
      final again = await md.saveText(
        note.id,
        'mine 2',
        baseVersion: r.textVersion,
      );
      expect(again.outcome, MarkdownSaveOutcome.saved);
      final listing = await store.library
          .watchListing(LibraryQuery(folderId: folder.id))
          .first;
      expect(listing.notes, hasLength(2));
    },
  );

  test('saveText refusals change nothing', () async {
    final note = await md.create(title: 'a', text: 'x');
    final v = (await doc(note.id)).textVersion;
    expect(
      () => md.saveText('missing', 'y', baseVersion: v),
      throwsA(isA<EntityNotFoundException>()),
    );
    final ink = await store.library.createNote(title: 'ink');
    expect(
      () => md.saveText(ink.id, 'y', baseVersion: null),
      throwsA(isA<WrongNoteFormatException>()),
    );
    expect(await md.get(ink.id), isNull);
    expect(
      () => md.saveText(note.id, 'a' * 400001, baseVersion: v),
      throwsA(isA<MarkdownTooLargeException>()),
    );
    await store.library.trashItems([NoteRef(note.id)]);
    final trashed = await doc(note.id);
    expect(trashed.readOnlyReason, MarkdownReadOnlyReason.trashed);
    expect(
      () => md.saveText(note.id, 'y', baseVersion: v),
      throwsA(isA<ReadOnlyNoteException>()),
    );
    await store.trash.restore([NoteRef(note.id)]);
    expect((await doc(note.id)).text, 'x');
  });

  test('a note without its body is read-only (bodyPresent false)', () async {
    final note = await md.create(title: 'a', text: 'x');
    await hooks.removeBody(store, note.id);
    final d = await doc(note.id);
    expect(d.bodyPresent, isFalse);
    expect(d.text, '');
    expect(d.readOnlyReason, MarkdownReadOnlyReason.bodyMissing);
    expect(
      () => md.saveText(note.id, 'y', baseVersion: null),
      throwsA(isA<ReadOnlyNoteException>()),
    );
    expect(await md.preview(note.id), '');
  });

  test(
    'openSession refuses an MD document (WrongNoteFormatException)',
    () async {
      final note = await md.create(title: 'a');
      expect(
        () => store.openSession(note.id),
        throwsA(isA<WrongNoteFormatException>()),
      );
    },
  );

  test('copyItems copies the body; purge removes it', () async {
    final note = await md.create(title: 'a', text: '본문');
    final copies = await store.library.copyItems(
      [NoteRef(note.id)],
      targetFolderId: null,
      nameSuffix: ' 사본',
    );
    final copyId = copies.single.id;
    final copy = await doc(copyId);
    expect(copy.text, '본문');
    expect(copy.note.isMarkdown, isTrue);
    expect(copy.note.title, 'a 사본');
    await store.library.trashItems([NoteRef(note.id)]);
    await store.trash.purge([NoteRef(note.id)]);
    expect(await md.get(note.id), isNull);
    expect((await doc(copyId)).text, '본문');
  });

  test('providers: doc, preview keyed by updatedAt', () async {
    final container = ProviderContainer(
      overrides: [noteStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final note = await md.create(title: 'a', text: '첫 줄');
    final sub = container.listen(markdownDocProvider(note.id), (_, _) {});
    addTearDown(sub.close);
    final d = await container.read(markdownDocProvider(note.id).future);
    expect(d!.text, '첫 줄');
    final preview = await container.read(
      markdownPreviewProvider((noteId: note.id, updatedAt: d.note.updatedAt))
          .future,
    );
    expect(preview, '첫 줄');
    expect(container.read(markdownRepositoryProvider), same(md));
  });

  test(
    'the text is stored byte for byte (BOM, CRLF, Korean, emoji, NUL-free C0)',
    () async {
      const text = '﻿# 제목 🙂\r\n\r\n- [ ] 할 일\r\n\t탭\u0007\r\n';
      final note = await md.create(title: 'bytes', text: text);
      expect((await doc(note.id)).text, text);
      final r = await md.saveText(
        note.id,
        '﻿﻿$text',
        baseVersion: (await doc(note.id)).textVersion,
      );
      expect(r.outcome, MarkdownSaveOutcome.saved);
      expect((await doc(note.id)).text, '﻿﻿$text');
    },
  );

  test(
    'size limits: over maxTextBytes or maxEncodedBytes → nothing changes',
    () async {
      final note = await md.create(title: 'big', text: 'x');
      final v = (await doc(note.id)).textVersion;
      // 400,000 bytes exactly is fine.
      final ok = await md.saveText(note.id, 'a' * 400000, baseVersion: v);
      expect(ok.outcome, MarkdownSaveOutcome.saved);
      // Control characters cost 6 bytes as JSON: under the text limit, over the encoded one.
      expect(
        () => md.saveText(
          note.id,
          '\u0001' * 160000,
          baseVersion: ok.textVersion,
        ),
        throwsA(
          isA<MarkdownTooLargeException>().having(
            (e) => e.encodedBytes,
            'encodedBytes',
            greaterThan(MarkdownLimits.maxEncodedBytes),
          ),
        ),
      );
      expect((await doc(note.id)).text, 'a' * 400000);
    },
  );

  test(
    'search finds the body; the trash hides it; restore brings it back',
    () async {
      final note = await md.create(
        title: '검색',
        text: '# 회의\n\n- [x] **예산** 확정\n\n| 표 | 칸 |\n|---|---|\n| 사과 | 배 |\n',
      );
      final hits = await store.search.searchPages('예산');
      expect(hits.map((h) => (h.noteId, h.pageId, h.source)), [
        (note.id, MarkdownText.idFor(note.id), SearchSource.markdown),
      ]);
      expect(hits.single.rects, isEmpty);
      expect((await store.search.searchPages('사과')).map((h) => h.noteId), [
        note.id,
      ]);
      expect(
        await store.search.searchPages('예산', withinNote: note.id),
        hasLength(1),
      );
      await md.saveText(
        note.id,
        '다른 글',
        baseVersion: (await doc(note.id)).textVersion,
      );
      expect(await store.search.searchPages('예산'), isEmpty);
      expect(await store.search.searchPages('다른'), hasLength(1));
      await store.library.trashItems([NoteRef(note.id)]);
      expect(await store.search.searchPages('다른'), isEmpty);
      await store.trash.restore([NoteRef(note.id)]);
      expect(await store.search.searchPages('다른'), hasLength(1));
      await store.library.trashItems([NoteRef(note.id)]);
      await store.trash.purge([NoteRef(note.id)]);
      expect(await store.search.searchPages('다른'), isEmpty);
    },
  );

  test(
    'search: a word after 1,000 characters is found; rebuild keeps MD bodies',
    () async {
      final long = '${'가나다라 ' * 300}끝말잇기';
      final note = await md.create(title: 'long', text: long);
      expect((await store.search.searchPages('끝말잇기')).map((h) => h.noteId), [
        note.id,
      ]);
      await store.search.rebuild();
      expect((await store.search.searchPages('끝말잇기')).map((h) => h.noteId), [
        note.id,
      ]);
      await store.search.rebuild(sources: const {SearchSource.markdown});
      expect(await store.search.searchPages('끝말잇기'), hasLength(1));
    },
  );

  test(
    'a copy without a body gets an empty body; recent and rename work',
    () async {
      final note = await md.create(title: 'a', text: 'x');
      await hooks.removeBody(store, note.id);
      final copies = await store.library.copyItems([
        NoteRef(note.id),
      ], targetFolderId: null);
      final copy = await doc(copies.single.id);
      expect(copy.bodyPresent, isTrue);
      expect(copy.text, '');
      final other = await md.create(title: 'b', text: 'y');
      await store.library.renameNote(other.id, '새 이름');
      expect((await doc(other.id)).note.title, '새 이름');
      expect((await doc(other.id)).text, 'y');
      final folder = await store.library.createFolder(name: '옮김');
      await store.library.moveItems([
        NoteRef(other.id),
      ], targetFolderId: folder.id);
      expect((await doc(other.id)).note.folderId, folder.id);
    },
  );
}
