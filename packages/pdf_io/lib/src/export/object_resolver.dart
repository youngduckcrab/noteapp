// lib/src/export/object_resolver.dart — references → draw items (m5-7/06-pdf 6.2.4). Internal
// (not in the barrel).
//
// T25a: image assets (objects and image backgrounds). The bytes come from the gateway (or the
// JPEG cache), the header decides the path:
// - JPEG fast path (SOF0·1·2, 8 bit, 1 or 3 components, no Adobe APP14, no EXIF rotation,
//   ≤ 8 MiB): the bytes as stored (PdfJpegData), held as `encoded` until the part is sent, then
//   offered back to the cache.
// - slow path (PNG, GIF, WebP, other JPEGs): engine decode at a target size (long side ≤ 2048,
//   pixels ≤ max(1 Mpx, min(4 Mpx, (16 MiB − input) ÷ 4)) — 6.2.10 ③ ⑤) → straight RGBA,
//   held as `rgba` until the part is sent; the input is held as `encoded` during the decode.
// Text boxes and formulas (T25b) come next.
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

import '../common/cancel_signal.dart';
import '../errors.dart';
import '../gateway/pdf_note_gateway.dart';
import '../tuning.dart';
import '../ui/strings_ko.dart';
import 'export_memory.dart';
import 'export_types.dart';
import 'image_probe.dart';
import 'object_geometry.dart';
import 'vectors.dart';

/// Per export: options, cancel, the page being resolved and the warnings collected so far.
final class ResolveContext {
  ResolveContext({
    this.missingAssetPolicy = PdfMissingAssetPolicy.blankPage,
    this.cancel,
    this.fontsReady = true,
  });

  final PdfMissingAssetPolicy missingAssetPolicy;
  final PdfCancelSignal? cancel;

  /// InkFonts.ensureLoaded() finished in time (6.2.2 step 1) — T25b.
  bool fontsReady;

  /// 1-based note page number of the page being resolved (warning page lists).
  int notePageNumber = 1;

  /// Pages with an image left out (bytes missing or not decodable).
  final SplayTreeSet<int> missingImagePages = SplayTreeSet<int>();

  /// Object warnings in the result order (6.2.9), pages ascending.
  List<PdfExportWarning> get warnings => [
    if (missingImagePages.isNotEmpty)
      PdfExportMissingImages(List.unmodifiable(missingImagePages)),
  ];

  Future<T> race<T>(Future<T> future) =>
      cancel == null ? future : cancel!.raceCancel(future);
}

final class ObjectResolver {
  ObjectResolver({required this.gateway, ExportMemoryLedger? ledger})
    : ledger = ledger ?? ExportMemoryLedger() {
    cache = ExportJpegCache(this.ledger);
  }

  final PdfNoteGateway gateway;
  final ExportMemoryLedger ledger;
  late final ExportJpegCache cache;

  /// Image data handed out and not sent yet → what it holds in the ledger (identity keys).
  final Map<PdfImageData, ({ExportMemoryHandle h, core.AssetId? cacheAs})>
  _held = Map.identity();

  /// Images resolved and not reported [sent] yet.
  int get heldImageCount => _held.length;

  /// [ref] → the items to draw, in order. Empty = left out (the warning is in [ctx]).
  ///
  /// Throws PdfIoException(assetMissing) for missing image bytes under
  /// PdfMissingAssetPolicy.fail, PdfIoException(cancelled) after a cancel.
  Future<List<PdfDrawItem>> resolve(PdfPlanItem ref, ResolveContext ctx) {
    ctx.cancel?.throwIfCancelled();
    return switch (ref) {
      PdfDrawItem() => Future.value([ref]),
      PdfAssetImageRef() => _image(ref, ctx),
      // T25b: text objects / raster fallback, formula rasters (6.2.4 · 6.2.5)
      PdfTextBoxRef() || PdfMathRef() => throw UnimplementedError(
        'Text box and formula references are resolved from PDF T25b on',
      ),
    };
  }

  /// After backend.addPages: releases what the sent [images] held; fast path JPEGs go back to
  /// the cache when there is room (6.2.10 ②). Unknown images are ignored.
  void sent(Iterable<PdfImageData> images) {
    for (final image in images) {
      final held = _held.remove(image);
      if (held == null) continue;
      ledger.release(held.h);
      final id = held.cacheAs;
      if (id != null && image is PdfJpegData) cache.offer(id, image.bytes);
    }
  }

  /// End of the export (finished, failed or cancelled): releases everything, cache included.
  void dispose() {
    for (final held in _held.values) {
      ledger.release(held.h);
    }
    _held.clear();
    cache.clear();
  }

  Future<List<PdfDrawItem>> _image(
    PdfAssetImageRef ref,
    ResolveContext ctx,
  ) async {
    final id = ref.assetId;
    var bytes = cache.take(id);
    if (bytes == null) {
      bytes = await ctx.race(gateway.readAssetBytes(id));
      if (bytes == null) {
        if (ctx.missingAssetPolicy == PdfMissingAssetPolicy.fail) {
          throw PdfIoException(
            PdfErrorCode.assetMissing,
            detail: PdfStringsKo.pageList([ctx.notePageNumber]),
          );
        }
        ctx.missingImagePages.add(ctx.notePageNumber);
        return const [];
      }
    }
    ExportMemoryHandle? encoded = ledger.hold(
      ExportMemoryKind.encoded,
      bytes.length,
    );
    try {
      final probe = PdfImageProbe.parse(bytes);
      final PdfImageData data;
      final int shownWidth, shownHeight;
      if (probe.jpegFastPath(bytes.length)) {
        data = PdfJpegData(bytes, width: probe.width!, height: probe.height!);
        _held[data] = (h: encoded, cacheAs: id);
        encoded = null; // held until sent
        shownWidth = data.width;
        shownHeight = data.height;
      } else {
        final size = probe.hasSize
            ? (width: probe.orientedWidth!, height: probe.orientedHeight!)
            : await ctx.race(engineImageSize(bytes));
        final decoded = size == null
            ? null
            : await _decode(bytes, probe, size, ctx);
        if (decoded == null) {
          ctx.missingImagePages.add(ctx.notePageNumber);
          return const [];
        }
        data = decoded;
        shownWidth = size!.width;
        shownHeight = size.height;
      }
      return [
        PdfImageItem(
          image: data,
          matrix: imagePlacement(ref, shownWidth, shownHeight),
        ),
      ];
    } finally {
      // slow path: the input goes once the codec was disposed (6.2.4)
      if (encoded != null) ledger.release(encoded);
    }
  }

  Future<PdfRgbaData?> _decode(
    Uint8List bytes,
    PdfImageProbe probe,
    ({int width, int height}) size,
    ResolveContext ctx,
  ) async {
    final target = decodeTargetSize(size.width, size.height, bytes.length);
    var handle = ledger.hold(
      ExportMemoryKind.rgba,
      target.width * target.height * 4,
    );
    var handed = false;
    try {
      final rgba = await ctx.race(
        engineDecodeRgba(bytes, width: target.width, height: target.height),
      );
      if (rgba == null) return null;
      if (rgba.rgba.length != handle.bytes) {
        ledger.release(handle);
        handle = ledger.hold(ExportMemoryKind.rgba, rgba.rgba.length);
      }
      final data = PdfRgbaData(
        rgba.rgba,
        width: rgba.width,
        height: rgba.height,
        hasAlpha: probe.mayHaveAlpha && rgbaHasAlpha(rgba.rgba),
      );
      _held[data] = (h: handle, cacheAs: null);
      handed = true;
      return data;
    } finally {
      if (!handed) ledger.release(handle);
    }
  }
}

/// The unit square of an image → note pt: an image object fills its frame (F ∘ U(frame-local
/// rect)); an image background is placed by its fit with F = identity (6.2.3). [shownWidth] /
/// [shownHeight] = the image size as shown (EXIF applied) — only the background fit uses it.
PdfAffine imagePlacement(
  PdfAssetImageRef ref,
  int shownWidth,
  int shownHeight,
) {
  final frame = ref.frame;
  if (frame != null) {
    final r = frame.rect;
    return unitSquareToRect(ui.Rect.fromLTWH(0, 0, r.width, r.height))
        .then(PdfAffine.frame(frame));
  }
  return unitSquareToRect(
    backgroundFitRect(
      shownWidth.toDouble(),
      shownHeight.toDouble(),
      ref.pageSize!,
      ref.fit,
    ),
  );
}

/// 6.2.3 image background fit — the INK ImageBackgroundLayerBuilder formula (03-ink 6.11.5):
/// contain k = min(W/pw, H/ph), cover k = max(W/pw, H/ph), rect ((W − pw·k)/2, (H − ph·k)/2,
/// pw·k, ph·k); fill = the page; null = contain.
ui.Rect backgroundFitRect(
  double pixelWidth,
  double pixelHeight,
  ui.Size page,
  core.ImageFit? fit,
) {
  if (fit == core.ImageFit.fill || pixelWidth <= 0 || pixelHeight <= 0) {
    return ui.Offset.zero & page;
  }
  final kw = page.width / pixelWidth, kh = page.height / pixelHeight;
  final k = fit == core.ImageFit.cover ? math.max(kw, kh) : math.min(kw, kh);
  final w = pixelWidth * k, h = pixelHeight * k;
  return ui.Rect.fromLTWH((page.width - w) / 2, (page.height - h) / 2, w, h);
}

/// 6.2.4 slow path target: long side ≤ exportDecodeLongSidePx and pixels ≤
/// max(exportMinDecodePixels, min(maxRasterPixels, ⌊(exportImageTempBytes − input) ÷ 4⌋)),
/// never larger than the image (no upscaling), aspect kept (± one pixel of rounding).
({int width, int height}) decodeTargetSize(
  int width,
  int height,
  int inputBytes,
) {
  final maxPixels = math.max(
    PdfTuning.exportMinDecodePixels,
    math.min(
      PdfTuning.maxRasterPixels,
      (PdfTuning.exportImageTempBytes - inputBytes) ~/ 4,
    ),
  );
  const maxSide = PdfTuning.exportDecodeLongSidePx;
  final pixels = width * height;
  var s = math.min(1.0, maxSide / math.max(width, height));
  if (pixels * s * s > maxPixels) s = math.sqrt(maxPixels / pixels);
  int side(int full, int v) =>
      math.min(full, math.min(maxSide, math.max(1, v)));
  var w = side(width, (width * s).round()),
      h = side(height, (height * s).round());
  if (w * h > maxPixels) {
    // rounding up passed the pixel cap: round both down (keeps a square square)
    w = side(width, (width * s).floor());
    h = side(height, (height * s).floor());
  }
  while (w * h > maxPixels) {
    if (w >= h) {
      w--;
    } else {
      h--;
    }
  }
  return (width: w, height: h);
}

/// Any alpha < 255 in straight RGBA.
bool rgbaHasAlpha(Uint8List rgba) {
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] != 255) return true;
  }
  return false;
}

/// Engine decode at exactly [width] × [height] (EXIF orientation applied by the engine) →
/// straight RGBA; null = not decodable. The ui.Image is disposed right after its bytes are
/// copied, then the codec (6.2.4). The engine's own temporary memory is outside the ledger.
Future<({Uint8List rgba, int width, int height})?> engineDecodeRgba(
  Uint8List bytes, {
  required int width,
  required int height,
}) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: width,
      targetHeight: height,
      allowUpscaling: false,
    );
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) return null;
    return (
      rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      width: image.width,
      height: image.height,
    );
  } on Object {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

/// The size as the engine decodes it (EXIF applied), for formats whose header has none; null =
/// not decodable. VM / native: ui.ImageDescriptor.encoded (no decode). Web: the descriptor has no
/// size (UnsupportedError — checked in web/object_resolver_browser_test), so the first frame is
/// decoded once and disposed.
Future<({int width, int height})?> engineImageSize(Uint8List bytes) async {
  if (kIsWeb) {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      image = (await codec.getNextFrame()).image;
      return (width: image.width, height: image.height);
    } on Object {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width, h = descriptor.height;
    return w > 0 && h > 0 ? (width: w, height: h) : null;
  } on Object {
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}
