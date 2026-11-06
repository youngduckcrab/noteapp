// lib/src/search/search_text.dart — (v2.0) 2nd-round contract 7.2.5 / 02-core 4.6, 6.10.1,
// 6.10.2: SearchText (THE normalizer) and SearchTextMapping.
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'search_runs.dart';

abstract final class SearchText {
  static const int normalizerVersion = 1;

  /// Hangul jamo composition → lowercase → whitespace folding. THE normalizer for titles
  /// (searchLibrary), PDF text, handwriting and text boxes (replaces common/text_normalize.dart's
  /// private copy and must equal pdf_io PdfTextNormalizer on the same input — test in PDF).
  ///
  /// CORE 6.10.1 steps, one pass over the code units (pdf_io's 1차 PdfTextNormalizer steps,
  /// then trimmed like its normalizeQuery):
  ///   1. letter/digit + '-' + (\r?\n) + letter/digit → the '-' and the line break are dropped;
  ///   2. U+00AD, U+200B..U+200D, U+FEFF are dropped;
  ///   3. a whitespace run (Dart / JavaScript \s as a fixed code unit list, U+00A0 and U+3000
  ///      included, dropped characters inside it too) → one ' ';
  ///   4. conjoining jamo (L + V [+ T], LV syllable + T) → the precomposed syllable;
  ///   5. lowercase per code point (no context rule — the web's final sigma does not apply);
  ///      U+0130 (İ) → 'i' on every platform (the web's full mapping would add U+0307);
  ///   6. leading / trailing ' ' removed.
  static String normalize(String text) => _normalize(text, mapped: false).text;

  // syllable bigrams for Hangul words, words otherwise
  /// (CORE 6.10.2) For every run of [normalized]: a CJK run → its overlapping code point bigrams
  /// ('회의록을' → '회의 의록 록을'; a one-character run as it is), another run as it is; joined
  /// with ' ' (the FTS `g` column).
  static String indexTerms(String normalized) => [
    for (final r in searchRunsOf(normalized))
      if (r.isCjk) ...codePointBigrams(r.text) else r.text,
  ].join(' ');

  // FTS5 MATCH text; null → use LIKE fallback
  /// (CORE 6.10.2) Only the runs of two or more code points: a CJK run → a bigram phrase
  /// (`"방정 정식"`), another run → a prefix (`"meet"*`), joined with ' AND '. Each item is quoted
  /// with inner '"' doubled. null when there is no such run.
  static String? matchQuery(String normalized) {
    final items = [
      for (final r in searchRunsOf(normalized))
        if (r.codePoints >= 2)
          r.isCjk
              ? _quote(codePointBigrams(r.text).join(' '))
              : '${_quote(r.text)}*',
    ];
    return items.isEmpty ? null : items.join(' AND ');
  }

  /// (v2.1, CP-10) normalize with a map back to source offsets (pdf_io highlight) — the same
  /// result text as normalize(); fields: 02-core 4.6.
  static SearchTextMapping normalizeMapped(String text) =>
      _normalize(text, mapped: true);
}

String _quote(String s) => '"${s.replaceAll('"', '""')}"';

// lib/src/search/search_text.dart — fields of SearchText.normalizeMapped (contract: 'fields: 02-core 4.6')
@immutable
final class SearchTextMapping {
  const SearchTextMapping({
    required this.text,
    required this.sourceStart,
    required this.sourceEnd,
  });
  final String text; // == SearchText.normalize(source), always
  /// For normalized code unit i: the source range [sourceStart[i], sourceEnd[i]) in the input
  /// (same shape as pdf_io's 1차 PdfNormalizedText — PDF's normalize can wrap this one).
  final Int32List sourceStart, sourceEnd;

  // ==, hashCode (text and both lists)
  @override
  bool operator ==(Object other) =>
      other is SearchTextMapping &&
      other.text == text &&
      const ListEquality<int>().equals(other.sourceStart, sourceStart) &&
      const ListEquality<int>().equals(other.sourceEnd, sourceEnd);

  @override
  int get hashCode => Object.hash(
    text,
    const ListEquality<int>().hash(sourceStart),
    const ListEquality<int>().hash(sourceEnd),
  );

  @override
  String toString() => 'SearchTextMapping("$text")';
}

final Int32List _noOffsets = Int32List(0);

SearchTextMapping _normalize(String raw, {required bool mapped}) {
  final n = raw.length;
  final out = StringBuffer();
  final starts = mapped ? <int>[] : null;
  final ends = mapped ? <int>[] : null;
  void emit(int unit, int start, int end) {
    out.writeCharCode(unit);
    starts?.add(start);
    ends?.add(end);
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
      emit(0x20, i, j);
      i = j;
      continue;
    }
    // 4. Hangul jamo composition (syllables have no case)
    final syllable = _syllableAt(raw, i);
    if (syllable != null) {
      emit(syllable.syllable, i, i + syllable.length);
      i += syllable.length;
      continue;
    }
    // 5. lower-casing, one code point at a time
    final pair =
        _isHighSurrogate(c) &&
        i + 1 < n &&
        _isLowSurrogate(raw.codeUnitAt(i + 1));
    final width = pair ? 2 : 1;
    if (c < 0x80) {
      emit(c >= 0x41 && c <= 0x5A ? c + 0x20 : c, i, i + 1);
    } else if (c == 0x130) {
      emit(0x69, i, i + 1);
    } else {
      final lower = raw.substring(i, i + width).toLowerCase();
      for (var k = 0; k < lower.length; k++) {
        emit(lower.codeUnitAt(k), i, i + width);
      }
    }
    i += width;
  }
  // 6. trim: step 3 leaves at most one ' ' at each end.
  var text = out.toString();
  var from = 0, to = text.length;
  if (to > 0 && text.codeUnitAt(0) == 0x20) from = 1;
  if (to > from && text.codeUnitAt(to - 1) == 0x20) to--;
  if (from != 0 || to != text.length) text = text.substring(from, to);
  if (!mapped) {
    return SearchTextMapping(
      text: text,
      sourceStart: _noOffsets,
      sourceEnd: _noOffsets,
    );
  }
  return SearchTextMapping(
    text: text,
    sourceStart: Int32List.fromList(starts!.sublist(from, to)),
    sourceEnd: Int32List.fromList(ends!.sublist(from, to)),
  );
}

/// [raw] has '-' at [i]: the index after '-' + (\r?\n) when it joins two word characters
/// (step 1), else null.
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

/// \s of Dart / JavaScript regular expressions as a fixed list (U+00A0, U+3000, \r, \n, \t
/// included) — the same set on every platform.
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

const int _sBase = 0xAC00, _sCount = 11172;
const int _lBase = 0x1100, _lCount = 19; // U+1100..U+1112
const int _vBase = 0x1161, _vCount = 21; // U+1161..U+1175
const int _tBase = 0x11A7, _tCount = 28; // T: U+11A8..U+11C2 (index 0 = none)

bool _isL(int c) => c >= _lBase && c < _lBase + _lCount;
bool _isV(int c) => c >= _vBase && c < _vBase + _vCount;
bool _isT(int c) => c > _tBase && c < _tBase + _tCount;
bool _isLV(int c) =>
    c >= _sBase && c < _sBase + _sCount && (c - _sBase) % _tCount == 0;

/// The syllable composed from the jamo sequence at code unit [index] (L + V [+ T], or LV
/// syllable + T) and its length in code units; null when none starts there (step 4).
({int syllable, int length})? _syllableAt(String text, int index) {
  final n = text.length;
  final c = text.codeUnitAt(index);
  if (_isL(c) && index + 1 < n && _isV(text.codeUnitAt(index + 1))) {
    var syllable =
        _sBase +
        ((c - _lBase) * _vCount + (text.codeUnitAt(index + 1) - _vBase)) *
            _tCount;
    var length = 2;
    if (index + 2 < n && _isT(text.codeUnitAt(index + 2))) {
      syllable += text.codeUnitAt(index + 2) - _tBase;
      length = 3;
    }
    return (syllable: syllable, length: length);
  }
  if (_isLV(c) && index + 1 < n && _isT(text.codeUnitAt(index + 1))) {
    return (syllable: c + text.codeUnitAt(index + 1) - _tBase, length: 2);
  }
  return null;
}
