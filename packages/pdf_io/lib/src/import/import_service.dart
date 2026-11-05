// lib/src/import/import_service.dart — 06-pdf 4.6, 6.3, 6.4.
//
// The constructor keeps the 4.6 parameter list word for word (plain named parameters
// assigned to private fields), hence:
// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;

import '../common/cancel_signal.dart';
import '../common/progress.dart';
import '../config.dart';
import '../engine/page_info.dart';
import '../engine/pdf_engine.dart';
import '../errors.dart';
import '../files/pdf_file_source.dart';
import '../gateway/pdf_note_gateway.dart';
import '../model/page_range.dart';
import '../render/document_pool.dart';
import '../render/render_service.dart';
import 'import_session.dart';
import 'import_types.dart';

abstract interface class PdfImportService {
  /// Reads and opens the file (password prompts via [onPassword]); checks limits and the
  /// user-password policy. Throws notPdf / tooLarge / tooManyPages / passwordCancelled /
  /// userPasswordRefused / corrupt / pickerFailed / engineUnavailable.
  Future<PdfImportSession> open(
    PickedPdfFile file, {
    PdfPasswordCallback? onPassword,
    PdfProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  });
}

/// An opened, not yet committed import. Keeps the bytes and the engine document.
abstract interface class PdfImportSession {
  PickedPdfFile get file;
  PdfDocumentInfo get info;
  int get byteLength;
  bool get isLargeFile; // byteLength > limits.warnBytes
  /// info.usedPassword (policy storeDecryptedCopy)
  bool get willStoreDecryptedCopy;
  String get suggestedTitle; // PdfTitlePolicy.fromFileName(file.name)

  /// Stores the asset, creates the pages, hands the opened document to the pool, writes the
  /// new note's cover (6.3). Cancellable until pages are created: the putPdf wait is raced
  /// with [cancel] (PdfCancelSignal.raceCancel → cancelled at once); once createNote /
  /// insertPages is called it is not cancellable.
  /// While CORE retries a failed commit (putPdf's metadata commit, createNote, the session
  /// open / page loads of insertPages) this Future stays pending — no completion, no error
  /// (contract 7.2.9 v1.2); the progress dialog shows the delay text and '닫기' (6.3).
  /// Throws storageFailed (put byte-chunk write / other NoteCoreException — 4.4) /
  /// noteNotFound / readOnlyNote / cancelled.
  Future<PdfImportResult> commit(
    PdfImportTarget target, {
    PdfPageRange range = const PdfPageRange.all(),
    PdfProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  });
  Future<void> dispose(); // idempotent; closes the document if not committed
}

final class DefaultPdfImportService implements PdfImportService {
  /// [thumbnailRenderer] = core.pageThumbnailRendererProvider (INK renderer from INFRA, or null).
  DefaultPdfImportService({
    required PdfEngine engine,
    required PdfNoteGateway gateway,
    required PdfDocumentPool pool,
    required PdfPageRenderer renderer,
    required PdfIoConfig config,
    core.PageThumbnailRenderer? thumbnailRenderer,
  }) : _engine = engine,
       _gateway = gateway,
       _pool = pool,
       _renderer = renderer,
       _config = config,
       _thumbnailRenderer = thumbnailRenderer;

  final PdfEngine _engine;
  final PdfNoteGateway _gateway;
  final PdfDocumentPool _pool;
  final PdfPageRenderer _renderer;
  final PdfIoConfig _config;
  final core.PageThumbnailRenderer? _thumbnailRenderer;

  /// 6.3 open steps 1–6.
  @override
  Future<PdfImportSession> open(
    PickedPdfFile file, {
    PdfPasswordCallback? onPassword,
    PdfProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  }) async {
    final limits = _config.limits;
    cancel?.throwIfCancelled();
    // 1. declared size, before reading
    final declared = file.sizeBytes;
    if (declared != null && declared > limits.maxBytes) {
      throw PdfIoException(
        PdfErrorCode.tooLarge,
        detail: '${file.name}: $declared bytes > ${limits.maxBytes}',
      );
    }
    // 2. read
    onProgress?.call(const PdfProgress(PdfJobPhase.readingFile));
    final bytes = await _readBytes(file, cancel);
    if (bytes.length > limits.maxBytes) {
      throw PdfIoException(
        PdfErrorCode.tooLarge,
        detail: '${file.name}: ${bytes.length} bytes > ${limits.maxBytes}',
      );
    }
    // 3. magic
    if (!hasPdfMagic(bytes)) {
      throw PdfIoException(
        PdfErrorCode.notPdf,
        detail: "${file.name}: no '%PDF-' in the first 1024 bytes",
      );
    }
    cancel?.throwIfCancelled();
    // 4. open (6.4 passwords)
    onProgress?.call(const PdfProgress(PdfJobPhase.openingPdf));
    await _race(cancel, _initializeEngine());
    final document = await _openDocument(file, bytes, onPassword, cancel);
    // 5. limits on the opened document
    final pageCount = document.info.pageCount;
    if (pageCount > limits.maxPages || pageCount == 0) {
      await document.dispose();
      throw pageCount == 0
          ? PdfIoException(
              PdfErrorCode.corrupt,
              detail: '${file.name} has no pages',
            )
          : PdfIoException(
              PdfErrorCode.tooManyPages,
              detail: '${file.name}: $pageCount pages > ${limits.maxPages}',
            );
    }
    if (cancel?.isCancelled ?? false) {
      await document.dispose();
      cancel!.throwIfCancelled();
    }
    // 6.
    return PdfImportSessionImpl(
      file: file,
      bytes: bytes,
      document: document,
      gateway: _gateway,
      pool: _pool,
      renderer: _renderer,
      config: _config,
      thumbnailRenderer: _thumbnailRenderer,
    );
  }

  static Future<T> _race<T>(PdfCancelSignal? cancel, Future<T> future) =>
      cancel == null ? future : cancel.raceCancel(future);

  static Future<Uint8List> _readBytes(
    PickedPdfFile file,
    PdfCancelSignal? cancel,
  ) async {
    try {
      return await _race(cancel, Future<Uint8List>.sync(file.readBytes));
    } on PdfIoException {
      rethrow;
    } on Object catch (e) {
      throw PdfIoException(
        PdfErrorCode.pickerFailed,
        detail: 'could not read ${file.name}',
        cause: e,
      );
    }
  }

  Future<void> _initializeEngine() async {
    try {
      await _engine.ensureInitialized();
    } on PdfIoException {
      rethrow;
    } on Object catch (e) {
      throw PdfIoException(
        PdfErrorCode.engineUnavailable,
        detail: 'PDF engine initialization failed',
        cause: e,
      );
    }
  }

  Future<PdfEngineDocument> _openDocument(
    PickedPdfFile file,
    Uint8List bytes,
    PdfPasswordCallback? onPassword,
    PdfCancelSignal? cancel,
  ) async {
    final refuse = _config.userPasswordPolicy == PdfUserPasswordPolicy.refuse;
    var passwordNeeded = false;
    // A request means the PDF needs a user password (a permission-only PDF opens with
    // the empty password first and never asks — 6.4).
    Future<String?> askPassword(PdfPasswordRequest request) async {
      passwordNeeded = true;
      if (refuse || (cancel?.isCancelled ?? false) || onPassword == null) {
        return null;
      }
      return onPassword(request);
    }

    final opening = Future<PdfEngineDocument>.sync(
      () => _engine.open(
        bytes,
        sourceName: 'import:${DateTime.now().millisecondsSinceEpoch}',
        fileName: file.name,
        onPassword: askPassword,
        maxPasswordAttempts: _config.limits.maxPasswordAttempts,
        transferOwnership: false, // commit stores these bytes
      ),
    );
    try {
      return await _race(cancel, opening);
    } on PdfIoException catch (e) {
      if (e.code == PdfErrorCode.cancelled) {
        // The open goes on: close what it opens.
        unawaited(
          opening.then<void>(
            (document) => document.dispose(),
            onError: (Object _) {},
          ),
        );
      } else if (e.code == PdfErrorCode.passwordCancelled &&
          refuse &&
          passwordNeeded) {
        throw PdfIoException(
          PdfErrorCode.userPasswordRefused,
          detail: '${file.name} needs a user password (policy refuse)',
          cause: e,
        );
      }
      rethrow;
    } on Object catch (e) {
      throw PdfIoException(
        PdfErrorCode.corrupt,
        detail: 'could not open ${file.name}',
        cause: e,
      );
    }
  }
}
