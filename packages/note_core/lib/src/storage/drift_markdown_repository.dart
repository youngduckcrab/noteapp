// lib/src/storage/drift_markdown_repository.dart — (v2.17-md) the real store's
// MarkdownRepository (m5-7/08-markdown 4.3–4.5, 5.3, 12.1; C217M-03 · 04 · 05 · 07).
//
// An MD 문서 = a notes row (schema_version 100..199, no pages) + one md_docs row (id
// 'md_<noteId>'). Writes go through the write queue: the body with putLocal (field versions,
// outbox ['text'] with the noteId hint, the search hook inside the job's savepoint), the
// note's updated_at bumped as a local-only value (no outbox entry — other devices bump it
// when the body arrives, DriftSyncStore applyRemote). md_docs.base_text_version is
// device-local: the text version this device knows the server has (5.3 L2).
import 'package:drift/drift.dart';

import '../common/errors.dart';
import '../common/hlc.dart';
import '../common/ids.dart';
import '../model/markdown_text.dart';
import '../model/note.dart';
import '../model/sync_entity.dart';
import '../repo/markdown_repository.dart';
import '../sync/field_versions.dart';
import '../sync/outbox_types.dart';
import 'db/note_database.dart';
import 'drift_library_repository.dart';
import 'drift_note_store.dart';
import 'outbox_writer.dart';
import 'row_mappers.dart';
import 'watch_hub.dart';
import 'write_queue.dart';

bool _touchesMarkdown(CommitTouch t) =>
    t.kinds.contains(EntityKind.note) || t.kinds.contains(EntityKind.markdown);

/// The kv key of the last conflict copy this device made for an MD 문서 (5.3: copies of
/// one document within [kMarkdownConflictCopyWindow] are rewritten, not multiplied).
String markdownConflictCopyKey(NoteId noteId) => 'md.conflictCopy.$noteId';

/// 5.3 — one live conflict copy per document per 10 minutes.
const Duration kMarkdownConflictCopyWindow = Duration(minutes: 10);

/// What [DriftMarkdownRepository.guardRemoteText] did.
typedef MarkdownGuardOutcome = ({NoteId noteId, NoteId copyId, bool rewrote});

final class DriftMarkdownRepository implements MarkdownRepository {
  DriftMarkdownRepository(this.s);

  final DriftNoteStore s;

  NoteDatabase get _db => s.db;

  Future<NoteRow?> _noteRow(NoteId id) =>
      (_db.select(_db.notes)
            ..where((t) => t.id.equals(id) & t.ownerId.equals(s.ownerId)))
          .getSingleOrNull();

  Future<MdDocRow?> _bodyRow(NoteId noteId) => (_db.select(
    _db.mdDocs,
  )..where((t) => t.id.equals(MarkdownText.idFor(noteId)))).getSingleOrNull();

  Future<MarkdownDoc?> _doc(NoteId id) async {
    final r = await _noteRow(id);
    if (r == null) return null;
    final note = noteOf(r);
    if (!note.isMarkdown) return null;
    final body = await _bodyRow(id);
    if (body == null) {
      return MarkdownDoc(note: note, text: '', bodyPresent: false);
    }
    return MarkdownDoc(
      note: note,
      text: markdownTextOf(body),
      bodyPresent: true,
      textVersion: fieldVersionsOf(body.version, body.fieldVersions).of('text'),
    );
  }

  @override
  Stream<MarkdownDoc?> watch(NoteId id) =>
      s.watches.watch(affects: _touchesMarkdown, query: () => _doc(id));

  @override
  Future<MarkdownDoc?> get(NoteId id) => _doc(id);

  DriftLibraryRepository get _library => s.library;

  /// A new MD 문서 (note + body) inside [tx]. The caller checked title and text.
  Future<Note> insertDocument(
    WriteTxn tx, {
    required FolderId? folderId,
    required String title,
    required String text,
  }) async {
    final note = Note(
      id: s.ids.newId(),
      ownerId: s.ownerId,
      folderId: folderId,
      title: title,
      sortKey: await _library.sortKeyAtEnd(folderId),
      schemaVersion: kMarkdownNoteSchemaVersion,
      createdAt: tx.now,
      updatedAt: tx.now,
    );
    final v = await tx.putLocal(note, const {kAllFields}, isNew: true);
    await tx.putLocal(
      MarkdownText(
        noteId: note.id,
        text: text,
        createdAt: tx.now,
        updatedAt: tx.now,
      ),
      const {kAllFields},
      isNew: true,
    );
    return note.copyWith(version: v.max);
  }

  @override
  Future<Note> create({
    FolderId? folderId,
    required String title,
    String text = '',
  }) async {
    final t = checkLibraryName(title, what: 'title');
    MarkdownLimits.check(text);
    return s.queue.run((tx) async {
      await _library.requireTarget(folderId);
      return insertDocument(tx, folderId: folderId, title: t, text: text);
    }, bytes: text.length);
  }

  /// Writes [text] as the body of [noteId] (row exists or not) and bumps the note's
  /// updated_at (local value). Returns the new text field version.
  Future<Hlc> _writeText(
    WriteTxn tx,
    Note note,
    String text, {
    required MdDocRow? stored,
  }) async {
    final body = MarkdownText(
      noteId: note.id,
      text: text,
      createdAt: stored?.createdAt ?? tx.now,
      updatedAt: tx.now,
    );
    final versions = await tx.putLocal(
      body,
      stored == null ? const {kAllFields} : const {'text'},
      isNew: stored == null,
    );
    await tx.putLocal(note.copyWith(updatedAt: tx.now), const {'updatedAt'});
    return versions.of('text');
  }

  @override
  Future<MarkdownSaveResult> saveText(
    NoteId id,
    String text, {
    required Hlc? baseVersion,
  }) async {
    MarkdownLimits.check(text);
    return s.queue.run((tx) async {
      final doc = await _doc(id);
      if (doc == null) {
        final r = await _noteRow(id);
        if (r == null) throw EntityNotFoundException('Note $id does not exist');
        throw WrongNoteFormatException('Note $id is not an MD document');
      }
      if (doc.isReadOnly) {
        throw ReadOnlyNoteException(
          'MD document $id is read-only (${doc.readOnlyReason!.name})',
        );
      }
      if (doc.text == text) {
        return MarkdownSaveResult(
          outcome: MarkdownSaveOutcome.unchanged,
          textVersion: doc.textVersion,
        );
      }
      NoteId? copyId;
      if (doc.textVersion != baseVersion) {
        // The stored text changed since the caller loaded it: keep it (C217M-07 L1).
        copyId = (await insertDocument(
          tx,
          folderId: doc.note.folderId,
          title: MarkdownConflictCopy.titleFor(doc.note.title, s.clock.now()),
          text: doc.text,
        )).id;
      }
      final v = await _writeText(
        tx,
        doc.note,
        text,
        stored: await _bodyRow(id),
      );
      return MarkdownSaveResult(
        outcome: copyId == null
            ? MarkdownSaveOutcome.saved
            : MarkdownSaveOutcome.savedWithConflictCopy,
        textVersion: v,
        conflictCopyId: copyId,
      );
    }, bytes: text.length);
  }

  /// Characters read for a preview: enough for front matter and markup around
  /// [maxChars] visible characters.
  static int _previewWindow(int maxChars) => maxChars * 8 + 2000;

  @override
  Future<String> preview(
    NoteId id, {
    int maxChars = MarkdownLimits.previewChars,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT substr(d.text, 1, ?) AS t FROM md_docs d '
          'JOIN notes n ON n.id = d.note_id '
          'WHERE d.id = ? AND n.owner_id = ?',
          variables: [
            Variable<int>(_previewWindow(maxChars)),
            Variable<String>(MarkdownText.idFor(id)),
            Variable<String>(s.ownerId),
          ],
          readsFrom: {_db.mdDocs, _db.notes},
        )
        .get();
    if (rows.isEmpty) return '';
    return MarkdownPreviewText.of(
      rows.first.read<String>('t'),
      maxChars: maxChars,
    );
  }

  // ---- internal paths (copy, purge, sync) ------------------------------------------

  /// copyItems / duplicateNoteForRecovery: the body of [from] for the new note [to]
  /// ('' when [from] has no body yet).
  Future<void> copyBody(WriteTxn tx, NoteId from, NoteId to) async {
    final stored = await _bodyRow(from);
    await tx.putLocal(
      MarkdownText(
        noteId: to,
        text: stored == null ? '' : markdownTextOf(stored),
        createdAt: tx.now,
        updatedAt: tx.now,
      ),
      const {kAllFields},
      isNew: true,
    );
  }

  /// base_text_version := max(stored, [v]) of the body [bodyId] (5.3 (1) and (3)).
  Future<void> raiseBase(String bodyId, Hlc v) async {
    final r = await (_db.select(
      _db.mdDocs,
    )..where((t) => t.id.equals(bodyId))).getSingleOrNull();
    if (r == null) return;
    final base = r.baseTextVersion;
    if (base != null && Hlc.parse(base).compareTo(v) >= 0) return;
    await (_db.update(_db.mdDocs)..where((t) => t.id.equals(bodyId))).write(
      MdDocsCompanion(baseTextVersion: Value(v.toString())),
    );
  }

  /// (C217M-07 L2) Before the received body [remote] (versions [versions]) is applied:
  /// when this device has an unsent text of the same document that differs, and the
  /// received text version is newer than base_text_version and not this device's own,
  /// the text that will lose the field merge (newer text version wins — the merge rule of
  /// a one-field unit) is kept byte for byte as an MD 문서 '<title> (충돌 사본 …)' in the same
  /// folder — or written into this device's copy of the last 10 minutes when it is still
  /// alive — and base_text_version becomes the received version. null: nothing to keep.
  Future<MarkdownGuardOutcome?> guardRemoteText(
    MarkdownText remote,
    EntityFieldVersions versions,
  ) => s.queue.run((tx) async {
    final noteId = remote.noteId;
    final stored = await _bodyRow(noteId);
    if (stored == null || stored.id != remote.id) return null;
    final entry = await outboxRowOf(_db, EntityKind.markdown, stored.id);
    if (entry == null || entry.op != OutboxOp.upsert.name) return null;
    final pending = outboxFieldsOf(entry);
    if (!pending.contains('text') && !pending.contains(kAllFields)) return null;
    final storedText = markdownTextOf(stored);
    if (storedText == remote.text) return null;
    final remoteV = versions.of('text');
    final base = stored.baseTextVersion;
    if (base != null && !(remoteV > Hlc.parse(base))) return null;
    if (remoteV.nodeId == s.queue.hlc.nodeId) return null;
    final localV = fieldVersionsOf(
      stored.version,
      stored.fieldVersions,
    ).of('text');
    final loser = remoteV > localV ? storedText : remote.text;
    try {
      MarkdownLimits.check(loser);
    } on MarkdownTooLargeException {
      return null; // cannot be stored here; the other side keeps it
    }
    final noteRow = await _noteRow(noteId);
    if (noteRow == null) return null;
    final note = noteOf(noteRow);
    final now = s.clock.now();
    NoteId? copyId;
    var rewrote = false;
    final key = markdownConflictCopyKey(noteId);
    final kv = await (_db.select(
      _db.kv,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    if (kv != null) {
      final parts = kv.value.split(' ');
      final at = parts.length == 2 ? int.tryParse(parts[1]) : null;
      if (at != null &&
          now.millisecondsSinceEpoch - at <=
              kMarkdownConflictCopyWindow.inMilliseconds) {
        final copy = await _doc(parts[0]);
        if (copy != null && !copy.isReadOnly) {
          if (copy.text != loser) {
            await _writeText(
              tx,
              copy.note,
              loser,
              stored: await _bodyRow(copy.note.id),
            );
          }
          copyId = copy.note.id;
          rewrote = true;
        }
      }
    }
    copyId ??= (await insertDocument(
      tx,
      folderId: await _activeFolderOrNull(note.folderId),
      title: MarkdownConflictCopy.titleFor(note.title, now),
      text: loser,
    )).id;
    await _db
        .into(_db.kv)
        .insertOnConflictUpdate(
          KvCompanion.insert(
            key: key,
            value: '$copyId ${now.millisecondsSinceEpoch}',
          ),
        );
    tx.touchKv(key);
    await raiseBase(stored.id, remoteV);
    return (noteId: noteId, copyId: copyId, rewrote: rewrote);
  });

  Future<FolderId?> _activeFolderOrNull(FolderId? id) async {
    if (id == null) return null;
    final r =
        await (_db.select(_db.folders)..where(
              (t) =>
                  t.id.equals(id) &
                  t.ownerId.equals(s.ownerId) &
                  t.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    return r == null ? null : id;
  }
}
