// lib/src/viewport/page_layout.dart — 04-editor 6.3.2.
//
// Pages laid out one after another along the main axis (vertical scroll or
// horizontal paged mode), centred on the cross axis. All values are in doc
// coordinates (pt, 6.2). Lookups binary-search the page starts.
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'viewport_constants.dart';

enum LayoutAxis { vertical, horizontal }

@immutable
class PageLayout {
  const PageLayout._({
    required this.axis,
    required this.pageRects,
    required this.contentSize,
    required this.crossExtent,
  });

  /// O(n). [pageSizes] in pt, in display order.
  factory PageLayout.compute({
    required List<Size> pageSizes,
    required LayoutAxis axis,
    double pageGap = ViewportConstants.pageGap,
    double leadingPadding = ViewportConstants.leadingPadding,
    double trailingPadding = ViewportConstants.trailingPadding,
  }) {
    final vertical = axis == LayoutAxis.vertical;
    double mainOf(Size s) => vertical ? s.height : s.width;
    double crossOf(Size s) => vertical ? s.width : s.height;

    var crossExtent = 0.0;
    for (final s in pageSizes) {
      crossExtent = math.max(crossExtent, crossOf(s));
    }
    final rects = <Rect>[];
    var main = leadingPadding;
    for (final s in pageSizes) {
      final cross = (crossExtent - crossOf(s)) / 2;
      rects.add(
        vertical
            ? Rect.fromLTWH(cross, main, s.width, s.height)
            : Rect.fromLTWH(main, cross, s.width, s.height),
      );
      main += mainOf(s) + pageGap;
    }
    // No pages: just the paddings (the "+ page" room stays reachable).
    final mainExtent = rects.isEmpty
        ? leadingPadding + trailingPadding
        : main - pageGap + trailingPadding;
    return PageLayout._(
      axis: axis,
      pageRects: List.unmodifiable(rects),
      contentSize: vertical
          ? Size(crossExtent, mainExtent)
          : Size(mainExtent, crossExtent),
      crossExtent: crossExtent,
    );
  }

  final LayoutAxis axis;
  final List<Rect> pageRects; // doc coordinates
  final Size contentSize;
  final double crossExtent; // max page width (vertical) / height (horizontal)

  int get length => pageRects.length;
  Rect rectOf(int index) => pageRects[index];

  bool get _vertical => axis == LayoutAxis.vertical;
  double _start(Rect r) => _vertical ? r.top : r.left;
  double _end(Rect r) => _vertical ? r.bottom : r.right;
  double _main(Offset p) => _vertical ? p.dy : p.dx;

  /// Last index whose start ≤ [value], or -1 when every page starts after it.
  int _lastStartingAtOrBefore(double value) {
    var lo = 0;
    var hi = pageRects.length - 1;
    var found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (_start(pageRects[mid]) <= value) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  /// First index whose end ≥ [value], or length when every page ends before.
  int _firstEndingAtOrAfter(double value) {
    var lo = 0;
    var hi = pageRects.length - 1;
    var found = pageRects.length;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (_end(pageRects[mid]) >= value) {
        found = mid;
        hi = mid - 1;
      } else {
        lo = mid + 1;
      }
    }
    return found;
  }

  /// Page containing [docPoint] (edges included), or null (gap / outside).
  /// O(log n).
  int? pageIndexAt(Offset docPoint) {
    final i = _lastStartingAtOrBefore(_main(docPoint));
    if (i < 0) return null;
    final r = pageRects[i];
    final inside =
        docPoint.dx >= r.left &&
        docPoint.dx <= r.right &&
        docPoint.dy >= r.top &&
        docPoint.dy <= r.bottom;
    return inside ? i : null;
  }

  /// Nearest page along the main axis (a point in a gap goes to the closer
  /// neighbour, the earlier one on a tie). O(log n). Requires length > 0.
  int nearestPageIndex(Offset docPoint) {
    if (pageRects.isEmpty) {
      throw StateError('nearestPageIndex needs at least one page');
    }
    final v = _main(docPoint);
    final i = _lastStartingAtOrBefore(v);
    if (i < 0) return 0;
    if (v <= _end(pageRects[i]) || i == pageRects.length - 1) return i;
    final toPrevious = v - _end(pageRects[i]);
    final toNext = _start(pageRects[i + 1]) - v;
    return toNext < toPrevious ? i + 1 : i;
  }

  /// Inclusive index range of pages whose main-axis span meets [docRect]'s
  /// (touching counts), or null. O(log n).
  ({int first, int last})? rangeIntersecting(Rect docRect) {
    if (pageRects.isEmpty) return null;
    final from = _vertical ? docRect.top : docRect.left;
    final to = _vertical ? docRect.bottom : docRect.right;
    final first = _firstEndingAtOrAfter(from);
    final last = _lastStartingAtOrBefore(to);
    if (first > last) return null;
    return (first: first, last: last);
  }

  static const _rects = ListEquality<Rect>();

  @override
  bool operator ==(Object other) =>
      other is PageLayout &&
      other.axis == axis &&
      other.contentSize == contentSize &&
      other.crossExtent == crossExtent &&
      _rects.equals(other.pageRects, pageRects);

  @override
  int get hashCode =>
      Object.hash(axis, contentSize, crossExtent, _rects.hash(pageRects));

  @override
  String toString() =>
      'PageLayout(${axis.name}, ${pageRects.length} pages, $contentSize)';
}
