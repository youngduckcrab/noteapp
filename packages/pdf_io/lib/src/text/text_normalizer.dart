// lib/src/text/text_normalizer.dart — 06-pdf 4.8, 6.10.1 (PDF T11); (2차) m5-7/06-pdf 6.4.5
// (T28, CP-10): the steps are CORE's SearchText.normalizeMapped — one normalizer for titles,
// PDF text, handwriting and text boxes (contract 7.2.5). The 1차 copy (normalizePdfText,
// hangul_jamo.dart) is gone.
import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

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
  // (2차, T28) Delegates to core.SearchText.normalizeMapped (CORE 6.10.1, the 1차 steps plus
  // the trim and İ → 'i' on every platform), so text == core.SearchText.normalize(raw).
  static PdfNormalizedText normalize(String raw) {
    final m = core.SearchText.normalizeMapped(raw);
    return PdfNormalizedText(
      text: m.text,
      sourceStart: m.sourceStart,
      sourceEnd: m.sourceEnd,
    );
  }

  static String normalizeQuery(String query) =>
      core.SearchText.normalize(query);
}

/// Internal (not exported): [raw] normalized like [PdfTextNormalizer.normalize] but in the
/// original case — the search snippet (6.10.2 step 5). Every group of normalized code units
/// that came from one source character (lower-casing, step 5) is that character again; a
/// whitespace run stays ' ' and a composed syllable stays composed. The table has the same
/// shape as [PdfNormalizedText] (one source range per code unit of the result).
PdfNormalizedText normalizeKeepingCase(String raw) {
  final m = core.SearchText.normalizeMapped(raw);
  final out = StringBuffer();
  final starts = <int>[];
  final ends = <int>[];
  final n = m.text.length;
  var i = 0;
  while (i < n) {
    final s = m.sourceStart[i];
    final e = m.sourceEnd[i];
    var j = i + 1;
    while (j < n && m.sourceStart[j] == s && m.sourceEnd[j] == e) {
      j++;
    }
    final group = m.text.substring(i, j);
    final oneCharacter =
        e - s == 1 ||
        (e - s == 2 &&
            _isHighSurrogate(raw.codeUnitAt(s)) &&
            _isLowSurrogate(raw.codeUnitAt(s + 1)));
    final kept = group != ' ' && oneCharacter ? raw.substring(s, e) : group;
    for (var k = 0; k < kept.length; k++) {
      out.writeCharCode(kept.codeUnitAt(k));
      starts.add(s);
      ends.add(e);
    }
    i = j;
  }
  return PdfNormalizedText(
    text: out.toString(),
    sourceStart: Int32List.fromList(starts),
    sourceEnd: Int32List.fromList(ends),
  );
}

/// Internal (not exported, 1차 4.15): step 4 of 6.10.1 only — Hangul conjoining jamo
/// (L + V [+ T], LV syllable + T) composed, other text unchanged (no lower-casing, no
/// whitespace change). Note titles (6.3) and the import sheet's file name use it.
abstract final class HangulJamo {
  /// Runs of Hangul jamo (U+1100..U+11FF) and syllables (U+AC00..U+D7A3): characters without
  /// case, whitespace, hyphens or dropped characters, so CORE's normalize only composes them.
  static final RegExp _hangulRun = RegExp('[\u1100-\u11FF\uAC00-\uD7A3]+');

  static bool _isJamo(int c) => c >= 0x1100 && c <= 0x11FF;

  static String compose(String text) {
    if (!text.codeUnits.any(_isJamo)) return text;
    return text.replaceAllMapped(
      _hangulRun,
      (match) => core.SearchText.normalize(match[0]!),
    );
  }
}

bool _isHighSurrogate(int c) => c >= 0xD800 && c <= 0xDBFF;
bool _isLowSurrogate(int c) => c >= 0xDC00 && c <= 0xDFFF;
