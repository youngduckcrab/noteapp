// lib/src/render/base_cache.dart — INTERNAL (03-ink 6.12 R2–R4, 6.10-6/-7,
// 6.13 L2/L4).
//
// The vector caches of the two base layers of one page:
// - InkContentDiff: what changed between two InkPageContents (by id + object
//   identity, K-4) — R2.
// - InkChunkCache: the ink layer cut into chunkSizePt chunks, one Picture per
//   chunk plus small 'appended' Pictures for strokes added on top (R3, R4).
// - HighlighterBaseCache: one page Picture of the highlighter groups that are
//   not being written, and the opaque Picture of each group that is (6.10-6).
// The raster tiles of the ink chunks (6.13 L3) are in raster_tiles.dart.
import 'dart:ui' as ui;

import 'package:meta/meta.dart';

import '../model/ink_layer.dart';
import '../model/ink_stroke.dart';
import 'highlighter_compositor.dart';
import 'ink_page_content.dart';
import 'stroke_painter.dart';

/// R2: the change from one content to the next, by id + object identity. O(n).
@immutable
final class InkContentDiff {
  const InkContentDiff._({
    required this.isNoop,
    required this.isReset,
    required this.backgroundChanged,
    required this.appended,
    required this.inserted,
    required this.removed,
    required this.changed,
  });

  factory InkContentDiff.between(InkPageContent? old, InkPageContent now) {
    if (old != null && old == now) return _noop;
    if (old == null || old.page.size != now.page.size) {
      return InkContentDiff._(
        isNoop: false,
        isReset: true,
        backgroundChanged: true,
        appended: const [],
        inserted: const [],
        removed: const [],
        changed: const [],
      );
    }
    final strokes = now.strokes;
    // the run of new ids at the top of the z order is appended (R3)
    var suffixStart = strokes.length;
    while (suffixStart > 0 &&
        old.strokeById(strokes[suffixStart - 1].id) == null) {
      suffixStart--;
    }
    final inserted = <InkStroke>[];
    final changed = <(InkStroke, InkStroke)>[];
    for (var i = 0; i < suffixStart; i++) {
      final s = strokes[i];
      final before = old.strokeById(s.id);
      if (before == null) {
        inserted.add(s);
      } else if (!identical(before.source, s.source)) {
        changed.add((before, s));
      }
    }
    final removed = <InkStroke>[
      for (final s in old.strokes)
        if (now.strokeById(s.id) == null) s,
    ];
    return InkContentDiff._(
      isNoop: false,
      isReset: false,
      backgroundChanged: old.page.background != now.page.background,
      appended: List.unmodifiable(strokes.sublist(suffixStart)),
      inserted: List.unmodifiable(inserted),
      removed: List.unmodifiable(removed),
      changed: List.unmodifiable(changed),
    );
  }

  static const InkContentDiff _noop = InkContentDiff._(
    isNoop: true,
    isReset: false,
    backgroundChanged: false,
    appended: [],
    inserted: [],
    removed: [],
    changed: [],
  );

  /// Same page, revision and stroke objects: nothing to do.
  final bool isNoop;

  /// First content or another page size: every cache starts over.
  final bool isReset;

  /// Paper color / kind changed (the highlighter blend depends on it, 6.10-4).
  final bool backgroundChanged;

  /// New ids forming the top of the z order, bottom → top (R3 append).
  final List<InkStroke> appended;

  /// New ids below kept strokes (e.g. undo of an old stroke) → dirty.
  final List<InkStroke> inserted;

  /// Old objects of the ids that are gone → dirty.
  final List<InkStroke> removed;

  /// (old, new) objects of the same id → dirty at both places.
  final List<(InkStroke, InkStroke)> changed;

  /// Every stroke whose layer may need a new picture (old and new objects).
  Iterable<InkStroke> get touched sync* {
    yield* appended;
    yield* inserted;
    yield* removed;
    for (final (a, b) in changed) {
      yield a;
      yield b;
    }
  }

  @override
  String toString() => isNoop
      ? 'InkContentDiff(no-op)'
      : isReset
      ? 'InkContentDiff(reset)'
      : 'InkContentDiff(+${appended.length} append, +${inserted.length} '
            'insert, -${removed.length}, ~${changed.length})';
}

/// Draws one stroke into a picture being recorded.
typedef InkStrokeDraw = void Function(ui.Canvas canvas, InkStroke stroke);

/// Draws chunk [index] some other way (a raster tile, 6.13-5); false → the
/// vector picture is drawn.
typedef InkChunkDraw = bool Function(ui.Canvas canvas, int index);

/// R3/R4, 6.13 L2: the ink layer as chunkSizePt × chunkSizePt Pictures.
/// A chunk records the strokes that overlap it (z order), clipped to its
/// rectangle without anti-aliasing so neighbouring chunks never paint a pixel
/// twice. The outer chunks reach far past the page (the view clips).
///
/// 6.13 time slicing: a chunk not recorded since [reset] (the page has just
/// been shown) is recorded stroke by stroke within a frame budget, visible
/// chunks first, and stays blank until it is complete. A chunk recorded
/// before that an edit made dirty is recorded in full at the next paint, so
/// an edit never blanks a chunk.
final class InkChunkCache {
  InkChunkCache({
    required this.chunkSizePt,
    required this.maxAppended,
    this.onChunkCleared,
  }) : assert(chunkSizePt > 0);

  final double chunkSizePt;

  /// More appended pictures than this → the chunk is re-recorded (R4).
  final int maxAppended;

  /// A chunk's pictures were dropped (dirty, consolidated, reset): its raster
  /// tiles are stale (6.13-6).
  final void Function(int index)? onChunkCleared;

  /// CORE bounds hold the outline (K-1); this covers the anti-aliased fringe.
  static const double marginPt = 4;

  /// How far the outer chunks reach past the page.
  static const double _farPt = 1e5;

  int _cols = 0;
  int _rows = 0;
  ui.Size _pageSize = ui.Size.zero;
  List<_Chunk> _chunks = const [];
  int _recordCount = 0;
  bool _disposed = false;

  int get columns => _cols;
  int get rows => _rows;
  int get chunkCount => _chunks.length;

  /// Chunk pictures + appended pictures (InkPageRenderStats.chunkPictures).
  int get pictureCount {
    var n = 0;
    for (final c in _chunks) {
      if (c.picture != null) n++;
      n += c.appended.length;
    }
    return n;
  }

  /// Chunks waiting to be recorded at the next paint.
  int get dirtyCount => _chunks.where((c) => c.picture == null).length;

  /// Chunks not recorded since the last [reset] (still blank, 6.13).
  int get loadingCount => _chunks.where((c) => !c.loaded).length;

  /// Times a chunk was (re-)recorded — appends do not count.
  @visibleForTesting
  int get recordCount => _recordCount;

  @visibleForTesting
  int appendedCountAt(int col, int row) =>
      _chunks[row * _cols + col].appended.length;

  @visibleForTesting
  bool isDirtyAt(int col, int row) =>
      _chunks[row * _cols + col].picture == null;

  /// New grid for [pageSize]; every chunk dirty and loading.
  void reset(ui.Size pageSize) {
    _disposeAll();
    if (_disposed) return;
    _pageSize = pageSize;
    _cols = (pageSize.width / chunkSizePt).ceil().clamp(1, 1000000);
    _rows = (pageSize.height / chunkSizePt).ceil().clamp(1, 1000000);
    _chunks = [for (var i = 0; i < _cols * _rows; i++) _Chunk()];
  }

  /// The chunks [pageRect] (+ [marginPt]) touches are recorded again.
  void markDirty(ui.Rect pageRect) {
    for (final i in _indicesFor(pageRect)) {
      _clearAt(i);
    }
  }

  void markAllDirty() {
    for (var i = 0; i < _chunks.length; i++) {
      _clearAt(i);
    }
  }

  /// R3: [stroke] lies on top of everything recorded — one small picture per
  /// chunk it touches; a dirty chunk will include it when it is recorded.
  void append(InkStroke stroke, InkStrokeDraw draw) {
    for (final i in _indicesFor(stroke.bounds)) {
      final chunk = _chunks[i];
      if (chunk.picture == null) {
        // a recording in progress takes it as its new top stroke
        chunk.partial?.strokes.add(stroke);
        continue;
      }
      if (chunk.appended.length >= maxAppended) {
        _clearAt(i); // consolidate (R4)
        continue;
      }
      chunk.appended.add(_record(i, [stroke], draw));
    }
  }

  /// Records the dirty chunks from [zOrdered] (the visible ink strokes,
  /// bottom → top). Chunks recorded before are recorded in full; loading
  /// chunks in [order] (every index, highest priority first; default: index
  /// order) until [outOfTime] — asked after each stroke, so a call always
  /// makes progress — says the budget is spent. True when every chunk has
  /// its picture.
  bool record(
    Iterable<InkStroke> zOrdered,
    InkStrokeDraw draw, {
    List<int>? order,
    bool Function()? outOfTime,
  }) {
    if (_chunks.isEmpty) return true;
    final need = <int, List<InkStroke>>{
      for (var i = 0; i < _chunks.length; i++)
        if (_chunks[i].picture == null && _chunks[i].partial == null)
          i: <InkStroke>[],
    };
    if (need.isEmpty && _chunks.every((c) => c.picture != null)) return true;
    if (need.isNotEmpty) {
      for (final s in zOrdered) {
        for (final i in _indicesFor(s.bounds)) {
          need[i]?.add(s);
        }
      }
    }
    // edits: in full now (never blank a chunk that was shown)
    for (final MapEntry(key: i, value: strokes) in need.entries) {
      final c = _chunks[i];
      if (!c.loaded) continue;
      c.picture = _record(i, strokes, draw);
      c.recordedStrokes = strokes.length;
      _recordCount++;
    }
    // loading: stroke by stroke within the budget, [order] first
    var spent = false;
    for (final i in order ?? Iterable<int>.generate(_chunks.length)) {
      final c = _chunks[i];
      if (c.picture != null) continue;
      if (spent) return false;
      final p = c.partial ??= _Partial(_clipRectOf(i), need[i] ?? []);
      while (p.next < p.strokes.length) {
        draw(p.canvas, p.strokes[p.next++]);
        if (outOfTime != null && outOfTime()) {
          spent = true;
          break;
        }
      }
      if (p.next < p.strokes.length) return false;
      c
        ..picture = p.recorder.endRecording()
        ..recordedStrokes = p.strokes.length
        ..loaded = true
        ..partial = null;
      _recordCount++;
    }
    return _chunks.every((c) => c.picture != null);
  }

  /// Draws every recorded chunk with its appended pictures — or through
  /// [other] (a raster tile) when it says so. Loading chunks stay blank.
  void drawChunks(ui.Canvas canvas, {InkChunkDraw? other}) {
    for (var i = 0; i < _chunks.length; i++) {
      final c = _chunks[i];
      final picture = c.picture;
      if (picture == null) continue;
      if (other != null && other(canvas, i)) continue;
      canvas.drawPicture(picture);
      for (final p in c.appended) {
        canvas.drawPicture(p);
      }
    }
  }

  /// [record] everything, then [drawChunks].
  void paint(
    ui.Canvas canvas,
    Iterable<InkStroke> zOrdered,
    InkStrokeDraw draw,
  ) {
    record(zOrdered, draw);
    drawChunks(canvas);
  }

  // --- chunk access (raster tiles, 6.13 L3) ----------------------------------

  /// The chunk's recorded picture; null while dirty or loading.
  ui.Picture? pictureOf(int index) => _chunks[index].picture;

  /// The chunk's appended pictures, bottom → top.
  List<ui.Picture> appendedOf(int index) => _chunks[index].appended;

  /// Bumped whenever the chunk's pictures are dropped.
  int generationOf(int index) => _chunks[index].generation;

  /// Strokes drawn by the chunk's picture and appended pictures.
  int strokeCountOf(int index) {
    final c = _chunks[index];
    return c.recordedStrokes + c.appended.length;
  }

  /// The chunk's grid cell in page pt (not reaching past the page).
  ui.Rect cellRectOf(int index) {
    final col = index % _cols;
    final row = index ~/ _cols;
    return ui.Rect.fromLTWH(
      col * chunkSizePt,
      row * chunkSizePt,
      chunkSizePt,
      chunkSizePt,
    );
  }

  /// The part of the page the chunk shows (its cell ∩ the page).
  ui.Rect pageRectOf(int index) =>
      cellRectOf(index).intersect(ui.Offset.zero & _pageSize);

  /// Every chunk index: those meeting [visible] (null = the whole page)
  /// first, then by the distance of their centre to its centre.
  List<int> priorityOrder(ui.Rect? visible) {
    final v = visible ?? (ui.Offset.zero & _pageSize);
    final centre = v.center;
    final keyed =
        [
          for (var i = 0; i < _chunks.length; i++)
            (
              i,
              cellRectOf(i).overlaps(v) ? 0 : 1,
              (cellRectOf(i).center - centre).distanceSquared,
            ),
        ]..sort((a, b) {
          final byVisible = a.$2.compareTo(b.$2);
          if (byVisible != 0) return byVisible;
          final byDistance = a.$3.compareTo(b.$3);
          return byDistance != 0 ? byDistance : a.$1.compareTo(b.$1);
        });
    return [for (final k in keyed) k.$1];
  }

  /// Draws [stroke] the way a chunk picture would: once per chunk it touches,
  /// under that chunk's clip. Skia rasterizes the anti-aliased edge of a
  /// path differently when a clip cuts it, so a pending stroke drawn like
  /// this hands over to its chunk pictures pixel for pixel (6.12 R6).
  void paintClipped(ui.Canvas canvas, InkStroke stroke, InkStrokeDraw draw) {
    if (_chunks.isEmpty) {
      draw(canvas, stroke);
      return;
    }
    for (final i in _indicesFor(stroke.bounds)) {
      canvas
        ..save()
        ..clipRect(_clipRectOf(i), doAntiAlias: false);
      draw(canvas, stroke);
      canvas.restore();
    }
  }

  void dispose() {
    _disposed = true;
    _disposeAll();
  }

  void _clearAt(int index) {
    _chunks[index].clear();
    onChunkCleared?.call(index);
  }

  void _disposeAll() {
    for (var i = 0; i < _chunks.length; i++) {
      _clearAt(i);
    }
    _chunks = const [];
    _cols = 0;
    _rows = 0;
  }

  ui.Picture _record(int index, List<InkStroke> strokes, InkStrokeDraw draw) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..clipRect(_clipRectOf(index), doAntiAlias: false);
    for (final s in strokes) {
      draw(canvas, s);
    }
    return recorder.endRecording();
  }

  /// The chunk's page tile; the outer edges reach [_farPt] past the page.
  ui.Rect _clipRectOf(int index) {
    final col = index % _cols;
    final row = index ~/ _cols;
    return ui.Rect.fromLTRB(
      col == 0 ? -_farPt : col * chunkSizePt,
      row == 0 ? -_farPt : row * chunkSizePt,
      col == _cols - 1 ? _farPt : (col + 1) * chunkSizePt,
      row == _rows - 1 ? _farPt : (row + 1) * chunkSizePt,
    );
  }

  Iterable<int> _indicesFor(ui.Rect pageRect) sync* {
    if (_chunks.isEmpty) return;
    final r = pageRect.inflate(marginPt);
    if (!r.isFinite) {
      yield* Iterable<int>.generate(_chunks.length);
      return;
    }
    final c0 = (r.left / chunkSizePt).floor().clamp(0, _cols - 1);
    final c1 = (r.right / chunkSizePt).floor().clamp(0, _cols - 1);
    final r0 = (r.top / chunkSizePt).floor().clamp(0, _rows - 1);
    final r1 = (r.bottom / chunkSizePt).floor().clamp(0, _rows - 1);
    for (var row = r0; row <= r1; row++) {
      for (var col = c0; col <= c1; col++) {
        yield row * _cols + col;
      }
    }
  }
}

final class _Chunk {
  ui.Picture? picture;
  final List<ui.Picture> appended = [];

  /// Strokes in [picture].
  int recordedStrokes = 0;

  /// Recorded at least once since the grid was made.
  bool loaded = false;

  /// A loading recording that ran out of frame budget.
  _Partial? partial;

  int generation = 0;

  void clear() {
    picture?.dispose();
    picture = null;
    recordedStrokes = 0;
    for (final p in appended) {
      p.dispose();
    }
    appended.clear();
    partial?.recorder.endRecording().dispose();
    partial = null;
    generation++;
  }
}

/// A chunk recording resumed in the next frame (6.13 time slicing).
final class _Partial {
  _Partial(ui.Rect clip, this.strokes) : recorder = ui.PictureRecorder() {
    canvas = ui.Canvas(recorder)..clipRect(clip, doAntiAlias: false);
  }

  final ui.PictureRecorder recorder;
  late final ui.Canvas canvas;

  /// Bottom → top; appends land at the end.
  final List<InkStroke> strokes;
  int next = 0;
}

/// The opaque lines of one highlighter group, recorded once (6.10-2).
final class HighlighterGroupPicture {
  HighlighterGroupPicture._(this.picture, this.bounds);
  final ui.Picture picture;
  final ui.Rect bounds;
}

/// 6.10-6/-7, 6.13 L4: one page Picture of the highlighter groups whose key is
/// not active, plus the opaque Picture of each active group's committed lines
/// (composited with the stroke being written by the active layer).
final class HighlighterBaseCache {
  ui.Picture? _base;
  Set<HighlighterGroupKey> _baseExcluded = const {};
  int _basePaper = 0;
  double _baseMargin = -1;
  final Map<HighlighterGroupKey, HighlighterGroupPicture?> _groups = {};
  int _recordCount = 0;

  /// Times the page picture was recorded.
  @visibleForTesting
  int get recordCount => _recordCount;

  /// The highlighter strokes changed: record everything again when painted.
  void markDirty() {
    _base?.dispose();
    _base = null;
    _disposeGroups();
  }

  /// Paints the groups of [zOrdered] (visible committed highlighters) whose
  /// key is not in [excluded], from the cached page picture.
  void paintBase(
    ui.Canvas canvas,
    Iterable<InkStroke> zOrdered, {
    required Set<HighlighterGroupKey> excluded,
    required int paperColorArgb,
    required double marginPt,
  }) {
    if (_base == null ||
        paperColorArgb != _basePaper ||
        marginPt != _baseMargin ||
        !_sameKeys(excluded, _baseExcluded)) {
      _base?.dispose();
      final recorder = ui.PictureRecorder();
      paintHighlighterGroups(
        ui.Canvas(recorder),
        groupHighlighters([
          for (final s in zOrdered)
            if (s.layer == InkLayer.highlighter &&
                !excluded.contains(HighlighterGroupKey.of(s.style)))
              s,
        ]),
        paperColorArgb: paperColorArgb,
        marginPt: marginPt,
      );
      _base = recorder.endRecording();
      _baseExcluded = Set.of(excluded);
      _basePaper = paperColorArgb;
      _baseMargin = marginPt;
      _recordCount++;
    }
    canvas.drawPicture(_base!);
  }

  /// The opaque lines of the committed strokes of [key] among [zOrdered];
  /// null when the group has none. Cached until [markDirty].
  HighlighterGroupPicture? groupOpaque(
    HighlighterGroupKey key,
    Iterable<InkStroke> zOrdered,
  ) => _groups.putIfAbsent(key, () {
    final group = HighlighterGroup(key);
    for (final s in zOrdered) {
      if (s.layer == InkLayer.highlighter &&
          HighlighterGroupKey.of(s.style) == key) {
        group.lines.add(HighlighterLine.of(s));
      }
    }
    if (group.lines.isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paintColor = ui.Color(key.colorArgb);
    for (final line in group.lines) {
      drawHighlighterLine(
        canvas,
        line.xy,
        highlighterLinePaint(line.width, paintColor),
      );
    }
    return HighlighterGroupPicture._(recorder.endRecording(), group.bounds);
  });

  /// Drops the group pictures of keys that are no longer active.
  void retainGroups(Set<HighlighterGroupKey> active) {
    _groups.removeWhere((key, g) {
      if (active.contains(key)) return false;
      g?.picture.dispose();
      return true;
    });
  }

  void dispose() => markDirty();

  void _disposeGroups() {
    for (final g in _groups.values) {
      g?.picture.dispose();
    }
    _groups.clear();
  }

  static bool _sameKeys(
    Set<HighlighterGroupKey> a,
    Set<HighlighterGroupKey> b,
  ) => a.length == b.length && a.containsAll(b);
}
