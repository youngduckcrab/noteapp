// Internal (not exported) — the match judgement and the FTS5 candidate model of m5-7/02-core
// 6.10.2 / 6.10.6. The real index (FTS5 MATCH or LIKE, then searchMatches) and the fake index
// (ftsCandidateMatches or the same LIKE test, then searchMatches) decide with this one file, so
// their results and order are the same (CP-14).
import 'search_runs.dart';

/// The final match decision on normalized text (6.10.2 table). Every run q of [queryNorm]
/// must match:
///   one code point → [unitNorm] contains q;
///   two or more, CJK → some CJK run of the unit contains q;
///   two or more, not CJK → some non-CJK run starts with q, or (q is two code points) some CJK
///     run contains q (the FTS prefix also matches an equal bigram).
/// A query without runs matches nothing.
///
/// (CORE T33b — PF-3) Decided from the occurrences of q in [unitNorm] instead of splitting the
/// whole unit into runs: q consists of run characters only, so each occurrence lies inside one
/// run of the unit — a CJK q makes that run CJK (the rule is then 'contains'), a non-CJK q looks
/// only at the run around each occurrence (its start and whether it holds a CJK character).
bool searchMatches(String unitNorm, String queryNorm) {
  final query = searchRunsOf(queryNorm);
  if (query.isEmpty) return false;
  for (final q in query) {
    if (q.codePoints == 1 || q.isCjk) {
      if (!unitNorm.contains(q.text)) return false;
      continue;
    }
    var ok = false;
    for (
      var i = unitNorm.indexOf(q.text);
      i >= 0 && !ok;
      i = unitNorm.indexOf(q.text, i + 1)
    ) {
      final run = runAround(unitNorm, i, i + q.text.length);
      ok = run.cjk ? q.codePoints == 2 : run.start == i;
    }
    if (!ok) return false;
  }
  return true;
}

/// The LIKE path of a query with no run of two or more code points: [unitNorm] contains every
/// run (`norm LIKE '%x%'` per run).
bool likeCandidateMatches(String unitNorm, String queryNorm) {
  final query = searchRunsOf(queryNorm);
  return query.isNotEmpty && query.every((q) => unitNorm.contains(q.text));
}

/// What SQLite FTS5 answers for `g MATCH [matchQuery]` on a row whose `g` is [unitTerms]
/// (SearchText.indexTerms of its norm), for the query shapes SearchText.matchQuery builds:
/// items joined by ' AND '; `"t1 t2 …"` = a phrase (the tokens appear consecutively),
/// `"p"*` = a prefix (some token starts with p). Inner '""' is one '"'. A null query matches
/// nothing (the caller takes the LIKE path).
bool ftsCandidateMatches(String unitTerms, String? matchQuery) {
  if (matchQuery == null) return false;
  final tokens = [
    for (final t in unitTerms.split(' '))
      if (t.isNotEmpty) t,
  ];
  for (final item in _items(matchQuery)) {
    if (item.prefix) {
      final p = item.tokens.single;
      if (!tokens.any((t) => t.startsWith(p))) return false;
    } else if (!_hasPhrase(tokens, item.tokens)) {
      return false;
    }
  }
  return true;
}

bool _hasPhrase(List<String> tokens, List<String> phrase) {
  if (phrase.isEmpty) return true;
  outer:
  for (var i = 0; i + phrase.length <= tokens.length; i++) {
    for (var j = 0; j < phrase.length; j++) {
      if (tokens[i + j] != phrase[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// The items of a matchQuery string (quoted, '""' escapes, optional trailing '*').
List<({List<String> tokens, bool prefix})> _items(String query) {
  final items = <({List<String> tokens, bool prefix})>[];
  var i = 0;
  while (i < query.length) {
    if (query.startsWith(' AND ', i)) {
      i += 5;
      continue;
    }
    if (query.codeUnitAt(i) != 0x22) {
      throw FormatException('not a SearchText.matchQuery: $query');
    }
    final text = StringBuffer();
    i++;
    while (true) {
      if (i >= query.length) {
        throw FormatException('unterminated item: $query');
      }
      if (query.codeUnitAt(i) == 0x22) {
        if (i + 1 < query.length && query.codeUnitAt(i + 1) == 0x22) {
          text.write('"');
          i += 2;
          continue;
        }
        i++;
        break;
      }
      text.writeCharCode(query.codeUnitAt(i));
      i++;
    }
    final prefix = i < query.length && query.codeUnitAt(i) == 0x2A;
    if (prefix) i++;
    items.add((
      tokens: [
        for (final t in text.toString().split(' '))
          if (t.isNotEmpty) t,
      ],
      prefix: prefix,
    ));
  }
  return items;
}
