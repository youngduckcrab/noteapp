// lib/src/model/page_range.dart — 06-pdf 4.6.
import 'package:flutter/foundation.dart';

/// 1-based page range text such as '1-3, 5, 8-'. Resolves to 0-based indices.
@immutable
final class PdfPageRange {
  const PdfPageRange.all() : _segments = null;

  const PdfPageRange._(this._segments);

  /// Throws FormatException (message in Korean) on invalid input or out-of-range pages.
  ///
  /// Parts are separated by ','. A part is 'n', 'n-m' or 'n-' (to the last page); '–' and
  /// '~' are accepted for '-'. Empty parts are skipped; an input without any part throws.
  factory PdfPageRange.parse(String input, {required int pageCount}) {
    final segments = <_Segment>[];
    for (final raw in input.split(_separator)) {
      final part = raw.trim();
      if (part.isEmpty) continue;
      segments.add(_parsePart(part, pageCount));
    }
    if (segments.isEmpty) {
      throw const FormatException('페이지 범위를 입력해 주세요. 예: 1-3, 5, 8-');
    }
    return PdfPageRange._(List.unmodifiable(_normalize(segments)));
  }

  static final RegExp _separator = RegExp('[,，、]');
  static final RegExp _single = RegExp(r'^(\d+)$');
  static final RegExp _span = RegExp(r'^(\d+)\s*[-–~]\s*(\d+)?$');

  static _Segment _parsePart(String part, int pageCount) {
    final single = _single.firstMatch(part);
    if (single != null) {
      final page = _page(single.group(1)!, part, pageCount);
      return _Segment(page, page);
    }
    final span = _span.firstMatch(part);
    if (span == null) {
      throw FormatException("'$part'은 페이지 범위로 읽을 수 없어요. 예: 1-3, 5, 8-");
    }
    final start = _page(span.group(1)!, part, pageCount);
    final endText = span.group(2);
    if (endText == null) return _Segment(start, null);
    final end = _page(endText, part, pageCount);
    if (end < start) {
      throw FormatException("'$part'은 시작 쪽이 끝 쪽보다 커요.");
    }
    return _Segment(start, end);
  }

  static int _page(String digits, String part, int pageCount) {
    // Long digit strings would not fit a web-safe int: they are out of range anyway.
    final page = digits.length > 9 ? null : int.tryParse(digits);
    if (page == null || page < 1 || page > pageCount) {
      throw FormatException(
        pageCount < 1
            ? "'$part'쪽이 없어요. 이 PDF에는 페이지가 없어요."
            : "'$part'쪽이 없어요. 1–$pageCount쪽 중에서 골라 주세요.",
      );
    }
    return page;
  }

  /// Sorted by start, overlapping / adjacent parts merged; an open part absorbs the rest.
  static List<_Segment> _normalize(List<_Segment> segments) {
    final sorted = [...segments]..sort((a, b) => a.start.compareTo(b.start));
    final out = <_Segment>[];
    for (final s in sorted) {
      if (out.isEmpty) {
        out.add(s);
        continue;
      }
      final last = out.last;
      final lastEnd = last.end;
      // An open part already covers everything after it.
      if (lastEnd == null) break;
      if (s.start > lastEnd + 1) {
        out.add(s);
        continue;
      }
      final end = s.end;
      out[out.length - 1] = _Segment(
        last.start,
        end == null ? null : (end > lastEnd ? end : lastEnd),
      );
    }
    return out;
  }

  /// null = all pages.
  final List<_Segment>? _segments;

  /// The whole document: PdfPageRange.all() or a parsed range that normalizes to '1-'.
  bool get isAll {
    final segments = _segments;
    if (segments == null) return true;
    return segments.length == 1 &&
        segments.single.start == 1 &&
        segments.single.end == null;
  }

  /// ascending input order, duplicates removed
  ///
  /// 0-based indices in ascending page order. Pages past [pageCount] are left out.
  List<int> resolve(int pageCount) {
    final segments = _segments;
    if (segments == null) return List<int>.generate(pageCount, (i) => i);
    final out = <int>[];
    for (final s in segments) {
      final end = s.end;
      final last = end == null || end > pageCount ? pageCount : end;
      for (var page = s.start; page <= last; page++) {
        out.add(page - 1);
      }
    }
    return out;
  }

  /// canonical text, e.g. '1-3, 5'
  ///
  /// PdfPageRange.all() → '1-'.
  String format() {
    final segments = _segments ?? const [_Segment(1, null)];
    return segments.map((s) => s.format()).join(', ');
  }

  /// Same canonical text ('1-3, 5' == '5, 1-2, 3'; all() == '1-').
  @override
  bool operator ==(Object other) =>
      other is PdfPageRange && other.format() == format();

  @override
  int get hashCode => format().hashCode;

  @override
  String toString() => 'PdfPageRange(${format()})';
}

@immutable
final class _Segment {
  const _Segment(this.start, this.end);
  final int start; // 1-based
  final int? end; // 1-based, inclusive; null = to the last page

  String format() {
    final end = this.end;
    if (end == null) return '$start-';
    if (end == start) return '$start';
    return '$start-$end';
  }
}
