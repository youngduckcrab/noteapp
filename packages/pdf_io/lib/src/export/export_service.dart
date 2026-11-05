// lib/src/export/export_service.dart — 06-pdf 4.9, 6.11.2, 6.11.9–6.11.11 (PDF T15).
//
// The export pipeline: flush (cancellable — CORE may retry a commit forever, contract 7.2.9
// v1.2) → pages of the note and the range → compose plan (sources once each, first-seen
// order; a PDF page without local bytes becomes a blank page or fails the export) →
// backend.begin → per page loadPage → vectorize → encode, sent in chunks → finish.
// One export (single or batch) at a time per service (busy).
//
// The constructor keeps the 4.9 parameter list word for word (plain named parameters
// assigned to private fields), hence:
// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

import '../common/cancel_signal.dart';
import '../common/error_report.dart';
import '../common/progress.dart';
import '../compose/compose_backend.dart';
import '../errors.dart';
import '../gateway/pdf_note_gateway.dart';
import '../model/file_naming.dart';
import '../tuning.dart';
import '../ui/strings_ko.dart';
import 'batch_export.dart';
import 'compose_encoder.dart';
import 'compose_plan.dart';
import 'export_types.dart';
import 'vectors.dart';

abstract interface class PdfExportService {
  /// Starts with cancel.raceCancel(gateway.flush()) (6.11.2 step 1): pending while CORE
  /// retries a commit (contract 7.2.9 v1.2); cancel() → cancelled at once (nothing composed).
  /// Throws assetMissing (policy fail) / noteNotFound / exportFailed / cancelled /
  /// engineUnavailable / busy.
  Future<PdfExportResult> exportNote(
    core.NoteId noteId,
    PdfExportOptions options, {
    PdfProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  });

  /// Notes one after another in [noteIds] order with options.copyWith(range: all pages)
  /// (6.11.11). Per-note failures are recorded in the items, not thrown. Cancel → result
  /// .cancelled with the files made so far. Throws only busy / engineUnavailable /
  /// unsupportedPlatform.
  Future<PdfBatchExportResult> exportNotes(
    List<core.NoteId> noteIds,
    PdfExportOptions options, {
    PdfBatchProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  });
}

/// T15 details:
/// - busy: one exportNote / exportNotes at a time per service (the job notifiers also keep
///   imports and exports apart, 6.13). A backend that is not supported → unsupportedPlatform.
/// - Range (6.11.2 step 1): current page not in the note → ArgumentError; selected pages in
///   note order, unknown ids ignored, none left → ArgumentError. A note without pages →
///   exportFailed.
/// - Progress: preparingExport → composing (0/n … n/n, n = output pages) → finishingExport
///   (n/n, so a batch's overall fraction never goes back).
/// - Chunks: up to 16 pages on the web (dedicated worker), 8 elsewhere (shared pdfrx
///   worker), and at most PdfTuning.exportChunkMaxBytes of ops unless one page is larger.
///   Pages without ops are not sent (the source page stays as it is).
/// - Cancel: every wait (flush, reads, begin, page loads, addPages, finish) races the
///   signal, so cancel() ends the export at once; an open compose job is aborted.
/// - Errors after begin abort the job. Non-PdfIoException errors there become exportFailed
///   (cause kept); every exportFailed is reported once (6.13).
/// - Batch: a missing note → item noteNotFound (title ''); other per-note PdfIoExceptions
///   are recorded; engineUnavailable / unsupportedPlatform end the batch with that error.
///   The size limit (PdfTuning.batchMaxTotalBytesWeb) applies on every platform: all
///   results are held in memory until the result sheet is closed.
final class DefaultPdfExportService implements PdfExportService {
  DefaultPdfExportService({
    required PdfNoteGateway gateway,
    required PdfInkVectorizer vectorizer,
    required PdfComposeBackend backend,
  }) : _gateway = gateway,
       _vectorizer = vectorizer,
       _backend = backend;

  final PdfNoteGateway _gateway;
  final PdfInkVectorizer _vectorizer;
  final PdfComposeBackend _backend;
  bool _running = false;

  static const int _chunkPages = kIsWeb
      ? PdfTuning.exportChunkPages
      : PdfTuning.nativeExportChunkPages;

  @override
  Future<PdfExportResult> exportNote(
    core.NoteId noteId,
    PdfExportOptions options, {
    PdfProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  }) async {
    _enter();
    try {
      return await _export(
        noteId,
        options,
        onProgress ?? _ignoreProgress,
        cancel ?? PdfCancelSignal(),
      );
    } finally {
      _running = false;
    }
  }

  @override
  Future<PdfBatchExportResult> exportNotes(
    List<core.NoteId> noteIds,
    PdfExportOptions options, {
    PdfBatchProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  }) async {
    _enter();
    try {
      return await _exportBatch(
        noteIds,
        options.copyWith(range: const PdfExportAllPages()),
        onProgress,
        cancel ?? PdfCancelSignal(),
      );
    } finally {
      _running = false;
    }
  }

  static void _ignoreProgress(PdfProgress _) {}

  void _enter() {
    if (_running) throw const PdfIoException(PdfErrorCode.busy);
    if (!_backend.isSupported) {
      throw const PdfIoException(
        PdfErrorCode.unsupportedPlatform,
        detail: 'no compose backend on this platform',
      );
    }
    _running = true;
  }

  // ------------------------------------------------------------------ batch (6.11.11)

  Future<PdfBatchExportResult> _exportBatch(
    List<core.NoteId> noteIds,
    PdfExportOptions options,
    PdfBatchProgressCallback? onProgress,
    PdfCancelSignal cancel,
  ) async {
    final items = <PdfBatchExportItem>[];
    var totalBytes = 0;
    var cancelled = false, stopped = false;
    for (var i = 0; i < noteIds.length; i++) {
      if (cancel.isCancelled) {
        cancelled = true;
        break;
      }
      if (totalBytes >= PdfTuning.batchMaxTotalBytesWeb) {
        stopped = true;
        break;
      }
      final noteId = noteIds[i];
      var title = '';
      try {
        final result = await _export(
          noteId,
          options,
          (p) => onProgress?.call(
            PdfBatchProgress(
              noteIndex: i,
              noteCount: noteIds.length,
              current: p,
            ),
          ),
          cancel,
          onNote: (note) => title = note.title,
        );
        items.add(
          PdfBatchExportItem(noteId: noteId, title: title, result: result),
        );
        totalBytes += result.bytes.length;
      } on PdfIoException catch (e) {
        if (e.code == PdfErrorCode.cancelled) {
          cancelled = true;
          break;
        }
        if (e.code == PdfErrorCode.engineUnavailable ||
            e.code == PdfErrorCode.unsupportedPlatform) {
          rethrow;
        }
        items.add(PdfBatchExportItem(noteId: noteId, title: title, error: e));
      } on Object catch (e, s) {
        reportPdfError(e, s, 'pdf batch export of note $noteId');
        items.add(
          PdfBatchExportItem(
            noteId: noteId,
            title: title,
            error: PdfIoException(
              PdfErrorCode.exportFailed,
              detail: 'unexpected export error',
              cause: e,
            ),
          ),
        );
      }
    }
    return PdfBatchExportResult(
      requestedCount: noteIds.length,
      items: _deduplicated(items),
      cancelled: cancelled,
      stoppedAtSizeLimit: stopped,
    );
  }

  /// Same file name twice in one batch → ' (2)', ' (3)' (6.11.10 rule 4).
  static List<PdfBatchExportItem> _deduplicated(
    List<PdfBatchExportItem> items,
  ) {
    final names = PdfFileNaming.deduplicate([
      for (final item in items) ?item.result?.fileName,
    ]);
    var n = 0;
    final out = <PdfBatchExportItem>[];
    for (final item in items) {
      final result = item.result;
      if (result == null) {
        out.add(item);
        continue;
      }
      final name = names[n++];
      out.add(
        name == result.fileName
            ? item
            : PdfBatchExportItem(
                noteId: item.noteId,
                title: item.title,
                result: PdfExportResult(
                  bytes: result.bytes,
                  fileName: name,
                  pageCount: result.pageCount,
                  elapsed: result.elapsed,
                  warnings: result.warnings,
                ),
              ),
      );
    }
    return out;
  }

  // ------------------------------------------------------------------ one note (6.11.2)

  Future<PdfExportResult> _export(
    core.NoteId noteId,
    PdfExportOptions options,
    PdfProgressCallback onProgress,
    PdfCancelSignal cancel, {
    void Function(core.Note note)? onNote,
  }) async {
    final watch = Stopwatch()..start();
    // 1. preparingExport: committed state first (pending while CORE retries a commit).
    onProgress(const PdfProgress(PdfJobPhase.preparingExport));
    await cancel.raceCancel(_gateway.flush());
    final note = await cancel.raceCancel(_gateway.getNote(noteId));
    if (note == null) {
      throw PdfIoException(PdfErrorCode.noteNotFound, detail: 'note $noteId');
    }
    onNote?.call(note);
    final pages = await cancel.raceCancel(_gateway.pagesOf(noteId));
    final selection = _select(pages, options.range);
    if (selection.isEmpty) {
      throw PdfIoException(
        PdfErrorCode.exportFailed,
        detail: 'note $noteId has no pages',
      );
    }
    final fileName = _fileName(note, options, selection);

    // 2. Output pages; each source once, in first-seen order.
    final sources = <PdfComposeSource>[];
    final sourceIndex = <core.AssetId, int?>{}; // null: no bytes on this device
    final missing = <int>[]; // 1-based note page numbers
    final planned = <PdfComposePagePlan>[];
    for (final i in selection) {
      final page = pages[i];
      final noteSize = ui.Size(page.size.width, page.size.height);
      final background = page.background;
      if (background is core.PdfBackground) {
        final assetId = background.assetId;
        if (!sourceIndex.containsKey(assetId)) {
          final bytes = await cancel.raceCancel(
            _gateway.readAssetBytes(assetId),
          );
          if (bytes != null) {
            sourceIndex[assetId] = sources.length;
            sources.add(PdfComposeSource(assetId: assetId, bytes: bytes));
          } else {
            sourceIndex[assetId] = null;
          }
        }
        final index = sourceIndex[assetId];
        if (index != null) {
          planned.add(
            PdfComposeSourcePage(
              sourceIndex: index,
              pdfPageIndex: background.pdfPageIndex,
              noteSize: noteSize,
            ),
          );
          continue;
        }
        missing.add(i + 1);
      }
      planned.add(PdfComposeBlankPage(noteSize: noteSize));
    }
    if (missing.isNotEmpty &&
        options.missingAssetPolicy == PdfMissingAssetPolicy.fail) {
      throw PdfIoException(
        PdfErrorCode.assetMissing,
        detail: PdfStringsKo.pageList(missing),
      );
    }
    cancel.throwIfCancelled();

    // 4. begin. A cancel while the backend loads the sources aborts the job it gives later.
    final total = planned.length;
    final beginning = _backend.begin(
      PdfComposePlan(sources: sources, pages: planned),
    );
    final PdfComposeJob job;
    try {
      job = await cancel.raceCancel(beginning);
    } on PdfIoException catch (e, s) {
      if (e.code == PdfErrorCode.cancelled) {
        beginning.then(_abortQuietly, onError: (Object _) {}).ignore();
      } else if (e.code == PdfErrorCode.exportFailed) {
        reportPdfError(e, s, 'pdf export: compose backend begin');
      }
      rethrow;
    } on Object catch (e, s) {
      throw _unexpected(e, s, 'pdf export: compose backend begin');
    }

    // 5. composing, 6. finishingExport.
    var finishing = false;
    try {
      onProgress(PdfProgress(PdfJobPhase.composing, total: total));
      final chunk = <PdfComposePageOps>[];
      var chunkBytes = 0;
      Future<void> send() async {
        final ready = [...chunk];
        chunk.clear();
        chunkBytes = 0;
        await cancel.raceCancel(job.addPages(ready));
      }

      final slice = Stopwatch()..start();
      for (var out = 0; out < total; out++) {
        cancel.throwIfCancelled();
        final ops = await _opsFor(pages[selection[out]], out, options, cancel);
        if (ops != null) {
          if (chunk.isNotEmpty &&
              chunkBytes + ops.byteLength > PdfTuning.exportChunkMaxBytes) {
            await send();
          }
          chunk.add(ops);
          chunkBytes += ops.byteLength;
          if (chunk.length >= _chunkPages ||
              chunkBytes >= PdfTuning.exportChunkMaxBytes) {
            await send();
          }
        }
        onProgress(
          PdfProgress(PdfJobPhase.composing, done: out + 1, total: total),
        );
        if (slice.elapsed > PdfTuning.exportSliceBudget) {
          // Keep frames coming on the main isolate (6.11.2 step 5).
          await Future<void>.delayed(Duration.zero);
          slice.reset();
        }
      }
      if (chunk.isNotEmpty) await send();
      cancel.throwIfCancelled();
      onProgress(
        PdfProgress(PdfJobPhase.finishingExport, done: total, total: total),
      );
      finishing = true; // finish cleans the job up, whatever its outcome
      final bytes = await cancel.raceCancel(job.finish());
      return PdfExportResult(
        bytes: bytes,
        fileName: fileName,
        pageCount: total,
        elapsed: watch.elapsed,
        warnings: [
          if (missing.isNotEmpty) PdfExportBlankedMissingAsset(missing),
        ],
      );
    } on PdfIoException catch (e, s) {
      if (!finishing) unawaited(_abortQuietly(job));
      if (e.code == PdfErrorCode.exportFailed) {
        reportPdfError(e, s, 'pdf export: compose');
      }
      rethrow;
    } on Object catch (e, s) {
      if (!finishing) unawaited(_abortQuietly(job));
      throw _unexpected(e, s, 'pdf export: compose');
    }
  }

  /// Output page indexes into [pages] (6.11.2 step 1).
  static List<int> _select(List<core.Page> pages, PdfExportRange range) {
    switch (range) {
      case PdfExportAllPages():
        return [for (var i = 0; i < pages.length; i++) i];
      case PdfExportCurrentPage(:final pageId):
        final i = pages.indexWhere((p) => p.id == pageId);
        if (i < 0) {
          throw ArgumentError.value(pageId, 'range', 'page not in the note');
        }
        return [i];
      case PdfExportSelectedPages(:final pageIds):
        final wanted = pageIds.toSet();
        final out = [
          for (var i = 0; i < pages.length; i++)
            if (wanted.contains(pages[i].id)) i,
        ];
        if (out.isEmpty) {
          throw ArgumentError.value(
            pageIds,
            'range',
            'no selected page is in the note',
          );
        }
        return out;
    }
  }

  /// options.fileName (sanitized, '.pdf' added when missing) or PdfFileNaming.forExport.
  static String _fileName(
    core.Note note,
    PdfExportOptions options,
    List<int> selection,
  ) {
    final given = options.fileName;
    if (given != null) {
      final stem = given.toLowerCase().endsWith('.pdf')
          ? given.substring(0, given.length - 4)
          : given;
      return '${PdfFileNaming.sanitize(stem)}.pdf';
    }
    return PdfFileNaming.forExport(
      note.title,
      options.range,
      currentPageNumber: options.range is PdfExportCurrentPage
          ? selection.single + 1
          : null,
      selectedCount: selection.length,
    );
  }

  /// The ops of one output page, or null when there is nothing to draw on it.
  Future<PdfComposePageOps?> _opsFor(
    core.Page page,
    int outputIndex,
    PdfExportOptions options,
    PdfCancelSignal cancel,
  ) async {
    var current = page;
    var strokes = const <core.Stroke>[];
    if (options.includeInk) {
      // The page as committed now (6.11.2 step 8 — not a whole-note snapshot).
      final content = await cancel.raceCancel(_gateway.loadPage(page.id));
      current = content.page;
      strokes = content.strokes;
    }
    final vectors = _vectorizer.vectorize(
      current,
      strokes,
      includeInk: options.includeInk,
      includeTemplate: options.includeTemplates,
    );
    if (vectors.isEmpty) return null;
    final ops = PdfComposeEncoder.encode(
      outputIndex: outputIndex,
      vectors: vectors,
    );
    return ops.isEmpty ? null : ops;
  }

  static Future<void> _abortQuietly(PdfComposeJob job) async {
    try {
      await job.abort();
    } on Object catch (e, s) {
      reportPdfError(e, s, 'pdf export: compose job abort');
    }
  }

  static PdfIoException _unexpected(Object e, StackTrace s, String where) {
    reportPdfError(e, s, where);
    return PdfIoException(
      PdfErrorCode.exportFailed,
      detail: 'unexpected error: ${e.runtimeType}',
      cause: e,
    );
  }
}
