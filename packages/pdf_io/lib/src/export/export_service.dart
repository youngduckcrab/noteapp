// lib/src/export/export_service.dart — 06-pdf 4.9, 6.11.2, 6.11.9–6.11.11 (PDF T15).
//
// The export pipeline: flush (cancellable — CORE may retry a commit forever, contract 7.2.9
// v1.2) → pages of the note and the range → compose plan (sources once each, first-seen
// order; a PDF page without local bytes becomes a blank page or fails the export) →
// backend.begin → per page loadPage → vectorize → encode, sent in chunks → finish.
// One export (single or batch) at a time per service (busy).
//
// (2차, m5-7/06-pdf T26 — 6.2.2) The page plan of the vectorizer (planPage, L-1 order) is
// resolved item by item (ObjectResolver — images, text boxes, formulas) and encoded into parts
// (PdfComposeEncoder.encodeItems — fonts ride on the first part that uses them, per job). A part
// with an image or a raster goes out right after the item that made it, before the next item is
// resolved (S-2), so one image at a time is held (ExportMemoryLedger ≤ 16 MiB — 6.2.10); on the
// native worker the part's copy is counted as `copy` while addPages runs (CP-PDF-14 ①). Fonts:
// InkFonts.ensureLoaded() ≤ exportFontLoadTimeout once per export / batch; on the web without
// fonts a text box with a non-ASCII character stops the export before begin (S-12).
//
// The public constructor keeps the 4.9 parameter list word for word; it redirects to the
// private one that also takes the internal ports (src-only createPdfExportService). Named
// parameters cannot be private, hence:
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
import 'export_diagnostics.dart';
import 'export_memory.dart';
import 'export_types.dart';
import 'object_resolver.dart';
import 'raster_ports.dart';
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

/// (2차, m5-7/06-pdf T26) src only (not in the barrel): DefaultPdfExportService with its
/// internal ports replaced — the raster ports (6.2.4), the font wait and bytes (6.2.2 step 1),
/// the web rules on the VM ([web]: S-12 stop, 16-part chunks, no `copy`) and a look at each
/// export's memory ledger ([onLedger], called once per note before begin's compose loop);
/// [diagnostics] records each note's ledger after its compose loop (C26-02 — the developer
/// lines of pdfDevOverlayLinesProvider).
DefaultPdfExportService createPdfExportService({
  required PdfNoteGateway gateway,
  required PdfInkVectorizer vectorizer,
  required PdfComposeBackend backend,
  PdfMathRasterizer math = const InkMathRasterizer(),
  PdfTextRasterizer text = const InkTextRasterizer(),
  Future<void> Function() loadFonts = loadNoteSansFonts,
  PdfFontBytesSource? fontBytes,
  Duration fontLoadTimeout = PdfTuning.exportFontLoadTimeout,
  Duration mathTimeout = PdfTuning.exportMathRasterTimeout,
  bool web = kIsWeb,
  void Function(ExportMemoryLedger ledger)? onLedger,
  PdfExportDiagnostics? diagnostics,
}) => DefaultPdfExportService._ports(
  gateway: gateway,
  vectorizer: vectorizer,
  backend: backend,
  math: math,
  text: text,
  loadFonts: loadFonts,
  fontBytes: fontBytes,
  fontLoadTimeout: fontLoadTimeout,
  mathTimeout: mathTimeout,
  web: web,
  onLedger: onLedger,
  diagnostics: diagnostics,
);

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
///
/// (2차, T26 — 6.2.2) Objects: see the file comment. Warnings = 1차 missing originals, then
/// missing images · rasterized text · skipped formulas (pages ascending). The web stop without
/// fonts is PdfIoException(exportFailed, detail: 'fonts-unavailable') before begin, not
/// reported (an offline device, not a fault).
final class DefaultPdfExportService implements PdfExportService {
  DefaultPdfExportService({
    required PdfNoteGateway gateway,
    required PdfInkVectorizer vectorizer,
    required PdfComposeBackend backend,
  }) : this._ports(gateway: gateway, vectorizer: vectorizer, backend: backend);

  DefaultPdfExportService._ports({
    required PdfNoteGateway gateway,
    required PdfInkVectorizer vectorizer,
    required PdfComposeBackend backend,
    PdfMathRasterizer math = const InkMathRasterizer(),
    PdfTextRasterizer text = const InkTextRasterizer(),
    Future<void> Function() loadFonts = loadNoteSansFonts,
    PdfFontBytesSource? fontBytes,
    Duration fontLoadTimeout = PdfTuning.exportFontLoadTimeout,
    Duration mathTimeout = PdfTuning.exportMathRasterTimeout,
    bool web = kIsWeb,
    void Function(ExportMemoryLedger ledger)? onLedger,
    PdfExportDiagnostics? diagnostics,
  }) : _gateway = gateway,
       _vectorizer = vectorizer,
       _backend = backend,
       _math = math,
       _text = text,
       _loadFonts = loadFonts,
       _fontBytes = fontBytes,
       _fontLoadTimeout = fontLoadTimeout,
       _mathTimeout = mathTimeout,
       _web = web,
       _onLedger = onLedger,
       _diagnostics = diagnostics;

  final PdfNoteGateway _gateway;
  final PdfInkVectorizer _vectorizer;
  final PdfComposeBackend _backend;
  final PdfMathRasterizer _math;
  final PdfTextRasterizer _text;
  final Future<void> Function() _loadFonts;
  final PdfFontBytesSource? _fontBytes;
  final Duration _fontLoadTimeout, _mathTimeout;
  final bool _web;
  final void Function(ExportMemoryLedger ledger)? _onLedger;
  final PdfExportDiagnostics? _diagnostics;
  bool _running = false;

  int get _chunkPages =>
      _web ? PdfTuning.exportChunkPages : PdfTuning.nativeExportChunkPages;

  @override
  Future<PdfExportResult> exportNote(
    core.NoteId noteId,
    PdfExportOptions options, {
    PdfProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  }) async {
    _enter();
    try {
      final signal = cancel ?? PdfCancelSignal();
      return await _export(
        noteId,
        options,
        onProgress ?? _ignoreProgress,
        signal,
        fonts: _fontsOnce(signal),
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

  /// 6.2.2 step 1: InkFonts.ensureLoaded() within exportFontLoadTimeout, asked for once (an
  /// export or a whole batch). A failure or a time-out → false (text boxes are rasterized); a
  /// cancel is rethrown.
  Future<bool> Function() _fontsOnce(PdfCancelSignal cancel) {
    Future<bool>? ready;
    Future<bool> wait() async {
      try {
        await cancel.raceCancel(_loadFonts().timeout(_fontLoadTimeout));
        return true;
      } on PdfIoException catch (e) {
        if (e.code == PdfErrorCode.cancelled) rethrow;
        return false;
      } on Object {
        return false;
      }
    }

    return () => ready ??= wait();
  }

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
    final fonts = _fontsOnce(cancel); // waited for once per batch (6.2.2)
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
          fonts: fonts,
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
    required Future<bool> Function() fonts,
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
    // (2차) the fonts of the text boxes (6.2.2 step 1 — once per export / batch)
    final fontsReady = await fonts();

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
    // (2차, S-12) the web without NoteSans: Hangul would come out as tofu even in the raster
    // fallback when offline — stop before begin if a text box needs more than ASCII.
    if (_web && !fontsReady && options.includeInk) {
      for (final i in selection) {
        final content = await cancel.raceCancel(_gateway.loadPage(pages[i].id));
        if (content.objects.any(_needsFonts)) {
          throw const PdfIoException(
            PdfErrorCode.exportFailed,
            detail: PdfStringsKo.fontsUnavailableDetail,
          );
        }
      }
    }

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
    final ledger = ExportMemoryLedger();
    _onLedger?.call(ledger);
    final resolver = ObjectResolver(
      gateway: _gateway,
      math: _math,
      text: _text,
      fontBytes: _fontBytes,
      mathTimeout: _mathTimeout,
      ledger: ledger,
    );
    final ctx = ResolveContext(
      missingAssetPolicy: options.missingAssetPolicy,
      cancel: cancel,
      fontsReady: fontsReady,
    );
    final composer = _PartSender(
      job: job,
      cancel: cancel,
      resolver: resolver,
      ledger: ledger,
      chunkPages: _chunkPages,
      countCopy: !_web,
    );
    final sentFonts =
        <int>{}; // per job: every note is its own document (6.2.6)
    var finishing = false;
    try {
      onProgress(PdfProgress(PdfJobPhase.composing, total: total));
      final slice = Stopwatch()..start();
      for (var out = 0; out < total; out++) {
        cancel.throwIfCancelled();
        ctx.notePageNumber = selection[out] + 1;
        final plan = await _planFor(pages[selection[out]], options, cancel);
        final pending = <PdfDrawItem>[];
        for (final item in plan.items) {
          cancel.throwIfCancelled();
          final draws = item is PdfDrawItem
              ? <PdfDrawItem>[item]
              : await resolver.resolve(item, ctx);
          pending.addAll(draws);
          if (draws.any((d) => d is PdfImageItem)) {
            // S-2: the image goes out before the next item is resolved (6.2.10 ①).
            await composer.queue(_encode(out, pending, ctx, sentFonts));
            pending.clear();
            await composer.flush();
          }
        }
        if (pending.isNotEmpty) {
          await composer.queue(_encode(out, pending, ctx, sentFonts));
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
      await composer.flush();
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
          ...ctx.warnings,
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
    } finally {
      resolver.dispose();
      // The developer's count (6.2.10 ⑤ — M-3 outside input, CP-PDF-14 ②; C26-02): peak and
      // overBudget of this note, finished or not.
      _diagnostics?.record(ledger);
    }
  }

  /// A live text box with a character outside ASCII (6.2.2 S-12).
  static bool _needsFonts(core.PageObject o) =>
      o is core.TextBoxObject &&
      o.deletedAt == null &&
      o.text.codeUnits.any((c) => c > 0x7F);

  /// [items] of output page [outputIndex] → its next parts (fonts first used here ride along).
  static List<PdfComposePageOps> _encode(
    int outputIndex,
    List<PdfDrawItem> items,
    ResolveContext ctx,
    Set<int> sentFonts,
  ) => PdfComposeEncoder.encodeItems(
    outputIndex: outputIndex,
    items: items,
    fontBytes: ctx.fontBytes,
    sentFonts: sentFonts,
  );

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

  /// The page plan of one output page (6.2.2 step 4): with ink the page as committed now
  /// (6.11.2 step 8 — not a whole-note snapshot); original only → the page without strokes and
  /// objects (its background — an image background too — is on the Page).
  Future<PdfPagePlan> _planFor(
    core.Page page,
    PdfExportOptions options,
    PdfCancelSignal cancel,
  ) async {
    final content = options.includeInk
        ? await cancel.raceCancel(_gateway.loadPage(page.id))
        : core.PageContent(page: page, strokes: const [], revision: 0);
    return _vectorizer.planPage(
      content,
      includeInk: options.includeInk,
      includeTemplate: options.includeTemplates,
    );
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

/// The parts of one export on their way to the compose job (6.2.2 step 4): queued by the 1차
/// chunk rules (chunkPages parts, ≤ exportChunkMaxBytes unless one part is larger) and sent with
/// [flush]. After a send the resolver releases what the sent images held. While addPages runs:
/// on the native worker the images' copy is held as `copy` (CP-PDF-14 ①); on the web RGBA is
/// transferred (no copy) and JPEG bytes are cloned (they may go back to the cache — T23), so
/// that clone is held as `encoded` (6.2.10 '보내는 사본'). Both are released in finally, also
/// after an error or a cancel.
final class _PartSender {
  _PartSender({
    required this.job,
    required this.cancel,
    required this.resolver,
    required this.ledger,
    required this.chunkPages,
    required this.countCopy,
  });

  final PdfComposeJob job;
  final PdfCancelSignal cancel;
  final ObjectResolver resolver;
  final ExportMemoryLedger ledger;
  final int chunkPages;
  final bool countCopy;
  final List<PdfComposePageOps> _queued = [];
  int _queuedBytes = 0;

  Future<void> queue(List<PdfComposePageOps> parts) async {
    for (final part in parts) {
      if (_queued.isNotEmpty &&
          _queuedBytes + part.byteLength > PdfTuning.exportChunkMaxBytes) {
        await flush();
      }
      _queued.add(part);
      _queuedBytes += part.byteLength;
      if (_queued.length >= chunkPages ||
          _queuedBytes >= PdfTuning.exportChunkMaxBytes) {
        await flush();
      }
    }
  }

  Future<void> flush() async {
    if (_queued.isEmpty) return;
    final ready = List<PdfComposePageOps>.of(_queued);
    _queued.clear();
    _queuedBytes = 0;
    final images = [for (final part in ready) ...part.images];
    var copyBytes = 0, jpegBytes = 0;
    for (final image in images) {
      copyBytes += image.byteLength;
      if (image is PdfJpegData) jpegBytes += image.byteLength;
    }
    final ExportMemoryHandle? copy;
    if (countCopy) {
      copy = copyBytes > 0 ? ledger.holdCopy(copyBytes) : null;
    } else {
      copy = jpegBytes > 0
          ? ledger.hold(ExportMemoryKind.encoded, jpegBytes)
          : null;
    }
    try {
      await cancel.raceCancel(job.addPages(ready));
    } finally {
      if (copy != null) ledger.release(copy);
    }
    resolver.sent(images);
  }
}
