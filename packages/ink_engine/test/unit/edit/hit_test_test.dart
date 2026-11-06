// T14 (03-ink 6.18): the exact ink tests. g(u) = dist(p(u), S) − (R + r(u))
// is convex; its golden-section minimum matches dense sampling within
// 0.01 pt; dot strokes are one disc; highlighter radius = width / 2 (square
// caps ignored); controller.hitTest picks the topmost z and honours the three
// core.StrokeFilter values; strokeIdsInRect is exact, not bounds-based.
// (m5-7 T40) hitTestRecorded: only strokes linked to a recording (the given id),
// every tool, the topmost, 8 pt default tolerance.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/edit/hit_test.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../../support/pixels.dart';

const _samples = 20000;

double _dense(double Function(double u) g) {
  var best = double.infinity;
  for (var k = 0; k <= _samples; k++) {
    final v = g(k / _samples);
    if (v < best) best = v;
  }
  return best;
}

/// Dense-sampled min g over every segment of [s] against a capsule.
double _denseStroke(InkStroke s, ui.Offset a, ui.Offset b, double radius) {
  final p = s.points;
  var best = double.infinity;
  for (var i = 0; i + 1 < p.length; i++) {
    final x0 = p.x(i), y0 = p.y(i), x1 = p.x(i + 1), y1 = p.y(i + 1);
    final r0 = s.radiusAt(i), r1 = s.radiusAt(i + 1);
    final v = _dense(
      (u) => InkHitTest.capsuleGapAt(u, x0, y0, r0, x1, y1, r1, a, b, radius),
    );
    if (v < best) best = v;
  }
  return best;
}

core.StrokeStyle _style(core.PenTool tool, {double? width}) {
  final s = core.StrokeStyle.defaultsFor(tool);
  return width == null ? s : s.copyWith(width: width);
}

void main() {
  group('convex g: golden-section minimum vs dense sampling', () {
    final rnd = math.Random(618);
    double coord(double span) => (rnd.nextDouble() - 0.5) * span;

    test('segment vs capsule: |golden − dense| < 0.01 pt (2000 cases)', () {
      var touching = 0, worst = 0.0;
      for (var k = 0; k < 2000; k++) {
        // short, long and zero-length segments; capsules and points
        final span = [3.0, 40.0, 400.0][k % 3];
        final x0 = coord(200), y0 = coord(200);
        final x1 = k % 17 == 0 ? x0 : x0 + coord(span);
        final y1 = k % 17 == 0 ? y0 : y0 + coord(span);
        final r0 = 0.05 + rnd.nextDouble() * 6,
            r1 = 0.05 + rnd.nextDouble() * 6;
        final a = ui.Offset(coord(200), coord(200));
        final b = k % 5 == 0 ? a : a + ui.Offset(coord(120), coord(120));
        final radius = rnd.nextDouble() * 20;
        final m = InkHitTest.segmentVsCapsule(
          x0,
          y0,
          r0,
          x1,
          y1,
          r1,
          a,
          b,
          radius,
        );
        final dense = _dense(
          (u) =>
              InkHitTest.capsuleGapAt(u, x0, y0, r0, x1, y1, r1, a, b, radius),
        );
        final err = (m.gap - dense).abs();
        if (err > worst) worst = err;
        expect(err, lessThan(0.01), reason: 'case $k');
        expect(m.u, inInclusiveRange(0, 1));
        // the reported u really has the reported value
        expect(
          InkHitTest.capsuleGapAt(m.u, x0, y0, r0, x1, y1, r1, a, b, radius),
          closeTo(m.gap, 1e-9),
        );
        if (m.gap <= 0) touching++;
      }
      expect(touching, greaterThan(100), reason: 'both outcomes are covered');
      expect(touching, lessThan(1900));
      expect(worst, lessThan(0.01));
    });

    test('segment vs rectangle: |golden − dense| < 0.01 pt (1000 cases)', () {
      for (var k = 0; k < 1000; k++) {
        final x0 = coord(300), y0 = coord(300);
        final x1 = x0 + coord(200), y1 = y0 + coord(200);
        final r0 = 0.05 + rnd.nextDouble() * 6,
            r1 = 0.05 + rnd.nextDouble() * 6;
        final rect = ui.Rect.fromLTWH(
          coord(300),
          coord(300),
          rnd.nextDouble() * 80,
          rnd.nextDouble() * 80,
        );
        final m = InkHitTest.segmentVsRect(x0, y0, r0, x1, y1, r1, rect);
        final dense = _dense(
          (u) =>
              InkHitTest.pointRectDistance(
                x0 + (x1 - x0) * u,
                y0 + (y1 - y0) * u,
                rect,
              ) -
              (r0 + (r1 - r0) * u),
        );
        expect((m.gap - dense).abs(), lessThan(0.01), reason: 'case $k');
      }
    });

    test('whole strokes: capsuleTouches agrees with dense sampling', () {
      var hits = 0, misses = 0;
      for (var k = 0; k < 300; k++) {
        final tool = core.PenTool.values[k % 5];
        final pts = <ui.Offset>[ui.Offset(100 + coord(100), 100 + coord(100))];
        for (var i = 0; i < 2 + rnd.nextInt(8); i++) {
          pts.add(pts.last + ui.Offset(coord(30), coord(30)));
        }
        final s = InkStroke.of(
          strokeThrough(
            pts,
            _style(tool, width: 0.5 + rnd.nextDouble() * 10),
            widthQ: 0.05 + rnd.nextDouble() * 0.4,
          ),
        );
        final a =
            pts[rnd.nextInt(pts.length)] + ui.Offset(coord(40), coord(40));
        final b = a + ui.Offset(coord(40), coord(40));
        final radius = 0.5 + rnd.nextDouble() * 10;
        final dense = _denseStroke(s, a, b, radius);
        final gap = InkHitTest.capsuleGap(s, a, b, radius);
        expect((gap - dense).abs(), lessThan(0.01), reason: 'case $k');
        if (dense < -0.01) {
          expect(InkHitTest.capsuleTouches(s, a, b, radius), isTrue);
          hits++;
        } else if (dense > 0.01) {
          expect(InkHitTest.capsuleTouches(s, a, b, radius), isFalse);
          misses++;
        }
      }
      expect(hits, greaterThan(30));
      expect(misses, greaterThan(30));
    });
  });

  group('shapes', () {
    test('a pen stroke: radius = 2 · width · widthQ (nominal → width / 2)', () {
      // ballpoint width 1.6, nominal widthQ 0.25 → r = 0.8
      final s = InkStroke.of(
        strokeThrough([
          const ui.Offset(100, 100),
          const ui.Offset(200, 100),
        ], _style(core.PenTool.ballpoint)),
      );
      expect(s.radiusAt(0), closeTo(0.8, 1e-6));
      const p = ui.Offset(150, 100 + 0.8 + 3);
      expect(InkHitTest.capsuleTouches(s, p, p, 3.01), isTrue);
      expect(InkHitTest.capsuleTouches(s, p, p, 2.99), isFalse);
      expect(InkHitTest.capsuleGap(s, p, p, 0), closeTo(3, 1e-4));
      // round cap past the end
      const q = ui.Offset(200 + 0.8 + 2, 100);
      expect(InkHitTest.capsuleTouches(s, q, q, 2.01), isTrue);
      expect(InkHitTest.capsuleTouches(s, q, q, 1.99), isFalse);
    });

    test('tapered segment: radius interpolates along the segment', () {
      // widthQ 0.05 → 0.25 at width 10: r = 1 → 5
      final data = Float32List.fromList([
        0, 0, 0.05, 0, 0, 0, //
        100, 0, 0.25, 0, 0, 10,
      ]);
      final s = InkStroke.of(
        interop.strokeFromData(
          data,
          id: 'taper',
          pageId: 'p1',
          style: _style(core.PenTool.fountain, width: 10),
          createdAt: 1,
        ),
      );
      expect(s.radiusAt(0), closeTo(1, 1e-5));
      expect(s.radiusAt(1), closeTo(5, 1e-5));
      // min over u of |(100u, 0) − (50, 10)| − (1 + 4u): u ≈ 0.504, g ≈ 6.992
      const p = ui.Offset(50, 10);
      expect(InkHitTest.capsuleGap(s, p, p, 0), closeTo(6.992, 0.002));
      expect(InkHitTest.capsuleTouches(s, p, p, 6.99), isFalse);
      expect(InkHitTest.capsuleTouches(s, p, p, 7.0), isTrue);
      // near the thin end the same offset is further away
      const q = ui.Offset(10, 10);
      expect(InkHitTest.capsuleGap(s, q, q, 0), greaterThan(8));
    });

    test('dot strokes are one disc of maxRadius', () {
      final single = InkStroke.of(
        strokeThrough(
          [const ui.Offset(300, 300)],
          _style(core.PenTool.marker),
          widthQ: 0.3,
        ),
      );
      final repeated = InkStroke.of(
        strokeThrough(
          [
            const ui.Offset(300, 300),
            const ui.Offset(300, 300),
            const ui.Offset(300, 300),
          ],
          _style(core.PenTool.marker),
          widthQ: 0.3,
        ),
      );
      for (final s in [single, repeated]) {
        expect(s.isDot, isTrue);
        final r = s.maxRadius; // 2 · 5 · 0.3 = 3
        expect(r, closeTo(3, 1e-5));
        // a capsule passing by at distance r + R ± 0.01
        const a = ui.Offset(250, 310), b = ui.Offset(350, 310);
        expect(InkHitTest.capsuleTouches(s, a, b, 10 - r + 0.01), isTrue);
        expect(InkHitTest.capsuleTouches(s, a, b, 10 - r - 0.01), isFalse);
        expect(InkHitTest.capsuleGap(s, a, b, 0), closeTo(10 - r, 1e-4));
        expect(
          InkHitTest.rectTouches(s, const ui.Rect.fromLTWH(302.9, 290, 5, 20)),
          isTrue,
        );
        expect(
          InkHitTest.rectTouches(s, const ui.Rect.fromLTWH(303.1, 290, 5, 20)),
          isFalse,
        );
      }
    });

    test(
      'highlighter radius = width / 2; the square-cap corner is ignored',
      () {
        final s = InkStroke.of(
          strokeThrough(
            [const ui.Offset(100, 100), const ui.Offset(200, 100)],
            _style(core.PenTool.highlighter), // width 12
            widthQ: 0.4, // ignored for the highlighter
          ),
        );
        expect(s.radiusAt(0), 6);
        // beside the line
        expect(
          InkHitTest.capsuleTouches(
            s,
            const ui.Offset(150, 107),
            const ui.Offset(150, 107),
            1.01,
          ),
          isTrue,
        );
        expect(
          InkHitTest.capsuleTouches(
            s,
            const ui.Offset(150, 107),
            const ui.Offset(150, 107),
            0.99,
          ),
          isFalse,
        );
        // straight past the end: the disc (r = 6), not the square cap
        expect(
          InkHitTest.capsuleTouches(
            s,
            const ui.Offset(205.9, 100),
            const ui.Offset(205.9, 100),
            0,
          ),
          isTrue,
        );
        expect(
          InkHitTest.capsuleTouches(
            s,
            const ui.Offset(206.1, 100),
            const ui.Offset(206.1, 100),
            0,
          ),
          isFalse,
        );
        // inside the square cap's corner (5, 5 past the end) but 7.07 from the end
        expect(
          InkHitTest.capsuleTouches(
            s,
            const ui.Offset(205, 105),
            const ui.Offset(205, 105),
            0,
          ),
          isFalse,
        );
      },
    );

    test(
      'a stroke without the capsule bounds is skipped; no points → never',
      () {
        final s = InkStroke.of(
          strokeThrough([
            ui.Offset.zero,
            const ui.Offset(10, 0),
            const ui.Offset(20, 0),
          ], _style(core.PenTool.ballpoint)),
        );
        expect(
          InkHitTest.capsuleTouches(
            s,
            const ui.Offset(500, 500),
            const ui.Offset(600, 600),
            5,
          ),
          isFalse,
        );
        expect(
          InkHitTest.capsuleTouches(
            s,
            const ui.Offset(15, 50),
            const ui.Offset(15, -50),
            0.1,
          ),
          isTrue,
          reason: 'a capsule crossing the line between samples',
        );
        expect(
          InkHitTest.capsuleTouches(
            s,
            const ui.Offset(15, 0),
            const ui.Offset(15, 0),
            double.nan,
          ),
          isFalse,
        );
      },
    );
  });

  group('controller queries', () {
    late InkPageController c;
    setUp(() => c = createTestPageController());
    tearDown(() => c.dispose());

    InkPageContent load(List<core.Stroke> strokes) {
      final content = SyntheticInk.pageContent(strokes: strokes);
      c.updateContent(content);
      return content;
    }

    test('hitTest is exact: inside the bounds but far from the ink → null', () {
      // a diagonal line: its bounds' corner is ~35 pt from the ink
      load([
        strokeThrough(
          [const ui.Offset(100, 100), const ui.Offset(200, 200)],
          _style(core.PenTool.ballpoint),
          id: 'diag',
        ),
      ]);
      expect(c.hitTest(const ui.Offset(195, 105)), isNull);
      expect(c.hitTest(const ui.Offset(150, 152))?.id, 'diag');
      expect(c.hitTest(const ui.Offset(150, 160), tolerance: 4), isNull);
      expect(
        c.hitTest(const ui.Offset(150, 160), tolerance: 6.5)?.id,
        'diag',
        reason: 'tolerance widens the probe',
      );
      expect(
        c.hitTest(const ui.Offset(150, 150.5), tolerance: -3)?.id,
        'diag',
        reason: 'negative tolerance = 0: the ink itself',
      );
      expect(c.hitTest(const ui.Offset(double.nan, 1)), isNull);
    });

    test(
      'topmost z wins; StrokeFilter all / highlighterOnly / exceptHighlighter',
      () {
        final content = load([
          strokeThrough(
            segment(const ui.Offset(50, 300), const ui.Offset(250, 300)),
            _style(core.PenTool.highlighter),
            id: 'hl',
            createdAt: 1000,
          ),
          strokeThrough(
            segment(const ui.Offset(150, 200), const ui.Offset(150, 400)),
            _style(core.PenTool.pencil),
            id: 'pencil',
            createdAt: 2000,
          ),
          strokeThrough(
            segment(const ui.Offset(100, 250), const ui.Offset(200, 350)),
            _style(core.PenTool.fountain),
            id: 'fountain',
            createdAt: 3000,
          ),
        ]);
        expect(
          [for (final s in content.strokes) s.id],
          ['hl', 'pencil', 'fountain'],
        );
        const centre = ui.Offset(150, 300);
        expect(c.hitTest(centre)?.id, 'fountain');
        expect(
          c.hitTest(centre, filter: core.StrokeFilter.all)?.id,
          'fountain',
        );
        expect(
          c.hitTest(centre, filter: core.StrokeFilter.highlighterOnly)?.id,
          'hl',
        );
        expect(
          c.hitTest(centre, filter: core.StrokeFilter.exceptHighlighter)?.id,
          'fountain',
        );
        // only the highlighter and the pencil reach (150, 296); the pencil is on top
        const upper = ui.Offset(150, 296);
        expect(c.hitTest(upper, tolerance: 0)?.id, 'pencil');
        expect(
          c
              .hitTest(
                upper,
                tolerance: 0,
                filter: core.StrokeFilter.highlighterOnly,
              )
              ?.id,
          'hl',
        );
        // only the highlighter at (60, 300)
        const left = ui.Offset(60, 300);
        expect(c.hitTest(left)?.id, 'hl');
        expect(
          c.hitTest(left, filter: core.StrokeFilter.exceptHighlighter),
          isNull,
        );
      },
    );

    test('strokes a pending erase hides are not hit', () {
      load([
        strokeThrough(
          segment(const ui.Offset(50, 50), const ui.Offset(150, 50)),
          _style(core.PenTool.ballpoint),
          id: 'below',
          createdAt: 1000,
        ),
        strokeThrough(
          segment(const ui.Offset(50, 50), const ui.Offset(150, 50)),
          _style(core.PenTool.ballpoint),
          id: 'above',
          createdAt: 2000,
        ),
      ]);
      expect(c.hitTest(const ui.Offset(100, 50))?.id, 'above');
      final eraser = c.beginErase(
        const InkSample(
          position: ui.Offset(100, 50),
          timeUs: 0,
          kind: InkPointerKind.stylus,
        ),
        spec: const EraserSpec(mode: EraserMode.stroke, radius: 2),
        viewScale: 1,
      );
      final edit = eraser.end();
      expect(edit, isNotNull);
      expect(c.hitTest(const ui.Offset(100, 50)), isNull);
      expect(
        c.strokeIdsInRect(const ui.Rect.fromLTWH(0, 0, 200, 200)),
        isEmpty,
      );
      c.discardEdit(edit!);
      expect(c.hitTest(const ui.Offset(100, 50))?.id, 'above');
    });

    test('strokeIdsInRect: exact ink, z order', () {
      load([
        strokeThrough(
          [const ui.Offset(100, 100), const ui.Offset(200, 200)],
          _style(core.PenTool.ballpoint),
          id: 'diag',
          createdAt: 2000,
        ),
        strokeThrough(
          [const ui.Offset(100, 180), const ui.Offset(200, 180)],
          _style(core.PenTool.highlighter),
          id: 'hl',
          createdAt: 1000,
        ),
      ]);
      // inside the diagonal's bounds, away from its ink
      expect(
        c.strokeIdsInRect(const ui.Rect.fromLTWH(170, 105, 20, 20)),
        isEmpty,
      );
      // crossing both: z order (hl below diag)
      expect(c.strokeIdsInRect(const ui.Rect.fromLTWH(170, 160, 20, 30)), [
        'hl',
        'diag',
      ]);
      // the highlighter's edge (r = 6) only
      expect(c.strokeIdsInRect(const ui.Rect.fromLTWH(110, 185.5, 10, 10)), [
        'hl',
      ]);
      expect(
        c.strokeIdsInRect(const ui.Rect.fromLTWH(110, 186.5, 10, 10)),
        isEmpty,
      );
      expect(
        c.strokeIdsInRect(const ui.Rect.fromLTRB(200, 200, 100, 100)),
        isEmpty,
        reason: 'inverted rect',
      );
    });

    test('no content → no hits', () {
      expect(c.hitTest(const ui.Offset(10, 10)), isNull);
      expect(
        c.strokeIdsInRect(const ui.Rect.fromLTWH(0, 0, 100, 100)),
        isEmpty,
      );
      expect(c.hitTestRecorded(const ui.Offset(10, 10)), isNull);
    });

    // m5-7 T40 (4.3, 4.10, 6.19): strokes linked to a recording only.
    core.Stroke recorded(
      String id,
      double y,
      String? recording, {
      core.PenTool tool = core.PenTool.ballpoint,
      int createdAt = 1000,
    }) => strokeThrough(
      segment(ui.Offset(100, y), ui.Offset(300, y)),
      _style(tool, width: 4),
      id: id,
      createdAt: createdAt,
    ).copyWith(recordingId: recording, recordingOffsetMs: 0);

    test('hitTestRecorded: recording id filter, topmost linked stroke', () {
      load([
        recorded('a-low', 100, 'A', createdAt: 1000),
        recorded('b', 100, 'B', createdAt: 2000),
        recorded('none', 100, null, createdAt: 3000),
        recorded('a-tape', 200, 'A', tool: core.PenTool.tape),
        recorded('a-hl', 300, 'A', tool: core.PenTool.highlighter),
      ]);
      const p = ui.Offset(200, 100);
      expect(c.hitTest(p)?.id, 'none', reason: 'the plain hit test sees all');
      expect(c.hitTestRecorded(p)?.id, 'b', reason: 'any recording: topmost');
      expect(c.hitTestRecorded(p, recordingId: 'A')?.id, 'a-low');
      expect(c.hitTestRecorded(p, recordingId: 'B')?.id, 'b');
      expect(c.hitTestRecorded(p, recordingId: 'C'), isNull);
      // every tool, tape and highlighter included
      expect(
        c.hitTestRecorded(const ui.Offset(200, 200), recordingId: 'A')?.id,
        'a-tape',
      );
      expect(
        c.hitTestRecorded(const ui.Offset(200, 300), recordingId: 'A')?.id,
        'a-hl',
      );
    });

    test('hitTestRecorded: default tolerance 8 pt from the ink edge', () {
      // radius = width / 2 = 2: the ink edge at y = 102
      load([recorded('a', 100, 'A')]);
      expect(c.hitTestRecorded(const ui.Offset(200, 109.9))?.id, 'a');
      expect(c.hitTestRecorded(const ui.Offset(200, 110.1)), isNull);
      expect(
        c.hitTestRecorded(const ui.Offset(200, 103.5), tolerance: 1),
        isNull,
      );
      expect(
        c.hitTestRecorded(const ui.Offset(200, 101.9), tolerance: -1)?.id,
        'a',
        reason: 'negative tolerance = the ink itself',
      );
      expect(c.hitTestRecorded(const ui.Offset(double.nan, 100)), isNull);
    });
  });
}
