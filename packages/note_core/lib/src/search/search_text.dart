// lib/src/search/search_text.dart — (v2.0) 2nd-round contract 7.2.5 / 02-core 4.6, 6.10.1,
// 6.10.2: SearchText (THE normalizer) and SearchTextMapping.
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../common/pending.dart';

abstract final class SearchText {
  static const int normalizerVersion = 1;

  /// Hangul jamo composition → lowercase → whitespace folding. THE normalizer for titles
  /// (searchLibrary), PDF text, handwriting and text boxes (replaces common/text_normalize.dart's
  /// private copy and must equal pdf_io PdfTextNormalizer on the same input — test in PDF).
  static String normalize(String text) => notYet('T21', 'SearchText.normalize');

  // syllable bigrams for Hangul words, words otherwise
  static String indexTerms(String normalized) =>
      notYet('T21', 'SearchText.indexTerms');

  // FTS5 MATCH text; null → use LIKE fallback
  static String? matchQuery(String normalized) =>
      notYet('T21', 'SearchText.matchQuery');

  /// (v2.1, CP-10) normalize with a map back to source offsets (pdf_io highlight) — the same
  /// result text as normalize(); fields: 02-core 4.6.
  static SearchTextMapping normalizeMapped(String text) =>
      notYet('T21', 'SearchText.normalizeMapped');
}

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
