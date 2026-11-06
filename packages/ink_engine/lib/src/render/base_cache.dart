// lib/src/render/base_cache.dart — INTERNAL (03-ink 6.12 R2–R4, 6.10-6/-7,
// 6.13 L2/L4).
//
// The vector caches of the two base layers of one page:
// - InkContentDiff: what changed between two InkPageContents (by id + object
//   identity, K-4) — R2. (m5-7/03-ink 6.8.2, T32a) + the page objects per L-1
//   layer (InkObjectDiff) and the top run of new items of the merged ink layer
//   (strokes + shapes — inkAppended).
// - InkChunkCache: a layer cut into chunkSizePt chunks, one Picture per chunk
//   plus small 'appended' Pictures for items added on top (R3, R4). (m5-7/03-ink
//   6.8.3, T32b) The items are InkLayerItems — the ink layer's strokes and
//   shapes (z mixed), the underlay's images, the annotation's text boxes /
//   formulas / unknown objects — and every chunk remembers the draw keys of
//   what it drew (assets, fonts, hairlines — 6.11.3), so a key change records
//   only the chunks that drew it.
// - CoverPictureCache: (T32b) one page Picture of the committed tapes.
// - HighlighterBaseCache: one page Picture of the highlighter groups that are
//   not being written, and the opaque Picture of each group that is (6.10-6).
// The raster tiles of the ink chunks (6.13 L3) are in raster_tiles.dart.
import 'dart:ui' as ui;

import 'package:meta/meta.dart';

import '../model/ink_layer.dart';
import '../model/ink_stroke.dart';
import '../object/object_view.dart';
import 'highlighter_compositor.dart';
import 'ink_page_content.dart';
import 'stroke_painter.dart';

/// (m5-7/03-ink 6.8.2) The object changes of one L-1 layer, by id + instance.
@immutable
final class InkObjectDiff {
  const InkObjectDiff({
    this.appended = const [],
    this.inserted = const [],
    this.removed = const [],
    this.changed = const [],
  });

  /// New ids at the top of the layer (the ink layer: of the merged strokes +
  /// shapes), bottom → top — appended pictures (R3).
  final List<InkObjectView> appended;

  /// New ids below kept items → dirty.
  final List<InkObjectView> inserted;

  /// Views of the ids that left the layer → dirty where they were.
  final List<InkObjectView> removed;

  /// (old, new) views of the same id → dirty at both places.
  final List<(InkObjectView, InkObjectView)> changed;

  bool get isEmpty =>
      appended.isEmpty &&
      inserted.isEmpty &&
      removed.isEmpty &&
      changed.isEmpty;

  /// Every view whose layer may need a new picture (old and new).
  Iterable<InkObjectView> get touched sync* {
    yield* appended;
    yield* inserted;
    yield* removed;
    for (final (a, b) in changed) {
      yield a;
      yield b;
    }
  }

  static const InkObjectDiff none = InkObjectDiff();

  /// The diff of one layer: [old] / [now] are that layer's views in z order;
  /// [appendable] = the ids allowed to count as appended (the new top run).
  factory InkObjectDiff._between(
    List<InkObjectView> old,
    List<InkObjectView> now,
    Set<String> appendable,
  ) {
    if (identical(old, now) || (old.isEmpty && now.isEmpty)) return none;
    final oldById = {for (final v in old) v.id: v};
    final nowIds = {for (final v in now) v.id};
    final appended = <InkObjectView>[];
    final inserted = <InkObjectView>[];
    final changed = <(InkObjectView, InkObjectView)>[];
    for (final v in now) {
      final before = oldById[v.id];
      if (before == null) {
        (appendable.contains(v.id) ? appended : inserted).add(v);
      } else if (!identical(before.object, v.object)) {
        changed.add((before, v));
      }
    }
    final removed = [
      for (final v in old)
        if (!nowIds.contains(v.id)) v,
    ];
    if (appended.isEmpty &&
        inserted.isEmpty &&
        removed.isEmpty &&
        changed.isEmpty) {
      return none;
    }
    return InkObjectDiff(
      appended: List.unmodifiable(appended),
      inserted: List.unmodifiable(inserted),
      removed: List.unmodifiable(removed),
      changed: List.unmodifiable(changed),
    );
  }

  @override
  String toString() =>
      'InkObjectDiff(+${appended.length} append, +${inserted.length} insert, '
      '-${removed.length}, ~${changed.length})';
}

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
    this.underlay = InkObjectDiff.none,
    this.shapes = InkObjectDiff.none,
    this.annotation = InkObjectDiff.none,
    this.inkAppended = const [],
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
    // objects (6.8.2): the appended run of each layer is its top run of new
    // ids — for the ink layer, of the merged strokes + shapes (a new shape
    // below a kept stroke is inserted, and so is a new stroke below a kept
    // shape for inkAppended)
    final oldUnderlay = objectViewsOf(old, InkObjectLayer.underlay);
    final oldShapes = objectViewsOf(old, InkObjectLayer.ink);
    final oldAnnotation = objectViewsOf(old, InkObjectLayer.annotation);
    final nowUnderlay = objectViewsOf(now, InkObjectLayer.underlay);
    final nowShapes = objectViewsOf(now, InkObjectLayer.ink);
    final nowAnnotation = objectViewsOf(now, InkObjectLayer.annotation);
    final oldShapeIds = {for (final v in oldShapes) v.id};
    final inkItems = inkLayerItemsOf(now);
    var inkStart = inkItems.length;
    while (inkStart > 0) {
      final item = inkItems[inkStart - 1];
      final isNew = switch (item) {
        InkStrokeItem(:final stroke) => old.strokeById(stroke.id) == null,
        InkObjectView(:final id) => !oldShapeIds.contains(id),
      };
      if (!isNew) break;
      inkStart--;
    }
    final inkAppended = inkItems.sublist(inkStart);
    return InkContentDiff._(
      isNoop: false,
      isReset: false,
      backgroundChanged: old.page.background != now.page.background,
      appended: List.unmodifiable(strokes.sublist(suffixStart)),
      inserted: List.unmodifiable(inserted),
      removed: List.unmodifiable(removed),
      changed: List.unmodifiable(changed),
      underlay: InkObjectDiff._between(
        oldUnderlay,
        nowUnderlay,
        _topNewIds(oldUnderlay, nowUnderlay),
      ),
      shapes: InkObjectDiff._between(oldShapes, nowShapes, {
        for (final item in inkAppended)
          if (item is InkObjectView) item.id,
      }),
      annotation: InkObjectDiff._between(
        oldAnnotation,
        nowAnnotation,
        _topNewIds(oldAnnotation, nowAnnotation),
      ),
      inkAppended: List.unmodifiable(inkAppended),
    );
  }

  /// The ids of the top run of [now] whose ids are not in [old].
  static Set<String> _topNewIds(
    List<InkObjectView> old,
    List<InkObjectView> now,
  ) {
    if (now.isEmpty) return const {};
    final oldIds = {for (final v in old) v.id};
    final out = <String>{};
    for (var i = now.length - 1; i >= 0; i--) {
      if (oldIds.contains(now[i].id)) break;
      out.add(now[i].id);
    }
    return out;
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

  /// (m5-7 T32a) ImageObject changes (underlay layer).
  final InkObjectDiff underlay;

  /// (m5-7 T32a) ShapeObject changes (ink layer); appended = the shapes of
  /// [inkAppended].
  final InkObjectDiff shapes;

  /// (m5-7 T32a) TextBoxObject / MathObject / UnknownObject changes.
  final InkObjectDiff annotation;

  /// (m5-7 T32a) The top run of new items of the merged ink layer (InkLayer.ink
  /// strokes + shapes), bottom → top: what the ink chunks may append (R3). On a
  /// reset or a no-op: empty.
  final List<InkLayerItem> inkAppended;

  /// No object changed in any layer.
  bool get objectsUnchanged =>
      underlay.isEmpty && shapes.isEmpty && annotation.isEmpty;

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
            'insert, -${removed.length}, ~${changed.length}; objects '
            '$underlay $shapes $annotation)';
}

/// Draws one stroke into a picture being recorded.
typedef InkStrokeDraw = void Function(ui.Canvas canvas, InkStroke stroke);

/// (m5-7 T32b) Draws one layer item (stroke or object) into a picture being recorded.
typedef InkItemDraw = void Function(ui.Canvas canvas, InkLayerItem item);

/// (m5-7 T32b, 6.11.3) The draw keys of [item] at the moment it is drawn: what its
/// picture depends on besides the item itself (an image asset, the fonts, the hairline
/// width). Asked right before the item is drawn into a chunk.
typedef InkDrawKeysOf = Iterable<Object> Function(InkLayerItem item);

/// (m5-7/03-ink 6.8.3, 6.11.3) The draw keys a chunk remembers. A key changes without a
/// content change (an image decoded at another bucket, NoteSans loaded, another zoom
/// octave); InkChunkCache.markDirtyWithKey records only the chunks that drew it.
@immutable
abstract final class InkDrawKeys {
  /// NoteSans was not loaded yet when a text box was drawn (the system font).
  static const Object fonts = #inkDrawKeyFonts;

  /// A 1-logical-px line was drawn (placeholders, 6.11.5 / 6.13): its width depends on the
  /// zoom octave the chunk was recorded at.
  static const Object hairline = #inkDrawKeyHairline;

  /// The image asset [assetId] was drawn (or its placeholder).
  static Object asset(String assetId) => (#inkDrawKeyAsset, assetId);
}

/// Draws chunk [index] some other way (a raster tile, 6.13-5); false → the
/// vector picture is drawn.
typedef InkChunkDraw = bool Function(ui.Canvas canvas, int index);

/// R3/R4, 6.13 L2: a layer as chunkSizePt × chunkSizePt Pictures. A chunk
/// records the items that overlap it (z order), clipped to its rectangle
/// without anti-aliasing so neighbouring chunks never paint a pixel twice. The
/// outer chunks reach far past the page (the view clips). (m5-7 T32b) Items are
/// InkLayerItems (the ink layer: strokes and shapes z mixed; underlay /
/// annotation: objects), and with [drawKeysOf] every chunk keeps the draw keys
/// of what it drew (markDirtyWithKey).
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
    this.drawKeysOf,
  }) : assert(chunkSizePt > 0);

  final double chunkSizePt;

  /// More appended pictures than this → the chunk is re-recorded (R4).
  final int maxAppended;

  /// A chunk's pictures were dropped (dirty, consolidated, reset): its raster
  /// tiles are stale (6.13-6).
  final void Function(int index)? onChunkCleared;

  /// (m5-7 T32b) The draw keys of an item as it is drawn; null = no keys kept.
  final InkDrawKeysOf? drawKeysOf;

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

  /// (m5-7 T32b, 6.11.3) Marks dirty the chunks that drew [key] (their draw keys);
  /// returns how many. A loading recording that drew it starts over.
  int markDirtyWithKey(Object key) {
    var n = 0;
    for (var i = 0; i < _chunks.length; i++) {
      final c = _chunks[i];
      if (c.keys.contains(key) || (c.partial?.keys.contains(key) ?? false)) {
        _clearAt(i);
        n++;
      }
    }
    return n;
  }

  /// The draw keys of chunk ([col], [row]): those of its picture and appended pictures.
  @visibleForTesting
  Set<Object> drawKeysAt(int col, int row) =>
      Set.unmodifiable(_chunks[row * _cols + col].keys);

  /// R3: [item] lies on top of everything recorded — one small picture per
  /// chunk it touches; a dirty chunk will include it when it is recorded.
  void append(InkLayerItem item, InkItemDraw draw) {
    for (final i in _indicesFor(item.bounds)) {
      final chunk = _chunks[i];
      if (chunk.picture == null) {
        // a recording in progress takes it as its new top item
        chunk.partial?.items.add(item);
        continue;
      }
      if (chunk.appended.length >= maxAppended) {
        _clearAt(i); // consolidate (R4)
        continue;
      }
      chunk.appended.add(_record(i, [item], draw, chunk.keys));
    }
  }

  /// Records the dirty chunks from [zOrdered] (the visible items of the layer,
  /// bottom → top). Chunks recorded before are recorded in full; loading
  /// chunks in [order] (every index, highest priority first; default: index
  /// order) until [outOfTime] — asked after each stroke, so a call always
  /// makes progress — says the budget is spent. True when every chunk has
  /// its picture.
  bool record(
    Iterable<InkLayerItem> zOrdered,
    InkItemDraw draw, {
    List<int>? order,
    bool Function()? outOfTime,
  }) {
    if (_chunks.isEmpty) return true;
    final need = <int, List<InkLayerItem>>{
      for (var i = 0; i < _chunks.length; i++)
        if (_chunks[i].picture == null && _chunks[i].partial == null)
          i: <InkLayerItem>[],
    };
    if (need.isEmpty && _chunks.every((c) => c.picture != null)) return true;
    if (need.isNotEmpty) {
      for (final item in zOrdered) {
        for (final i in _indicesFor(item.bounds)) {
          need[i]?.add(item);
        }
      }
    }
    // edits: in full now (never blank a chunk that was shown)
    for (final MapEntry(key: i, value: items) in need.entries) {
      final c = _chunks[i];
      if (!c.loaded) continue;
      c.picture = _record(i, items, draw, c.keys);
      c.recordedStrokes = items.length;
      _recordCount++;
    }
    // loading: item by item within the budget, [order] first
    var spent = false;
    for (final i in order ?? Iterable<int>.generate(_chunks.length)) {
      final c = _chunks[i];
      if (c.picture != null) continue;
      if (spent) return false;
      final p = c.partial ??= _Partial(_clipRectOf(i), need[i] ?? []);
      while (p.next < p.items.length) {
        final item = p.items[p.next++];
        _noteKeys(p.keys, item);
        draw(p.canvas, item);
        if (outOfTime != null && outOfTime()) {
          spent = true;
          break;
        }
      }
      if (p.next < p.items.length) return false;
      c
        ..picture = p.recorder.endRecording()
        ..recordedStrokes = p.items.length
        ..loaded = true
        ..partial = null;
      c.keys.addAll(p.keys);
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
    Iterable<InkLayerItem> zOrdered,
    InkItemDraw draw,
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

  /// Items (strokes, objects) drawn by the chunk's picture and appended pictures.
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

  /// Draws [item] the way a chunk picture would: once per chunk it touches,
  /// under that chunk's clip. Skia rasterizes the anti-aliased edge of a
  /// path differently when a clip cuts it, so a pending item drawn like
  /// this hands over to its chunk pictures pixel for pixel (6.12 R6).
  void paintClipped(ui.Canvas canvas, InkLayerItem item, InkItemDraw draw) {
    if (_chunks.isEmpty) {
      draw(canvas, item);
      return;
    }
    for (final i in _indicesFor(item.bounds)) {
      canvas
        ..save()
        ..clipRect(_clipRectOf(i), doAntiAlias: false);
      draw(canvas, item);
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

  ui.Picture _record(
    int index,
    List<InkLayerItem> items,
    InkItemDraw draw,
    Set<Object> keys,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..clipRect(_clipRectOf(index), doAntiAlias: false);
    for (final item in items) {
      _noteKeys(keys, item);
      draw(canvas, item);
    }
    return recorder.endRecording();
  }

  void _noteKeys(Set<Object> keys, InkLayerItem item) {
    final of = drawKeysOf;
    if (of != null) keys.addAll(of(item));
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

  /// Items in [picture].
  int recordedStrokes = 0;

  /// (m5-7 T32b) The draw keys of [picture] and [appended].
  final Set<Object> keys = {};

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
    keys.clear();
    partial?.recorder.endRecording().dispose();
    partial = null;
    generation++;
  }
}

/// A chunk recording resumed in the next frame (6.13 time slicing).
final class _Partial {
  _Partial(ui.Rect clip, this.items) : recorder = ui.PictureRecorder() {
    canvas = ui.Canvas(recorder)..clipRect(clip, doAntiAlias: false);
  }

  final ui.PictureRecorder recorder;
  late final ui.Canvas canvas;

  /// Bottom → top; appends land at the end.
  final List<InkLayerItem> items;
  int next = 0;

  /// The draw keys of the items drawn so far.
  final Set<Object> keys = {};
}

/// (m5-7/03-ink 6.8.3, T32b) The cover layer's base drawing: one page Picture of the
/// committed tapes (InkLayer.cover), recorded again when a tape changes or a tape is
/// revealed / covered (markDirty).
final class CoverPictureCache {
  ui.Picture? _picture;
  int _recordCount = 0;
  int _strokes = 0;

  /// Times the page picture was recorded.
  @visibleForTesting
  int get recordCount => _recordCount;

  /// Tapes in the current picture (0 when dirty).
  int get strokeCount => _picture == null ? 0 : _strokes;

  bool get isDirty => _picture == null;

  void markDirty() {
    _picture?.dispose();
    _picture = null;
  }

  /// Records [zOrdered] (the visible committed tapes) when dirty, then draws the picture.
  /// Nothing is recorded or drawn while there is no tape.
  void paint(ui.Canvas canvas, List<InkStroke> zOrdered, InkStrokeDraw draw) {
    if (zOrdered.isEmpty) {
      markDirty();
      return;
    }
    var picture = _picture;
    if (picture == null) {
      final recorder = ui.PictureRecorder();
      final c = ui.Canvas(recorder);
      for (final s in zOrdered) {
        draw(c, s);
      }
      picture = _picture = recorder.endRecording();
      _strokes = zOrdered.length;
      _recordCount++;
    }
    canvas.drawPicture(picture);
  }

  void dispose() => markDirty();
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
