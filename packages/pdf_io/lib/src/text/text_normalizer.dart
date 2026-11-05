// lib/src/text/text_normalizer.dart — 06-pdf 4.8, 6.10.1.
//
// Foundation step B4 (T0): signatures only; normalization comes with PDF T11.
import 'package:flutter/foundation.dart';

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
      throw UnimplementedError('PdfTextNormalizer.normalize (PDF T11)');

  static String normalizeQuery(String query) =>
      throw UnimplementedError('PdfTextNormalizer.normalizeQuery (PDF T11)');
}
