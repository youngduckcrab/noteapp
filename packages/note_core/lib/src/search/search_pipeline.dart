// Internal (not exported) — the query steps after candidate selection (m5-7/02-core 6.10.4
// steps 2 and 3): judgement, pdf expansion, grouping per page, scoring, ordering, limit, then
// the hits of the returned pages only (snippet, match range, rects). The real index (CORE T33b,
// candidates from FTS5 / LIKE) and the memory index of the fake store (candidates from the FTS
// model) both call these, so equal candidates give equal results and order (CP-14).
import '../common/geometry.dart';
import '../common/ids.dart';
import 'search_ranking.dart';
import 'search_rects.dart';
import 'search_runs.dart';
import 'search_types.dart';

/// The candidate cap: at most this many live units, most recent (highest id) first (6.10.4).
const int kSearchCandidateCap = 2000;

/// A candidate unit as step 1 reads it — no body, no rects.
final class SearchCandidate {
  const SearchCandidate({
    required this.id,
    required this.source,
    required this.ownerKey,
    required this.seq,
    required this.norm,
    this.noteId,
    this.pageId,
    this.assetId,
    this.pdfIndex,
  });
  final int id;
  final SearchSource source;
  final String ownerKey;
  final int seq;
  final String norm;

  /// Non-pdf units: the page they belong to.
  final NoteId? noteId;
  final PageId? pageId;

  /// Pdf units: the PDF page (shared by every note page that shows it).
  final AssetId? assetId;
  final int? pdfIndex;
}

/// A live note page a pdf candidate expands to.
typedef SearchPageRef = ({NoteId noteId, PageId pageId});

/// One returned page: its score, its representative unit and every matching unit on it.
final class RankedSearchPage {
  RankedSearchPage(this.noteId, this.pageId);
  final NoteId noteId;
  final PageId pageId;
  final List<SearchCandidate> units = [];
  final Map<int, double> unitScores = {};
  late SearchCandidate best;
  late double score;

  /// The note's updatedAt (the second sort key).
  late int noteUpdatedAt;
}

/// Step 2: judge (searchMatches), expand pdf units ([pdfPages]), group per page, score and
/// order (score ↓ → note.updatedAt ↓ → pageId ↑). [candidates] are already alive, most recent
/// first and capped. Returns the first [limit] pages and whether there were more.
({List<RankedSearchPage> pages, bool more}) rankSearchCandidates(
  List<SearchCandidate> candidates,
  String queryNorm, {
  required List<SearchPageRef> Function(SearchCandidate pdf) pdfPages,
  required int Function(NoteId noteId) noteUpdatedAt,
  required int limit,
}) {
  final runs = searchRunsOf(queryNorm);
  // Keyed by page id (a page belongs to one note); the note id is kept on the page.
  final byPage = <PageId, RankedSearchPage>{};
  for (final c in candidates) {
    final score = matchScore(c.source, c.norm, runs);
    if (score == null) continue;
    if (c.source == SearchSource.pdf) {
      for (final t in pdfPages(c)) {
        _addUnit(byPage, t.noteId, t.pageId, c, score);
      }
    } else {
      _addUnit(byPage, c.noteId!, c.pageId!, c, score);
    }
  }
  final ordered = byPage.values.toList();
  for (final p in ordered) {
    // The best unit: the highest score; a tie goes to the most recent unit (higher id).
    var best = p.units.first;
    var b = p.unitScores[best.id]!;
    for (final u in p.units.skip(1)) {
      final s = p.unitScores[u.id]!;
      if (s > b || (s == b && u.id > best.id)) {
        best = u;
        b = s;
      }
    }
    p
      ..best = best
      ..score = pageScore(b, p.units.length)
      ..noteUpdatedAt = noteUpdatedAt(p.noteId);
  }
  // comparePageHits without a record per comparison.
  ordered.sort((a, b) {
    final s = b.score.compareTo(a.score);
    if (s != 0) return s;
    final u = b.noteUpdatedAt.compareTo(a.noteUpdatedAt);
    if (u != 0) return u;
    return a.pageId.compareTo(b.pageId);
  });
  return (
    pages: ordered.length > limit ? ordered.sublist(0, limit) : ordered,
    more: ordered.length > limit,
  );
}

void _addUnit(
  Map<PageId, RankedSearchPage> byPage,
  NoteId noteId,
  PageId pageId,
  SearchCandidate c,
  double score,
) {
  final page = byPage[pageId] ??= RankedSearchPage(noteId, pageId);
  page.units.add(c);
  page.unitScores[c.id] = score;
}

/// What step 3 reads for a unit of a returned page.
typedef SearchUnitDetail = ({
  String body,
  PageRect? rect,
  List<PageRect> pdfRects,
  double? pdfAspect,
});

/// Step 3: the hit of one returned page from the bodies / rects of its units ([detail]) and
/// the note page size (pdf boxes → pt). Rects: pdf → the representative unit's boxes of the
/// first match merged per line; ink / text / math → the rect of each matching unit of the
/// representative's source on the page, in (ownerKey, seq) order, at most 8.
PageSearchHit searchHitOf(
  RankedSearchPage page,
  String queryNorm, {
  required SearchUnitDetail Function(SearchCandidate unit) detail,
  required double pageWidth,
  required double pageHeight,
}) {
  final best = page.best;
  final d = detail(best);
  final s = snippetOf(d.body, queryNorm, bodyNorm: best.norm);
  final List<PageRect> rects;
  if (best.source == SearchSource.pdf) {
    final (start, end) = s.bodyRange;
    rects = [
      for (final f in mergeLineRects(d.pdfRects, start, end))
        fractionToPagePt(f, pageWidth, pageHeight, pdfPageAspect: d.pdfAspect),
    ];
  } else {
    final same = page.units.where((u) => u.source == best.source).toList()
      ..sort((a, b) {
        final k = a.ownerKey.compareTo(b.ownerKey);
        return k != 0 ? k : a.seq.compareTo(b.seq);
      });
    rects = [for (final u in same.take(8)) ?detail(u).rect];
  }
  return PageSearchHit(
    noteId: page.noteId,
    pageId: page.pageId,
    source: best.source,
    snippet: s.snippet,
    matchRange: s.range,
    rects: List.unmodifiable(rects),
    score: page.score,
  );
}
