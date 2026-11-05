// lib/src/text/text_normalizer.dart — 06-pdf 4.8, 6.10.1 (PDF T11).
import 'package:flutter/foundation.dart';

import 'hangul_jamo.dart';

@immutable
final class PdfNormalizedText {
  const PdfNormalizedText({
    required this.text,
    required this.sourceStart,
    required this.sourceEnd,
  });
  final String text;

  /// For normalized code unit i: source range [sourceStart[i], sourceEnd[i]) in the raw text.
  final Int32List sourceStart;
  final Int32List sourceEnd;
}

abstract final class PdfTextNormalizer {
  /// Steps in 6.10.1 (end-of-line hyphenation join, soft hyphen/ZW removal, whitespace collapse,
  /// Hangul jamo composition, lower-casing).
  static PdfNormalizedText normalize(String raw) =>
      normalizePdfText(raw, lowerCase: true);

  static String normalizeQuery(String query) =>
      normalizePdfText(query, lowerCase: true).text.trim();
}

/// Internal (not exported): 6.10.1 steps 1–4, and step 5 when [lowerCase]. The search
/// snippet (6.10.2 step 5) uses steps 1–4 only, so it keeps the original case.
///
/// One pass over the code units of [raw]:
///   1. letter/digit + '-' + (\r?\n) + letter/digit → the '-' and the line break are dropped,
///   2. U+00AD, U+200B..U+200D, U+FEFF are dropped,
///   3. a whitespace run (dropped characters inside it included) → one ' ' whose source
///      range is the whole run; leading / trailing whitespace is kept,
///   4. conjoining jamo (HangulJamo.syllableAt) → one syllable whose source range is every
///      jamo it was composed from,
///   5. toLowerCase per character; when that changes the length, every resulting code unit
///      maps to the one source character.
PdfNormalizedText normalizePdfText(String raw, {required bool lowerCase}) {
  final n = raw.length;
  final out = StringBuffer();
  final starts = <int>[];
  final ends = <int>[];
  void emitUnit(int unit, int start, int end) {
    out.writeCharCode(unit);
    starts.add(start);
    ends.add(end);
  }

  var i = 0;
  while (i < n) {
    final c = raw.codeUnitAt(i);
    // 1. end-of-line hyphenation
    if (c == 0x2D) {
      final next = _hyphenJoinEnd(raw, i);
      if (next != null) {
        i = next;
        continue;
      }
    }
    // 2. dropped characters
    if (_isDropped(c)) {
      i++;
      continue;
    }
    // 3. whitespace runs
    if (_isSpace(c)) {
      var j = i + 1;
      while (j < n) {
        final d = raw.codeUnitAt(j);
        if (!_isSpace(d) && !_isDropped(d)) break;
        j++;
      }
      emitUnit(0x20, i, j);
      i = j;
      continue;
    }
    // 4. Hangul jamo composition (syllables have no case)
    final syllable = HangulJamo.syllableAt(raw, i);
    if (syllable != null) {
      emitUnit(syllable.syllable, i, i + syllable.length);
      i += syllable.length;
      continue;
    }
    // 5. lower-casing, one character (code point) at a time
    final pair =
        _isHighSurrogate(c) &&
        i + 1 < n &&
        _isLowSurrogate(raw.codeUnitAt(i + 1));
    final width = pair ? 2 : 1;
    if (!lowerCase || (c < 0x80 && (c < 0x41 || c > 0x5A))) {
      for (var k = 0; k < width; k++) {
        emitUnit(raw.codeUnitAt(i + k), i, i + width);
      }
    } else if (c >= 0x41 && c <= 0x5A) {
      emitUnit(c + 0x20, i, i + 1);
    } else {
      final lower = raw.substring(i, i + width).toLowerCase();
      for (var k = 0; k < lower.length; k++) {
        emitUnit(lower.codeUnitAt(k), i, i + width);
      }
    }
    i += width;
  }
  return PdfNormalizedText(
    text: out.toString(),
    sourceStart: Int32List.fromList(starts),
    sourceEnd: Int32List.fromList(ends),
  );
}

/// [raw] has '-' at [i]: the index after '-' + (\r?\n) when it joins two word characters
/// (6.10.1 step 1), else null.
int? _hyphenJoinEnd(String raw, int i) {
  if (i == 0 || !_isWordUnit(raw.codeUnitAt(i - 1))) return null;
  var j = i + 1;
  if (j < raw.length && raw.codeUnitAt(j) == 0x0D) j++;
  if (j >= raw.length || raw.codeUnitAt(j) != 0x0A) return null;
  j++;
  if (j >= raw.length || !_isWordUnit(raw.codeUnitAt(j))) return null;
  return j;
}

final RegExp _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// A letter or digit (surrogates — the halves of a supplementary character — count as one).
bool _isWordUnit(int c) {
  if (c < 0x80) {
    return (c >= 0x30 && c <= 0x39) ||
        (c >= 0x41 && c <= 0x5A) ||
        (c >= 0x61 && c <= 0x7A);
  }
  if (_isHighSurrogate(c) || _isLowSurrogate(c)) return true;
  return _wordChar.hasMatch(String.fromCharCode(c));
}

bool _isDropped(int c) =>
    c == 0x00AD || (c >= 0x200B && c <= 0x200D) || c == 0xFEFF;

/// \s of Dart / JavaScript regular expressions (U+00A0, U+3000, \r, \n, \t included).
bool _isSpace(int c) =>
    c == 0x20 ||
    (c >= 0x09 && c <= 0x0D) ||
    c == 0x85 ||
    c == 0xA0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000;

bool _isHighSurrogate(int c) => c >= 0xD800 && c <= 0xDBFF;
bool _isLowSurrogate(int c) => c >= 0xDC00 && c <= 0xDFFF;
