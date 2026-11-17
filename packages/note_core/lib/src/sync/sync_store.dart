// lib/src/sync/sync_store.dart — contract 00-overview 7.2.10 (v1.3) / CORE 4.6.
import '../common/ids.dart';
import '../model/markdown_text.dart';
import 'field_versions.dart';
import 'merge.dart';
import 'outbox_types.dart';

/// (v1.3) Writes (acknowledge, applyRemote, commitRepairs, writeMeta, reassignOwner,
/// duplicateNoteForRecovery) follow the write-Future rule of 7.2.9: they complete after the
/// commit and stay pending (no error) while the write queue retries a failed commit. Only
/// errors decided without retry complete with an error, and they change nothing:
/// ArgumentError, state errors (StateError for a WriteMerged invariant, NoteCoreException),
/// and a policy exception (applyRemote rolls back — metaUpdates included — and rethrows it).
abstract interface class SyncStore {
  String get deviceNodeId; // 16 hex, HLC node of local writes
  OwnerId get ownerId;
  Future<List<OutboxEntry>> pendingChanges({
    int limit = 500,
    int? afterSeq,
  }); // seq order
  Stream<int> watchPendingCount();

  /// Deletes entries whose (seq, rev) still match; newer revs stay pending.
  Future<void> acknowledge(List<OutboxAck> acks);

  /// Snapshots + field versions, including soft-deleted; null = purged or unknown.
  Future<List<VersionedEntity?>> readVersioned(List<EntityRef> refs);

  /// ONE transaction: merge via [policy], write without outbox (except WriteMerged
  /// .fieldsToUpload), advance HLC with receive(max version), store [metaUpdates],
  /// publish ChangeBatch(origin: remote). Remote writes never enter undo history.
  /// Bumps the local Note.updatedAt of affected notes to max(current, applied updatedAt)
  /// without outbox. Purges the trash group for RemotePurge.
  /// (v1.1) Device-local fields of the handed-over entities (TakeRemote: remote entity,
  /// WriteMerged: merged entity — both decoded from JSON, so they hold defaults) are IGNORED:
  ///   Note.lastOpenedAt              = current row value (new row: null)
  ///   Note.pageCount / firstPageId   = recomputed
  ///   Page.contentRevision           = current + 1 when the page row or its strokes were
  ///                                    written (new row: 0)
  ///   Asset.hasLocalBytes (+ CORE's local storage columns) = current row value
  ///                                    (new row: whether the blob store holds the bytes)
  Future<RemoteApplyReport> applyRemote(
    List<RemoteChange> changes, {
    required RemoteMergePolicy policy,
    Map<String, String> metaUpdates = const {},
  });

  /// ONE transaction: stamp EXACTLY [fields] of each entity with one fresh local HLC (SYNC
  /// passes whole merge units), queue them in the outbox, publish ChangeBatch(origin: remote),
  /// not added to undo history. (v1.1) Same device-local field rule as applyRemote: only
  /// [fields] are taken from [RepairWrite.entity]; local-only values are kept / recomputed.
  Future<void> commitRepairs(List<RepairWrite> repairs);

  /// SYNC meta KV: keys start with 'sync.', values ≤ 256 KiB.
  Future<String?> readMeta(String key);
  Future<void> writeMeta(Map<String, String> updates);

  /// First login: every row with ownerId == from gets to; the store's ownerId switches at
  /// runtime and is persisted (next openNoteStore uses it). Existing outbox entries stay.
  /// (v1.1) Publishes ChangeBatch(origin: remote) — no outbox change, so no push is scheduled.
  Future<void> reassignOwner({required OwnerId from, required OwnerId to});

  /// Copies a (possibly trashed) note with its active pages and strokes under new ids,
  /// active, same folder (or top level), title + suffix. null if the note row is gone.
  /// (v1.1) New entities go to the outbox ('*') and ChangeBatch(origin: local) is published.
  Future<NoteId?> duplicateNoteForRecovery(
    NoteId noteId, {
    required String titleSuffix,
  });

  /// (v2.17-md, C217M-07 L2 — m5-7/08-markdown 5.3) Called by SYNC before it applies a
  /// received MD 문서 body [remote] (field versions [versions]). When this device holds an
  /// unsent, different text of that document and the received text version is newer than
  /// what this device knows the server had (base_text_version) and was not written by this
  /// device, the text that will lose the merge is kept byte for byte as a conflict copy
  /// (a new MD 문서 '<title> (충돌 사본 …)' in the same folder; this device's copy of the
  /// last 10 minutes is reused only when it already holds exactly that text — a copy is
  /// never rewritten). One local write (ChangeBatch(origin: local), outbox). Returns the
  /// copy's note id, or null when nothing had to be kept. [applyRemote] applies the same
  /// rule again on the row as it is then (an edit saved after this call loses no text;
  /// such a copy is a local change of that remote commit, with no copy id returned).
  Future<NoteId?> keepMarkdownConflictCopy(
    MarkdownText remote,
    EntityFieldVersions versions,
  );
}
// Removed: readEntities, readCursor, applyRemote(cursorUpdates:), unversioned RemoteMergePolicy.
