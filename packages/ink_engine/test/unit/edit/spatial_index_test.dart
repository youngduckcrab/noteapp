// T14 (03-ink 6.18): the uniform-grid spatial index gives exactly the strokes
// a brute-force bounds scan gives — for random strokes and queries, after
// removals and replacements, and for bounds that leave the page; the
// controller keeps it up to date from the R2 content diff.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/edit/hit_test.dart';
import 'package:ink_engine/src/edit/spatial_index.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../../support/pixels.dart';

const _a4 = ui.Size(595.2756, 841.8898);

const _tools = [
  core.PenTool.ballpoint,
  core.PenTool.fountain,
  core.PenTool.highlighter,
  core.PenTool.pencil,
  core.PenTool.marker,
];

/// A random stroke of 1–6 points; most inside the page, some reaching far out.
core.Stroke _randomStroke(math.Random rnd, String id, {int createdAt = 1000}) {
  final far = rnd.nextDouble() < 0.15;
  final spanX = far ? 1600.0 : 700.0, spanY = far ? 2000.0 : 950.0;
  final x0 = (far ? -500.0 : -50.0) + rnd.nextDouble() * spanX;
  final y0 = (far ? -500.0 : -50.0) + rnd.nextDouble() * spanY;
  final step = rnd.nextDouble() < 0.1 ? 300.0 : 40.0;
  final n = 1 + rnd.nextInt(6);
  final pts = <ui.Offset>[ui.Offset(x0, y0)];
  for (var i = 1; i < n; i++) {
    final last = pts.last;
    pts.add(
      last +
          ui.Offset(
            (rnd.nextDouble() - 0.5) * step,
            (rnd.nextDouble() - 0.5) * step,
          ),
    );
  }
  final tool = _tools[rnd.nextInt(_tools.length)];
  final style = core.StrokeStyle.defaultsFor(tool)
      .copyWith(width: 0.5 + rnd.nextDouble() * 12);
  return strokeThrough(
    pts,
    style,
    id: id,
    createdAt: createdAt,
    widthQ: 0.05 + rnd.nextDouble() * 0.4,
  );
}

ui.Rect _randomQuery(math.Random rnd) {
  final x = -300 + rnd.nextDouble() * 1200, y = -300 + rnd.nextDouble() * 1450;
  final big = rnd.nextDouble() < 0.1;
  final w = rnd.nextDouble() * (big ? 900 : 80);
  final h = rnd.nextDouble() * (big ? 1200 : 80);
  return ui.Rect.fromLTWH(x, y, w, h);
}

Set<String> _brute(Iterable<InkStroke> strokes, ui.Rect q) => {
  for (final s in strokes)
    if (StrokeSpatialIndex.boundsMeet(s.bounds, q)) s.id,
};

Set<String> _ids(List<InkStroke> strokes) {
  final ids = {for (final s in strokes) s.id};
  expect(ids.length, strokes.length, reason: 'a stroke came back twice');
  return ids;
}

void main() {
  group('grid', () {
    test('A4 = 10 × 14 cells of 64 pt', () {
      final index = StrokeSpatialIndex(_a4);
      expect(index.cellPt, 64);
      expect(index.columns, 10);
      expect(index.rows, 14);
    });

    test('a zero or broken page size still has one cell', () {
      final index = StrokeSpatialIndex(ui.Size.zero);
      expect(index.columns, 1);
      expect(index.rows, 1);
      final s = InkStroke.of(
        strokeThrough(
          [const ui.Offset(10, 10), const ui.Offset(20, 30)],
          core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
          id: 'a',
        ),
      );
      index.insert(s);
      expect(_ids(index.query(const ui.Rect.fromLTWH(15, 15, 1, 1))), {'a'});
    });
  });

  group('random strokes vs brute force', () {
    final rnd = math.Random(14);
    final strokes = [
      for (var i = 0; i < 1000; i++) InkStroke.of(_randomStroke(rnd, 's$i')),
    ];
    final queries = [for (var i = 0; i < 500; i++) _randomQuery(rnd)];

    test('1000 strokes × 500 queries = brute force', () {
      final index = StrokeSpatialIndex.of(_a4, strokes);
      expect(index.length, 1000);
      var nonEmpty = 0;
      for (final q in queries) {
        final got = _ids(index.query(q));
        expect(got, _brute(strokes, q), reason: '$q');
        if (got.isNotEmpty) nonEmpty++;
      }
      // the queries really exercise the index
      expect(nonEmpty, greaterThan(250));
    });

    test('removed strokes are no longer returned', () {
      final index = StrokeSpatialIndex.of(_a4, strokes);
      final removed = <String>{};
      for (var i = 0; i < 1000; i += 3) {
        expect(index.remove('s$i'), isTrue);
        removed.add('s$i');
      }
      expect(index.remove('s0'), isFalse, reason: 'already removed');
      expect(index.remove('nope'), isFalse);
      expect(index.length, 1000 - removed.length);
      final remaining = [
        for (final s in strokes)
          if (!removed.contains(s.id)) s,
      ];
      for (final q in queries) {
        final got = _ids(index.query(q));
        expect(got.intersection(removed), isEmpty);
        expect(got, _brute(remaining, q));
      }
      for (final id in removed) {
        expect(index.contains(id), isFalse);
        expect(index.strokeOf(id), isNull);
      }
    });

    test('insert with a known id replaces the stroke (moved bounds)', () {
      final index = StrokeSpatialIndex.of(_a4, strokes.take(200));
      final moved = <InkStroke>[
        for (var i = 0; i < 200; i++)
          i.isEven ? InkStroke.of(_randomStroke(rnd, 's$i')) : strokes[i],
      ];
      for (var i = 0; i < 200; i += 2) {
        index.insert(moved[i]);
      }
      expect(index.length, 200);
      for (var i = 0; i < 200; i += 2) {
        expect(identical(index.strokeOf('s$i'), moved[i]), isTrue);
      }
      for (final q in queries) {
        expect(_ids(index.query(q)), _brute(moved, q));
      }
    });

    test('free slots are reused after removal; clear empties', () {
      final index = StrokeSpatialIndex(_a4);
      for (var round = 0; round < 3; round++) {
        for (final s in strokes.take(300)) {
          index.insert(s);
        }
        for (final s in strokes.take(300)) {
          index.remove(s.id);
        }
      }
      expect(index.length, 0);
      for (final q in queries.take(50)) {
        expect(index.query(q), isEmpty);
      }
      strokes.take(100).forEach(index.insert);
      for (final q in queries.take(100)) {
        expect(_ids(index.query(q)), _brute(strokes.take(100), q));
      }
      index.clear();
      expect(index.length, 0);
      expect(
        index.query(const ui.Rect.fromLTWH(-1e5, -1e5, 2e5, 2e5)),
        isEmpty,
      );
    });
  });

  group('bounds outside the page', () {
    final style = core.StrokeStyle.defaultsFor(core.PenTool.ballpoint);
    InkStroke line(String id, ui.Offset a, ui.Offset b) =>
        InkStroke.of(strokeThrough([a, b], style, id: id));

    final left = line(
      'left',
      const ui.Offset(-300, 100),
      const ui.Offset(-250, 120),
    );
    final below = line(
      'below',
      const ui.Offset(300, 1200),
      const ui.Offset(320, 1500),
    );
    final across = line(
      'across',
      const ui.Offset(-100, -100),
      const ui.Offset(700, 950),
    );
    final corner = line(
      'corner',
      const ui.Offset(590, 830),
      const ui.Offset(700, 900),
    );
    late StrokeSpatialIndex index;
    setUp(
      () => index = StrokeSpatialIndex.of(_a4, [left, below, across, corner]),
    );

    test('strokes off the page are found by queries off the page', () {
      expect(_ids(index.query(const ui.Rect.fromLTWH(-280, 105, 5, 5))), {
        'left',
      });
      expect(_ids(index.query(const ui.Rect.fromLTWH(305, 1300, 5, 5))), {
        'below',
      });
      expect(_ids(index.query(const ui.Rect.fromLTWH(650, 860, 5, 5))), {
        'corner',
        'across',
      });
    });

    test('a query off the page does not return strokes it does not meet', () {
      // the same clamped border cells as 'left', but far below it
      const q = ui.Rect.fromLTWH(-280, 700, 5, 5);
      expect(index.query(q), isEmpty);
      expect(_brute([left, below, across, corner], q), isEmpty);
      // right of the page, level with 'left'
      expect(index.query(const ui.Rect.fromLTWH(900, 105, 5, 5)), isEmpty);
    });

    test('a page-covering stroke comes back once from a page-sized query', () {
      final got = index.query(ui.Offset.zero & _a4);
      expect(_ids(got), {'across', 'corner'});
      expect(got.where((s) => s.id == 'across').length, 1);
    });

    test('touching edges count (closed rectangles)', () {
      final b = left.bounds;
      expect(_ids(index.query(ui.Rect.fromLTWH(b.right, b.top, 3, 3))), {
        'left',
      });
      expect(
        index.query(ui.Rect.fromLTWH(b.right + 0.001, b.top, 3, 3)),
        isEmpty,
      );
    });

    test('empty, inverted and NaN queries return nothing', () {
      expect(
        index.query(const ui.Rect.fromLTRB(10, 10, 5, 20)),
        isEmpty,
        reason: 'left > right',
      );
      expect(
        index.query(const ui.Rect.fromLTRB(double.nan, 0, 10, 10)),
        isEmpty,
      );
      // a zero-size rect is a point and still meets what covers it
      expect(_ids(index.query(ui.Rect.fromLTWH(100, 100, 0, 0))), {'across'});
    });
  });

  group('controller keeps the index up to date (R2 diff)', () {
    final rnd = math.Random(1414);
    late InkPageController c;
    setUp(() => c = createTestPageController());
    tearDown(() => c.dispose());

    Set<String> exact(InkPageContent content, ui.Rect q) => {
      for (final s in content.strokes)
        if (InkHitTest.rectTouches(s, q)) s.id,
    };

    test('add, remove, change, reset: strokeIdsInRect = brute force', () {
      var strokes = [
        for (var i = 0; i < 150; i++)
          _randomStroke(rnd, 'k$i', createdAt: 1000 + i * 10),
      ];
      var revision = 1;
      InkPageContent push({core.PageSize size = core.PageSize.a4Portrait}) {
        final content = SyntheticInk.pageContent(
          strokes: strokes,
          revision: revision++,
          size: size,
        );
        c.updateContent(content);
        return content;
      }

      void check(InkPageContent content) {
        for (var i = 0; i < 60; i++) {
          final q = _randomQuery(rnd);
          final got = c.strokeIdsInRect(q);
          expect(got.toSet(), exact(content, q), reason: '$q');
          // z order
          final z = [for (final id in got) content.zIndexOf(id)];
          expect(z, [...z]..sort());
        }
      }

      check(push()); // first use builds the index
      // remove a third, change a third (moved: same id, new object), append
      strokes = [
        for (var i = 0; i < strokes.length; i++)
          if (i % 3 == 1)
            _randomStroke(rnd, strokes[i].id, createdAt: strokes[i].createdAt)
          else if (i % 3 == 0)
            strokes[i],
        for (var i = 0; i < 40; i++)
          _randomStroke(rnd, 'new$i', createdAt: 10000 + i),
      ]..sort(core.Stroke.compareOrder);
      check(push());
      // inserted below existing ones
      strokes = [
        ...strokes,
        for (var i = 0; i < 20; i++) _randomStroke(rnd, 'low$i', createdAt: 0),
      ]..sort(core.Stroke.compareOrder);
      check(push());
      // another page size resets the index
      check(push(size: core.PageSize.widescreen16x9));
    });
  });
}
