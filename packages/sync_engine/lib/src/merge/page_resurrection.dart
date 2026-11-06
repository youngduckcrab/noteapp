// Internal (not exported). Page resurrection after an apply group (6.7.3; 2nd round 07-sync
// 6.2.6): a deleted page comes back when one side of the delete did not know a stroke or a
// page object written on it. Changes and deletions of known elements, handwriting results
// (derived data) and recordings are no reason.
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../model/sync_doc.dart';
import 'merge_recorder.dart';

/// One page to bring back: commit [write] (SyncStore.commitRepairs via
/// UploadPipeline.commitRepairs, which schedules the push) and announce PageRestored.
@immutable
final class PageRepair {
  const PageRepair(this.write, {required this.pageId, this.noteId});
  final RepairWrite write;
  final PageId pageId;
  final NoteId? noteId;

  @override
  String toString() => 'PageRepair($pageId of $noteId)';
}

final class PageResurrection {
  PageResurrection({required this.sync, this.outboxPageSize = 500});

  final SyncStore sync;
  final int outboxPageSize;

  /// [outcomes] = MergeRecorder.outcomes of one apply group (committed calls only).
  ///
  /// Element kinds whose creation on a deleted page brings the page back (6.2.6): strokes
  /// and page objects (any type, unknown ones too — user content).
  static const Set<EntityKind> elementKinds = {
    EntityKind.stroke,
    EntityKind.pageObject,
  };

  /// (a) deleter side: a stroke or page object new to this device ('created') and active,
  ///     on a page this device deleted (deletedAt version node == own node).
  /// (b) writer side: a page taken / merged and deleted by another node, with an unsent
  ///     stroke or page object creation ('*') on it in this device's outbox.
  /// Both skip a page whose note row is gone (a purged note's orphan row, SYNC-3-3).
  Future<List<PageRepair>> check(
    Map<EntityRef, MergeOutcomeKind> outcomes,
  ) async {
    final node = sync.deviceNodeId;
    final createdElements = [
      for (final MapEntry(:key, :value) in outcomes.entries)
        if (elementKinds.contains(key.kind) &&
            value == MergeOutcomeKind.created)
          key,
    ];
    final deleterPages = <String>{};
    if (createdElements.isNotEmpty) {
      final rows = await sync.readVersioned(createdElements);
      for (final row in rows) {
        if (row == null) continue;
        final doc = SyncDoc.fromEntity(row.entity);
        if (doc.isDeleted) continue;
        if (doc.json['pageId'] case final String pageId
            when pageId.isNotEmpty) {
          deleterPages.add(pageId);
        }
      }
    }
    final writerPages = <String>{
      for (final MapEntry(:key, :value) in outcomes.entries)
        if (key.kind == EntityKind.page &&
            (value == MergeOutcomeKind.taken ||
                value == MergeOutcomeKind.merged))
          key.id,
    };
    final pageIds = {...deleterPages, ...writerPages}.toList()..sort();
    if (pageIds.isEmpty) return const [];

    final pages = await sync.readVersioned([
      for (final id in pageIds) EntityRef(EntityKind.page, id),
    ]);
    final candidates = <(SyncDoc, VersionedEntity)>[];
    Set<String>? unsentElementPages;
    for (final (i, row) in pages.indexed) {
      if (row == null) continue;
      final doc = SyncDoc.fromEntity(row.entity);
      if (!doc.isDeleted) continue;
      final deletedBy = row.versions.of('deletedAt').nodeId;
      final id = pageIds[i];
      if (deletedBy == node) {
        if (deleterPages.contains(id)) candidates.add((doc, row));
      } else if (writerPages.contains(id)) {
        unsentElementPages ??= await _pagesWithUnsentElements();
        if (unsentElementPages.contains(id)) candidates.add((doc, row));
      }
    }
    if (candidates.isEmpty) return const [];

    final withNote = [
      for (final (doc, _) in candidates)
        if (doc.json['noteId'] case final String noteId when noteId.isNotEmpty)
          (doc, noteId),
    ];
    if (withNote.isEmpty) return const [];
    final notes = await sync.readVersioned([
      for (final (_, noteId) in withNote) EntityRef(EntityKind.note, noteId),
    ]);
    return [
      for (final (i, (doc, noteId)) in withNote.indexed)
        if (notes[i] != null)
          PageRepair(
            (
              entity: doc.withFields({'deletedAt': null}).toEntity(),
              fields: const {'deletedAt'},
            ),
            pageId: doc.id,
            noteId: noteId,
          ),
    ];
  }

  /// Page ids with a pending stroke or page object entry whose changedFields hold '*' (an
  /// unsent creation; the pageId hint is always set for both kinds).
  Future<Set<String>> _pagesWithUnsentElements() async {
    final pages = <String>{};
    int? afterSeq;
    while (true) {
      final page = await sync.pendingChanges(
        limit: outboxPageSize,
        afterSeq: afterSeq,
      );
      for (final e in page) {
        if (elementKinds.contains(e.kind) &&
            e.op == OutboxOp.upsert &&
            e.changedFields.contains(kAllFields) &&
            e.pageId != null) {
          pages.add(e.pageId!);
        }
      }
      if (page.length < outboxPageSize) break;
      afterSeq = page.last.seq;
    }
    return pages;
  }
}
