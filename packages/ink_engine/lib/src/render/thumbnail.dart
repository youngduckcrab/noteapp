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
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart' show internal;

import '../background/background_builder.dart';
import '../background/builder_choice.dart';
import '../geometry/outline_generator.dart';
import 'ink_page_content.dart';
import 'layer_painters.dart';
import 'pencil_grain.dart';

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
  const _RasterKey(this.pageId, this.pageSize, this.revision, this.paper);
  final String pageId;
  final Size pageSize;
  final int revision;

  /// The highlighter blend depends on the paper (6.10-4).
  final int paper;

  @override
  bool operator ==(Object other) =>
      other is _RasterKey &&
      other.pageId == pageId &&
      other.pageSize == pageSize &&
      other.revision == revision &&
      other.paper == paper;

  @override
  int get hashCode => Object.hash(pageId, pageSize, revision, paper);
}

class _InkPageThumbnailState extends State<InkPageThumbnail> {
  ui.Image? _image;
  _RasterKey? _imageKey;
  _RasterKey? _pendingKey;

  /// The image has pencil strokes drawn without the grain.
  bool _missingGrain = false;
  PencilGrain? _grainListened;

  @override
  void didUpdateWidget(InkPageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.pencilGrain, widget.pencilGrain)) _unlistenGrain();
  }

  @override
  void dispose() {
    _unlistenGrain();
    _pendingKey = null;
    _image?.dispose();
    _image = null;
    super.dispose();
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
    final hasStrokes = content.strokes.isNotEmpty;
    if (hasStrokes) {
      _rasterIfNeeded(
        _RasterKey(
          content.pageId,
          pageSize,
          content.revision,
          background.paperColorArgb,
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
    final recorder = ui.PictureRecorder();
    final pageWidth = content.pageSize.width;
    final canvas = ui.Canvas(recorder)..scale(w / pageWidth);
    paintStrokeLayers(
      canvas,
      content.strokes,
      paperColorArgb: content.background.paperColorArgb,
      outlineOf: OutlineGenerator.outline,
      grain: textured ? grain?.value : null,
      marginPt: pageWidth / w,
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
