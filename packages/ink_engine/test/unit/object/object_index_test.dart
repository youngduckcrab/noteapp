// m5-7/03-ink T32a (6.8.1): the object spatial index (64 pt cells, id → CORE
// bounds) gives the same candidates as a brute-force scan — 1,000 seeded
// objects of every kind (some off the page, some huge), 500 queries — and
// keeps that after removals and replacements. The stroke index (1st round
// spatial_index_test) shares the grid code.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/src/edit/spatial_index.dart';
import 'package:ink_engine/src/object/object_view.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

const ui.Size _page = ui.Size(595, 842);

core.PageObject _object(math.Random rnd, int i) {
  final w = rnd.nextDouble() < 0.05
      ? 400 + 800 * rnd.nextDouble()
      : 1 + 80 * rnd.nextDouble();
  final h = rnd.nextDouble() < 0.05
      ? 400 + 800 * rnd.nextDouble()
      : 1 + 80 * rnd.nextDouble();
  final x = -100 + 800 * rnd.nextDouble();
  final y = -100 + 1050 * rnd.nextDouble();
  final rect = core.PageRect(x, y, x + w, y + h);
  return switch (i % 5) {
    0 => PageObjectFixtures.shape(
      pageId: 'p1',
      id: 'o$i',
      rect: rect,
      kind: core.ShapeKind.values[i % core.ShapeKind.values.length],
    ),
    1 => PageObjectFixtures.textBox(pageId: 'p1', id: 'o$i', rect: rect),
    2 => PageObjectFixtures.image(
      pageId: 'p1',
      id: 'o$i',
      assetId: 'a$i',
      rect: rect,
    ),
    3 => PageObjectFixtures.math(pageId: 'p1', id: 'o$i', rect: rect),
    _ => PageObjectFixtures.unknown(pageId: 'p1', id: 'o$i', rect: rect),
  };
}

ui.Rect _query(math.Random rnd) {
  final x = -150 + 900 * rnd.nextDouble();
  final y = -150 + 1150 * rnd.nextDouble();
  final big = rnd.nextDouble() < 0.1;
  final w = big ? 300 * rnd.nextDouble() : 30 * rnd.nextDouble();
  final h = big ? 300 * rnd.nextDouble() : 30 * rnd.nextDouble();
  return ui.Rect.fromLTWH(x, y, w, h); // w or h 0 → a point / segment
}

Set<String> _bruteForce(Iterable<InkObjectView> views, ui.Rect r) => {
  for (final v in views)
    if (GridSpatialIndex.boundsMeet(v.bounds, r)) v.id,
};

void main() {
  test('1,000 random objects, 500 queries = brute force', () {
    final rnd = math.Random(20261106);
    final views = [
      for (var i = 0; i < 1000; i++) InkObjectView.of(_object(rnd, i)),
    ];
    final index = ObjectSpatialIndex.of(_page, views);
    expect(index.length, 1000);
    var nonEmpty = 0;
    for (var q = 0; q < 500; q++) {
      final r = _query(rnd);
      final got = index.query(r);
      final ids = got.map((v) => v.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'each once');
      expect(ids.toSet(), _bruteForce(views, r), reason: '$r');
      if (ids.isNotEmpty) nonEmpty++;
    }
    expect(nonEmpty, greaterThan(100), reason: 'the queries hit objects');
  });

  test('remove and replace keep the index equal to a scan', () {
    final rnd = math.Random(7);
    final byId = <String, InkObjectView>{};
    for (var i = 0; i < 300; i++) {
      final v = InkObjectView.of(_object(rnd, i));
      byId[v.id] = v;
    }
    final index = ObjectSpatialIndex.of(_page, byId.values);
    for (var step = 0; step < 300; step++) {
      final id = 'o${rnd.nextInt(300)}';
      if (rnd.nextBool()) {
        expect(index.remove(id), byId.remove(id) != null);
      } else {
        // a new instance of the same id somewhere else replaces the old one
        final v = InkObjectView.of(_object(rnd, int.parse(id.substring(1))));
        index.insert(v);
        byId[id] = v;
      }
      expect(index.length, byId.length);
      if (step % 10 == 0) {
        for (var q = 0; q < 20; q++) {
          final r = _query(rnd);
          expect(
            index.query(r).map((v) => v.id).toSet(),
            _bruteForce(byId.values, r),
          );
        }
      }
    }
    for (final MapEntry(:key, :value) in byId.entries) {
      expect(index.itemOf(key), same(value));
      expect(index.contains(key), isTrue);
    }
    expect(index.itemOf('missing'), isNull);
    expect(index.remove('missing'), isFalse);
  });

  test('NaN or inverted queries and an empty index give nothing', () {
    final empty = ObjectSpatialIndex(_page);
    expect(empty.query(const ui.Rect.fromLTWH(0, 0, 595, 842)), isEmpty);
    final index = ObjectSpatialIndex.of(_page, [
      InkObjectView.of(PageObjectFixtures.shape(pageId: 'p1', id: 'a')),
    ]);
    expect(index.query(const ui.Rect.fromLTRB(10, 10, 5, 5)), isEmpty);
    expect(
      index.query(const ui.Rect.fromLTRB(double.nan, 0, 600, 900)),
      isEmpty,
    );
    expect(index.query(const ui.Rect.fromLTWH(0, 0, 595, 842)), hasLength(1));
    index.clear();
    expect(index.length, 0);
    expect(index.query(const ui.Rect.fromLTWH(0, 0, 595, 842)), isEmpty);
  });
}
