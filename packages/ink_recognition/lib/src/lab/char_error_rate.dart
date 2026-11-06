// lib/src/lab/char_error_rate.dart — (internal) the A-4 lab's character
// error rate (m5-7/05-library 6.20): both strings through CORE's
// SearchText.normalize (conjoining jamo → syllables, lowercase, whitespace
// folded), then every space removed; the code point Levenshtein distance
// over the target's length. A group's rate is the sum of distances over the
// sum of lengths (not the mean of the sentences' rates).
import 'package:note_core/note_core.dart' as core;

/// The code points the rate compares: normalized, without spaces.
List<int> cerCodePoints(String text) => [
  for (final r in core.SearchText.normalize(text).runes)
    if (r != 0x20) r,
];

/// The code point edit distance (insert, delete, substitute — 1 each).
int codePointDistance(List<int> a, List<int> b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var previous = List<int>.generate(b.length + 1, (j) => j);
  var current = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final substitute = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      final delete = previous[j] + 1;
      final insert = current[j - 1] + 1;
      var best = substitute < delete ? substitute : delete;
      if (insert < best) best = insert;
      current[j] = best;
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}

/// (distance, target length) of [hypothesis] against [target].
({int distance, int length}) charErrorCounts(String target, String hypothesis) {
  final t = cerCodePoints(target);
  final h = cerCodePoints(hypothesis);
  return (distance: codePointDistance(t, h), length: t.length);
}

/// distance ÷ target length. An empty target: 0 when the hypothesis is
/// empty too, else 1.
double charErrorRate(String target, String hypothesis) {
  final c = charErrorCounts(target, hypothesis);
  if (c.length == 0) return c.distance == 0 ? 0 : 1;
  return c.distance / c.length;
}
