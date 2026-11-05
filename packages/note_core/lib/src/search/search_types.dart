// lib/src/search/search_types.dart — (v2.0) 2nd-round contract 7.2.5 / 02-core 4.6, 6.10:
// SearchSource, SearchUnitDraft, SearchIndexWriter, PageSearchHit, SearchIndexStatus,
// SearchIndex. The provider is in providers.dart.
// Contract comments are kept verbatim (they contain <placeholders>).
// ignore_for_file: unintended_html_in_doc_comment
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../common/geometry.dart';
import '../common/ids.dart';

enum SearchSource { ink, pdf, text, math }

@immutable
final class SearchUnitDraft {
  const SearchUnitDraft({
    required this.body,
    this.rects = const [],
    this.pdfPageAspect,
  });
  final String body; // original text (CORE normalizes)
  /// source pdf: fractions [0,1] of the PDF page — one per char of body, or empty; PageRect.zero =
  /// position unknown (skipped when hit rects are merged per line). (v2.1) CORE may store them at
  /// reduced precision (≥ 1/65535 of the page) and outside SQLite (7.4.5 index size).
  ///
  /// CORE 4.6 — how CORE reads rects (6.10.4):
  ///   rects.length == body.length → one box per UTF-16 code unit of body; a hit's rects are the
  ///     boxes of the matched range merged per text line, PageRect.zero boxes skipped;
  ///   rects empty → no boxes (a hit without rects); any other length → ArgumentError.
  ///   Fractions become note-page pt by PDF 1차 PdfPageFit (contain, centered) using
  ///   pdfPageAspect; without it (null) the fractions fill the note page (exact for imported pages,
  ///   1차 PDF C-2). Stored quantized to 1/65535 of the page OUTSIDE SQLite (blob store, 6.10.3).
  final List<PageRect> rects;
  final double? pdfPageAspect; // (v2.1, CP-3) pdf only: PDF page width / height

  // CORE 4.6: ==, hashCode
  @override
  bool operator ==(Object other) =>
      other is SearchUnitDraft &&
      other.body == body &&
      const ListEquality<PageRect>().equals(other.rects, rects) &&
      other.pdfPageAspect == pdfPageAspect;

  @override
  int get hashCode => Object.hash(
    body,
    const ListEquality<PageRect>().hash(rects),
    pdfPageAspect,
  );

  @override
  String toString() =>
      'SearchUnitDraft(${body.length} chars, ${rects.length} rects)';
}

/// For pdf_io (source pdf only). ink / text / math are indexed by CORE itself from
/// HandwritingText and PageObject rows (no other package writes them).
abstract interface class SearchIndexWriter {
  /// ownerKey for pdf: '<assetId>#<pdfPageIndex>' (one entry per PDF page, shared by every note
  /// that uses the asset). sourceRev for pdf: '<assetId>:<SearchText.normalizerVersion>' plus an
  /// optional pdf_io tail (':x<extractorVersion>', v2.1 CP-PDF-2); CORE compares it as a string.
  ///
  /// CORE 4.6: SearchIndexWriter.sourceRev: any string ≤ 200 chars, compared and stored as given
  /// (CP-PDF-2 tail).
  Future<String?> sourceRevOf(SearchSource source, String ownerKey);

  /// ownerKey → sourceRev of every owner of [source] (a feeder's start-up catch-up in one query).
  Future<Map<String, String>> sourceRevs(SearchSource source);

  /// (v2.1) An empty [units] list still records the owner with [sourceRev] (a scanned page, or the
  /// '#0 last' completion mark of pdf_io) — sourceRevOf / sourceRevs then return it.
  Future<void> replaceUnits(
    SearchSource source,
    String ownerKey,
    List<SearchUnitDraft> units, {
    required String sourceRev,
  });
  Future<void> removeOwner(SearchSource source, String ownerKey);
}

@immutable
final class PageSearchHit {
  const PageSearchHit({
    required this.noteId,
    required this.pageId,
    required this.source,
    required this.snippet,
    required this.matchRange,
    this.rects = const [],
    required this.score,
  });
  final NoteId noteId;
  final PageId pageId;
  final SearchSource source;
  final String snippet; // ≤ 80 chars of original text around the match
  final (int, int) matchRange; // [start, end) in snippet
  final List<PageRect> rects; // page pt of the note's Page.size (pdf converted)
  final double score; // higher = better; for ordering only

  // CORE 4.6: ==, hashCode
  @override
  bool operator ==(Object other) =>
      other is PageSearchHit &&
      other.noteId == noteId &&
      other.pageId == pageId &&
      other.source == source &&
      other.snippet == snippet &&
      other.matchRange == matchRange &&
      const ListEquality<PageRect>().equals(other.rects, rects) &&
      other.score == score;

  @override
  int get hashCode => Object.hash(
    noteId,
    pageId,
    source,
    snippet,
    matchRange,
    const ListEquality<PageRect>().hash(rects),
    score,
  );

  @override
  String toString() =>
      'PageSearchHit($noteId/$pageId, ${source.name}, "$snippet", $score)';
}

@immutable
final class SearchIndexStatus {
  const SearchIndexStatus({
    this.pendingOwners = 0,
    this.rebuilding = false,
    this.lastRebuildAt,
  });
  final int pendingOwners;
  final bool rebuilding;
  final EpochMillis? lastRebuildAt;

  // CORE 4.6: ==, hashCode
  @override
  bool operator ==(Object other) =>
      other is SearchIndexStatus &&
      other.pendingOwners == pendingOwners &&
      other.rebuilding == rebuilding &&
      other.lastRebuildAt == lastRebuildAt;

  @override
  int get hashCode => Object.hash(pendingOwners, rebuilding, lastRebuildAt);

  @override
  String toString() =>
      'SearchIndexStatus(pending: $pendingOwners'
      '${rebuilding ? ', rebuilding' : ''}, lastRebuildAt: $lastRebuildAt)';
}

abstract interface class SearchIndex implements SearchIndexWriter {
  /// normalize → bigram phrase query (FTS5) or LIKE fallback for 1-char queries; trashed notes
  /// excluded; results grouped by page, best score first. (v2.1) At most 2,000 candidates, most
  /// recent units first; candidates are judged without reading body excerpts or rects — only the
  /// returned hits read them. createFakeNoteStore uses the same judgement and order (CP-14).
  Future<List<PageSearchHit>> searchPages(
    String query, {
    int limit = 100,
    NoteId? withinNote,
  });
  Stream<SearchIndexStatus> get status;

  /// Drops and rebuilds derived rows (also run when normalizerVersion changes).
  Future<void> rebuild({Set<SearchSource>? sources});
}
