// lib/src/background/background_builder.dart — contract 7.2.16 (03-ink 4.10).
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'background_spec.dart';

/// INK 4.10 fields + isThumbnail.
@immutable
final class PageBackgroundContext {
  const PageBackgroundContext({
    required this.pageId,
    required this.pageSize,
    required this.background,
    required this.viewScale,
    required this.ancestorScale,
    required this.devicePixelRatio,
    required this.isScaling,
    this.visiblePageRect,
    this.isThumbnail = false,
  });
  final String pageId;

  /// pt
  final Size pageSize;
  final InkBackgroundSpec background;

  /// (v1.1) viewScale = logical px per pt (layout). ancestorScale = scale of ancestor
  /// Transforms (pinch preview) — already applied on screen. deviceScale = viewScale ×
  /// ancestorScale × devicePixelRatio (render resolution only).
  final double viewScale; // logical px per pt (layout)
  final double ancestorScale;
  final double devicePixelRatio;

  /// avoid expensive re-render while true
  final bool isScaling;

  /// pt; render only this part at high zoom
  final Rect? visiblePageRect;

  /// added: page panel / thumbnail rendering
  final bool isThumbnail;

  /// viewScale * ancestorScale * devicePixelRatio
  double get deviceScale => viewScale * ancestorScale * devicePixelRatio;

  @override
  bool operator ==(Object other) =>
      other is PageBackgroundContext &&
      other.pageId == pageId &&
      other.pageSize == pageSize &&
      other.background == background &&
      other.viewScale == viewScale &&
      other.ancestorScale == ancestorScale &&
      other.devicePixelRatio == devicePixelRatio &&
      other.isScaling == isScaling &&
      other.visiblePageRect == visiblePageRect &&
      other.isThumbnail == isThumbnail;

  @override
  int get hashCode => Object.hash(
    pageId,
    pageSize,
    background,
    viewScale,
    ancestorScale,
    devicePixelRatio,
    isScaling,
    visiblePageRect,
    isThumbnail,
  );
}

/// THE extension point for page backgrounds (PDF implements it for InkBackgroundKind.pdf).
abstract interface class PageBackgroundLayerBuilder {
  bool handles(InkBackgroundSpec background);

  /// Widget filling pageSize * viewScale; must paint opaque paper; no pointer handling.
  /// (v1.1) Layout size / painter scale use ctx.viewScale ONLY; ancestorScale enters only
  /// through ctx.deviceScale (resolution / bucket choice). Multiplying the layout by
  /// ancestorScale would double the pinch zoom.
  Widget build(BuildContext context, PageBackgroundContext ctx);
}

/// Optional second interface for offscreen thumbnails (checked with `is`).
abstract interface class PageBackgroundStillRenderer {
  /// The whole opaque page background (paper included) at [pixelSize].
  /// (v1.1) null → cannot render now (InkPageThumbnailRenderer returns null)
  Future<ui.Image?> renderStill(
    InkBackgroundSpec background, {
    required Size pageSize,
    required Size pixelSize,
  });
}
