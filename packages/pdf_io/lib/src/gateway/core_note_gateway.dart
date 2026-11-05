// lib/src/gateway/core_note_gateway.dart — 06-pdf 4.4. Thin adapter over the CORE public
// API (contract 7.2.8 / 7.2.9 / 7.2.11 / 7.2.12). CORE exceptions become PdfIoException
// here (cause kept): EntityNotFoundException → noteNotFound, ReadOnlyNoteException →
// readOnlyNote, writes that fail WITHOUT retry → storageFailed.
//
// Foundation step B4 (T0): signatures only; the adapter comes with PDF T4.
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;

import 'pdf_note_gateway.dart';

final class CorePdfNoteGateway implements PdfNoteGateway {
  CorePdfNoteGateway(this.store);
  final core.NoteStore store;

  static Never _t4(String member) =>
      throw UnimplementedError('CorePdfNoteGateway.$member (PDF T4)');

  @override
  Future<core.Asset> putPdf(Uint8List bytes, {required String fileName}) =>
      _t4('putPdf');

  @override
  Future<Uint8List?> readAssetBytes(core.AssetId assetId) =>
      _t4('readAssetBytes');

  @override
  Stream<core.AssetId> get bytesArrived => _t4('bytesArrived');

  @override
  Future<core.Note> createNote({
    core.FolderId? folderId,
    required String title,
    required List<core.PageDraft> pages,
  }) => _t4('createNote');

  @override
  Future<List<core.PageId>> insertPages(
    core.NoteId noteId,
    List<core.PageDraft> pages,
    core.PagePosition position,
  ) => _t4('insertPages');

  @override
  Future<void> flush() => _t4('flush');

  @override
  Future<core.Note?> getNote(core.NoteId noteId) => _t4('getNote');

  @override
  Future<List<core.Page>> pagesOf(core.NoteId noteId) => _t4('pagesOf');

  @override
  Future<core.PageContent> loadPage(core.PageId pageId) => _t4('loadPage');

  @override
  Future<void> writeThumbnail(core.PageThumbnail thumbnail) =>
      _t4('writeThumbnail');
}
