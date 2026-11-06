// Internal (not exported) — the run ('낱말') rules of m5-7/02-core 6.10.2, shared by SearchText,
// the match judgement, the FTS candidate model, the ranking and the indexes (real and fake).

/// A maximal run of `[\p{L}\p{N}\p{Co}]` in normalized text — the token characters of FTS5
/// unicode61 (categories L*, N*, Co). Everything else separates runs.
final RegExp _run = RegExp(r'[\p{L}\p{N}\p{Co}]+', unicode: true);

/// A Hangul, Han, Hiragana or Katakana character.
final RegExp _cjk = RegExp(
  r'[\p{Script=Hangul}\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}]',
  unicode: true,
);

/// One run of a normalized text.
final class SearchRun {
  SearchRun(this.text, this.start)
    : isCjk = _cjk.hasMatch(text),
      codePoints = text.runes.length;

  /// The run itself.
  final String text;

  /// Its start (UTF-16 code unit index) in the text it came from.
  final int start;

  /// It holds at least one Hangul / Han / Hiragana / Katakana character.
  final bool isCjk;

  /// Its length in code points.
  final int codePoints;
}

/// The runs of [normalized], in order.
List<SearchRun> searchRunsOf(String normalized) => [
  for (final m in _run.allMatches(normalized)) SearchRun(m[0]!, m.start),
];

/// Overlapping code point bigrams ('회의록을' → ['회의', '의록', '록을']); a one-code-point
/// string is returned as it is.
List<String> codePointBigrams(String run) {
  final cps = run.runes.toList();
  if (cps.length < 2) return [run];
  return [
    for (var i = 0; i + 1 < cps.length; i++)
      String.fromCharCodes([cps[i], cps[i + 1]]),
  ];
}

/// Whether the code point ending just before code unit [index] of [text] is a run character
/// (false at the start of the text).
bool runCharBefore(String text, int index) {
  if (index <= 0) return false;
  var from = index - 1;
  final c = text.codeUnitAt(from);
  if (c >= 0xDC00 && c <= 0xDFFF && from > 0) {
    final h = text.codeUnitAt(from - 1);
    if (h >= 0xD800 && h <= 0xDBFF) from--;
  }
  return _run.matchAsPrefix(text.substring(from, index)) != null;
}
