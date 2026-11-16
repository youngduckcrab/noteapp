// lib/src/render/playback_objects.dart — INTERNAL (m5-7/03-ink 6.19, v2.13-rec).
//
// Page objects in the playback emphasis. An object linked to a recording
// (core.PageObject.recordingId / recordingOffsetMs — EDITOR sets them for an
// object made while recording, or from the earliest recorded source stroke of a
// conversion) is 'unwritten' at the audio position p while p < its offset, and
// drawn as usual from its offset on (an object appears at once — it has no
// points to write one by one).
//
// dimUnwritten veils every unwritten linked object with the paper color at
// 1 − playbackDimOpacity, like an unwritten stroke: the object is drawn again
// into one layer whose color filter turns every pixel it covers into the paper
// color (srcIn), and the layer is composited at that alpha — the object's own
// pixels (shape outline and fill, glyphs, formula raster) are veiled, nothing
// around them. An image is veiled over its whole frame. highlightRecent dims no
// object. Objects of other recordings and objects without one: unchanged.
//
// Where: shapes (ink layer) and images (underlay) at layer 4′ with the stroke
// veils; text boxes, formulas and unknown objects at the end of the annotation
// layer (they are drawn above layer 4′). The annotation layer repaints only
// when the set of veiled annotation objects changes ([annotationKey]).
import 'dart:ui' as ui;

import 'package:note_core/note_core.dart' as core;

import '../math/math_raster_cache.dart' show MathRaster;
import '../object/object_painter.dart';
import '../tuning.dart';
import 'ink_page_content.dart';
import 'playback.dart';

/// One linked object: its offset and its L-1 layer.
final class PlaybackObjectEntry {
  const PlaybackObjectEntry(this.object, this.offsetMs, this.layer);
  final core.PageObject object;
  final int offsetMs;
  final InkObjectLayer layer;
}

/// The linked objects of a content, per recording (offset order, ties: z order).
final class PlaybackObjectIndex {
  InkPageContent? _content;
  final Map<String, List<PlaybackObjectEntry>> _tracks = {};

  /// Drops the tracks when [content] is another content.
  void update(InkPageContent content) {
    if (identical(content, _content)) return;
    _content = content;
    _tracks.clear();
  }

  /// The objects of [recordingId] (empty when none).
  List<PlaybackObjectEntry> trackOf(String recordingId) {
    final content = _content;
    if (content == null) return const [];
    return _tracks[recordingId] ??= () {
      final out = <PlaybackObjectEntry>[
        for (final o in content.objects)
          if (o.recordingId == recordingId)
            if (o.recordingOffsetMs case final offset?)
              PlaybackObjectEntry(o, offset, objectLayerOf(o)),
      ];
      // a stable sort keeps the z order of equal offsets
      final indexed = [for (var i = 0; i < out.length; i++) (i, out[i])]
        ..sort((a, b) {
          final c = a.$2.offsetMs.compareTo(b.$2.offsetMs);
          return c != 0 ? c : a.$1.compareTo(b.$1);
        });
      return List<PlaybackObjectEntry>.unmodifiable([
        for (final (_, e) in indexed) e,
      ]);
    }();
  }

  /// The objects of [focus] (normalized) to veil in [layers], z order; empty unless
  /// the style is dimUnwritten. [hidden]: objects the page does not draw now.
  List<core.PageObject> unwritten(
    InkPlaybackFocus focus,
    Set<InkObjectLayer> layers,
    Set<String> hidden,
  ) {
    if (focus.style != InkPlaybackStyle.dimUnwritten) return const [];
    final track = trackOf(focus.recordingId);
    if (track.isEmpty) return const [];
    final p = focus.positionMs;
    final ids = <String>{
      for (final e in track)
        if (e.offsetMs > p &&
            layers.contains(e.layer) &&
            !hidden.contains(e.object.id))
          e.object.id,
    };
    if (ids.isEmpty) return const [];
    return [
      for (final o in _content!.objects)
        if (ids.contains(o.id)) o,
    ];
  }

  /// What the annotation layer's veil depends on: the recording and the ids of its
  /// veiled annotation objects (null: none veiled).
  String? annotationKey(InkPlaybackFocus? focus) {
    if (focus == null) return null;
    final veiled = unwritten(normalizedPlaybackFocus(focus), const {
      InkObjectLayer.annotation,
    }, const {});
    if (veiled.isEmpty) return null;
    return '${focus.recordingId}:${veiled.map((o) => o.id).join(',')}';
  }
}

/// Veils [objects] (see the file comment). [paperArgb]: the page's paper.
void paintObjectVeils(
  ui.Canvas canvas,
  List<core.PageObject> objects, {
  required int paperArgb,
  required double onePx,
  MathRaster? Function(core.MathObject o)? mathRasterOf,
}) {
  if (objects.isEmpty) return;
  ui.Rect? bounds;
  for (final o in objects) {
    final b = o.bounds;
    final r = ui.Rect.fromLTRB(b.left, b.top, b.right, b.bottom);
    bounds = bounds == null ? r : bounds.expandToInclude(r);
  }
  final alpha = ((1 - InkTuning.playbackDimOpacity) * 255).round();
  canvas.saveLayer(
    bounds!.inflate(2 * onePx),
    ui.Paint()
      ..color = ui.Color.fromARGB(alpha, 0, 0, 0)
      ..colorFilter = ui.ColorFilter.mode(
        ui.Color(0xFF000000 | (paperArgb & 0xFFFFFF)),
        ui.BlendMode.srcIn,
      ),
  );
  for (final o in objects) {
    if (o is core.ImageObject) {
      final corners = o.frame.corners;
      canvas.drawPath(
        ui.Path()
          ..addPolygon([for (final c in corners) ui.Offset(c.x, c.y)], true),
        ui.Paint()..color = const ui.Color(0xFF000000),
      );
      continue;
    }
    paintObjectSimple(
      canvas,
      o,
      paperArgb: paperArgb,
      onePx: onePx,
      mathRasterOf: mathRasterOf,
    );
  }
  canvas.restore();
}
