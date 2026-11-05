// lib/src/gateway/pdf_note_gateway.dart — 06-pdf 4.4. Everything PDF does to CORE goes
// through this port (default implementation: CorePdfNoteGateway).
//
// A failed CORE commit is NOT an exception (contract 7.2.9 v1.2 C12-09): CORE retries it
// forever and the write Future stays pending — no completion, no error.
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;

abstract interface class PdfNoteGateway {
  /// AssetStore.put(bytes, type: AssetType.pdf, mimeType: 'application/pdf', fileName: fileName).
  /// Same bytes → same Asset (content hash, C-5). Completes after the metadata commit; while
  /// CORE retries that commit it stays pending — no completion, no error (contract 7.2.9 /
  /// 7.2.11 v1.2). Throws PdfIoException(storageFailed) only for a failed byte-chunk write
  /// (put fails with that error at once, no retry, no metadata row) or another
  /// NoteCoreException — never for a failed commit.
  Future<core.Asset> putPdf(Uint8List bytes, {required String fileName});

  /// null when the bytes are not on this device (C-6).
  Future<Uint8List?> readAssetBytes(core.AssetId assetId);

  /// AssetStore.bytesArrived: ids whose bytes were just stored or downloaded (P-2).
  Stream<core.AssetId> get bytesArrived;

  /// LibraryRepository.createNote — 1..2000 drafts in ONE transaction (C-3). Completes after
  /// the DB commit; while CORE retries the commit it stays pending — no completion, no error
  /// (contract 7.2.9 v1.2). State errors (EntityNotFoundException → noteNotFound) end it
  /// without retry; a failed commit is never thrown.
  Future<core.Note> createNote({
    core.FolderId? folderId,
    required String title,
    required List<core.PageDraft> pages,
  });

  /// ONE undoable step: NoteStore.openSession(noteId) → executeAsync(InsertPages(drafts:,
  /// position:)) → session.close() (ref-counted, N-5; the editor's session stays open).
  /// receipt.persisted is not awaited: the pages are already in the session (N-1). A storage
  /// failure is never thrown here — it surfaces only through CORE PersistenceStatus (editor
  /// storage banner, contract 7.2.9 v1.2). openSession / the page loads executeAsync needs may
  /// wait behind earlier queued writes (CORE 6.9 openPage flushes first), so this Future can
  /// stay pending while CORE retries — the import progress dialog handles that (6.3).
  /// Called only from UI flows (a tap → sheet), NEVER from a session stream listener:
  /// contract 7.2.8 N-2 (v1.1) — execute() inside a listener throws StateError; executeAsync
  /// applies after its first await. PDF uses executeAsync only (no execute / undo / redo).
  /// Returns receipt.edit.insertedPageIds. Throws noteNotFound / readOnlyNote (N-4).
  Future<List<core.PageId>> insertPages(
    core.NoteId noteId,
    List<core.PageDraft> pages,
    core.PagePosition position,
  );

  /// NoteStore.flush(): every queued write committed. Pending — no completion, no error —
  /// while CORE retries a commit (contract 7.2.9 v1.2); callers that must stay cancellable
  /// wrap it in PdfCancelSignal.raceCancel (6.10.2, 6.11.2).
  Future<void> flush();

  /// includes trashed notes (C-3 of LIBRARY)
  Future<core.Note?> getNote(core.NoteId noteId);

  /// active, ordered
  Future<List<core.Page>> pagesOf(core.NoteId noteId);

  /// committed state (flush first)
  Future<core.PageContent> loadPage(core.PageId pageId);

  /// ThumbnailCache.write (C-7)
  Future<void> writeThumbnail(core.PageThumbnail thumbnail);
}
