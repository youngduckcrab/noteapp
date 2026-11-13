// Internal (not exported) — Korean spacing of recognized handwriting (m5-7/02-core 6.10.2
// 'ink 띄어쓰기'). A handwriting engine often adds or drops a space inside a Korean word
// ('회의 록' for 회의록), so for SearchSource.ink units only:
//   - the FTS terms also hold the terms of the unit's norm with every space between two CJK
//     characters removed ([unitIndexTerms]);
//   - a unit whose norm does not match the query is judged again on both texts with those
//     spaces removed ([cjkCompact]) — the score features then come from the compact texts;
//   - the snippet range is found on the compact texts and mapped back ([inkSpacingBodyRange]).
// Text boxes, formulas and pdf text keep the exact 6.10.2 rule. The real and the fake index
// both use this file (CP-14).
import 'search_runs.dart';
import 'search_text.dart';
import 'search_types.dart';

/// (v1) Version of the ink terms: an index built without them (no kv value or another one)
/// re-indexes its ink owners once at store open.
const int kInkTermsVersion = 1;

/// [norm] (normalized text) with every ' ' between two CJK characters removed:
/// '회의 록 meeting' → '회의록 meeting'; '회의 meeting' stays.
String cjkCompact(String norm) => _compact(norm).text;

/// [cjkCompact] and, for each code unit of the result, its index in [norm].
({String text, List<int> at}) _compact(String norm) {
  if (!norm.contains(' ')) {
    return (text: norm, at: List<int>.generate(norm.length, (i) => i));
  }
  final out = StringBuffer();
  final at = <int>[];
  for (var i = 0; i < norm.length; i++) {
    final c = norm.codeUnitAt(i);
    if (c == 0x20 &&
        i > 0 &&
        i + 1 < norm.length &&
        _isCjkUnit(norm.codeUnitAt(i - 1)) &&
        _isCjkUnit(norm.codeUnitAt(i + 1))) {
      continue;
    }
    out.writeCharCode(c);
    at.add(i);
  }
  return (text: out.toString(), at: at);
}

/// A CJK character in one UTF-16 code unit (Hangul syllables and jamo, Han, kana) — enough
/// for the space test: the normalizer folds whitespace to one ' ' between them.
bool _isCjkUnit(int c) =>
    (c >= 0xAC00 && c <= 0xD7A3) || // Hangul syllables
    (c >= 0x1100 && c <= 0x11FF) || // Hangul jamo
    (c >= 0x3130 && c <= 0x318F) || // compatibility jamo
    (c >= 0x3040 && c <= 0x30FF) || // Hiragana, Katakana
    (c >= 0x3400 && c <= 0x4DBF) || // Han extension A
    (c >= 0x4E00 && c <= 0x9FFF) || // Han
    (c >= 0xF900 && c <= 0xFAFF); // Han compatibility

/// The FTS `g` column of a unit: SearchText.indexTerms of [norm]; for an ink unit whose
/// compact text differs, the compact text's terms are added after them.
String unitIndexTerms(SearchSource source, String norm) {
  final terms = SearchText.indexTerms(norm);
  if (source != SearchSource.ink) return terms;
  final compact = cjkCompact(norm);
  if (compact == norm) return terms;
  final more = SearchText.indexTerms(compact);
  return terms.isEmpty ? more : '$terms $more';
}

/// The runs of the compact query (the ink spacing judgement); null for a query without runs.
List<SearchRun>? inkCompactRuns(String queryNorm) {
  final runs = searchRunsOf(cjkCompact(queryNorm));
  return runs.isEmpty ? null : runs;
}

/// The range in [body] of the first compact query run's first match in the compact [bodyNorm]
/// (null when there is none) — the ink snippet range when the plain rule found no match.
(int, int)? inkSpacingBodyRange(
  String body,
  String bodyNorm,
  String queryNorm,
) {
  final runs = searchRunsOf(cjkCompact(queryNorm));
  if (runs.isEmpty) return null;
  final q = runs.first.text;
  final compact = _compact(bodyNorm);
  final at = compact.text.indexOf(q);
  if (at < 0 || q.isEmpty) return null;
  final start = compact.at[at];
  final end = compact.at[at + q.length - 1] + 1;
  final mapping = SearchText.normalizeMapped(body);
  if (end > mapping.text.length) return null;
  return (mapping.sourceStart[start], mapping.sourceEnd[end - 1]);
}
