// Internal (not exported). Protection before received purges are applied (6.7.4; 2nd round
// 07-sync 6.2.5): a note another device purged while this device still edits it — unsent
// changes of its pages, strokes, recordings or page objects, an unsent change of its own
// non-trash fields, or content of its scope sent in the last purgeGuardWindow — is first
// copied (CORE duplicateNoteForRecovery, which also copies recordings, page objects and
// handwriting results) so the edits survive the purge (S08, S08b). Handwriting results are
// derived data and never an edit: their outbox entries do not count here, and
// UploadPipeline does not report a chunk carrying only handwriting records as sent (D-S11,
// SYNC-M3). Folder purges come with one purge per note of the group (CORE 6.8), so checking
// notes is enough.
import 'package:note_core/note_core.dart';

import '../model/records.dart';
import '../model/scopes.dart';
import '../status/sync_notice.dart';

/// The note's trash unit: changing only these is not an edit worth recovering.
const Set<String> kNoteTrashFields = {'deletedAt', 'trashRootId'};

final class PurgeGuard {
  PurgeGuard({
    required this.sync,
    required this.titleSuffix,
    required this.window,
    required this.nowMillis,
    this.outboxPageSize = 500,
  });

  final SyncStore sync;

  /// SyncConfig.recoveredNoteTitleSuffix.
  final String titleSuffix;

  /// SyncConfig.purgeGuardWindow (10 min).
  final Duration window;

  /// The engine wall clock, ms.
  final int Function() nowMillis;
  final int outboxPageSize;

  /// Note scope → when this device last committed records of it (ms).
  final Map<NoteId, int> _sent = {};

  /// UploadPipeline committed records of these scopes now.
  void scopesSent(Iterable<String> scopes) {
    final now = nowMillis();
    for (final scope in scopes) {
      if (scope != SyncScopes.library) _sent[scope] = now;
    }
  }

  /// Notes whose scope was sent within [window] (tests, debug).
  Set<NoteId> get recentlySent {
    final now = nowMillis();
    return {
      for (final MapEntry(:key, :value) in _sent.entries)
        if (now - value <= window.inMilliseconds) key,
    };
  }

  /// Before [purges] are applied (DownloadPipeline.purgeGuard): copies every purged note
  /// this device is still editing. Returns one notice per copy made.
  Future<List<NoteRecoveredFromPurge>> guard(List<PurgeRecord> purges) async {
    final notes = {
      for (final p in purges)
        if (p.ref.kind == EntityKind.note) p.ref.id,
    };
    if (notes.isEmpty) return const [];
    final now = nowMillis();
    _sent.removeWhere((_, at) => now - at > window.inMilliseconds);
    final editing = {
      for (final n in notes)
        if (_sent.containsKey(n)) n,
    };
    if (editing.length < notes.length) {
      editing.addAll(await _editedInOutbox(notes.difference(editing)));
    }
    final out = <NoteRecoveredFromPurge>[];
    for (final noteId in editing.toList()..sort()) {
      final copy = await sync.duplicateNoteForRecovery(
        noteId,
        titleSuffix: titleSuffix,
      );
      if (copy == null) continue; // the note row is gone here too
      out.add(
        NoteRecoveredFromPurge(
          at: nowMillis(),
          purgedNoteId: noteId,
          copyNoteId: copy,
        ),
      );
    }
    return out;
  }

  /// Notes of [notes] with unsent edits in the outbox (read to the end with afterSeq).
  Future<Set<NoteId>> _editedInOutbox(Set<NoteId> notes) async {
    final found = <NoteId>{};
    int? afterSeq;
    while (true) {
      final page = await sync.pendingChanges(
        limit: outboxPageSize,
        afterSeq: afterSeq,
      );
      for (final e in page) {
        if (e.op != OutboxOp.upsert) continue;
        switch (e.kind) {
          // (v2.17-md, C217M-06 — review D2) an unsent MD 문서 text is an edit: the
          // recovery copy (duplicateNoteForRecovery) copies the body.
          case EntityKind.page ||
              EntityKind.stroke ||
              EntityKind.recording ||
              EntityKind.pageObject ||
              EntityKind.markdown:
            if (e.noteId case final n? when notes.contains(n)) found.add(n);
          case EntityKind.note when notes.contains(e.entityId):
            if (e.changedFields.any((f) => !kNoteTrashFields.contains(f))) {
              found.add(e.entityId);
            }
          default: // handwriting: derived data, re-recognized from the copied strokes
        }
      }
      if (page.length < outboxPageSize) break;
      afterSeq = page.last.seq;
    }
    return found;
  }
}
