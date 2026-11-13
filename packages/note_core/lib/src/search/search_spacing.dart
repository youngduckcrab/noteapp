// Internal (not exported) — Korean spacing of recognized handwriting (m5-7/02-core 6.10.2
// 'ink 띄어쓰기'). A handwriting engine often adds or drops a space inside a Korean word
// ('회의 록' for 회의록), so for SearchSource.ink units only:
//   - the FTS terms also hold the terms of the unit's norm with every space between two CJK
//     characters (or a Hangul syllable and an ASCII digit: '3 월', '회의 3분기') removed
//     ([unitIndexTerms]);
//   - a unit whose norm does not match the query is judged again on both texts with those
//     spaces removed ([cjkCompact]) — the score features then come from the compact texts,
//     less [kInkSpacingPenalty], and a compact query of one CJK run of ≤ 2 characters gets
//     no second judgement (joining two words would make '사과' find '이사 과장');
//   - the snippet range is found on the compact texts and mapped back ([inkSpacingBodyRange]).
// Text boxes, formulas and pdf text keep the exact 6.10.2 rule. The real and the fake index
// both use this file (CP-14).
import 'search_runs.dart';
import 'search_text.dart';
import 'search_types.dart';

/// (v2: Hangul next to a digit is joined too) Version of the ink terms: an index built
/// without them (no kv value or another one) re-indexes its ink owners once at store open.
const int kInkTermsVersion = 2;

/// Taken off the score of a unit matched only on the compact texts, so that it ranks below
/// a plain match of the same unit shape.
const double kInkSpacingPenalty = 0.1;

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
        _joins(_cpBefore(norm, i), _cpAt(norm, i + 1))) {
      continue;
    }
    out.writeCharCode(c);
    at.add(i);
  }
  return (text: out.toString(), at: at);
}

/// The code point ending just before code unit [i].
int _cpBefore(String s, int i) {
  final c = s.codeUnitAt(i - 1);
  if (c >= 0xDC00 && c <= 0xDFFF && i >= 2) {
    final h = s.codeUnitAt(i - 2);
    if (h >= 0xD800 && h <= 0xDBFF) {
      return 0x10000 + ((h - 0xD800) << 10) + (c - 0xDC00);
    }
  }
  return c;
}

/// The code point starting at code unit [i].
int _cpAt(String s, int i) {
  final c = s.codeUnitAt(i);
  if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
    final l = s.codeUnitAt(i + 1);
    if (l >= 0xDC00 && l <= 0xDFFF) {
      return 0x10000 + ((c - 0xD800) << 10) + (l - 0xDC00);
    }
  }
  return c;
}

/// A space between [a] and [b] is dropped: both CJK, or a Hangul syllable next to an ASCII
/// digit ('3 월', '회의 3분기') — the normalizer folds whitespace to one ' ' between them.
bool _joins(int a, int b) =>
    (_isCjk(a) && _isCjk(b)) ||
    (_isSyllable(a) && _isDigit(b)) ||
    (_isDigit(a) && _isSyllable(b));

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

bool _isSyllable(int c) => c >= 0xAC00 && c <= 0xD7A3;

/// A CJK character (Hangul syllables and jamo, Han with its extensions, kana).
bool _isCjk(int c) =>
    _isSyllable(c) ||
    (c >= 0x1100 && c <= 0x11FF) || // Hangul jamo
    (c >= 0x3130 && c <= 0x318F) || // compatibility jamo
    (c >= 0x3040 && c <= 0x30FF) || // Hiragana, Katakana
    (c >= 0x3400 && c <= 0x4DBF) || // Han extension A
    (c >= 0x4E00 && c <= 0x9FFF) || // Han
    (c >= 0xF900 && c <= 0xFAFF) || // Han compatibility
    (c >= 0x20000 && c <= 0x3134F); // Han extensions B–H (supplementary planes)

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

/// The runs of the compact query (the ink spacing judgement); null for a query without runs,
/// and for one CJK run of ≤ 2 letters (no digit): such a short query would find two
/// unrelated neighbouring words joined ('사과' in '이사 과장').
List<SearchRun>? inkCompactRuns(String queryNorm) {
  final runs = searchRunsOf(cjkCompact(queryNorm));
  if (runs.isEmpty) return null;
  if (runs.length == 1) {
    final r = runs.single;
    if (r.isCjk && r.codePoints <= 2 && !r.text.runes.any(_isDigit)) {
      return null;
    }
  }
  return runs;
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
