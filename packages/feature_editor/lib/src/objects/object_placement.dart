// lib/src/objects/object_placement.dart — m5-7/04-editor 6.12.2 step 3 (where
// an inserted image goes), 6.13.2 (EditorInsertContext.visibleRectPt), 6.12.3
// (the size of an image page).
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:note_core/note_core.dart' as core;

import '../viewport/viewport_controller.dart';

abstract final class ObjectPlacement {
  /// Share of the image's pixel width, of the visible width and of the page
  /// width an inserted image may take (6.12.2 step 3).
  static const double pixelShare = 0.5;
  static const double visibleShare = 0.6;
  static const double pageShare = 0.8;

  /// An image page keeps the current orientation when the image's
  /// width / height is in [squareMin, squareMax] (6.12.3).
  static const double squareMin = 0.9;
  static const double squareMax = 1.1;

  /// The part of page [index] the viewport shows, in that page's pt — the
  /// whole page when none of it is on screen (or before the viewport has a
  /// size).
  static Rect visibleRectPt(ViewportController viewport, int index) {
    final pages = viewport.pages;
    if (index < 0 || index >= pages.length) return Rect.zero;
    final size = pages[index].size;
    final pageRect = Rect.fromLTWH(0, 0, size.width, size.height);
    if (viewport.viewportSize.isEmpty) return pageRect;
    final topLeft = viewport.screenToPage(index, Offset.zero);
    final bottomRight = viewport.screenToPage(
      index,
      viewport.viewportSize.bottomRight(Offset.zero),
    );
    return clipToPage(Rect.fromPoints(topLeft, bottomRight), size);
  }

  /// [visible] ∩ the page; the whole page when that is empty (6.12.2 step
  /// 3 — '비면 페이지 전체').
  static Rect clipToPage(Rect visible, core.PageSize page) {
    final pageRect = Rect.fromLTWH(0, 0, page.width, page.height);
    final clipped = visible.intersect(pageRect);
    return clipped.width > 0 && clipped.height > 0 ? clipped : pageRect;
  }

  /// The frame rect (page pt, rotation 0) of an inserted image of
  /// [pixelWidth] × [pixelHeight] (6.12.2 step 3): width = min(pixel width
  /// × 0.5, visible width × 0.6, page width × 0.8), height from the pixel
  /// aspect — when that height is over visible height × 0.6 or page height ×
  /// 0.8 the size is worked out from the height instead. Centred on
  /// [center] (the long-press point of an image paste) or else on the
  /// visible centre, moved so the whole image is on the page. [visible] is
  /// clipped to the page first ([clipToPage]).
  static Rect forImage({
    required core.PageSize pageSize,
    required Rect visibleRectPt,
    required int pixelWidth,
    required int pixelHeight,
    Offset? center,
  }) {
    final visible = clipToPage(visibleRectPt, pageSize);
    final pw = math.max(1, pixelWidth).toDouble();
    final ph = math.max(1, pixelHeight).toDouble();
    var width = math.min(
      pw * pixelShare,
      math.min(visible.width * visibleShare, pageSize.width * pageShare),
    );
    var height = width * ph / pw;
    final maxHeight = math.min(
      visible.height * visibleShare,
      pageSize.height * pageShare,
    );
    if (height > maxHeight) {
      height = maxHeight;
      width = height * pw / ph;
    }
    final c = center ?? visible.center;
    final cx = _clampCentre(c.dx, width, pageSize.width);
    final cy = _clampCentre(c.dy, height, pageSize.height);
    return Rect.fromCenter(
      center: Offset(cx, cy),
      width: width,
      height: height,
    );
  }

  static double _clampCentre(double c, double extent, double page) {
    final half = extent / 2;
    if (page - half <= half) return page / 2;
    return c.clamp(half, page - half).toDouble();
  }

  /// The size of an image page (6.12.3): [current]'s size, turned to the
  /// image's orientation — landscape for a wide image, portrait for a tall
  /// one, [current] as it is when width / height is in [squareMin,
  /// squareMax].
  static core.PageSize imagePageSize(
    core.PageSize current,
    int pixelWidth,
    int pixelHeight,
  ) {
    if (pixelWidth <= 0 || pixelHeight <= 0) return current;
    final ratio = pixelWidth / pixelHeight;
    if (ratio >= squareMin && ratio <= squareMax) return current;
    return ratio > squareMax ? current.landscape : current.portrait;
  }
}
