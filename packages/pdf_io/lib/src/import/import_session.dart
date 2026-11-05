// lib/src/import/import_session.dart — 06-pdf 4.6, 6.3 (commit steps 1–7), 6.4.
//
// Internal (not exported): DefaultPdfImportService.open returns this as a PdfImportSession.
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;

import '../common/cancel_signal.dart';
import '../common/error_report.dart';
import '../common/progress.dart';
import '../config.dart';
import '../engine/page_info.dart';
import '../engine/pdf_engine.dart';
import '../errors.dart';
import '../files/pdf_file_source.dart';
import '../gateway/pdf_note_gateway.dart';
import '../model/page_range.dart';
import '../model/page_size_policy.dart';
import '../model/title_policy.dart';
import '../render/document_pool.dart';
import '../render/render_service.dart';
import 'cover_thumbnail.dart';
import 'import_service.dart';
import 'import_types.dart';

/// Internal implementation of [PdfImportSession] (6.3).
final class PdfImportSessionImpl implements PdfImportSession {
  PdfImportSessionImpl({
    required this.file,
    required this._bytes,
    required this._document,
    required this._gateway,
    required this._pool,
    required this._renderer,
    required this._config,
    this._thumbnailRenderer,
  }) : suggestedTitle = PdfTitlePolicy.fromFileName(file.name);

  final Uint8List _bytes;
  final PdfEngineDocument _document;
  final PdfNoteGateway _gateway;
  final PdfDocumentPool _pool;
  final PdfPageRenderer _renderer;
  final PdfIoConfig _config;
  final core.PageThumbnailRenderer? _thumbnailRenderer;

  bool _committing = false;

  /// The engine document left this session (adopted by the pool, or closed after storing
  /// a decrypted copy) — commit succeeded up to the page creation.
  bool _handedOver = false;
  bool _disposed = false;

  @override
  final PickedPdfFile file;

  @override
  final String suggestedTitle;

  @override
  PdfDocumentInfo get info => _document.info;

  @override
  int get byteLength => _bytes.length;

  @override
  bool get isLargeFile => byteLength > _config.limits.warnBytes;

  @override
  bool get willStoreDecryptedCopy => info.usedPassword;

  @override
  Future<PdfImportResult> commit(
    PdfImportTarget target, {
    PdfPageRange range = const PdfPageRange.all(),
    PdfProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  }) async {
    if (_disposed) throw StateError('PdfImportSession is disposed');
    if (_handedOver) throw StateError('PdfImportSession is already committed');
    if (_committing) throw StateError('PdfImportSession.commit is running');
    // 1. pages to import
    final indices = range.resolve(info.pageCount);
    if (indices.isEmpty) {
      throw FormatException('가져올 페이지가 없어요. 이 PDF는 ${info.pageCount}쪽이에요.');
    }
    _committing = true;
    try {
      cancel?.throwIfCancelled();
      // 2. store the asset (6.4: a user-password PDF is stored without security)
      onProgress?.call(const PdfProgress(PdfJobPhase.storingPdf));
      final storeDecryptedCopy = info.usedPassword;
      final storeBytes = storeDecryptedCopy ? await _encodeDecrypted() : _bytes;
      cancel?.throwIfCancelled();
      final putting = _gateway.putPdf(storeBytes, fileName: file.name);
      // CORE retries a failed metadata commit and the Future stays pending meanwhile
      // (contract 7.2.9 v1.2): race it with the cancel signal.
      final asset = cancel == null
          ? await putting
          : await cancel.raceCancel(putting);
      cancel?.throwIfCancelled();
      // 3. drafts — the last cancel point
      final total = indices.length;
      onProgress?.call(
        PdfProgress(PdfJobPhase.creatingPages, done: 0, total: total),
      );
      final drafts = [
        for (final i in indices)
          core.PageDraft(
            size: PdfPageSizePolicy.toNotePageSize(
              info.pages[i].width,
              info.pages[i].height,
            ),
            background: core.PdfBackground(assetId: asset.id, pdfPageIndex: i),
          ),
      ];
      cancel?.throwIfCancelled();
      // 4. pages (not raced: once called the write is in CORE's queue)
      final core.NoteId noteId;
      final List<core.PageId> pageIds;
      switch (target) {
        case PdfImportAsNewNote(:final folderId, :final title):
          final given = title?.trim();
          final note = await _gateway.createNote(
            folderId: folderId,
            title: given == null || given.isEmpty ? suggestedTitle : given,
            pages: drafts,
          );
          noteId = note.id;
          pageIds = [
            for (final page in await _gateway.pagesOf(note.id)) page.id,
          ];
        case PdfImportIntoNote(noteId: final id, :final position):
          noteId = id;
          pageIds = await _gateway.insertPages(id, drafts, position);
      }
      onProgress?.call(
        PdfProgress(PdfJobPhase.creatingPages, done: total, total: total),
      );
      // 5. hand the opened document over
      await _handOver(asset.id, storeDecryptedCopy);
      // 6. cover of a new note
      final createdNewNote = target is PdfImportAsNewNote;
      if (createdNewNote &&
          _config.generateCoverThumbnail &&
          pageIds.isNotEmpty) {
        onProgress?.call(const PdfProgress(PdfJobPhase.coverThumbnail));
        await _writeCover(pageIds.first, indices.first);
      }
      // 7.
      return PdfImportResult(
        noteId: noteId,
        insertedPageIds: List<core.PageId>.unmodifiable(pageIds),
        assetId: asset.id,
        sourcePageCount: info.pageCount,
        storedDecryptedCopy: storeDecryptedCopy,
        createdNewNote: createdNewNote,
      );
    } finally {
      _committing = false;
      // dispose() during the commit leaves the cleanup to us.
      if (_disposed && !_handedOver) await _document.dispose();
    }
  }

  Future<Uint8List> _encodeDecrypted() async {
    try {
      return await _document.encodeWithoutSecurity();
    } on PdfIoException {
      rethrow;
    } on Object catch (e) {
      throw PdfIoException(
        PdfErrorCode.corrupt,
        detail: 'could not re-encode ${file.name} without security',
        cause: e,
      );
    }
  }

  /// 6.3 step 5: the pool keeps the opened document (no second open for the editor or the
  /// cover); a decrypted copy is opened later from the stored bytes instead.
  Future<void> _handOver(core.AssetId assetId, bool storedDecryptedCopy) async {
    _handedOver = true;
    if (storedDecryptedCopy || _disposed) {
      await _document.dispose();
      return;
    }
    try {
      _pool.adopt(assetId, _document);
    } on Object catch (e, s) {
      reportPdfError(e, s, 'pdf import: handing the document to the pool');
      await _document.dispose();
    }
  }

  /// 6.3 step 6: failures never fail the import — reported, not shown; null is no error.
  Future<void> _writeCover(core.PageId pageId, int pdfPageIndex) async {
    try {
      final content = await _gateway.loadPage(pageId);
      final thumbnail = await renderImportCover(
        content: content,
        pdfPage: info.pages[pdfPageIndex],
        renderer: _renderer,
        thumbnailRenderer: _thumbnailRenderer,
      );
      if (thumbnail != null) await _gateway.writeThumbnail(thumbnail);
    } on Object catch (e, s) {
      reportPdfError(e, s, 'pdf import: cover thumbnail of page $pageId');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Handed over: the pool owns it. Committing: the commit's finally closes it.
    if (_handedOver || _committing) return;
    await _document.dispose();
  }
}
