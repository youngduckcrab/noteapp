// lib/src/render/playback_painter.dart — INTERNAL (m5-7/03-ink 6.19, T40, K-7, K-9).
//
// The playback emphasis, drawn at layer 4′ (the end of inkActive: above every ink
// item, below the annotation and cover layers — text, formulas and covered tapes
// are never changed by it, K-9). The base chunks and raster tiles are untouched
// (K-7): setPlaybackFocus only repaints inkActive.
//
// dimUnwritten
//   veil      the outline of an unwritten ink-layer stroke filled with the paper
//             color at 1 − playbackDimOpacity — the stroke looks like
//             playbackDimOpacity of its density (highlighter and tape strokes are
//             not dimmed — CP-INK-8)
//   blocks    the track in blocks of playbackVeilBlock entries: one cached veil
//             path (the block's outlines in one nonZero path — overlapping
//             unwritten strokes are veiled once) per wholly unwritten block, one
//             for the unwritten part of the boundary block (built again only when
//             the boundary moves inside it — ≤ playbackVeilBlock strokes), and the
//             not yet written points of the writing strokes: the round-capped
//             band of its remaining points stroked in the veil color, clipped to
//             the stroke's outline (two operations — cheap to record every frame)
// both styles
//   emphasis  the outline of every recent stroke (any layer) stroked in
//             playbackEmphasisArgb, playbackEmphasisWidthPx logical px wide, at
//             opacity 0.8 (one layer — overlaps are not darker); the list is
//             built again when the recent range changes
//
// Why paths and not recorded pictures (T43, B15): the inkActive layer is recorded
// again every frame, and drawing a recorded picture into a recording costs time
// in proportion to the operations inside it (measured: 47 block pictures of 64
// paths ≈ 1.5 ms a frame on the debug VM), while one drawPath of a cached path is
// one operation whatever its size (47 block paths ≈ 0.015 ms).
import 'dart:ui' as ui;

import '../geometry/stroke_outline.dart';
import '../model/ink_layer.dart';
import '../model/ink_stroke.dart';
import '../tuning.dart';
import 'playback.dart';
import 'playback_index.dart';

/// (tests, benchmarks) What the painter built.
final class PlaybackPaintStats {
  /// Veil paths built (blocks, boundary parts, writing remainders).
  int veilRecords = 0;

  /// Strokes put into those paths.
  int veilStrokes = 0;

  /// Emphasis paths built.
  int emphasisRecords = 0;

  /// Strokes put into the emphasis paths.
  int emphasisStrokes = 0;

  /// Strokes put into paths (veil + emphasis) by the last paint.
  int lastPaintStrokes = 0;

  /// Paints of the layer 4′ playback stage.
  int paints = 0;
}

final class PlaybackPainter {
  final PlaybackPaintStats stats = PlaybackPaintStats();

  static const double _emphasisOpacity = 0.8;

  // what every veil path depends on
  PlaybackTrack? _track;
  int? _paper;
  Set<String> _hidden = const {};

  final Map<int, ui.Path?> _blocks = {};
  _Edge? _edge;
  final Map<InkStroke, _Remainder> _remainders = {};
  _Emphasis? _emphasis;

  /// Paints the emphasis of [focus] (normalized) over [track]. [hidden]: strokes
  /// the page does not draw now (pending removals, live overrides, …) — neither
  /// veiled nor outlined.
  void paint(
    ui.Canvas canvas, {
    required PlaybackTrack track,
    required InkPlaybackFocus focus,
    required double viewScale,
    required int paperArgb,
    required Set<String> hidden,
    required StrokeOutline Function(InkStroke stroke) outlineOf,
  }) {
    var built = 0;
    if (!identical(track, _track) ||
        paperArgb != _paper ||
        !_sameSet(hidden, _hidden)) {
      clear();
      _track = track;
      _paper = paperArgb;
      _hidden = hidden;
    }
    final p = focus.positionMs;
    if (focus.style == InkPlaybackStyle.dimUnwritten) {
      built += _paintVeils(canvas, track, p, viewScale, outlineOf);
    }
    final (start, end) = track.recentRange(p, focus.recentWindowMs);
    if (start < end) {
      var e = _emphasis;
      if (e == null || e.start != start || e.end != end) {
        final paths = <ui.Path>[];
        ui.Rect? bounds;
        for (var i = start; i < end; i++) {
          final s = track.entries[i].stroke;
          if (_hidden.contains(s.id)) continue;
          final outline = outlineOf(s);
          paths.add(outline.toPath());
          bounds = bounds == null
              ? outline.bounds
              : bounds.expandToInclude(outline.bounds);
        }
        e = _emphasis = _Emphasis(start, end, paths, bounds);
        stats
          ..emphasisRecords += 1
          ..emphasisStrokes += paths.length;
        built += paths.length;
      }
      final bounds = e.bounds;
      if (bounds != null) {
        final width = InkTuning.playbackEmphasisWidthPx / viewScale;
        final paint = ui.Paint()
          ..isAntiAlias = true
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = ui.StrokeJoin.round
          ..color = const ui.Color(InkTuning.playbackEmphasisArgb);
        canvas.saveLayer(
          bounds.inflate(width),
          ui.Paint()..color = _withOpacity(0, _emphasisOpacity),
        );
        for (final path in e.paths) {
          canvas.drawPath(path, paint);
        }
        canvas.restore();
      }
    }
    stats
      ..lastPaintStrokes = built
      ..paints += 1;
  }

  /// Drops every cached path (focus off, track gone, dispose).
  void clear() {
    _blocks.clear();
    _edge = null;
    _remainders.clear();
    _emphasis = null;
    _track = null;
    _paper = null;
    _hidden = const {};
  }

  int _paintVeils(
    ui.Canvas canvas,
    PlaybackTrack track,
    int p,
    double viewScale,
    StrokeOutline Function(InkStroke stroke) outlineOf,
  ) {
    const block = InkTuning.playbackVeilBlock;
    final n = track.length;
    final k = track.boundary(p);
    var built = 0;
    final paint = _veilPaint(_paper!);
    // the not yet written points of the writing strokes
    final keep = <InkStroke>{};
    for (final i in track.writing(p)) {
      final s = track.entries[i].stroke;
      if (!_veiled(s)) continue;
      keep.add(s);
      final from = track.firstUnwrittenPoint(i, p);
      if (from >= s.points.length) continue;
      var r = _remainders[s];
      if (r == null || r.from != from) {
        r = _remainders[s] = _Remainder(from, _bandOf(s, from));
        stats
          ..veilRecords += 1
          ..veilStrokes += 1;
        built += 1;
      }
      _drawRemainder(canvas, s, r, viewScale, outlineOf, paint);
    }
    _remainders.removeWhere((s, _) => !keep.contains(s));
    if (k >= n) {
      _edge = null;
      return built;
    }
    // the boundary block: its unwritten part [k, block end)
    final edgeBlock = k ~/ block;
    var firstFull = edgeBlock;
    if (k % block != 0) {
      firstFull = edgeBlock + 1;
      var edge = _edge;
      if (edge == null || edge.from != k) {
        final (path, count) = _buildPath(
          track,
          k,
          _min(n, firstFull * block),
          outlineOf,
          _veiled,
        );
        edge = _edge = _Edge(k, path);
        stats
          ..veilRecords += 1
          ..veilStrokes += count;
        built += count;
      }
      final path = edge.path;
      if (path != null) canvas.drawPath(path, paint);
    } else {
      _edge = null;
    }
    // the wholly unwritten blocks
    final blocks = (n + block - 1) ~/ block;
    for (var b = firstFull; b < blocks; b++) {
      ui.Path? path;
      if (_blocks.containsKey(b)) {
        path = _blocks[b];
      } else {
        final (built_, count) = _buildPath(
          track,
          b * block,
          _min(n, (b + 1) * block),
          outlineOf,
          _veiled,
        );
        path = _blocks[b] = built_;
        stats
          ..veilRecords += 1
          ..veilStrokes += count;
        built += count;
      }
      if (path != null) canvas.drawPath(path, paint);
    }
    return built;
  }

  bool _veiled(InkStroke s) =>
      s.layer == InkLayer.ink && !_hidden.contains(s.id);

  /// The outlines of the entries [from, to) that pass [include], in one nonZero
  /// path (every outline is positively oriented — overlaps are a union); null
  /// when none passes.
  (ui.Path?, int) _buildPath(
    PlaybackTrack track,
    int from,
    int to,
    StrokeOutline Function(InkStroke stroke) outlineOf,
    bool Function(InkStroke stroke) include,
  ) {
    ui.Path? path;
    var count = 0;
    for (var i = from; i < to; i++) {
      final s = track.entries[i].stroke;
      if (!include(s)) continue;
      (path ??= ui.Path()..fillType = ui.PathFillType.nonZero).addPath(
        outlineOf(s).toPath(),
        ui.Offset.zero,
      );
      count++;
    }
    return (path, count);
  }

  /// The centerline of [s] from point [from] on (a single point: a zero-length
  /// line, which a round cap draws as a disc).
  static ui.Path _bandOf(InkStroke s, int from) {
    final points = s.points;
    final band = ui.Path()..moveTo(points.x(from), points.y(from));
    if (from == points.length - 1) {
      band.lineTo(points.x(from), points.y(from));
    }
    for (var i = from + 1; i < points.length; i++) {
      band.lineTo(points.x(i), points.y(i));
    }
    return band;
  }

  /// The veil of [s]'s outline kept only inside the round-capped band (radius =
  /// the stroke's widest radius + 1 logical px) along its remaining points: the
  /// band stroked in the veil color, clipped to the outline (one stroked path —
  /// its self-overlaps are not veiled twice).
  void _drawRemainder(
    ui.Canvas canvas,
    InkStroke s,
    _Remainder r,
    double viewScale,
    StrokeOutline Function(InkStroke stroke) outlineOf,
    ui.Paint paint,
  ) {
    final outline = outlineOf(s).toPath();
    if (r.from <= 0) {
      canvas.drawPath(outline, paint);
      return;
    }
    canvas
      ..save()
      ..clipPath(outline)
      ..drawPath(
        r.band,
        ui.Paint()
          ..isAntiAlias = true
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 2 * (s.maxRadius + 1 / viewScale)
          ..strokeCap = ui.StrokeCap.round
          ..strokeJoin = ui.StrokeJoin.round
          ..color = paint.color,
      )
      ..restore();
  }

  static ui.Paint _veilPaint(int paperArgb) => ui.Paint()
    ..isAntiAlias = true
    ..style = ui.PaintingStyle.fill
    ..color = _withOpacity(paperArgb, 1 - InkTuning.playbackDimOpacity);

  static ui.Color _withOpacity(int argb, double opacity) {
    final alpha = (opacity * 255).round();
    return ui.Color(alpha * 0x1000000 + argb % 0x1000000);
  }

  static int _min(int a, int b) => a < b ? a : b;

  static bool _sameSet(Set<String> a, Set<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}

final class _Edge {
  _Edge(this.from, this.path);
  final int from;
  final ui.Path? path;
}

final class _Remainder {
  _Remainder(this.from, this.band);
  final int from;
  final ui.Path band;
}

final class _Emphasis {
  _Emphasis(this.start, this.end, this.paths, this.bounds);
  final int start;
  final int end;

  /// The cached outline paths of the recent strokes (one draw each, inside one
  /// layer at 0.8 — overlaps are not darker).
  final List<ui.Path> paths;
  final ui.Rect? bounds;
}
