// lib/src/background/image_builder.dart — contract 7.2.9 (m5-7/03-ink 4.7, 6.11.5).
//
// Foundation step R2-B3 (03-ink 4.13): paper color only (build and
// renderStill). T35 draws the image with its fit (contain / cover / fill)
// from [images].
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:note_core/note_core.dart' as core;

import '../image/image_cache.dart';
import '../interop/core_interop.dart' as interop;
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

  /// Size = pageSize × ctx.viewScale (never × ancestorScale). R2-B3: the paper only.
  @override
  Widget build(BuildContext context, PageBackgroundContext ctx) => SizedBox(
    width: ctx.pageSize.width * ctx.viewScale,
    height: ctx.pageSize.height * ctx.viewScale,
    child: ColoredBox(
      color: Color(interop.opaqueArgb(ctx.background.paperColorArgb)),
    ),
  );

  /// The whole opaque page at [pixelSize]. R2-B3: the paper only.
  @override
  Future<ui.Image?> renderStill(
    InkBackgroundSpec background, {
    required Size pageSize,
    required Size pixelSize,
  }) {
    final w = math.max(1, pixelSize.width.round()).clamp(1, 16384);
    final h = math.max(1, pixelSize.height.round()).clamp(1, 16384);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = Color(interop.opaqueArgb(background.paperColorArgb)),
    );
    final picture = recorder.endRecording();
    return picture.toImage(w, h).whenComplete(picture.dispose);
  }
}
