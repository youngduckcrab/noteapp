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
//
// T25b: text boxes and formulas (6.2.4 · 6.2.5). A text box background is a vector fill under
// the text; the text is PDF text objects (one per laid-out line, NoteSans embedded on first use)
// when the fonts are ready, INK laid out lines and NoteSans covers every character — otherwise
// a frame-size raster from the text port. A formula is a raster from the math port, contain-
// fitted into its frame. Rasters are ≤ 4 Mpx (cappedPixelsPerPt) and held as `rgba` (room
// taken before the call) until the part is sent.
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../common/cancel_signal.dart';
import '../common/error_report.dart';
import '../errors.dart';
import '../gateway/pdf_note_gateway.dart';
import '../tuning.dart';
import '../ui/strings_ko.dart';
import 'compose_plan.dart';
import 'export_memory.dart';
import 'export_types.dart';
import 'image_probe.dart';
import 'object_geometry.dart';
import 'raster_ports.dart';
import 'vectors.dart';

/// Reads one NoteSans file for embedding (default: ink.InkFonts.noteSansBytes — ≤ 5 s, then a
/// TimeoutException).
typedef PdfFontBytesSource = Future<Uint8List> Function({required bool bold});

/// (T26) The export service's default font wait (6.2.2 step 1): ink.InkFonts.ensureLoaded —
/// here so that package:ink_engine stays in the files of 3.5.
Future<void> loadNoteSansFonts() => ink.InkFonts.ensureLoaded();

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

  /// Pages with a text box drawn as a raster (or left out when even the raster failed).
  final SplayTreeSet<int> rasterizedTextPages = SplayTreeSet<int>();

  /// Pages with a formula left out (invalid LaTeX, raster failed or timed out).
  final SplayTreeSet<int> skippedFormulaPages = SplayTreeSet<int>();

  /// NoteSans bytes read so far (PdfComposeOpcodes.fontRegular / fontBold → TrueType bytes) —
  /// the encoder's fontBytes (sent with the first part that uses them, 6.2.6).
  final Map<int, Uint8List> fontBytes = {};

  /// Font ids whose read failed in this export (not tried again — the boxes are rasterized).
  final Set<int> failedFontIds = {};

  /// Object warnings in the result order (4.1.5 · 6.16), pages ascending.
  List<PdfExportWarning> get warnings => [
    if (missingImagePages.isNotEmpty)
      PdfExportMissingImages(List.unmodifiable(missingImagePages)),
    if (rasterizedTextPages.isNotEmpty)
      PdfExportRasterizedText(List.unmodifiable(rasterizedTextPages)),
    if (skippedFormulaPages.isNotEmpty)
      PdfExportSkippedFormulas(List.unmodifiable(skippedFormulaPages)),
  ];

  Future<T> race<T>(Future<T> future) =>
      cancel == null ? future : cancel!.raceCancel(future);
}

final class ObjectResolver {
  ObjectResolver({
    required this.gateway,
    PdfMathRasterizer math = const InkMathRasterizer(),
    PdfTextRasterizer text = const InkTextRasterizer(),
    PdfFontBytesSource? fontBytes,
    this.mathTimeout = PdfTuning.exportMathRasterTimeout,
    ExportMemoryLedger? ledger,
  }) : mathRasterizer = math,
       textRasterizer = text,
       fontBytes = fontBytes ?? ink.InkFonts.noteSansBytes,
       ledger = ledger ?? ExportMemoryLedger() {
    cache = ExportJpegCache(this.ledger);
  }

  final PdfNoteGateway gateway;
  final PdfMathRasterizer mathRasterizer;
  final PdfTextRasterizer textRasterizer;
  final PdfFontBytesSource fontBytes;

  /// One formula raster at most this long (exportMathRasterTimeout) — then left out.
  final Duration mathTimeout;
  final ExportMemoryLedger ledger;
  late final ExportJpegCache cache;

  /// A failed text raster is reported once per export (6.2.4).
  bool _reportedTextRaster = false;

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
      PdfTextBoxRef() => _textBox(ref, ctx),
      PdfMathRef() => _formula(ref.object, ctx),
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

  /// 6.2.4 PdfTextBoxRef: ① background fill, ② text objects, ③ else the raster fallback.
  Future<List<PdfDrawItem>> _textBox(
    PdfTextBoxRef ref,
    ResolveContext ctx,
  ) async {
    final object = ref.object;
    final frame = object.frame;
    final background = textBoxBackground(object);
    final items = <PdfDrawItem>[?background];
    if (object.text.trim().isEmpty) return items; // nothing to write
    if (ctx.fontsReady &&
        ref.lines.isNotEmpty &&
        ink.InkFonts.covers(object.text)) {
      final fontId = object.style.bold
          ? PdfComposeOpcodes.fontBold
          : PdfComposeOpcodes.fontRegular;
      if (await _fontReady(fontId, ctx)) {
        final f = PdfAffine.frame(frame);
        for (final line in ref.lines) {
          final lineText = _lineText(line.text);
          if (lineText == null) continue;
          items.add(
            PdfTextItem(
              text: lineText,
              fontId: fontId,
              fontSize: object.style.fontSizePt,
              colorArgb: object.style.colorArgb,
              matrix: textSpaceAt(line.x, line.baselineY).then(f),
            ),
          );
        }
        return items;
      }
    }
    // ③ raster fallback (CP-PDF-8): uncovered characters, no INK lines or no font
    ctx.rasterizedTextPages.add(ctx.notePageNumber);
    final r = frame.rect;
    final size = ui.Size(r.width, r.height);
    final k = cappedPixelsPerPt(PdfTuning.textRasterDpi / 72, size);
    final raster = await _raster(
      size,
      k,
      ctx,
      () => textRasterizer.rasterize(object, pixelsPerPt: k),
    );
    if (raster.data == null) {
      if (!_reportedTextRaster) {
        _reportedTextRaster = true;
        reportPdfError(
          raster.error ?? StateError('The text raster gave no image'),
          raster.stack ?? StackTrace.current,
          'pdf export: text box raster (${object.id})',
        );
      }
      return items; // the box is left out; its background stays
    }
    items.add(
      PdfImageItem(
        image: raster.data!,
        matrix: unitSquareToRect(ui.Rect.fromLTWH(0, 0, r.width, r.height))
            .then(PdfAffine.frame(frame)),
      ),
    );
    return items;
  }

  /// 6.2.4 PdfMathRef: layout → contain rect → raster at ⌈mathRasterDpi⌉ (capped) ≤ mathTimeout.
  Future<List<PdfDrawItem>> _formula(
    core.MathObject object,
    ResolveContext ctx,
  ) async {
    final r = object.frame.rect;
    ui.Size? layout;
    try {
      layout = mathRasterizer.layoutSize(object);
    } on Object {
      layout = null;
    }
    final contain = layout == null
        ? null
        : mathContainRect(layout, ui.Size(r.width, r.height));
    if (layout == null || contain == null) {
      ctx.skippedFormulaPages.add(ctx.notePageNumber);
      return const [];
    }
    final s = contain.width / layout.width;
    final k = cappedPixelsPerPt(s * PdfTuning.mathRasterDpi / 72, layout);
    final raster = await _raster(
      layout,
      k,
      ctx,
      () => mathRasterizer
          .rasterize(object, pixelsPerPt: k)
          .timeout(mathTimeout, onTimeout: () => null),
    );
    if (raster.data == null) {
      ctx.skippedFormulaPages.add(ctx.notePageNumber);
      return const [];
    }
    return [
      PdfImageItem(
        image: raster.data!,
        matrix: unitSquareToRect(contain).then(PdfAffine.frame(object.frame)),
      ),
    ];
  }

  /// One raster of [sizePt] at [pixelsPerPt]: room for ⌈w·k⌉ × ⌈h·k⌉ RGBA is taken before
  /// [draw] runs (6.2.10 ④ — the cache gives way first), the real size replaces it after. A
  /// raster over maxRasterPixels, null or an exception → data null (nothing held). A cancel is
  /// rethrown.
  Future<({PdfRgbaData? data, Object? error, StackTrace? stack})> _raster(
    ui.Size sizePt,
    double pixelsPerPt,
    ResolveContext ctx,
    Future<PdfRgbaData?> Function() draw,
  ) async {
    const none = (data: null, error: null, stack: null);
    if (!(pixelsPerPt > 0)) return none;
    final want = rasterPixelSize(sizePt, pixelsPerPt);
    if (want.width < 1 || want.height < 1) return none;
    var handle = ledger.hold(
      ExportMemoryKind.rgba,
      want.width * want.height * 4,
    );
    var handed = false;
    try {
      final PdfRgbaData? data;
      try {
        data = await ctx.race(draw());
      } on PdfIoException {
        rethrow; // cancelled
      } on Object catch (e, s) {
        return (data: null, error: e, stack: s);
      }
      if (data == null ||
          data.width < 1 ||
          data.height < 1 ||
          data.width * data.height > PdfTuning.maxRasterPixels ||
          data.rgba.length != data.width * data.height * 4) {
        return none;
      }
      if (data.rgba.length != handle.bytes) {
        ledger.release(handle);
        handle = ledger.hold(ExportMemoryKind.rgba, data.rgba.length);
      }
      _held[data] = (h: handle, cacheAs: null);
      handed = true;
      return (data: data, error: null, stack: null);
    } finally {
      if (!handed) ledger.release(handle);
    }
  }

  /// The NoteSans file for [fontId] is in ctx.fontBytes — read once per export on first need;
  /// a failed read (TimeoutException …) is remembered and not tried again.
  Future<bool> _fontReady(int fontId, ResolveContext ctx) async {
    if (ctx.fontBytes.containsKey(fontId)) return true;
    if (ctx.failedFontIds.contains(fontId)) return false;
    try {
      final bytes = await ctx.race(
        fontBytes(bold: fontId == PdfComposeOpcodes.fontBold),
      );
      if (bytes.isEmpty) {
        ctx.failedFontIds.add(fontId);
        return false;
      }
      ctx.fontBytes[fontId] = bytes;
      return true;
    } on PdfIoException {
      rethrow; // cancelled
    } on Object {
      ctx.failedFontIds.add(fontId);
      return false;
    }
  }
}

/// A laid-out line as one text object: without its trailing line break; null for an empty or
/// whitespace-only line (6.2.4 ②).
String? _lineText(String line) {
  var text = line;
  while (text.endsWith('\n') || text.endsWith('\r')) {
    text = text.substring(0, text.length - 1);
  }
  return text.trim().isEmpty ? null : text;
}

/// 6.2.4 ①: style.backgroundArgb → the frame's four corners as one fill under the text, the
/// colour's alpha as the opacity (7.2.12 'a text box background is a vector rect under the
/// text'). null without a background or with alpha 0.
PdfFillItem? textBoxBackground(core.TextBoxObject object) {
  final argb = object.style.backgroundArgb;
  if (argb == null) return null;
  final alpha = argbChannel(argb, 3);
  if (alpha == 0) return null;
  final corners = object.frame.corners;
  final coords = Float32List(8);
  for (var i = 0; i < 4; i++) {
    coords[2 * i] = corners[i].x;
    coords[2 * i + 1] = corners[i].y;
  }
  return PdfFillItem(
    path: PdfVectorPath(Uint8List.fromList(const [0, 1, 1, 1, 3]), coords),
    colorArgb: 0xFF000000 + argb % 0x1000000,
    opacity: alpha / 255,
  );
}

/// 6.2.3 formula contain: s = min(fw/lw, fh/lh), rect ((fw − lw·s)/2, (fh − lh·s)/2, lw·s, lh·s)
/// in frame-local pt (03-ink 6.12.4, K-6). null when a side is not > 0.
ui.Rect? mathContainRect(ui.Size layout, ui.Size frame) {
  final lw = layout.width, lh = layout.height;
  final fw = frame.width, fh = frame.height;
  if (!(lw > 0) || !(lh > 0) || !(fw > 0) || !(fh > 0)) return null;
  if (!lw.isFinite || !lh.isFinite || !fw.isFinite || !fh.isFinite) {
    return null;
  }
  final s = math.min(fw / lw, fh / lh);
  final w = lw * s, h = lh * s;
  return ui.Rect.fromLTWH((fw - w) / 2, (fh - h) / 2, w, h);
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
