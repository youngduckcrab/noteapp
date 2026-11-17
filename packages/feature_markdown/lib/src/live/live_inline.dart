// Inline looks of the live field (08-markdown 24.5 L-9, 24.17 L′9): `**bold**`, `*italic*`,
// `~~strike~~`, `` `code` ``, `$math$` and `[link](url)` are drawn styled inside the field,
// their markers faded. Display only — the field's text is the source, character for
// character; a miss only draws a run plain.
import 'package:meta/meta.dart';

/// Look flags of one run (a bit set).
abstract final class LiveInline {
  static const int bold = 1;
  static const int italic = 2;
  static const int strike = 4;
  static const int code = 8;
  static const int math = 16;
  static const int link = 32;

  /// A marker (`**`, `` ` ``, `$`, `[`, `](url)`): drawn faded.
  static const int marker = 64;
}

/// Characters [start, end) of a line drawn with [flags].
@immutable
final class LiveInlineRun {
  const LiveInlineRun(this.start, this.end, this.flags);

  final int start;
  final int end;
  final int flags;

  @override
  bool operator ==(Object other) =>
      other is LiveInlineRun &&
      other.start == start &&
      other.end == end &&
      other.flags == flags;

  @override
  int get hashCode => Object.hash(start, end, flags);

  @override
  String toString() => 'LiveInlineRun($start..$end, $flags)';
}

final RegExp _link = RegExp(
  r'!?\[([^\[\]\n]*)\]\(([^()\s]*(?:\s+"[^"\n]*")?)\)',
);
final RegExp _bold = RegExp(r'(\*\*|__)(?=[^\s\x01])(.+?)(?<=[^\s\x01])\1');
final RegExp _strike = RegExp(r'~~(?=[^\s\x01])(.+?)(?<=[^\s\x01])~~');
final RegExp _italicStar = RegExp(
  r'(?<![*\w])\*(?=[^\s*\x01])(.+?)(?<=[^\s*])\*(?!\*)',
);
final RegExp _italicUnder = RegExp(
  r'(?<![\w_])_(?=[^\s_\x01])(.+?)(?<=[^\s_])_(?![\w_])',
);

final Map<String, List<LiveInlineRun>> _cache = {};

/// The styled runs of one source [line] (characters not in a run are plain).
List<LiveInlineRun> liveInlineRuns(String line) {
  if (line.isEmpty) return const [];
  final hit = _cache[line];
  if (hit != null) return hit;
  final runs = _scan(line);
  if (_cache.length > 400) _cache.clear();
  _cache[line] = runs;
  return runs;
}

List<LiveInlineRun> _scan(String line) {
  final n = line.length;
  final flags = List<int>.filled(n, 0);
  // Characters no later rule may use (escapes, code, math, link targets).
  final taken = List<bool>.filled(n, false);
  void mark(int from, int to, int f, {bool take = true}) {
    for (var i = from; i < to && i < n; i++) {
      flags[i] |= f;
      if (take) taken[i] = true;
    }
  }

  bool free(int from, int to) {
    for (var i = from; i < to; i++) {
      if (taken[i]) return false;
    }
    return true;
  }

  // Escapes: `\*` is a literal star.
  for (var i = 0; i + 1 < n; i++) {
    if (line.codeUnitAt(i) == 0x5C) {
      taken[i] = true;
      taken[i + 1] = true;
      i++;
    }
  }
  // Code spans: a run of k backticks up to the next run of exactly k.
  var i = 0;
  while (i < n) {
    if (line.codeUnitAt(i) != 0x60 || taken[i]) {
      i++;
      continue;
    }
    var k = i;
    while (k < n && line.codeUnitAt(k) == 0x60) {
      k++;
    }
    final len = k - i;
    var j = k;
    var close = -1;
    while (j < n) {
      if (line.codeUnitAt(j) == 0x60) {
        var e = j;
        while (e < n && line.codeUnitAt(e) == 0x60) {
          e++;
        }
        if (e - j == len) {
          close = j;
          break;
        }
        j = e;
      } else {
        j++;
      }
    }
    if (close < 0) {
      i = k;
      continue;
    }
    mark(i, k, LiveInline.marker);
    mark(k, close, LiveInline.code);
    mark(close, close + len, LiveInline.marker);
    i = close + len;
  }
  // Inline math: `$…$` (not `$$`, no space inside the dollars, no digit after).
  i = 0;
  while (i < n) {
    if (line.codeUnitAt(i) != 0x24 ||
        taken[i] ||
        (i + 1 < n && line.codeUnitAt(i + 1) == 0x24) ||
        i + 1 >= n ||
        line[i + 1].trim().isEmpty) {
      i++;
      continue;
    }
    var j = i + 1;
    var close = -1;
    while (j < n) {
      if (taken[j]) break;
      if (line.codeUnitAt(j) == 0x24) {
        final spaceBefore = line[j - 1].trim().isEmpty;
        final digitAfter =
            j + 1 < n &&
            line.codeUnitAt(j + 1) >= 0x30 &&
            line.codeUnitAt(j + 1) <= 0x39;
        if (!spaceBefore && !digitAfter) close = j;
        break;
      }
      j++;
    }
    if (close < 0) {
      i++;
      continue;
    }
    mark(i, i + 1, LiveInline.marker);
    mark(i + 1, close, LiveInline.math);
    mark(close, close + 1, LiveInline.marker);
    i = close + 1;
  }
  // Links and images: `[` and `](url)` faded, the text drawn as a link.
  for (final m in _link.allMatches(line)) {
    if (!free(m.start, m.end)) continue;
    final textStart = line.indexOf('[', m.start) + 1;
    final textEnd = textStart + m.group(1)!.length;
    mark(m.start, textStart, LiveInline.marker);
    mark(textStart, textEnd, LiveInline.link, take: false);
    mark(textEnd, m.end, LiveInline.marker);
  }
  // Emphasis on what is left (taken characters masked out).
  var masked = String.fromCharCodes([
    for (var c = 0; c < n; c++) taken[c] ? 0x01 : line.codeUnitAt(c),
  ]);
  void emphasis(RegExp re, int f, int markerLen) {
    for (final m in re.allMatches(masked)) {
      final ml = markerLen < 0 ? m.group(1)!.length : markerLen;
      mark(m.start, m.start + ml, LiveInline.marker);
      mark(m.start + ml, m.end - ml, f, take: false);
      mark(m.end - ml, m.end, LiveInline.marker);
    }
    // Used markers mask out, so `***x***` is bold and italic.
    masked = String.fromCharCodes([
      for (var c = 0; c < n; c++) taken[c] ? 0x01 : masked.codeUnitAt(c),
    ]);
  }

  emphasis(_bold, LiveInline.bold, -1);
  emphasis(_strike, LiveInline.strike, 2);
  emphasis(_italicStar, LiveInline.italic, 1);
  emphasis(_italicUnder, LiveInline.italic, 1);

  final runs = <LiveInlineRun>[];
  var s = 0;
  while (s < n) {
    var e = s + 1;
    while (e < n && flags[e] == flags[s]) {
      e++;
    }
    if (flags[s] != 0) runs.add(LiveInlineRun(s, e, flags[s]));
    s = e;
  }
  return runs;
}
