// lib/src/viewport/viewport_camera.dart — 04-editor 6.3.3.
//
// screen = (doc − origin) × scale, doc = screen / scale + origin (6.2).
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:meta/meta.dart';

import 'page_layout.dart';
import 'viewport_constants.dart';

@immutable
class ViewportCamera {
  const ViewportCamera({required this.scale, required this.origin});
  final double scale; // logical px per pt
  final Offset origin; // doc point at the viewport's top-left

  Offset docToScreen(Offset doc) => (doc - origin) * scale;
  Offset screenToDoc(Offset screen) => screen / scale + origin;
  Rect visibleDocRect(Size viewport) => Rect.fromLTWH(
    origin.dx,
    origin.dy,
    viewport.width / scale,
    viewport.height / scale,
  );

  /// Keeps the doc point under [screenFocal] fixed.
  ViewportCamera zoomedAround(Offset screenFocal, double newScale) =>
      ViewportCamera(
        scale: newScale,
        origin: screenToDoc(screenFocal) - screenFocal / newScale,
      );

  ViewportCamera pannedBy(Offset screenDelta) => // origin -= delta / scale
      ViewportCamera(scale: scale, origin: origin - screenDelta / scale);

  ViewportCamera copyWith({double? scale, Offset? origin}) =>
      ViewportCamera(scale: scale ?? this.scale, origin: origin ?? this.origin);

  @override
  bool operator ==(Object other) =>
      other is ViewportCamera && other.scale == scale && other.origin == origin;
  @override
  int get hashCode => Object.hash(scale, origin);

  @override
  String toString() => 'ViewportCamera(scale: $scale, origin: $origin)';
}

/// Pure functions used by ViewportController (unit-tested).
abstract final class CameraMath {
  /// Vertical: (vw - 2*sideMargin) / crossExtent.
  /// Horizontal: min((vw - 2m)/w_i, (vh - 2m)/h_i) of [pageIndex].
  /// An empty layout (or an empty viewport) gives 1.
  static double fitScale(
    PageLayout layout,
    Size viewport, {
    int pageIndex = 0,
  }) {
    const m = ViewportConstants.sideMargin;
    final double fit;
    if (layout.axis == LayoutAxis.vertical) {
      if (layout.crossExtent <= 0) return 1;
      fit = (viewport.width - 2 * m) / layout.crossExtent;
    } else {
      if (layout.length == 0) return 1;
      final page = layout.rectOf(pageIndex.clamp(0, layout.length - 1));
      if (page.width <= 0 || page.height <= 0) return 1;
      fit = math.min(
        (viewport.width - 2 * m) / page.width,
        (viewport.height - 2 * m) / page.height,
      );
    }
    return fit > 0 && fit.isFinite ? fit : 1;
  }

  /// Scale limited to [fit*minZoom, fit*maxZoom].
  static double clampScale(double scale, double fitScale) => scale.clamp(
    fitScale * ViewportConstants.minZoom,
    fitScale * ViewportConstants.maxZoom,
  );

  /// Clamps scale to [fit*minZoom, fit*maxZoom] and origin to bounds:
  /// cross axis centred while the widest page fits (with side margins), else
  /// limited to the content plus a side margin; main axis centred while the
  /// content is shorter than the viewport, else within [0, content − visible].
  /// Horizontal (paged) layout: the main-axis range also reaches the first
  /// and the last page centred, so every page can be shown centred at its
  /// fit scale (the leading padding alone is narrower than that margin).
  static ViewportCamera clamp(
    ViewportCamera camera,
    PageLayout layout,
    Size viewport,
    double fitScale,
  ) {
    const m = ViewportConstants.sideMargin;
    final scale = clampScale(camera.scale, fitScale);
    final vertical = layout.axis == LayoutAxis.vertical;
    final crossViewport = vertical ? viewport.width : viewport.height;
    final mainViewport = vertical ? viewport.height : viewport.width;
    final crossOrigin = vertical ? camera.origin.dx : camera.origin.dy;
    final mainOrigin = vertical ? camera.origin.dy : camera.origin.dx;

    final visCross = crossViewport / scale;
    final double cross;
    if (layout.crossExtent * scale <= crossViewport - 2 * m + 0.5) {
      cross = (layout.crossExtent - visCross) / 2;
    } else {
      cross = crossOrigin.clamp(
        -m / scale,
        layout.crossExtent - visCross + m / scale,
      );
    }

    final visMain = mainViewport / scale;
    final content = vertical
        ? layout.contentSize.height
        : layout.contentSize.width;
    var low = 0.0;
    var high = content - visMain;
    if (!vertical && layout.length > 0) {
      low = math.min(low, layout.rectOf(0).center.dx - visMain / 2);
      final last = layout.rectOf(layout.length - 1).center.dx - visMain / 2;
      high = math.max(high, last);
    }
    final double main;
    if (vertical && content <= visMain) {
      main = (content - visMain) / 2;
    } else if (high <= low) {
      main = (low + high) / 2;
    } else {
      main = mainOrigin.clamp(low, high);
    }

    return ViewportCamera(
      scale: scale,
      origin: vertical ? Offset(cross, main) : Offset(main, cross),
    );
  }

  /// Pull to add a page (6.11.7): the shown overscroll (logical px) for a
  /// finger travel of [excess] px past the document end — damped by
  /// [ViewportConstants.pullToAddResistance], capped at
  /// [ViewportConstants.pullToAddMaxExtent]; 0 for no travel past the end.
  static double pullExtent(double excess) {
    if (!(excess > 0)) return 0;
    return math.min(
      excess * ViewportConstants.pullToAddResistance,
      ViewportConstants.pullToAddMaxExtent,
    );
  }

  /// Camera after a navigation gesture, computed from the baseline (no drift):
  /// newScale = clampScale(base.scale * scaleRatio);
  /// newOrigin = base.screenToDoc(baselineFocal) - focal / newScale.
  static ViewportCamera applyGesture({
    required ViewportCamera base,
    required Offset baselineFocal,
    required Offset focal,
    required double scaleRatio,
    required PageLayout layout,
    required Size viewport,
    required double fitScale,
  }) {
    final newScale = clampScale(base.scale * scaleRatio, fitScale);
    final anchor = base.screenToDoc(baselineFocal);
    return clamp(
      ViewportCamera(scale: newScale, origin: anchor - focal / newScale),
      layout,
      viewport,
      fitScale,
    );
  }
}
