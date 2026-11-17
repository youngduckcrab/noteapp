// B-7 / B-9 / MD-T15 / MD-T16 (08-markdown 8.5, 8.7): the controller on the fake store —
// load, autosave, echo, incoming changes (clean / dirty → conflict copy), failures keep
// the text, CRLF + BOM kept after an edit, task toggles, read-only states, flush.
import 'dart:async';

import 'package:feature_markdown/src/screen/markdown_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';

/// A repository whose saves can be made to fail.
final class _FlakyRepo implements MarkdownRepository {
  _FlakyRepo(this.inner);
  final MarkdownRepository inner;
  Object? failWith;
  int saves = 0;

  @override
  Stream<MarkdownDoc?> watch(NoteId id) => inner.watch(id);
  @override
  Future<MarkdownDoc?> get(NoteId id) => inner.get(id);
  @override
  Future<Note> create({
    FolderId? folderId,
    required String title,
    String text = '',
  }) => inner.create(folderId: folderId, title: title, text: text);
  @override
  Future<String> preview(
    NoteId id, {
    int maxChars = MarkdownLimits.previewChars,
  }) => inner.preview(id, maxChars: maxChars);
  @override
  Future<MarkdownSaveResult> saveText(
    NoteId id,
    String text, {
    required Hlc? baseVersion,
  }) async {
    saves++;
    final f = failWith;
    if (f != null) throw StateError('$f');
    return inner.saveText(id, text, baseVersion: baseVersion);
  }
}

Future<void> _settle([int ms = 60]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late NoteStore store;
  late _FlakyRepo repo;
  var storeFlushes = 0;

  setUp(() {
    store = createFakeNoteStore();
    repo = _FlakyRepo(store.markdown);
    storeFlushes = 0;
  });
  tearDown(() => store.close());

  Future<(MarkdownController, NoteId)> open(String text) async {
    final note = await store.markdown.create(title: '문서', text: text);
    final c = MarkdownController(
      noteId: note.id,
      repository: repo,
      flushStore: () async => storeFlushes++,
      debounce: const Duration(milliseconds: 20),
      maxWait: const Duration(milliseconds: 200),
    );
    addTearDown(c.dispose);
    await _settle(10);
    expect(c.loaded, isTrue);
    return (c, note.id);
  }

  Future<String> stored(NoteId id) async =>
      (await store.markdown.get(id))!.text;

  test('loads the decoded text and the base version', () async {
    final (c, id) = await open('﻿# 제목\r\n본문\r\n');
    expect(c.text.text, '# 제목\n본문\n');
    expect(c.base, (await store.markdown.get(id))!.textVersion);
    expect(c.state, MdSaveState.saved);
    expect(c.dirty, isFalse);
    expect(c.canEdit, isTrue);
    expect(c.encoded, '﻿# 제목\r\n본문\r\n');
  });

  test(
    'typing saves after the debounce; CRLF and BOM are kept (MD-T16)',
    () async {
      final (c, id) = await open('﻿가\r\n나\r\n');
      c.text.text = '가\n나다\n';
      expect(c.dirty, isTrue);
      expect(c.state, MdSaveState.pending);
      await _settle();
      expect(c.state, MdSaveState.saved);
      expect(c.dirty, isFalse);
      expect(await stored(id), '﻿가\r\n나다\r\n');
    },
  );

  test('our own save coming back does not move the cursor', () async {
    final (c, _) = await open('abc');
    c.text.value = const TextEditingValue(
      text: 'abcd',
      selection: TextSelection.collapsed(offset: 2),
    );
    final revision = c.revision;
    await _settle();
    expect(c.text.selection.baseOffset, 2);
    expect(c.revision, revision);
  });

  test('another device\'s text replaces a clean buffer, cursor kept', () async {
    final (c, id) = await open('one two three');
    c.text.selection = const TextSelection.collapsed(offset: 4);
    final v = await FakeMarkdownHooks.remoteText(
      store,
      id,
      'one TWO three four',
    );
    await _settle(10);
    expect(c.text.text, 'one TWO three four');
    expect(c.text.selection.baseOffset, 4);
    expect(c.base, v);
    expect(c.dirty, isFalse);
  });

  test(
    'a dirty buffer is kept; the next save leaves a conflict copy',
    () async {
      final (c, id) = await open('원문');
      c.text.text = '내가 고친 글';
      await FakeMarkdownHooks.remoteText(store, id, '다른 기기 글');
      await _settle(5);
      expect(c.text.text, '내가 고친 글');
      await c.flush();
      expect(await stored(id), '내가 고친 글');
      expect(c.conflictCopyId, isNotNull);
      expect((await store.markdown.get(c.conflictCopyId!))!.text, '다른 기기 글');
      c.dismissConflictCopy();
      expect(c.conflictCopyId, isNull);
    },
  );

  test('a failed save keeps the text; retry saves it', () async {
    final (c, id) = await open('a');
    repo.failWith = 'disk';
    c.text.text = 'ab';
    await _settle();
    expect(c.state, MdSaveState.failed);
    expect(c.failure, MdSaveFailure.error);
    expect(c.text.text, 'ab');
    expect(c.dirty, isTrue);
    expect(await c.flush(), isFalse);
    repo.failWith = null;
    expect(await c.flush(), isTrue);
    expect(c.state, MdSaveState.saved);
    expect(await stored(id), 'ab');
  });

  test('too large: tooLarge failure, nothing written, text kept', () async {
    final (c, id) = await open('a');
    final big = 'x' * (MarkdownLimits.maxTextBytes + 1);
    c.text.text = big;
    expect(await c.flush(), isFalse);
    expect(c.failure, MdSaveFailure.tooLarge);
    expect(c.text.text, big);
    expect(await stored(id), 'a');
  });

  test('task toggle flips one character and saves at once', () async {
    const src = '- [ ] 하나\n- [x] 둘';
    final (c, id) = await open(src);
    expect(await c.toggleTaskAt(src.indexOf('[ ]') + 1), isTrue);
    expect(await stored(id), '- [x] 하나\n- [x] 둘');
    expect(await c.toggleTaskAt(src.indexOf('[x]') + 1), isTrue);
    expect(await stored(id), '- [x] 하나\n- [ ] 둘');
    // not a box mark
    expect(await c.toggleTaskAt(0), isFalse);
    expect(await c.toggleTaskAt(999), isFalse);
  });

  test(
    'read-only: trashed, body missing (then arriving), too large to edit',
    () async {
      final (c, id) = await open('본문');
      await store.library.trashItems([NoteRef(id)]);
      await _settle(10);
      expect(c.doc!.readOnlyReason, MarkdownReadOnlyReason.trashed);
      expect(c.canEdit, isFalse);

      final note = await store.markdown.create(title: '빈', text: '받는 중');
      await FakeMarkdownHooks.removeBody(store, note.id);
      final c2 = MarkdownController(
        noteId: note.id,
        repository: repo,
        flushStore: () async {},
      );
      addTearDown(c2.dispose);
      await _settle(10);
      expect(c2.doc!.readOnlyReason, MarkdownReadOnlyReason.bodyMissing);
      expect(c2.canEdit, isFalse);
      await FakeMarkdownHooks.remoteText(store, note.id, '도착한 글');
      await _settle(10);
      expect(c2.text.text, '도착한 글');
      expect(c2.canEdit, isTrue);

      final (c3, _) = await open('y' * (kMaxEditUnits + 1));
      expect(c3.tooLargeToEdit, isTrue);
      expect(c3.canEdit, isFalse);
    },
  );

  test('missing document', () async {
    final ink = await store.library.createNote(title: '필기');
    final c = MarkdownController(
      noteId: ink.id,
      repository: repo,
      flushStore: () async {},
    );
    addTearDown(c.dispose);
    await _settle(10);
    expect(c.loaded, isTrue);
    expect(c.missing, isTrue);
    expect(c.doc, isNull);
  });

  test('flush saves whatever the composition and flushes the store', () async {
    final (c, id) = await open('가');
    c.text.value = const TextEditingValue(
      text: '가나',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 1, end: 2),
    );
    expect(await c.flush(store: true), isTrue);
    expect(await stored(id), '가나');
    expect(storeFlushes, 1);
  });

  test('saves while typing goes on are chained, the last text wins', () async {
    final (c, id) = await open('');
    for (var i = 0; i < 20; i++) {
      c.text.text = 'x' * i;
      await _settle(3);
    }
    await c.flush();
    expect(await stored(id), 'x' * 19);
    expect(c.dirty, isFalse);
    unawaited(c.flush());
  });
}
