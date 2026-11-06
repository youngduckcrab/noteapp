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

/// Per code point: bit 1 = run character, bit 2 = CJK character (cached — the regexes run
/// once per distinct code point).
final Map<int, int> _classes = {};

int _classOf(int cp) {
  // Fast paths: ASCII, Hangul syllables.
  if (cp < 0x80) {
    final alnum =
        (cp >= 0x30 && cp <= 0x39) ||
        (cp >= 0x41 && cp <= 0x5A) ||
        (cp >= 0x61 && cp <= 0x7A);
    return alnum ? 1 : 0;
  }
  if (cp >= 0xAC00 && cp <= 0xD7A3) return 3;
  return _classes[cp] ??= () {
    final c = String.fromCharCode(cp);
    return (_run.hasMatch(c) ? 1 : 0) | (_cjk.hasMatch(c) ? 2 : 0);
  }();
}

/// The code point ending just before code unit [index] of [text] and its start.
(int, int) _cpBefore(String text, int index) {
  final c = text.codeUnitAt(index - 1);
  if (c >= 0xDC00 && c <= 0xDFFF && index >= 2) {
    final h = text.codeUnitAt(index - 2);
    if (h >= 0xD800 && h <= 0xDBFF) {
      return (0x10000 + ((h - 0xD800) << 10) + (c - 0xDC00), index - 2);
    }
  }
  return (c, index - 1);
}

/// The code point at code unit [index] of [text] and its length in code units.
(int, int) _cpAt(String text, int index) {
  final c = text.codeUnitAt(index);
  if (c >= 0xD800 && c <= 0xDBFF && index + 1 < text.length) {
    final l = text.codeUnitAt(index + 1);
    if (l >= 0xDC00 && l <= 0xDFFF) {
      return (0x10000 + ((c - 0xD800) << 10) + (l - 0xDC00), 2);
    }
  }
  return (c, 1);
}

/// The maximal run of [text] around the run characters [start, end) (code units): its start,
/// end and whether it holds a CJK character — the run [searchRunsOf] would give there.
({int start, int end, bool cjk}) runAround(String text, int start, int end) {
  var cjk = false;
  for (var i = start; i < end;) {
    final (cp, n) = _cpAt(text, i);
    if (_classOf(cp) & 2 != 0) cjk = true;
    i += n;
  }
  var s = start;
  while (s > 0) {
    final (cp, from) = _cpBefore(text, s);
    final k = _classOf(cp);
    if (k & 1 == 0) break;
    if (k & 2 != 0) cjk = true;
    s = from;
  }
  var e = end;
  while (e < text.length) {
    final (cp, n) = _cpAt(text, e);
    final k = _classOf(cp);
    if (k & 1 == 0) break;
    if (k & 2 != 0) cjk = true;
    e += n;
  }
  return (start: s, end: e, cjk: cjk);
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
