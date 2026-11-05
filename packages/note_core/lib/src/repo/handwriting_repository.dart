// lib/src/repo/handwriting_repository.dart — (v2.0) 2nd-round contract 7.2.5 / 02-core 4.6,
// 6.9: HandwritingRepository.
import '../common/ids.dart';
import '../model/handwriting.dart';

abstract interface class HandwritingRepository {
  Future<HandwritingText?> forPage(PageId pageId);
  Stream<HandwritingText?> watchPage(PageId pageId);

  /// Upsert. Also re-indexes the page's ink units (same transaction when possible; an index
  /// failure never fails the write — C-13). (v2.1) Local writers (indexer, conversion UI) use
  /// [update] so a write that arrived meanwhile is merged, not overwritten (G-4).
  Future<void> put(HandwritingText value);

  /// (v2.1) Read-merge-write in ONE CORE write transaction: [transform] gets the stored value
  /// (null if none / deleted) and returns the value to store (null = leave as is). Synchronous and
  /// pure (no await inside). Returns the stored value afterwards. Same validation as put.
  Future<HandwritingText?> update(
    PageId pageId,
    HandwritingText? Function(HandwritingText? current) transform,
  );
  Future<void> removeForPage(PageId pageId);

  /// Active pages of [noteId] whose input strokes' sourceRevOf differs from the stored value
  /// (or that have none and at least one input stroke). Cheap: uses DB columns, no point decode.
  /// (v2.1) Page order.
  Future<List<PageId>> stalePages(NoteId noteId);

  /// (v2.1) Active notes with ≥ 1 stale page, one query over the pages.ink_rev cache — the
  /// indexer's start-up catch-up. Most recently updated note first.
  Future<List<NoteId>> notesWithStalePages();
}
