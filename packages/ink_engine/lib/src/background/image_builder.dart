// lib/src/background/image_builder.dart — contract 7.2.9 (m5-7/03-ink 4.7, 6.11.5).
//
// (T35) Image page backgrounds: the paper, then the image of InkImageCache with
// its fit — contain (inside the page, aspect kept, centred), cover (covers the
// page, aspect kept, centred, cut to the page), fill (stretched); no imageFit →
// contain. The widget listens to the cache's changes for its own asset only and
// pins the decode it shows while it shows it (6.11.3). Layout size and painter
// scale use ctx.viewScale only; the bucket comes from ctx.deviceScale (1st round
// 7.2.16 v1.1 — ancestorScale enters through deviceScale only); while
// ctx.isScaling no other bucket is asked for. The size of a background is not in
// the model: the cache reads it from the PNG / JPEG header (no full-resolution
// decode — 6.11.1). renderStill: load at the long side of pixelSize → paper +
// image; bytes not there / undecodable → null (the thumbnail tries later).
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:note_core/note_core.dart' as core;

import '../image/image_cache.dart';
import '../interop/core_interop.dart' as interop;
import '../render/pinned_raster_cache.dart';
import 'background_builder.dart';
import 'background_spec.dart';

final class ImageBackgroundLayerBuilder
    implements PageBackgroundLayerBuilder, PageBackgroundStillRenderer {
  const ImageBackgroundLayerBuilder({
    required this.assets,
    required this.images,
  });
  final core.AssetStore assets;
  final InkImageCache images;

  /// kind == image && assetId != null
  @override
  bool handles(InkBackgroundSpec background) =>
      background.kind == InkBackgroundKind.image && background.assetId != null;

  /// Size = pageSize × ctx.viewScale (never × ancestorScale): the paper, then the image
  /// with its fit (6.11.5) once the cache has it.
  @override
  Widget build(BuildContext context, PageBackgroundContext ctx) => SizedBox(
    width: ctx.pageSize.width * ctx.viewScale,
    height: ctx.pageSize.height * ctx.viewScale,
    child: _ImageBackground(images: images, ctx: ctx),
  );

  /// The whole opaque page at [pixelSize]: the paper and the image with its fit; null when
  /// the bytes are not on this device or do not decode.
  @override
  Future<ui.Image?> renderStill(
    InkBackgroundSpec background, {
    required Size pageSize,
    required Size pixelSize,
  }) async {
    final w = math.max(1, pixelSize.width.round()).clamp(1, 16384);
    final h = math.max(1, pixelSize.height.round()).clamp(1, 16384);
    final assetId = background.assetId;
    ({ui.Image image, int bucket})? entry;
    if (assetId != null) {
      entry = await images.loadEntry(assetId, longSidePx: math.max(w, h));
      if (entry == null) return null;
    }
    // pinned while it is drawn (6.11.3 — a thumbnail holds it only while it draws)
    final pin = entry == null || assetId == null
        ? InkRasterPin.none
        : images.pin(assetId, entry.bucket);
    try {
      final recorder = ui.PictureRecorder();
      paintImageBackground(
        ui.Canvas(recorder),
        Size(w.toDouble(), h.toDouble()),
        paperArgb: background.paperColorArgb,
        image: entry?.image,
        fit: background.imageFit,
      );
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(w, h);
      } finally {
        picture.dispose();
      }
    } finally {
      pin.release();
    }
  }
}

/// INTERNAL (6.11.5): the paper over [size], then [image] with [fit] (null → contain).
@visibleForTesting
void paintImageBackground(
  ui.Canvas canvas,
  Size size, {
  required int paperArgb,
  required ui.Image? image,
  required core.ImageFit? fit,
}) {
  final page = Offset.zero & size;
  canvas.drawRect(page, Paint()..color = Color(interop.opaqueArgb(paperArgb)));
  if (image == null || page.isEmpty) return;
  final iw = image.width.toDouble(), ih = image.height.toDouble();
  final Rect dst;
  switch (fit ?? core.ImageFit.contain) {
    case core.ImageFit.fill:
      dst = page;
    case core.ImageFit.contain:
      final s = math.min(size.width / iw, size.height / ih);
      dst = Rect.fromCenter(center: page.center, width: iw * s, height: ih * s);
    case core.ImageFit.cover:
      final s = math.max(size.width / iw, size.height / ih);
      dst = Rect.fromCenter(center: page.center, width: iw * s, height: ih * s);
  }
  canvas
    ..save()
    ..clipRect(page)
    ..drawImageRect(
      image,
      Rect.fromLTWH(0, 0, iw, ih),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    )
    ..restore();
}

/// The background widget: asks the cache at the page's long side × deviceScale, listens
/// to its own asset's changes, pins what it shows.
class _ImageBackground extends StatefulWidget {
  const _ImageBackground({required this.images, required this.ctx});
  final InkImageCache images;
  final PageBackgroundContext ctx;

  @override
  State<_ImageBackground> createState() => _ImageBackgroundState();
}

class _ImageBackgroundState extends State<_ImageBackground> {
  StreamSubscription<({String assetId, int bucket})>? _changes;
  InkRasterPin _pin = InkRasterPin.none;
  ({String assetId, int bucket})? _pinned;
  int? _longSidePx;

  @override
  void initState() {
    super.initState();
    _changes = widget.images.changes.listen(_onChange);
  }

  @override
  void didUpdateWidget(_ImageBackground old) {
    super.didUpdateWidget(old);
    if (!identical(old.images, widget.images)) {
      unawaited(_changes?.cancel());
      _changes = widget.images.changes.listen(_onChange);
      _release();
    }
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    _changes = null;
    _release();
    super.dispose();
  }

  void _onChange(({String assetId, int bucket}) change) {
    if (!mounted || change.assetId != widget.ctx.background.assetId) return;
    setState(() {});
  }

  void _release() {
    _pin.release();
    _pin = InkRasterPin.none;
    _pinned = null;
  }

  /// The long side asked for: the page's long side × deviceScale, kept while scaling.
  int _wantedLongSide(PageBackgroundContext ctx) {
    final kept = _longSidePx;
    if (ctx.isScaling && kept != null) return kept;
    final long = math.max(ctx.pageSize.width, ctx.pageSize.height);
    final s = ctx.deviceScale;
    final px = long * (s > 0 && s.isFinite ? s : 2.0);
    return _longSidePx = !px.isFinite || px < 1
        ? 1
        : math.min(px.ceil(), 1 << 16);
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final assetId = ctx.background.assetId;
    ui.Image? image;
    if (assetId != null) {
      final found = widget.images.lookup(
        assetId,
        longSidePx: _wantedLongSide(ctx),
      );
      image = found.image;
      final shown = image == null
          ? null
          : (assetId: assetId, bucket: found.bucket);
      if (shown != _pinned) {
        _release();
        if (shown != null) {
          _pin = widget.images.pin(shown.assetId, shown.bucket);
          _pinned = shown;
        }
      }
    } else {
      _release();
    }
    return CustomPaint(
      painter: _ImageBackgroundPainter(
        image: image,
        paperArgb: ctx.background.paperColorArgb,
        fit: ctx.background.imageFit,
      ),
    );
  }
}

class _ImageBackgroundPainter extends CustomPainter {
  _ImageBackgroundPainter({
    required this.image,
    required this.paperArgb,
    required this.fit,
  });
  final ui.Image? image;
  final int paperArgb;
  final core.ImageFit? fit;

  @override
  void paint(Canvas canvas, Size size) => paintImageBackground(
    canvas,
    size,
    paperArgb: paperArgb,
    image: image,
    fit: fit,
  );

  @override
  bool shouldRepaint(_ImageBackgroundPainter old) =>
      !identical(old.image, image) ||
      old.paperArgb != paperArgb ||
      old.fit != fit;
}
