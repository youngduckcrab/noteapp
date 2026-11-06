// Internal (not exported) — the query steps after candidate selection (m5-7/02-core 6.10.4
// steps 2 and 3): judgement, pdf expansion, grouping per page, scoring, ordering, limit, then
// the hits of the returned pages only (snippet, match range, rects). The real index (CORE T33b,
// candidates from FTS5 / LIKE) and the memory index of the fake store (candidates from the FTS
// model) both call these, so equal candidates give equal results and order (CP-14).
import '../common/geometry.dart';
import '../common/ids.dart';
import 'search_match.dart';
import 'search_ranking.dart';
import 'search_rects.dart';
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
  final byPage = <(NoteId, PageId), RankedSearchPage>{};
  for (final c in candidates) {
    if (!searchMatches(c.norm, queryNorm)) continue;
    final score = unitScore(c.source, c.norm, queryNorm);
    final targets = c.source == SearchSource.pdf
        ? pdfPages(c)
        : [(noteId: c.noteId!, pageId: c.pageId!)];
    for (final t in targets) {
      final page = byPage[(t.noteId, t.pageId)] ??= RankedSearchPage(
        t.noteId,
        t.pageId,
      );
      page.units.add(c);
      page.unitScores[c.id] = score;
    }
  }
  for (final p in byPage.values) {
    // The best unit: the highest score; a tie goes to the most recent unit (higher id).
    var best = p.units.first;
    for (final u in p.units.skip(1)) {
      final s = p.unitScores[u.id]!, b = p.unitScores[best.id]!;
      if (s > b || (s == b && u.id > best.id)) best = u;
    }
    p
      ..best = best
      ..score = pageScore(p.unitScores[best.id]!, p.units.length);
  }
  final ordered = byPage.values.toList()
    ..sort(
      (a, b) => comparePageHits(
        (
          score: a.score,
          noteUpdatedAt: noteUpdatedAt(a.noteId),
          pageId: a.pageId,
        ),
        (
          score: b.score,
          noteUpdatedAt: noteUpdatedAt(b.noteId),
          pageId: b.pageId,
        ),
      ),
    );
  return (
    pages: ordered.length > limit ? ordered.sublist(0, limit) : ordered,
    more: ordered.length > limit,
  );
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
  final s = snippetOf(d.body, queryNorm);
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
