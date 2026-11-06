// Internal (not exported) — scores and snippets of m5-7/02-core 6.10.4, shared by the real and
// the fake index (CP-14). Only the normalized text is read for the score, so candidates are
// ranked before any body or rect is loaded. Scores are IEEE 754 doubles computed in one fixed
// order (no fused multiply-add on the VM or in JavaScript), so the VM, the web and the fake give
// bit-identical values for the same input.
import 'dart:math' as math;

import 'search_match.dart';
import 'search_runs.dart';
import 'search_text.dart';
import 'search_types.dart';

/// The source weight of a unit (text 1.0, math 0.95, ink 0.9, pdf 0.8).
double sourceWeight(SearchSource source) => switch (source) {
  SearchSource.text => 1.0,
  SearchSource.math => 0.95,
  SearchSource.ink => 0.9,
  SearchSource.pdf => 0.8,
};

/// Unit score = weight + 0.3 (the first query run matches at a run start) + 0.05 × min(its
/// match count, 6) − 0.0005 × min(its first match position, 400). Matches of the first query
/// run are non-overlapping occurrences in [unitNorm]; positions are UTF-16 code units.
double unitScore(SearchSource source, String unitNorm, String queryNorm) =>
    unitScoreRuns(source, unitNorm, searchRunsOf(queryNorm));

/// [unitScore] with the runs of the query already split (CORE T33b, PF-3).
double unitScoreRuns(
  SearchSource source,
  String unitNorm,
  List<SearchRun> runs,
) {
  final w = sourceWeight(source);
  if (runs.isEmpty) return w;
  final q = runs.first.text;
  var count = 0;
  var first = -1;
  var atStart = false;
  var i = unitNorm.indexOf(q);
  while (i >= 0) {
    count++;
    if (first < 0) first = i;
    if (!atStart && !runCharBefore(unitNorm, i)) atStart = true;
    i = unitNorm.indexOf(q, i + q.length);
  }
  if (first < 0) first = 0;
  return w +
      (atStart ? 0.3 : 0.0) +
      0.05 * math.min(count, 6) -
      0.0005 * math.min(first, 400);
}

/// `searchMatches(unitNorm, q) ? unitScore(source, unitNorm, q) : null` in one pass over the
/// first query run's non-overlapping occurrences (CORE T33b — PF-3): they give its judgement
/// and its score features. Skipping the overlapping occurrences does not change the judgement:
/// one that overlaps a counted occurrence lies in the same run, so its run is CJK exactly when
/// that one's is, and it never starts the run.
double? matchScore(SearchSource source, String unitNorm, List<SearchRun> runs) {
  if (runs.isEmpty) return null;
  final head = runs.first;
  final q = head.text;
  final contains = head.codePoints == 1 || head.isCjk;
  var count = 0;
  var first = -1;
  var atStart = false;
  var ok = contains;
  var i = unitNorm.indexOf(q);
  while (i >= 0) {
    count++;
    if (first < 0) first = i;
    if (!atStart && !runCharBefore(unitNorm, i)) atStart = true;
    if (!ok) {
      final run = runAround(unitNorm, i, i + q.length);
      ok = run.cjk ? head.codePoints == 2 : run.start == i;
    }
    i = unitNorm.indexOf(q, i + q.length);
  }
  if (count == 0 || !ok) return null;
  if (runs.length > 1 && !searchMatchesRuns(unitNorm, runs.sublist(1))) {
    return null;
  }
  return sourceWeight(source) +
      (atStart ? 0.3 : 0.0) +
      0.05 * math.min(count, 6) -
      0.0005 * math.min(first, 400);
}

/// Page score = the best unit score + 0.02 × min(matching units − 1, 10).
double pageScore(double bestUnitScore, int matchingUnits) =>
    bestUnitScore + 0.02 * math.min(matchingUnits - 1, 10);

/// Page order: score ↓ → note.updatedAt ↓ → pageId ↑.
int comparePageHits(
  ({double score, int noteUpdatedAt, String pageId}) a,
  ({double score, int noteUpdatedAt, String pageId}) b,
) {
  final s = b.score.compareTo(a.score);
  if (s != 0) return s;
  final u = b.noteUpdatedAt.compareTo(a.noteUpdatedAt);
  if (u != 0) return u;
  return a.pageId.compareTo(b.pageId);
}

/// The ≤ 80-char snippet of [body] around the first match of the first query run (6.10.4):
/// from 30 code units before the match start, cut at code point boundaries; '\n', '\r' and
/// '\t' become ' ' (same length, so the range holds). Also returns the match range
/// [start, end) in the snippet and in [body].
///
/// [bodyNorm] (= SearchText.normalize(body), the unit's norm) lets the mapping stop at the
/// match (CORE T33b, PF-3) — the same answer.
({String snippet, (int, int) range, (int, int) bodyRange}) snippetOf(
  String body,
  String queryNorm, {
  String? bodyNorm,
}) {
  final runs = searchRunsOf(queryNorm);
  var srcStart = 0, srcEnd = 0;
  if (runs.isNotEmpty) {
    final q = runs.first.text;
    final hint = bodyNorm?.indexOf(q);
    final mapping = hint == null
        ? SearchText.normalizeMapped(body)
        : normalizeMappedPrefix(body, hint < 0 ? 0 : hint + q.length);
    final at = hint ?? mapping.text.indexOf(q);
    if (at >= 0 && q.isNotEmpty) {
      srcStart = mapping.sourceStart[at];
      srcEnd = mapping.sourceEnd[at + q.length - 1];
    }
  }
  var from = math.max(0, srcStart - 30);
  if (from > 0 &&
      _isLow(body.codeUnitAt(from)) &&
      _isHigh(body.codeUnitAt(from - 1))) {
    from--;
  }
  var to = math.min(body.length, from + 80);
  if (to < body.length && to > from && _isHigh(body.codeUnitAt(to - 1))) to--;
  final snippet = body
      .substring(from, to)
      .replaceAll('\n', ' ')
      .replaceAll('\r', ' ')
      .replaceAll('\t', ' ');
  final start = math.min(srcStart, to) - from;
  final end = math.min(srcEnd, to) - from;
  return (
    snippet: snippet,
    range: (start, math.max(start, end)),
    bodyRange: (srcStart, srcEnd),
  );
}

bool _isHigh(int c) => c >= 0xD800 && c <= 0xDBFF;
bool _isLow(int c) => c >= 0xDC00 && c <= 0xDFFF;
