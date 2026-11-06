// lib/src/text/text_service.dart — 06-pdf 4.8, 6.10 (PDF T11).
//
// DefaultPdfTextService keeps the 4.8 parameter list word for word (plain named parameters
// assigned to private fields), hence:
// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

import '../common/cancel_signal.dart';
import '../common/error_report.dart';
import '../engine/page_info.dart';
import '../errors.dart';
import '../gateway/pdf_note_gateway.dart';
import '../model/page_size_policy.dart';
import '../render/document_pool.dart';
import '../tuning.dart';
import 'search_types.dart';
import 'text_normalizer.dart';

abstract interface class PdfTextService {
  /// Cached (LRU PdfTuning.textCachePages). Throws assetMissing / corrupt.
  Future<PdfPageTextData> pageText(core.AssetId assetId, int pdfPageIndex);

  /// Scans PDF-background pages of the note in note order (non-PDF pages are skipped;
  /// totalPages counts PDF pages only). Emits every 10 pages or 100 ms.
  /// Starts with cancel.raceCancel(gateway.flush()) (6.10.2): the flush stays pending while
  /// CORE retries a commit (contract 7.2.9 v1.2); cancel() ends the stream at once (no error).
  Stream<PdfSearchProgress> searchNote(
    core.NoteId noteId,
    String query, {
    PdfCancelSignal? cancel,
    int maxHits = PdfTuning.maxSearchHits,
  });
  void clearCache();
}

/// 6.10.2. Errors on the stream: noteNotFound (pagesOf), engineUnavailable (no page can be
/// read). A page whose original is missing (assetMissing) or locked (passwordCancelled) is
/// skipped silently; a corrupt original is skipped and reported once per search. Both count
/// as scanned. When there is something to scan the first event is (0 / totalPages), right
/// after pagesOf; the last one has isDone (none after a cancel).
final class DefaultPdfTextService implements PdfTextService {
  DefaultPdfTextService({
    required PdfDocumentPool pool,
    required PdfNoteGateway gateway,
  }) : _pool = pool,
       _gateway = gateway;

  final PdfDocumentPool _pool;
  final PdfNoteGateway _gateway;

  /// LRU (oldest first), at most PdfTuning.textCachePages pages.
  final LinkedHashMap<_TextKey, _PageText> _cache =
      LinkedHashMap<_TextKey, _PageText>();
  final Map<_TextKey, Future<_PageText>> _loading = {};

  /// Bumped by clearCache so loads started before it are not cached.
  int _generation = 0;

  @override
  Future<PdfPageTextData> pageText(
    core.AssetId assetId,
    int pdfPageIndex,
  ) async => (await _pageText(assetId, pdfPageIndex)).data;

  @override
  void clearCache() {
    _generation++;
    _cache.clear();
    _loading.clear();
  }

  Future<_PageText> _pageText(core.AssetId assetId, int pdfPageIndex) {
    final key = _TextKey(assetId, pdfPageIndex);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached; // most recently used
      return Future.value(cached);
    }
    return _loading[key] ??= _load(key);
  }

  Future<_PageText> _load(_TextKey key) async {
    final generation = _generation;
    try {
      final lease = await _pool.acquire(key.assetId);
      final PdfPageTextData data;
      final ui.Size pdfSize;
      try {
        final pages = lease.document.info.pages;
        if (key.pageIndex < 0 || key.pageIndex >= pages.length) {
          throw PdfIoException(
            PdfErrorCode.corrupt,
            detail:
                'page ${key.pageIndex} of ${key.assetId} '
                '(${pages.length} pages)',
          );
        }
        final info = pages[key.pageIndex];
        pdfSize = ui.Size(info.width, info.height);
        data = await lease.document.loadText(key.pageIndex);
      } on PdfIoException {
        rethrow;
      } on Object catch (e, st) {
        Error.throwWithStackTrace(
          PdfIoException(
            PdfErrorCode.corrupt,
            detail: 'text of page ${key.pageIndex} of ${key.assetId}',
            cause: e,
          ),
          st,
        );
      } finally {
        lease.release();
      }
      final text = _PageText(data, pdfSize);
      if (generation == _generation) {
        _cache[key] = text;
        while (_cache.length > PdfTuning.textCachePages) {
          _cache.remove(_cache.keys.first);
        }
      }
      return text;
    } finally {
      if (generation == _generation) _loading.removeWhere((k, _) => k == key);
    }
  }

  @override
  Stream<PdfSearchProgress> searchNote(
    core.NoteId noteId,
    String query, {
    PdfCancelSignal? cancel,
    int maxHits = PdfTuning.maxSearchHits,
  }) async* {
    final signal = cancel ?? PdfCancelSignal();
    final needle = PdfTextNormalizer.normalizeQuery(query);
    // 0. Flush first so pages inserted a moment ago are visible to pagesOf. Pending while
    //    CORE retries a commit: a cancel ends the stream at once (no error, nothing scanned).
    try {
      await signal.raceCancel(_gateway.flush());
    } on PdfIoException catch (e) {
      if (e.code == PdfErrorCode.cancelled) return;
      rethrow;
    }
    if (signal.isCancelled) return;

    // 1. PDF-background pages in note order.
    final notePages = await _gateway.pagesOf(noteId);
    if (signal.isCancelled) return;
    final targets = <({core.Page page, int number, core.PdfBackground pdf})>[
      for (var i = 0; i < notePages.length; i++)
        if (notePages[i].background case final core.PdfBackground pdf)
          (page: notePages[i], number: i + 1, pdf: pdf),
    ];
    final total = targets.length;
    if (needle.isEmpty || total == 0 || maxHits <= 0) {
      yield PdfSearchProgress(
        scannedPages: 0,
        totalPages: total,
        newHits: const [],
        isDone: true,
      );
      return;
    }

    // The page count first, so a long search shows '(0/n쪽)' at once.
    yield PdfSearchProgress(
      scannedPages: 0,
      totalPages: total,
      newHits: const [],
      isDone: false,
    );
    if (signal.isCancelled) return;

    var scanned = 0, sinceEmit = 0, hitCount = 0;
    var truncated = false;
    var due = false;
    final pending = <PdfSearchHit>[];
    final skipped = <core.AssetId>{};
    final timer = Timer.periodic(
      PdfTuning.searchProgressInterval,
      (_) => due = true,
    );
    try {
      for (final target in targets) {
        if (signal.isCancelled) return;
        final assetId = target.pdf.assetId;
        if (!skipped.contains(assetId)) {
          _PageText? text;
          try {
            text = await signal.raceCancel(
              _pageText(assetId, target.pdf.pdfPageIndex),
            );
          } on PdfIoException catch (e, st) {
            switch (e.code) {
              case PdfErrorCode.cancelled:
                return;
              case PdfErrorCode.assetMissing || PdfErrorCode.passwordCancelled:
                skipped.add(assetId);
              case PdfErrorCode.engineUnavailable:
                rethrow;
              default:
                skipped.add(assetId);
                reportPdfError(e, st, 'pdf search: text of asset $assetId');
            }
          }
          if (text != null) {
            final hits = _find(
              text,
              needle,
              target.page,
              target.number,
              target.pdf,
              maxHits - hitCount,
            );
            hitCount += hits.length;
            pending.addAll(hits);
            if (hitCount >= maxHits) truncated = true;
          }
        }
        scanned++;
        sinceEmit++;
        if (truncated) break;
        if (sinceEmit >= 10 || due) {
          sinceEmit = 0;
          due = false;
          final batch = [...pending];
          pending.clear();
          yield PdfSearchProgress(
            scannedPages: scanned,
            totalPages: total,
            newHits: List.unmodifiable(batch),
            isDone: false,
          );
        }
      }
      if (signal.isCancelled) return;
      yield PdfSearchProgress(
        scannedPages: scanned,
        totalPages: total,
        newHits: List.unmodifiable(pending),
        isDone: true,
        truncated: truncated,
      );
    } finally {
      timer.cancel();
    }
  }

  /// 6.10.2 steps 3–5 on one note page: at most [limit] hits, in text order.
  List<PdfSearchHit> _find(
    _PageText text,
    String needle,
    core.Page page,
    int number,
    core.PdfBackground pdf,
    int limit,
  ) {
    final normalized = text.normalized;
    final raw = text.data.text;
    final rectsKnown = text.data.charRects.length == raw.length;
    if (!rectsKnown && !text.warned) {
      text.warned = true;
      debugPrint(
        'pdf_io: ${text.data.charRects.length} char rects for '
        '${raw.length} code units (page ${pdf.pdfPageIndex} of ${pdf.assetId}); '
        'search hits there have no highlight',
      );
    }
    final fit = rectsKnown
        ? PdfPageFit(
            notePageSize: ui.Size(page.size.width, page.size.height),
            pdfPageSize: text.pdfSize,
          )
        : null;
    final hits = <PdfSearchHit>[];
    var from = 0;
    while (hits.length < limit) {
      final at = normalized.text.indexOf(needle, from);
      if (at < 0) break;
      from = at + needle.length;
      final start = normalized.sourceStart[at];
      final end = normalized.sourceEnd[from - 1];
      // 6.10.2 step 4: identity fit (the usual case, P-1) → the rects as they are.
      final rects = fit == null
          ? const <ui.Rect>[]
          : List<ui.Rect>.unmodifiable(
              fit.isIdentity
                  ? _mergeLines(text.data.charRects, start, end)
                  : _mergeLines(
                      text.data.charRects,
                      start,
                      end,
                    ).map(fit.pdfToNote),
            );
      final snippet = _snippet(raw, start, end);
      hits.add(
        PdfSearchHit(
          pageId: page.id,
          notePageNumber: number,
          assetId: pdf.assetId,
          pdfPageIndex: pdf.pdfPageIndex,
          rects: rects,
          snippet: snippet.text,
          matchStart: snippet.matchStart,
          matchLength: snippet.matchLength,
        ),
      );
    }
    return hits;
  }
}

/// 6.10.2 step 4 (in displayed PDF pt): the non-empty char rects of [start, end) merged per
/// line — a rect joins the previous merged one when they overlap vertically by at least half
/// the smaller height and the horizontal gap is under half the larger height.
List<ui.Rect> _mergeLines(List<ui.Rect> charRects, int start, int end) {
  final merged = <ui.Rect>[];
  for (var i = start; i < end; i++) {
    final r = charRects[i];
    if (r.isEmpty || !r.isFinite) continue;
    if (merged.isNotEmpty) {
      final last = merged.last;
      final overlap =
          math.min(last.bottom, r.bottom) - math.max(last.top, r.top);
      final gap = math.max(r.left - last.right, last.left - r.right);
      if (overlap >= 0.5 * math.min(last.height, r.height) &&
          gap < 0.5 * math.max(last.height, r.height)) {
        merged[merged.length - 1] = last.expandToInclude(r);
        continue;
      }
    }
    merged.add(r);
  }
  return merged;
}

/// 6.10.2 step 5: PdfTuning.snippetContextChars raw characters before and after the match,
/// normalized without lower-casing (hyphen join, zero-width removal, whitespace collapsed,
/// jamo composed) and trimmed at the outer ends. (2차, T28) The window is normalized once
/// (normalizeKeepingCase — CORE's SearchText.normalizeMapped with the case put back) and cut
/// at the match's source offsets, so a run or a join at the edges is folded only once.
({String text, int matchStart, int matchLength}) _snippet(
  String raw,
  int start,
  int end,
) {
  var from = math.max(0, start - PdfTuning.snippetContextChars);
  var to = math.min(raw.length, end + PdfTuning.snippetContextChars);
  // Do not split a surrogate pair at the edges.
  if (from > 0 && _isLowSurrogate(raw.codeUnitAt(from))) from--;
  if (to < raw.length && _isLowSurrogate(raw.codeUnitAt(to))) to++;
  final window = normalizeKeepingCase(raw.substring(from, to));
  final text = window.text;
  var matchStart = 0;
  while (matchStart < text.length &&
      window.sourceStart[matchStart] + from < start) {
    matchStart++;
  }
  var matchEnd = matchStart;
  while (matchEnd < text.length && window.sourceStart[matchEnd] + from < end) {
    matchEnd++;
  }
  return (
    text: text,
    matchStart: matchStart,
    matchLength: matchEnd - matchStart,
  );
}

bool _isLowSurrogate(int c) => c >= 0xDC00 && c <= 0xDFFF;

@immutable
final class _TextKey {
  const _TextKey(this.assetId, this.pageIndex);
  final core.AssetId assetId;
  final int pageIndex;

  @override
  bool operator ==(Object other) =>
      other is _TextKey &&
      other.assetId == assetId &&
      other.pageIndex == pageIndex;

  @override
  int get hashCode => Object.hash(assetId, pageIndex);
}

/// One cached page: the engine text, its displayed PDF size (for PdfPageFit) and the
/// normalized text (computed on first search).
final class _PageText {
  _PageText(this.data, this.pdfSize);
  final PdfPageTextData data;
  final ui.Size pdfSize;
  late final PdfNormalizedText normalized = PdfTextNormalizer.normalize(
    data.text,
  );
  bool warned = false;
}
