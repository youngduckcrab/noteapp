// lib/src/model/page_range.dart — 06-pdf 4.6.
//
// Foundation step B4 (T0): signatures only (except `all`); parsing comes with PDF T1.
import 'package:flutter/foundation.dart';

/// 1-based page range text such as '1-3, 5, 8-'. Resolves to 0-based indices.
@immutable
final class PdfPageRange {
  const PdfPageRange.all();

  /// Throws FormatException (message in Korean) on invalid input or out-of-range pages.
  factory PdfPageRange.parse(String input, {required int pageCount}) =>
      throw UnimplementedError('PdfPageRange.parse (PDF T1)');

  bool get isAll => throw UnimplementedError('PdfPageRange.isAll (PDF T1)');

  /// ascending input order, duplicates removed
  List<int> resolve(int pageCount) =>
      throw UnimplementedError('PdfPageRange.resolve (PDF T1)');

  /// canonical text, e.g. '1-3, 5'
  String format() => throw UnimplementedError('PdfPageRange.format (PDF T1)');
}
