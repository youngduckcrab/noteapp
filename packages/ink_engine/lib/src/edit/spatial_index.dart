// lib/src/edit/spatial_index.dart — INTERNAL (03-ink 6.18, INK T14).
//
// Uniform grid over the page (cells of InkTuning.gridCellPt; A4 = 10 × 14).
// Each cell lists the strokes whose CORE bounds overlap it. Bounds outside the
// page are clamped into the border cells (the cell mapping is monotone, so a
// query clamped the same way still meets them); the exact bounds test after the
// cell walk keeps the result equal to a brute-force scan. Duplicates across
// cells are dropped with a per-slot query stamp (Int32List).
//
// (m5-7/03-ink 6.8.1, T32a) The grid is generic (GridSpatialIndex): the
// strokes (StrokeSpatialIndex) and the page objects (ObjectSpatialIndex — id →
// CORE bounds, the hit test / eraser / lasso candidates) use the same 64 pt
// cells and rules.
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:meta/meta.dart';

import '../model/ink_stroke.dart';
import '../object/object_view.dart';
import '../tuning.dart';

/// A uniform grid of items with an id and CORE bounds (see the file comment).
@internal
abstract base class GridSpatialIndex<T extends Object> {
  GridSpatialIndex(Size pageSize, {this.cellPt = InkTuning.gridCellPt})
    : columns = _cellsFor(pageSize.width, cellPt),
      rows = _cellsFor(pageSize.height, cellPt) {
    _cells = List<List<int>?>.filled(columns * rows, null);
  }

  final double cellPt;
  final int columns;
  final int rows;

  /// The id of [item] (one entry per id).
  String idOf(T item);

  /// The bounds [item] is indexed and queried by.
  Rect boundsOf(T item);

  late final List<List<int>?> _cells;
  final List<T?> _slots = [];
  final List<int> _freeSlots = [];
  final Map<String, int> _slotOf = {};
  Int32List _stamps = Int32List(64);
  int _query = 0;

  /// Number of indexed items.
  int get length => _slotOf.length;

  bool contains(String id) => _slotOf.containsKey(id);

  /// The indexed item with [id], or null.
  T? itemOf(String id) {
    final slot = _slotOf[id];
    return slot == null ? null : _slots[slot];
  }

  /// Adds [item]; an item with the same id is replaced. O(cells covered).
  void insert(T item) {
    final id = idOf(item);
    remove(id);
    final int slot;
    if (_freeSlots.isNotEmpty) {
      slot = _freeSlots.removeLast();
      _slots[slot] = item;
    } else {
      slot = _slots.length;
      _slots.add(item);
      if (slot >= _stamps.length) {
        final grown = Int32List(_stamps.length * 2);
        grown.setRange(0, _stamps.length, _stamps);
        _stamps = grown;
      }
    }
    _stamps[slot] = 0;
    _slotOf[id] = slot;
    _forCells(boundsOf(item), (cell) => (_cells[cell] ??= <int>[]).add(slot));
  }

  /// Removes the item with [id]; false if it was not indexed. O(cells covered).
  bool remove(String id) {
    final slot = _slotOf.remove(id);
    if (slot == null) return false;
    final item = _slots[slot] as T;
    _forCells(boundsOf(item), (cell) => _cells[cell]?.remove(slot));
    _slots[slot] = null;
    _freeSlots.add(slot);
    return true;
  }

  void clear() {
    _cells.fillRange(0, _cells.length, null);
    _slots.clear();
    _freeSlots.clear();
    _slotOf.clear();
    _query = 0;
  }

  /// Every indexed item whose CORE bounds meet [rect] (closed rectangles:
  /// touching edges count), each once, in no particular order.
  List<T> query(Rect rect) {
    final result = <T>[];
    if (rect.left.isNaN ||
        rect.top.isNaN ||
        rect.right.isNaN ||
        rect.bottom.isNaN ||
        rect.left > rect.right ||
        rect.top > rect.bottom ||
        _slotOf.isEmpty) {
      return result;
    }
    final stamp = _nextStamp();
    _forCells(rect, (cell) {
      final list = _cells[cell];
      if (list == null) return;
      for (final slot in list) {
        if (_stamps[slot] == stamp) continue;
        _stamps[slot] = stamp;
        final s = _slots[slot] as T;
        if (boundsMeet(boundsOf(s), rect)) result.add(s);
      }
    });
    return result;
  }

  /// Closed-rectangle overlap (the predicate of [query]).
  static bool boundsMeet(Rect a, Rect b) =>
      a.left <= b.right &&
      b.left <= a.right &&
      a.top <= b.bottom &&
      b.top <= a.bottom;

  int _nextStamp() {
    if (_query >= 0x7FFFFFF0) {
      _stamps.fillRange(0, _stamps.length, 0);
      _query = 0;
    }
    return ++_query;
  }

  void _forCells(Rect r, void Function(int cell) action) {
    final c0 = _cell(r.left, columns), c1 = _cell(r.right, columns);
    final r0 = _cell(r.top, rows), r1 = _cell(r.bottom, rows);
    for (var row = r0; row <= r1; row++) {
      final base = row * columns;
      for (var col = c0; col <= c1; col++) {
        action(base + col);
      }
    }
  }

  /// Monotone cell coordinate of [v], clamped into [0, count − 1].
  int _cell(double v, int count) {
    if (v.isNaN) return 0;
    final c = v / cellPt;
    if (c <= 0) return 0;
    if (c >= count - 1) return count - 1;
    return c.floor();
  }

  static int _cellsFor(double extent, double cellPt) {
    if (!(extent > 0) || extent.isInfinite) return 1;
    final n = (extent / cellPt).ceil();
    return n < 1 ? 1 : n;
  }
}

/// The strokes of a page by their CORE bounds (03-ink 6.18).
@internal
final class StrokeSpatialIndex extends GridSpatialIndex<InkStroke> {
  StrokeSpatialIndex(super.pageSize, {super.cellPt});

  /// Builds the index of every stroke of [strokes].
  factory StrokeSpatialIndex.of(
    Size pageSize,
    Iterable<InkStroke> strokes, {
    double cellPt = InkTuning.gridCellPt,
  }) {
    final index = StrokeSpatialIndex(pageSize, cellPt: cellPt);
    strokes.forEach(index.insert);
    return index;
  }

  @override
  String idOf(InkStroke item) => item.id;

  @override
  Rect boundsOf(InkStroke item) => item.bounds;

  /// The indexed stroke with [id], or null.
  InkStroke? strokeOf(String id) => itemOf(id);

  /// Closed-rectangle overlap (the predicate of [query]).
  static bool boundsMeet(Rect a, Rect b) => GridSpatialIndex.boundsMeet(a, b);
}

/// (m5-7/03-ink 6.8.1) The page objects of a page by their CORE bounds.
@internal
final class ObjectSpatialIndex extends GridSpatialIndex<InkObjectView> {
  ObjectSpatialIndex(super.pageSize, {super.cellPt});

  /// Builds the index of every object of [objects].
  factory ObjectSpatialIndex.of(
    Size pageSize,
    Iterable<InkObjectView> objects, {
    double cellPt = InkTuning.gridCellPt,
  }) {
    final index = ObjectSpatialIndex(pageSize, cellPt: cellPt);
    objects.forEach(index.insert);
    return index;
  }

  @override
  String idOf(InkObjectView item) => item.id;

  @override
  Rect boundsOf(InkObjectView item) => item.bounds;
}
