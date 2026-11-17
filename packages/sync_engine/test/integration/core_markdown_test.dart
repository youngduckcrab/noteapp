// (v2.17-md, A-11 — m5-7/08-markdown 5, MD-T08 · MD-T09) MD 문서 between two real CORE
// stores (DB v3) through the engine: a new document reaches the other device whole; a
// concurrent edit converges and the losing text is kept as exactly ONE conflict copy (and
// a MarkdownConflictCopied notice); trash on one side + an edit on the other keeps both; a
// purge with an unsent edit on the other side keeps a recovered copy WITH its body; a note
// that arrives before its body is read-only until the body comes.
@Tags(['integration'])
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';

import 'support/core_sync_device.dart';

Future<MarkdownDoc?> _doc(CoreSyncDevice d, NoteId id) =>
    d.store.markdown.get(id);

Future<List<Note>> _notes(CoreSyncDevice d) async =>
    (await d.store.library.watchListing(const LibraryQuery()).first).notes;

Future<void> _edit(CoreSyncDevice d, NoteId id, String text) async {
  final doc = (await _doc(d, id))!;
  await d.store.markdown.saveText(id, text, baseVersion: doc.textVersion);
}

void main() {
  coreScenario('M1 a new MD 문서 reaches B whole: title, format, text byte for '
      'byte; B finds it by a word', (s) async {
    final a = await s.device('A');
    final b = await s.device('B');
    const text = '﻿# 회의 메모\r\n\r\n- [ ] 발표 준비 🙂\r\n';
    final note = await a.store.markdown.create(title: '회의', text: text);
    await s.until(
      'the body on B',
      () async => (await _doc(b, note.id))?.bodyPresent ?? false,
    );
    await s.converge([a, b], [note.id]);
    final onB = (await _doc(b, note.id))!;
    expect(onB.note.isMarkdown, isTrue);
    expect(onB.text, text);
    expect(onB.isReadOnly, isFalse);
    await s.until(
      'B finds it',
      () async => (await b.store.search.searchPages('발표')).isNotEmpty,
    );
  });

  coreScenario('M2 concurrent edit offline: both converge to one text and the '
      'other text is kept as exactly one conflict copy', (s) async {
    final a = await s.device('A');
    final b = await s.device('B');
    final copied = listenNotices<MarkdownConflictCopied>([a, b]);
    final note = await a.store.markdown.create(title: '노트', text: '처음');
    await s.until(
      'the body on B',
      () async => (await _doc(b, note.id))?.bodyPresent ?? false,
    );
    await s.converge([a, b], [note.id]);

    a.goOffline();
    b.goOffline();
    await _edit(a, note.id, 'A의 글');
    await nextMillisecond();
    await _edit(b, note.id, 'B의 글'); // later: wins
    a.goOnline();
    await s.settle([a]);
    b.goOnline();
    await s.settle([a, b]);
    await s.until('both have the copy', () async {
      final na = await _notes(a);
      final nb = await _notes(b);
      return na.length == 2 && nb.length == 2;
    });
    await s.converge([a, b], [for (final n in await _notes(a)) n.id]);
    for (final d in [a, b]) {
      expect((await _doc(d, note.id))!.text, 'B의 글', reason: d.name);
      final copies = [
        for (final n in await _notes(d))
          if (n.id != note.id) n,
      ];
      expect(copies, hasLength(1), reason: d.name);
      expect((await _doc(d, copies.single.id))!.text, 'A의 글');
      expect(copies.single.title, startsWith('노트 (충돌 사본 '));
    }
    expect(copied.seen, hasLength(1));
    await copied.cancel();
  });

  coreScenario('M3 the same text on both: no copy', (s) async {
    final a = await s.device('A');
    final b = await s.device('B');
    final note = await a.store.markdown.create(title: '같음', text: '처음');
    await s.until(
      'the body on B',
      () async => (await _doc(b, note.id))?.bodyPresent ?? false,
    );
    await s.converge([a, b], [note.id]);
    a.goOffline();
    b.goOffline();
    await _edit(a, note.id, '같은 글');
    await nextMillisecond();
    await _edit(b, note.id, '같은 글');
    a.goOnline();
    b.goOnline();
    await s.converge([a, b], [note.id]);
    expect(await _notes(a), hasLength(1));
    expect(await _notes(b), hasLength(1));
  });

  coreScenario('M4 trash on A, an edit on B (offline): both land — the trashed '
      'document holds the newest text', (s) async {
    final a = await s.device('A');
    final b = await s.device('B');
    final note = await a.store.markdown.create(title: '휴지통', text: '처음');
    await s.until(
      'the body on B',
      () async => (await _doc(b, note.id))?.bodyPresent ?? false,
    );
    await s.converge([a, b], [note.id]);
    b.goOffline();
    await a.store.library.trashItems([NoteRef(note.id)]);
    await s.settle([a]);
    await nextMillisecond();
    await _edit(b, note.id, '고친 글');
    b.goOnline();
    await s.converge([a, b], [note.id]);
    for (final d in [a, b]) {
      final doc = (await _doc(d, note.id))!;
      expect(doc.note.isDeleted, isTrue, reason: d.name);
      expect(doc.text, '고친 글', reason: d.name);
      expect(doc.readOnlyReason, MarkdownReadOnlyReason.trashed);
    }
  });

  coreScenario('M5 purge on A while B has an unsent edit: B keeps a recovered '
      'copy with the edited text (PurgeGuard)', (s) async {
    final a = await s.device('A');
    final b = await s.device('B');
    final recovered = listenNotices<NoteRecoveredFromPurge>([b]);
    final note = await a.store.markdown.create(title: '지움', text: '처음');
    await s.until(
      'the body on B',
      () async => (await _doc(b, note.id))?.bodyPresent ?? false,
    );
    await s.converge([a, b], [note.id]);
    b.goOffline();
    await _edit(b, note.id, '살려야 할 글');
    await a.core.trashAndPurge(note.id);
    await s.settle([a]);
    b.goOnline();
    await s.until('the purge on B', () async => await _doc(b, note.id) == null);
    await s.settle([a, b]);
    expect(recovered.seen, hasLength(1));
    final copy = (await _doc(b, recovered.seen.single.copyNoteId))!;
    expect(copy.text, '살려야 할 글');
    expect(copy.note.isMarkdown, isTrue);
    await s.until(
      'the copy on A',
      () async => (await _doc(a, copy.note.id))?.bodyPresent ?? false,
    );
    expect((await _doc(a, copy.note.id))!.text, '살려야 할 글');
    await recovered.cancel();
  });

  coreScenario('M6 a device that does not know MD bodies yet holds them; the '
      'note arrives as an MD 문서 without its body (read-only)', (s) async {
    final a = await s.device('A');
    final old = await s.device(
      'old',
      knownKinds: EntityKind.values.toSet()..remove(EntityKind.markdown),
    );
    final note = await a.store.markdown.create(title: '새 형식', text: '본문');
    await s.until(
      'the note on the old device',
      () async => await _doc(old, note.id) != null,
    );
    await s.settle([a, old]);
    final doc = (await _doc(old, note.id))!;
    expect(doc.bodyPresent, isFalse);
    expect(doc.readOnlyReason, MarkdownReadOnlyReason.bodyMissing);
    await expectLater(
      old.store.markdown.saveText(note.id, 'x', baseVersion: null),
      throwsA(isA<ReadOnlyNoteException>()),
    );
  });
}
