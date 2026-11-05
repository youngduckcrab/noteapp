// The contract doc comments name generic types (ListEquality of rects / hits) literally.
// ignore_for_file: unintended_html_in_doc_comment

// lib/src/text/search_types.dart — 06-pdf 4.8, 6.10.2.
//
// Foundation step B4 (T0): value equality is real (contract 7.4.4). The highlight rect
// lookups are real from PDF T9 (the background painter reads them); the search itself is
// PDF T11.
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

import '../errors.dart';

@immutable
final class PdfSearchHit {
  const PdfSearchHit({
    required this.pageId,
    required this.notePageNumber,
    required this.assetId,
    required this.pdfPageIndex,
    required this.rects,
    required this.snippet,
    required this.matchStart,
    required this.matchLength,
  });
  final core.PageId pageId;
  final int notePageNumber; // 1-based position in the note
  final core.AssetId assetId;
  final int pdfPageIndex;

  /// Merged per line, in NOTE page pt of [pageId] (core.Page.size, origin top-left, y down) —
  /// the space of EditorMenuContext.navigateToPage focusRectPt (contract 7.2.17 v1.1).
  /// charRects are converted with PdfPageFit.pdfToNote (identity when the sizes match;
  /// 6.5 s ≠ 1 or a resized page → scaled / offset, 6.10.2). The highlight painter and
  /// onNavigate use these SAME rects.
  final List<ui.Rect> rects;
  final String snippet; // ±24 chars of context, whitespace collapsed
  final int matchStart; // in snippet
  final int matchLength;

  static const ListEquality<ui.Rect> _rects = ListEquality<ui.Rect>();

  /// Every field; rects with ListEquality<ui.Rect> (contract 7.4.4).
  @override
  bool operator ==(Object other) =>
      other is PdfSearchHit &&
      other.pageId == pageId &&
      other.notePageNumber == notePageNumber &&
      other.assetId == assetId &&
      other.pdfPageIndex == pdfPageIndex &&
      _rects.equals(other.rects, rects) &&
      other.snippet == snippet &&
      other.matchStart == matchStart &&
      other.matchLength == matchLength;

  @override
  int get hashCode => Object.hash(
    pageId,
    notePageNumber,
    assetId,
    pdfPageIndex,
    _rects.hash(rects),
    snippet,
    matchStart,
    matchLength,
  );

  @override
  String toString() =>
      'PdfSearchHit(page $notePageNumber ($pageId), pdf $pdfPageIndex, '
      '${rects.length} rects, "$snippet")';
}

enum PdfSearchStatus { idle, searching, done, failed }

@immutable
final class PdfSearchState {
  const PdfSearchState({
    this.noteId,
    this.query = '',
    this.status = PdfSearchStatus.idle,
    this.scannedPages = 0,
    this.totalPages = 0,
    this.hits = const [],
    this.currentIndex = -1,
    this.truncated = false,
    this.error,
  });
  static const PdfSearchState idle = PdfSearchState();
  final core.NoteId? noteId;
  final String query;
  final PdfSearchStatus status;
  final int scannedPages;
  final int totalPages;
  final List<PdfSearchHit> hits; // note page order, then position on page
  final int currentIndex; // -1 = none selected
  final bool truncated; // maxHits reached
  final PdfIoException? error;

  /// hits[currentIndex], or null when none is selected.
  PdfSearchHit? get current => currentIndex >= 0 && currentIndex < hits.length
      ? hits[currentIndex]
      : null;

  /// Highlight rects (note page pt) of one NOTE page — keyed by pageId, not by PDF page,
  /// because the same PDF page may back several note pages of different sizes.
  /// Used by PdfPageBackgroundView with params.pageId.
  List<ui.Rect> rectsFor(core.PageId pageId) => [
    for (final hit in hits)
      if (hit.pageId == pageId) ...hit.rects,
  ];

  List<ui.Rect> currentRectsFor(core.PageId pageId) {
    final hit = current;
    return hit != null && hit.pageId == pageId ? hit.rects : const [];
  }

  /// Union of current!.rects — the focusRectPt passed to onNavigate (6.10.2 step 7).
  ui.Rect? get currentFocusRect {
    final rects = current?.rects;
    if (rects == null || rects.isEmpty) return null;
    return rects
        .skip(1)
        .fold<ui.Rect>(rects.first, (a, b) => a.expandToInclude(b));
  }

  static const ListEquality<PdfSearchHit> _hits = ListEquality<PdfSearchHit>();

  /// Every field; hits with ListEquality<PdfSearchHit> (deep — PdfSearchHit ==), error with
  /// PdfIoException == (contract 7.4.4). pdfActiveSearchProvider (Riverpod: previous != next)
  /// and the pdfSearchHighlightsProvider ValueNotifier both skip equal states.
  @override
  bool operator ==(Object other) =>
      other is PdfSearchState &&
      other.noteId == noteId &&
      other.query == query &&
      other.status == status &&
      other.scannedPages == scannedPages &&
      other.totalPages == totalPages &&
      _hits.equals(other.hits, hits) &&
      other.currentIndex == currentIndex &&
      other.truncated == truncated &&
      other.error == error;

  @override
  int get hashCode => Object.hash(
    noteId,
    query,
    status,
    scannedPages,
    totalPages,
    _hits.hash(hits),
    currentIndex,
    truncated,
    error,
  );

  @override
  String toString() =>
      'PdfSearchState(${status.name}, note: $noteId, query: "$query", '
      '$scannedPages/$totalPages pages, ${hits.length} hits, '
      'current: $currentIndex, truncated: $truncated, error: $error)';
}

@immutable
final class PdfSearchProgress {
  const PdfSearchProgress({
    required this.scannedPages,
    required this.totalPages,
    required this.newHits,
    required this.isDone,
    this.truncated = false,
  });
  final int scannedPages, totalPages;
  final List<PdfSearchHit> newHits;
  final bool isDone;
  final bool truncated;
}
