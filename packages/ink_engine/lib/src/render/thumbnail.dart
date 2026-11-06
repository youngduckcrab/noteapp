// lib/src/render/thumbnail.dart — contract 7.2.16 (v1.1): the CALLER passes the provider values.
//
// 6.17 page panel widget (INK T20): the first builder of the list that
// handles the background builds it (isThumbnail: true, small viewScale,
// ancestorScale 1) on every build — so a preview content (revision 0, no
// strokes) shows a new size / background at once — and the committed strokes
// are rasterized ONCE (Picture.toImage, device px) per (pageId, pageSize,
// revision, paper color) and shown with RawImage; no strokes → no raster. The
// previous image stays until the new one is ready. No cache outside the
// widget state (two cells of one pageId never mix). A pencil stroke drawn
// before the grain was ready is rasterized again once it is.
//
// (m5-7 T41, 6.20) The page objects are part of the raster, in L-1 order
// (K-8, page_composite.dart). The widget cannot return null, so what is not
// ready is drawn as its placeholder (or the system font) and the page is
// rasterized again ONCE when it arrives: a decode of one of this page's image
// assets (InkImageCache.changes of the first ImageBackgroundLayerBuilder in the
// list — other assets are ignored; no such builder → placeholders), NoteSans
// loaded (the implicit load starts with the first raster of a text box), a
// formula raster at the thumbnail scale (kept by the state, disposed with it).
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart' show internal;
import 'package:note_core/note_core.dart' as core;

import '../background/background_builder.dart';
import '../background/builder_choice.dart';
import '../geometry/outline_generator.dart';
import '../image/image_cache.dart';
import '../math/math_raster_cache.dart';
import '../math/math_renderer.dart' show rasterizeFormula;
import '../text/fonts.dart';
import 'ink_page_content.dart';
import 'page_composite.dart';
import 'pencil_grain.dart';
import 'pinned_raster_cache.dart';

/// (v1.1) INK 4.9. ink_engine does not depend on flutter_riverpod, so the widget reads no
/// provider: the CALLER passes ref.watch(pageBackgroundBuildersProvider) and
/// ref.watch(pencilGrainProvider).
class InkPageThumbnail extends StatefulWidget {
  const InkPageThumbnail({
    super.key,
    required this.content,
    required this.width,
    required this.backgroundBuilders,
    this.pencilGrain,
  });
  final InkPageContent content;

  /// logical px; height = page aspect
  final double width;
  final List<PageBackgroundLayerBuilder> backgroundBuilders;
  final PencilGrain? pencilGrain;

  /// StatefulWidget member (not in the block)
  @override
  State<InkPageThumbnail> createState() => _InkPageThumbnailState();
}

/// What one stroke raster shows.
@immutable
final class _RasterKey {
  const _RasterKey(
    this.pageId,
    this.pageSize,
    this.revision,
    this.paper,
    this.generation,
  );
  final String pageId;
  final Size pageSize;
  final int revision;

  /// The highlighter blend depends on the paper (6.10-4).
  final int paper;

  /// (T41) Bumped when an image, the fonts or a formula raster arrived.
  final int generation;

  @override
  bool operator ==(Object other) =>
      other is _RasterKey &&
      other.pageId == pageId &&
      other.pageSize == pageSize &&
      other.revision == revision &&
      other.paper == paper &&
      other.generation == generation;

  @override
  int get hashCode =>
      Object.hash(pageId, pageSize, revision, paper, generation);
}

class _InkPageThumbnailState extends State<InkPageThumbnail> {
  ui.Image? _image;
  _RasterKey? _imageKey;
  _RasterKey? _pendingKey;

  /// The image has pencil strokes drawn without the grain.
  bool _missingGrain = false;
  PencilGrain? _grainListened;

  /// (T41) Raster again once something the last raster missed arrives.
  int _generation = 0;
  Set<String> _missingAssets = const {};
  bool _missingFonts = false;
  bool _fontsListening = false;
  InkImageCache? _cacheListened;
  StreamSubscription<({String assetId, int bucket})>? _changes;

  /// Formula rasters at the thumbnail scale (null = the raster host gave none — the
  /// placeholder stays); owned by the state.
  final Map<MathRasterKey, MathRaster?> _maths = {};
  final Set<MathRasterKey> _mathsPending = {};

  @override
  void didUpdateWidget(InkPageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.pencilGrain, widget.pencilGrain)) _unlistenGrain();
  }

  @override
  void dispose() {
    _unlistenGrain();
    unawaited(_changes?.cancel());
    _changes = null;
    if (_fontsListening) InkFontsDebug.removeLoadedListener(_fontsLoaded);
    for (final m in _maths.values) {
      m?.image.dispose();
    }
    _maths.clear();
    _pendingKey = null;
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  /// Something the last raster drew as a placeholder arrived: raster again.
  void _arrived() {
    if (!mounted) return;
    setState(() => _generation++);
  }

  void _fontsLoaded() {
    if (!_missingFonts) return;
    _missingFonts = false;
    _arrived();
  }

  void _assetChanged(({String assetId, int bucket}) change) {
    if (!_missingAssets.contains(change.assetId)) return;
    _missingAssets = const {};
    _arrived();
  }

  /// Watches [cache] for [assets] (this page's image assets the last raster missed).
  void _watchAssets(InkImageCache? cache, Set<String> assets) {
    _missingAssets = assets;
    if (assets.isEmpty || cache == null || identical(cache, _cacheListened)) {
      return;
    }
    unawaited(_changes?.cancel());
    _cacheListened = cache;
    _changes = cache.isDisposed ? null : cache.changes.listen(_assetChanged);
  }

  void _watchFonts(bool missing) {
    _missingFonts = missing;
    if (!missing) return;
    if (!_fontsListening) {
      _fontsListening = true;
      InkFontsDebug.addLoadedListener(_fontsLoaded);
    }
    unawaited(InkFontsDebug.loadImplicitly());
  }

  /// Starts the raster of [key] for [o] unless it is there or on its way.
  void _rasterMath(core.MathObject o, MathRasterKey key) {
    if (_maths.containsKey(key) || !_mathsPending.add(key)) return;
    unawaited(
      rasterizeFormula(
        o.latex,
        colorArgb: o.style.colorArgb,
        fontSizePt: o.style.fontSizePt,
        pixelsPerPt: key.bucket,
      ).then((r) {
        _mathsPending.remove(key);
        if (!mounted) {
          r?.image.dispose();
          return;
        }
        _maths[key] = r == null
            ? null
            : MathRaster.detached(key.formula, key.bucket, r);
        if (r != null) _arrived();
      }),
    );
  }

  void _unlistenGrain() {
    _grainListened?.removeListener(_grainChanged);
    _grainListened = null;
  }

  void _grainChanged() {
    if (!mounted || widget.pencilGrain?.value == null || !_missingGrain) {
      return;
    }
    _unlistenGrain();
    setState(() {
      _missingGrain = false;
      _imageKey = null; // raster again, with the grain
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final pageSize = content.pageSize;
    final viewScale = widget.width / pageSize.width;
    final height = pageSize.height * viewScale;
    final background = content.background;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final ctx = PageBackgroundContext(
      pageId: content.pageId,
      pageSize: pageSize,
      background: background,
      viewScale: viewScale,
      ancestorScale: 1,
      devicePixelRatio: dpr,
      isScaling: false,
      isThumbnail: true,
    );
    final hasStrokes = content.strokes.isNotEmpty || content.objects.isNotEmpty;
    if (hasStrokes) {
      _rasterIfNeeded(
        _RasterKey(
          content.pageId,
          pageSize,
          content.revision,
          background.paperColorArgb,
          _generation,
        ),
        Size(widget.width * dpr, height * dpr),
      );
    } else {
      // nothing to draw over the background; a late raster is dropped
      _pendingKey = null;
      _imageKey = null;
      _image?.dispose();
      _image = null;
    }
    final image = _image;
    return SizedBox(
      width: widget.width,
      height: height,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: IgnorePointer(
                child: backgroundBuilderFor(
                  widget.backgroundBuilders,
                  background,
                ).build(context, ctx),
              ),
            ),
            if (hasStrokes && image != null)
              Positioned.fill(
                child: RawImage(image: image, fit: BoxFit.fill),
              ),
          ],
        ),
      ),
    );
  }

  /// Starts the one-time raster of [key] at [pixelSize] unless it is shown or
  /// already on its way.
  void _rasterIfNeeded(_RasterKey key, Size pixelSize) {
    if (key == _imageKey || key == _pendingKey) return;
    _pendingKey = key;
    final content = widget.content;
    final w = pixelSize.width.round().clamp(1, 16384);
    final h = pixelSize.height.round().clamp(1, 16384);
    final grain = widget.pencilGrain;
    final textured = content.strokes.any((s) => s.profile.textured);
    final missingGrain = textured && grain?.value == null;
    if (missingGrain && grain != null && _grainListened == null) {
      _grainListened = grain..addListener(_grainChanged);
    }
    final pageWidth = content.pageSize.width;
    final pxPerPt = w / pageWidth;
    // (T41) what is ready now; the rest is a placeholder until it arrives
    final cache = imageCacheOf(widget.backgroundBuilders);
    final images = <String, ui.Image>{};
    final pins = <InkRasterPin>[];
    final missingAssets = <String>{};
    final maths = <String, MathRaster>{};
    final usedMaths = <MathRasterKey>{};
    var missingFonts = false;
    for (final o in content.objects) {
      switch (o) {
        case core.ImageObject():
          if (cache == null || cache.isDisposed) break;
          final r = o.frame.rect;
          final side = math.max(r.width, r.height) * pxPerPt;
          final found = cache.lookup(
            o.assetId,
            longSidePx: side.isFinite ? math.max(1, side.ceil()) : 1,
            pixelWidth: o.pixelWidth,
            pixelHeight: o.pixelHeight,
          );
          final image = found.image;
          if (image != null) {
            images[o.id] = image;
            pins.add(cache.pin(o.assetId, found.bucket));
          }
          if ((image == null || found.bucket != found.want) &&
              found.status == InkImageStatus.ok) {
            missingAssets.add(o.assetId);
          }
        case core.TextBoxObject():
          if (o.text.isNotEmpty && !InkFontsDebug.isLoaded) {
            missingFonts = true;
          }
        case core.MathObject():
          if (!isRenderableMath(o)) break;
          final key = (formula: mathFormulaOf(o), bucket: pxPerPt);
          usedMaths.add(key);
          final raster = _maths[key];
          if (raster != null) {
            maths[o.id] = raster;
          } else {
            _rasterMath(o, key);
          }
        case core.ShapeObject() || core.UnknownObject():
          break;
      }
    }
    // rasters of formulas this page no longer shows
    _maths.removeWhere((key, raster) {
      if (usedMaths.contains(key)) return false;
      raster?.image.dispose();
      return true;
    });
    _watchAssets(cache, missingAssets);
    _watchFonts(missingFonts);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(w / pageWidth);
    paintPageComposite(
      canvas,
      strokes: content.strokes,
      objects: content.objects,
      paperColorArgb: content.background.paperColorArgb,
      outlineOf: OutlineGenerator.outline,
      onePx: pageWidth / w,
      grain: textured ? grain?.value : null,
      marginPt: pageWidth / w,
      imageOf: (o) => images[o.id],
      mathRasterOf: (o) => maths[o.id],
    );
    final picture = recorder.endRecording();
    _rasters++;
    _busy++;
    picture
        .toImage(w, h)
        .then(
          (image) {
            if (!mounted || key != _pendingKey) {
              image.dispose();
              return;
            }
            setState(() {
              _image?.dispose();
              _image = image;
              _imageKey = key;
              _pendingKey = null;
              _missingGrain = missingGrain;
              // the grain arrived while this raster was on its way
              if (missingGrain && widget.pencilGrain?.value != null) {
                _missingGrain = false;
                _imageKey = null;
              }
            });
          },
          onError: (Object error, StackTrace stack) {
            if (key == _pendingKey) _pendingKey = null;
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stack,
                library: 'ink_engine',
                context: ErrorDescription('while rasterizing a thumbnail'),
              ),
            );
          },
        )
        .whenComplete(() {
          picture.dispose();
          for (final pin in pins) {
            pin.release();
          }
          _busy--;
        });
  }
}

int _rasters = 0;
int _busy = 0;

/// INTERNAL (tests): stroke rasters started by InkPageThumbnail widgets.
@internal
int get inkThumbnailRasterCount => _rasters;

/// INTERNAL (tests): rasters still on their way.
@internal
bool get inkThumbnailRasterBusy => _busy > 0;
