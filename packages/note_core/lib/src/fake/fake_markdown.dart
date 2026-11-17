// Internal: the fake store's MarkdownRepository (v2.17-md, m5-7/08-markdown 12.1 / C217M-04).
// Same validation, conflict-copy and read-only rules as the real store; bodies live in
// FakeNoteStore.markdownRows. Until Track A adds EntityKind.markdown a body write is reported
// as a change of its note (ChangeBatch), which is what the library and the screen listen to.
import 'package:meta/meta.dart';

import '../common/errors.dart';
import '../common/hlc.dart';
import '../common/ids.dart';
import '../common/sort_planner.dart';
import '../model/note.dart';
import '../repo/events.dart';
import '../repo/markdown_repository.dart';
import '../session/page_content.dart';
import 'fake_note_store.dart';

/// One body row of the fake store.
@immutable
final class FakeMarkdownBody {
  const FakeMarkdownBody({
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
  });

  final String text;
  final EpochMillis createdAt;
  final EpochMillis updatedAt;
  final Hlc version;
}

/// Node id of the fake store's simulated other device (`FakeMarkdownHooks.remoteText`).
const String kFakeRemoteNodeId = 'ffffffffffffffff';

String _checkTitle(String title) {
  final t = title.trim();
  if (t.isEmpty || t.length > 200) {
    throw ArgumentError.value(
      title,
      'title',
      'must be 1..200 characters after trim',
    );
  }
  return t;
}

final class FakeMarkdown implements MarkdownRepository {
  FakeMarkdown(this.s);

  final FakeNoteStore s;

  /// The own note [id] (any state), or null.
  Note? _ownNote(NoteId id) {
    final n = s.notes[id];
    return n != null && n.ownerId == s.ownerId ? n : null;
  }

  MarkdownDoc? docOf(NoteId id) {
    final n = _ownNote(id);
    if (n == null || !n.isMarkdown) return null;
    final body = s.markdownRows[id];
    return MarkdownDoc(
      note: n,
      text: body?.text ?? '',
      bodyPresent: body != null,
      textVersion: body?.version,
    );
  }

  @override
  Stream<MarkdownDoc?> watch(NoteId id) => s.watch(() => docOf(id));

  @override
  Future<MarkdownDoc?> get(NoteId id) async => docOf(id);

  /// A new MD 문서 note + body at the end of [folderId] (also the conflict copy).
  Note insert({
    required FolderId? folderId,
    required String title,
    required String text,
    required Hlc v,
    required List<EntityChange> changes,
  }) {
    final now = s.now;
    final id = s.ids.newId();
    final note = Note(
      id: id,
      ownerId: s.ownerId,
      folderId: folderId,
      title: title,
      sortKey: sortKeyAfterAll(
        s.ownNotes
            .where((n) => !n.isDeleted && n.folderId == folderId)
            .map((n) => n.sortKey),
      ),
      schemaVersion: kMarkdownNoteSchemaVersion,
      createdAt: now,
      updatedAt: now,
      version: v,
    );
    s.notes[id] = note;
    s.markdownRows[id] = FakeMarkdownBody(
      text: text,
      createdAt: now,
      updatedAt: now,
      version: v,
    );
    changes.add(s.changeOf(note));
    return note;
  }

  @override
  Future<Note> create({
    FolderId? folderId,
    required String title,
    String text = '',
  }) async {
    final t = _checkTitle(title);
    MarkdownLimits.check(text);
    return s.write(() {
      if (folderId != null && s.activeFolder(folderId) == null) {
        throw EntityNotFoundException('Folder $folderId does not exist');
      }
      final changes = <EntityChange>[];
      final note = insert(
        folderId: folderId,
        title: t,
        text: text,
        v: s.hlc.now(),
        changes: changes,
      );
      s.record(ChangeOrigin.local, changes);
      return note;
    });
  }

  @override
  Future<MarkdownSaveResult> saveText(
    NoteId id,
    String text, {
    required Hlc? baseVersion,
  }) async {
    MarkdownLimits.check(text);
    return s.write(() {
      final n = _ownNote(id);
      if (n == null) throw EntityNotFoundException('Note $id does not exist');
      if (!n.isMarkdown) {
        throw WrongNoteFormatException('Note $id is not an MD document');
      }
      final doc = docOf(id)!;
      if (doc.isReadOnly) {
        throw ReadOnlyNoteException(
          'MD document $id is read-only (${doc.readOnlyReason!.name})',
        );
      }
      final stored = s.markdownRows[id]!;
      if (stored.text == text) {
        return MarkdownSaveResult(
          outcome: MarkdownSaveOutcome.unchanged,
          textVersion: stored.version,
        );
      }
      final v = s.hlc.now();
      final changes = <EntityChange>[];
      NoteId? copyId;
      if (stored.version != baseVersion) {
        // The stored text changed since the caller loaded it: keep it (C217M-07 L1).
        copyId = insert(
          folderId: n.folderId,
          title: MarkdownConflictCopy.titleFor(n.title, s.clock.now()),
          text: stored.text,
          v: v,
          changes: changes,
        ).id;
      }
      final now = s.now;
      s.markdownRows[id] = FakeMarkdownBody(
        text: text,
        createdAt: stored.createdAt,
        updatedAt: now,
        version: v,
      );
      final note = n.copyWith(updatedAt: now, version: v);
      s.notes[id] = note;
      changes.add(s.changeOf(note));
      s.record(ChangeOrigin.local, changes);
      return MarkdownSaveResult(
        outcome: copyId == null
            ? MarkdownSaveOutcome.saved
            : MarkdownSaveOutcome.savedWithConflictCopy,
        textVersion: v,
        conflictCopyId: copyId,
      );
    });
  }

  @override
  Future<String> preview(
    NoteId id, {
    int maxChars = MarkdownLimits.previewChars,
  }) async {
    final doc = docOf(id);
    return doc == null
        ? ''
        : MarkdownPreviewText.of(doc.text, maxChars: maxChars);
  }

  /// The body copy of copyItems / recovery copies ([from] → [to]); a document whose body
  /// has not arrived gets an empty body (08-markdown 4.5).
  void copyBody(NoteId from, NoteId to, Hlc v) {
    final now = s.now;
    s.markdownRows[to] = FakeMarkdownBody(
      text: s.markdownRows[from]?.text ?? '',
      createdAt: now,
      updatedAt: now,
      version: v,
    );
  }

  // ---- test hooks (testing.dart FakeMarkdownHooks) ---------------------------------

  /// The body of [id] removed (a note that arrived before its body).
  Future<void> debugRemoveBody(NoteId id) => s.write(() {
    if (s.markdownRows.remove(id) == null) return;
    final n = s.notes[id];
    if (n != null) s.record(ChangeOrigin.remote, [s.changeOf(n)]);
  });

  /// [text] written as if it came from another device (origin remote, a version of
  /// [kFakeRemoteNodeId] newer than every local one; no conflict copy — that is the sync
  /// path's job).
  Future<Hlc> debugRemoteText(NoteId id, String text) => s.write(() {
    final n = _ownNote(id);
    if (n == null || !n.isMarkdown) {
      throw EntityNotFoundException('MD document $id does not exist');
    }
    final local = s.hlc.now();
    final v = Hlc(local.millis, local.counter + 1, kFakeRemoteNodeId);
    s.hlc.receive(v);
    final now = s.now;
    s.markdownRows[id] = FakeMarkdownBody(
      text: text,
      createdAt: s.markdownRows[id]?.createdAt ?? now,
      updatedAt: now,
      version: v,
    );
    final note = n.copyWith(updatedAt: now);
    s.notes[id] = note;
    s.record(ChangeOrigin.remote, [s.changeOf(note)]);
    return v;
  });
}
