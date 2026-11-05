// lib/src/gateway/core_note_gateway.dart — 06-pdf 4.4. Thin adapter over the CORE public
// API (contract 7.2.8 / 7.2.9 / 7.2.11 / 7.2.12). CORE exceptions become PdfIoException
// here (cause kept): EntityNotFoundException → noteNotFound, ReadOnlyNoteException →
// readOnlyNote, writes that fail WITHOUT retry → storageFailed.
//
// A failed commit is never an exception: CORE retries it forever and the write Future stays
// pending (contract 7.2.9 v1.2). Nothing here adds a timeout; callers that must stay
// cancellable race the wait with PdfCancelSignal.raceCancel (6.3, 6.10.2, 6.11.2).
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;

import '../errors.dart';
import 'pdf_note_gateway.dart';

final class CorePdfNoteGateway implements PdfNoteGateway {
  CorePdfNoteGateway(this.store);
  final core.NoteStore store;

  /// Maps CORE exceptions. [anyErrorIsStorage]: for AssetStore.put, whose only failure
  /// without retry is the byte-chunk write — that error type belongs to the blob store.
  static Future<T> _guard<T>(
    String what,
    Future<T> Function() body, {
    bool anyErrorIsStorage = false,
  }) async {
    try {
      return await body();
    } on PdfIoException {
      rethrow;
    } on core.EntityNotFoundException catch (e) {
      throw PdfIoException(PdfErrorCode.noteNotFound, detail: what, cause: e);
    } on core.ReadOnlyNoteException catch (e) {
      throw PdfIoException(PdfErrorCode.readOnlyNote, detail: what, cause: e);
    } on core.NoteCoreException catch (e) {
      throw PdfIoException(PdfErrorCode.storageFailed, detail: what, cause: e);
    } on Object catch (e) {
      if (!anyErrorIsStorage) rethrow;
      throw PdfIoException(PdfErrorCode.storageFailed, detail: what, cause: e);
    }
  }

  @override
  Future<core.Asset> putPdf(Uint8List bytes, {required String fileName}) =>
      _guard(
        'putPdf $fileName',
        () => store.assets.put(
          bytes,
          type: core.AssetType.pdf,
          mimeType: 'application/pdf',
          fileName: fileName,
        ),
        anyErrorIsStorage: true,
      );

  @override
  Future<Uint8List?> readAssetBytes(core.AssetId assetId) =>
      _guard('readAssetBytes $assetId', () => store.assets.readBytes(assetId));

  @override
  Stream<core.AssetId> get bytesArrived => store.assets.bytesArrived;

  @override
  Future<core.Note> createNote({
    core.FolderId? folderId,
    required String title,
    required List<core.PageDraft> pages,
  }) => _guard(
    'createNote',
    () => store.library.createNote(
      folderId: folderId,
      title: title,
      pages: pages,
    ),
  );

  @override
  Future<List<core.PageId>> insertPages(
    core.NoteId noteId,
    List<core.PageDraft> pages,
    core.PagePosition position,
  ) => _guard('insertPages $noteId', () async {
    // Ref-counted (N-5): when the editor has this note open we get its session, and our
    // close() only drops our reference.
    final session = await store.openSession(noteId);
    try {
      final receipt = await session.executeAsync(
        core.InsertPages(drafts: pages, position: position),
      );
      // Not awaited (N-1): the pages are already in the session. A storage problem shows
      // through PersistenceStatus, never as an error here (contract 7.2.9 v1.2).
      receipt.persisted.ignore();
      return receipt.edit.insertedPageIds;
    } finally {
      await session.close();
    }
  });

  @override
  Future<void> flush() => store.flush();

  @override
  Future<core.Note?> getNote(core.NoteId noteId) =>
      _guard('getNote $noteId', () => store.library.getNote(noteId));

  @override
  Future<List<core.Page>> pagesOf(core.NoteId noteId) =>
      _guard('pagesOf $noteId', () => store.content.pagesOf(noteId));

  @override
  Future<core.PageContent> loadPage(core.PageId pageId) =>
      _guard('loadPage $pageId', () => store.content.loadPage(pageId));

  @override
  Future<void> writeThumbnail(core.PageThumbnail thumbnail) => _guard(
    'writeThumbnail ${thumbnail.pageId}',
    () => store.thumbnails.write(thumbnail),
  );
}
