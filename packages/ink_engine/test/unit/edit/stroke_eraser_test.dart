// T15 (03-ink 6.19): the stroke eraser. The capsule from one sample to the
// next fills the gap, so samples 50 pt apart still erase every stroke in
// between; contact is exact ink (not bounds); core.StrokeFilter picks the
// tools; nothing touched → null; one gesture = one InkEdit = one
// core.RemoveStrokes = one undo step.
// (m5-7/03-ink 8.2 T37b, 6.15 — v2) EraserSpec.eraseShapes: a shape is removed
// whole when the swept capsule comes within R + w / 2 of its outline (exact —
// not its bounds: an unfilled shape's inside is safe, a filled one's is not;
// ellipses exact, arrow heads within R), with every eraser mode; text boxes,
// formulas, images and unknown objects are never erased; highlighterOnly leaves
// shapes, all / exceptHighlighter erase them; eraseShapes: false leaves them.
// One gesture = one edit: removedIds = strokes + shapes (z order),
// removedObjectIds = the shapes → RemoveElements (strokes only → RemoveStrokes).
// The touched shapes are hidden at once. The capsule rule = a dense sampling of
// the capsule on 2,000 random shape / capsule pairs.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/object/object_hit.dart';
import 'package:ink_engine/src/object/shape_path.dart' show shapeGeometryOf;
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkPageRenderOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import '../../support/pixels.dart';

final _pen = core.StrokeStyle.defaultsFor(core.PenTool.ballpoint);
final _hl = core.StrokeStyle.defaultsFor(core.PenTool.highlighter);

InkSample _at(double x, double y, [int i = 0]) => InkSample(
  position: ui.Offset(x, y),
  timeUs: i * 8333,
  kind: InkPointerKind.stylus,
);

/// One eraser gesture through [points] (the first one is the pen-down).
InkEdit? _erase(
  InkPageController c,
  List<ui.Offset> points, {
  double radius = 2,
  EraserMode mode = EraserMode.stroke,
  core.StrokeFilter filter = core.StrokeFilter.all,
  bool lastInEnd = false,
}) {
  final s = c.beginErase(
    _at(points.first.dx, points.first.dy),
    spec: EraserSpec(mode: mode, radius: radius, filter: filter),
    viewScale: 1,
  );
  final rest = points.skip(1).toList();
  final last = lastInEnd && rest.isNotEmpty ? rest.removeLast() : null;
  for (var i = 0; i < rest.length; i++) {
    s.addSample(_at(rest[i].dx, rest[i].dy, i + 1));
  }
  return s.end(last == null ? null : _at(last.dx, last.dy, points.length));
}

void main() {
  late InkPageController c;
  setUp(() => c = createTestPageController());
  tearDown(() => c.dispose());

  InkPageContent load(List<core.Stroke> strokes) {
    final content = SyntheticInk.pageContent(strokes: strokes);
    c.updateContent(content);
    return content;
  }

  test('samples 50 pt apart erase every stroke in between', () {
    // 40 short vertical strokes at x = 12, 24, …, 480 around y = 300
    load([
      for (var k = 1; k <= 40; k++)
        strokeThrough(
          segment(ui.Offset(12.0 * k, 290), ui.Offset(12.0 * k, 310)),
          _pen,
          id: 'v$k',
          createdAt: 1000 + k * 10,
        ),
    ]);
    // samples at x = 0, 50, …, 500 — most strokes lie between two samples
    final edit = _erase(c, [
      for (var x = 0.0; x <= 500; x += 50) ui.Offset(x, 300),
    ]);
    expect(edit, isNotNull);
    expect(edit!.kind, InkEditKind.eraseStrokes);
    expect(edit.removedIds, {for (var k = 1; k <= 40; k++) 'v$k'});
    // z order
    expect(edit.removedIds.toList(), [for (var k = 1; k <= 40; k++) 'v$k']);
  });

  test('contact is exact ink: inside the bounds, away from the ink → kept', () {
    load([
      strokeThrough(
        [const ui.Offset(100, 100), const ui.Offset(300, 300)],
        _pen,
        id: 'diag',
      ),
    ]);
    // passes through the bounds' top-right corner region, ~50 pt from the ink
    expect(
      _erase(c, [const ui.Offset(240, 110), const ui.Offset(290, 110)]),
      isNull,
    );
    expect(c.pendingIds, isEmpty);
    // crossing the ink between two samples far from it
    final edit = _erase(c, [
      const ui.Offset(150, 250),
      const ui.Offset(250, 150),
    ]);
    expect(edit?.removedIds, {'diag'});
  });

  test('the pen-down disc alone erases; end(last) adds the last segment', () {
    load([
      strokeThrough(
        segment(const ui.Offset(50, 50), const ui.Offset(150, 50)),
        _pen,
        id: 'a',
      ),
      strokeThrough(
        segment(const ui.Offset(50, 400), const ui.Offset(150, 400)),
        _pen,
        id: 'b',
      ),
    ]);
    expect(_erase(c, [const ui.Offset(100, 52)])?.removedIds, {'a'});
    c.discardEdit(
      InkEdit(
        pageId: c.pageId,
        kind: InkEditKind.eraseStrokes,
        removedIds: const {'a'},
      ),
    );
    // the last sample only reaches 'b' through end(last)
    final edit = _erase(c, [
      const ui.Offset(300, 300),
      const ui.Offset(100, 300),
      const ui.Offset(100, 450),
    ], lastInEnd: true);
    expect(edit?.removedIds, {'b'});
  });

  test('radius: the eraser reaches exactly R + r from the centerline', () {
    // ballpoint 1.6 at nominal widthQ → r = 0.8; eraser R = 5 → reach 5.8
    load([
      strokeThrough(
        segment(const ui.Offset(50, 100), const ui.Offset(250, 100)),
        _pen,
        id: 'line',
      ),
    ]);
    expect(
      _erase(c, [
        const ui.Offset(60, 105.85),
        const ui.Offset(240, 105.85),
      ], radius: 5),
      isNull,
    );
    expect(
      _erase(c, [
        const ui.Offset(60, 105.75),
        const ui.Offset(240, 105.75),
      ], radius: 5)?.removedIds,
      {'line'},
    );
  });

  group('core.StrokeFilter', () {
    // a pen line crossing a highlighter line
    void loadCross() => load([
      strokeThrough(
        segment(const ui.Offset(100, 200), const ui.Offset(300, 200)),
        _hl,
        id: 'hl',
        createdAt: 1000,
      ),
      strokeThrough(
        segment(const ui.Offset(200, 100), const ui.Offset(200, 300)),
        _pen,
        id: 'pen',
        createdAt: 2000,
      ),
    ]);
    const through = [ui.Offset(190, 190), ui.Offset(210, 210)];

    test('all → both', () {
      loadCross();
      expect(_erase(c, through)?.removedIds, {'hl', 'pen'});
    });

    test('highlighterOnly → the highlighter only', () {
      loadCross();
      final edit = _erase(
        c,
        through,
        filter: core.StrokeFilter.highlighterOnly,
      );
      expect(edit?.removedIds, {'hl'});
    });

    test('exceptHighlighter → everything but the highlighter', () {
      loadCross();
      final edit = _erase(
        c,
        through,
        filter: core.StrokeFilter.exceptHighlighter,
      );
      expect(edit?.removedIds, {'pen'});
    });

    test('a filter that excludes everything touched → null', () {
      load([
        strokeThrough(
          segment(const ui.Offset(100, 200), const ui.Offset(300, 200)),
          _pen,
          id: 'pen',
        ),
      ]);
      expect(
        _erase(c, through, filter: core.StrokeFilter.highlighterOnly),
        isNull,
      );
    });
  });

  test('nothing touched → null, no pending display, no command', () {
    load([
      strokeThrough(
        segment(const ui.Offset(50, 50), const ui.Offset(150, 50)),
        _pen,
        id: 'a',
      ),
    ]);
    final s = c.beginErase(
      _at(400, 400),
      spec: const EraserSpec(mode: EraserMode.stroke, radius: 10),
      viewScale: 1,
    );
    for (var i = 1; i < 20; i++) {
      s.addSample(_at(400 + i * 5.0, 400, i));
    }
    expect(s.touchedStrokeIds, isEmpty);
    expect(s.end(), isNull);
    expect(c.pendingIds, isEmpty);
    expect(c.activeSession, isNull);
    // no content at all
    final empty = createTestPageController();
    addTearDown(empty.dispose);
    expect(_erase(empty, [const ui.Offset(10, 10)]), isNull);
  });

  test('touchedStrokeIds grows during the gesture (hidden preview)', () {
    load([
      for (var k = 0; k < 5; k++)
        strokeThrough(
          segment(ui.Offset(50.0 + 40 * k, 80), ui.Offset(50.0 + 40 * k, 120)),
          _pen,
          id: 'k$k',
        ),
    ]);
    final s = c.beginErase(
      _at(30, 100),
      spec: const EraserSpec(mode: EraserMode.stroke, radius: 2),
      viewScale: 1,
    );
    final seen = <int>[];
    for (var i = 1; i <= 10; i++) {
      s.addSample(_at(30 + i * 20.0, 100, i));
      seen.add(s.touchedStrokeIds.length);
    }
    expect(seen, [1, 1, 2, 2, 3, 3, 4, 4, 5, 5]);
    // a stroke already touched is not touched twice (back and forth)
    s.addSample(_at(30, 100, 11));
    expect(s.touchedStrokeIds.length, 5);
    expect(s.end()!.removedIds.length, 5);
  });

  test('strokes hidden by a pending erase are not erased again', () {
    load([
      strokeThrough(
        segment(const ui.Offset(50, 50), const ui.Offset(150, 50)),
        _pen,
        id: 'a',
      ),
    ]);
    final first = _erase(c, [const ui.Offset(100, 50)]);
    expect(first?.removedIds, {'a'});
    expect(_erase(c, [const ui.Offset(100, 50)]), isNull);
  });

  test('one gesture → one InkEdit → one core.RemoveStrokes (z order)', () {
    load([
      for (var k = 0; k < 6; k++)
        strokeThrough(
          segment(ui.Offset(50, 50.0 + 30 * k), ui.Offset(250, 50.0 + 30 * k)),
          _pen,
          id: 'h$k',
          createdAt: 5000 - k * 100, // later rows are lower in z
        ),
    ]);
    // a zig-zag over every row, 30 samples
    final edit = _erase(c, [
      for (var i = 0; i < 30; i++) ui.Offset(i.isEven ? 60 : 240, 40 + i * 6.5),
    ]);
    expect(edit, isNotNull);
    final command = edit!.toCommand();
    expect(command, isA<core.RemoveStrokes>());
    final remove = command as core.RemoveStrokes;
    expect(remove.pageId, c.pageId);
    expect(remove.strokeIds, ['h5', 'h4', 'h3', 'h2', 'h1', 'h0']);
  });

  group('shapes (v2 — eraseShapes, 6.15)', () {
    core.ShapeObject shape(
      String id,
      core.ShapeGeometry g, {
      core.ShapeKind kind = core.ShapeKind.rectangle,
      double width = 4,
      int? fill,
      core.ArrowHeads heads = core.ArrowHeads.none,
      int createdAt = 1,
    }) => core.ShapeObject(
      id: id,
      pageId: 'p1',
      shapeKind: kind,
      geometry: g,
      style: core.ShapeStyle(
        strokeColorArgb: 0xFFDD0000,
        strokeWidth: width,
        fillColorArgb: fill,
        arrowHeads: heads,
      ),
      createdAt: createdAt,
    );

    void loadAll(
      List<core.PageObject> objects, {
      List<core.Stroke> strokes = const [],
    }) => c.updateContent(
      SyntheticInk.pageContentWith(strokes: strokes, objects: objects),
    );

    InkEdit? eraseWith(
      List<ui.Offset> points, {
      double radius = 2,
      EraserMode mode = EraserMode.stroke,
      core.StrokeFilter filter = core.StrokeFilter.all,
      bool eraseShapes = true,
    }) {
      final s = c.beginErase(
        _at(points.first.dx, points.first.dy),
        spec: EraserSpec(
          mode: mode,
          radius: radius,
          filter: filter,
          eraseShapes: eraseShapes,
        ),
        viewScale: 1,
      );
      for (var i = 1; i < points.length; i++) {
        s.addSample(_at(points[i].dx, points[i].dy, i));
      }
      return s.end();
    }

    final rect = shape(
      'rect',
      core.ShapeGeometry.rectangle(const core.PageRect(100, 100, 300, 200)),
    );

    test(
      'the outline within R + w / 2, not the bounds or the empty inside',
      () {
        loadAll([rect]);
        // a pass through the inside, far from the edges: kept
        expect(
          eraseWith(const [ui.Offset(150, 150), ui.Offset(250, 150)]),
          isNull,
        );
        // parallel to the top edge: R 2 + w / 2 2 = 4 pt
        expect(
          eraseWith(const [ui.Offset(150, 95.95), ui.Offset(250, 95.95)]),
          isNull,
        );
        final edit = eraseWith(const [
          ui.Offset(150, 96.05),
          ui.Offset(250, 96.05),
        ]);
        expect(edit?.removedIds, {'rect'});
        expect(edit!.removedObjectIds, {'rect'});
        c.discardEdit(edit);
        // inside the bounds (inflated by 0.75 w = 3) but outside the reach of a small
        // eraser (R 0.5 + w / 2 = 2.5)
        expect(rect.bounds.top, lessThan(97.2));
        expect(eraseWith(const [ui.Offset(150, 97.2)], radius: 0.5), isNull);
        final near = eraseWith(const [ui.Offset(150, 97.6)], radius: 0.5);
        expect(near?.removedIds, {'rect'});
        c.discardEdit(near!);
        // crossing an edge between two samples far from it
        expect(
          eraseWith(const [ui.Offset(200, 50), ui.Offset(200, 150)])
              ?.removedIds,
          {'rect'},
        );
      },
    );

    test('filled shapes: the inside erases too', () {
      final filled = shape(
        'filled',
        core.ShapeGeometry.rectangle(const core.PageRect(100, 300, 300, 400)),
        fill: 0xFF00AA00,
      );
      loadAll([rect, filled]);
      expect(eraseWith(const [ui.Offset(200, 350)])?.removedIds, {'filled'});
    });

    test('ellipses (exact, rotated) and arrow heads', () {
      final frame = core.ElementFrame(
        const core.PageRect(100, 100, 300, 180),
        rotation: 0.4,
      );
      final ellipse = shape(
        'el',
        core.EllipseGeometry(frame),
        kind: core.ShapeKind.ellipse,
      );
      final arrow = shape(
        'ar',
        core.ShapeGeometry.line(
          const core.PagePoint(100, 400),
          const core.PagePoint(300, 400),
        ),
        kind: core.ShapeKind.arrow,
        width: 4,
        heads: core.ArrowHeads.end,
      );
      loadAll([ellipse, arrow]);
      // the end of the major axis, approached along the axis from outside
      final c0 = frame.center;
      final dir = ui.Offset(math.cos(0.4), math.sin(0.4));
      final end = ui.Offset(c0.x, c0.y) + dir * 100;
      // reach R 2 + w / 2 2 = 4
      expect(eraseWith([end + dir * 4.05, end + dir * 20]), isNull);
      final e1 = eraseWith([end + dir * 3.95, end + dir * 20]);
      expect(e1?.removedIds, {'el'});
      c.discardEdit(e1!);
      // the center of an unfilled ellipse is safe
      expect(eraseWith([ui.Offset(c0.x, c0.y)], radius: 10), isNull);
      // an arrow head's back corner (L 12): farther from the line than R + w / 2 = 3,
      // within R = 1 of the head
      final l = arrow.style.arrowHeadLength;
      final back = 300 - l * math.cos(25 * math.pi / 180);
      final half = l * math.sin(25 * math.pi / 180);
      expect(half, greaterThan(4.5));
      expect(
        eraseWith([
          ui.Offset(back + 0.3, 400 + half + 0.6),
        ], radius: 1)?.removedIds,
        {'ar'},
      );
    });

    test('text boxes, formulas, images, unknown objects are never erased', () {
      const r = core.PageRect(100, 300, 300, 360);
      loadAll([
        core.TextBoxObject(
          id: 'tx',
          pageId: 'p1',
          frame: const core.ElementFrame(r),
          text: 'hi',
          style: const core.TextBoxStyle(backgroundArgb: 0xFF00AA00),
          createdAt: 1,
        ),
        core_testing.PageObjectFixtures.math(pageId: 'p1', id: 'mx', rect: r),
        core_testing.PageObjectFixtures.image(
          pageId: 'p1',
          assetId: 'a',
          id: 'im',
          rect: r,
        ),
        core_testing.PageObjectFixtures.unknown(
          pageId: 'p1',
          id: 'un',
          rect: r,
        ),
      ]);
      for (final mode in EraserMode.values) {
        expect(
          eraseWith(
            const [
              ui.Offset(90, 330),
              ui.Offset(200, 300),
              ui.Offset(310, 330),
            ],
            radius: 30,
            mode: mode,
          ),
          isNull,
          reason: '$mode',
        );
      }
    });

    test('filters: highlighterOnly keeps shapes; eraseShapes: false too', () {
      loadAll([rect]);
      const pass = [ui.Offset(200, 50), ui.Offset(200, 150)];
      expect(
        eraseWith(pass, filter: core.StrokeFilter.highlighterOnly),
        isNull,
      );
      expect(eraseWith(pass, eraseShapes: false), isNull);
      for (final f in [
        core.StrokeFilter.all,
        core.StrokeFilter.exceptHighlighter,
      ]) {
        final edit = eraseWith(pass, filter: f);
        expect(edit?.removedObjectIds, {'rect'}, reason: '$f');
        c.discardEdit(edit!);
      }
      final partial = eraseWith(pass, mode: EraserMode.partial);
      expect(partial?.removedObjectIds, {'rect'});
    });

    test(
      'one gesture = one edit: strokes + shapes in z order → RemoveElements',
      () {
        final old = shape(
          'old',
          core.ShapeGeometry.line(
            const core.PagePoint(50, 500),
            const core.PagePoint(50, 600),
          ),
          kind: core.ShapeKind.line,
          createdAt: 1,
        );
        final newer = shape(
          'newer',
          core.ShapeGeometry.line(
            const core.PagePoint(150, 500),
            const core.PagePoint(150, 600),
          ),
          kind: core.ShapeKind.line,
          createdAt: 5000,
        );
        final strokes = [
          strokeThrough(
            segment(const ui.Offset(100, 500), const ui.Offset(100, 600)),
            _pen,
            id: 'mid',
            createdAt: 2000,
          ),
        ];
        loadAll([old, newer], strokes: strokes);
        const pass = [ui.Offset(20, 550), ui.Offset(200, 550)];
        final edit = eraseWith(pass)!;
        expect(edit.kind, InkEditKind.eraseStrokes);
        expect(edit.removedIds.toList(), ['old', 'mid', 'newer']);
        expect(edit.removedObjectIds, {'old', 'newer'});
        final cmd = edit.toCommand() as core.RemoveElements;
        expect(cmd.elementIds, unorderedEquals(['old', 'mid', 'newer']));
        c.discardEdit(edit);
        // strokes only → RemoveStrokes; shapes only → RemoveElements
        expect(
          eraseWith(pass, filter: core.StrokeFilter.highlighterOnly),
          isNull,
        );
        final shapesOnly = eraseWith(const [
          ui.Offset(150, 520),
          ui.Offset(150, 580),
        ])!;
        expect(shapesOnly.toCommand(), isA<core.RemoveElements>());
        c.discardEdit(shapesOnly);
        expect(
          eraseWith(const [ui.Offset(100, 520), ui.Offset(100, 580)])!
              .toCommand(),
          isA<core.RemoveStrokes>(),
        );
      },
    );

    test(
      'touched shapes are hidden at once (the gesture is not over)',
      () async {
        final filled = shape(
          'filled',
          core.ShapeGeometry.rectangle(const core.PageRect(100, 300, 300, 400)),
          fill: 0xFF00AA00,
        );
        loadAll([filled]);
        Future<Pixels> paint() => renderPixels(400, 500, (canvas) {
          paintPaper(canvas, 0xFFFFFFFF);
          final render = inkPageRenderOf(c);
          for (final layer in InkRenderLayer.values) {
            render.paint(canvas, layer, 1);
          }
        });
        bool inked(Pixels p) =>
            !samePixel(p.at(200, 350), const [255, 255, 255, 255], tol: 2);
        expect(inked(await paint()), isTrue);
        final s = c.beginErase(
          _at(20, 20),
          spec: const EraserSpec(mode: EraserMode.stroke, radius: 4),
          viewScale: 1,
        );
        expect(inked(await paint()), isTrue);
        s.addSample(_at(200, 350, 1));
        expect(inked(await paint()), isFalse, reason: 'hidden while erasing');
        s.cancel();
        expect(inked(await paint()), isTrue, reason: 'cancel brings it back');
      },
    );

    test('the capsule rule = a dense sampling (2,000 random pairs)', () {
      final r = math.Random(4242);
      var touched = 0, checked = 0;
      for (var i = 0; i < 2000; i++) {
        final x = 100 + r.nextDouble() * 200, y = 100 + r.nextDouble() * 200;
        final w = 2 + r.nextDouble() * 120, h = 2 + r.nextDouble() * 100;
        final rr = core.PageRect(x, y, x + w, y + h);
        final width = 0.5 + r.nextDouble() * 8;
        final fill = r.nextBool() ? 0xFF00AA00 : null;
        final o = switch (r.nextInt(4)) {
          0 => shape(
            's',
            core.ShapeGeometry.ellipse(rr, rotation: r.nextDouble() * 3),
            kind: core.ShapeKind.ellipse,
            width: width,
            fill: fill,
          ),
          1 => shape(
            's',
            core.ShapeGeometry.star(rr),
            kind: core.ShapeKind.star,
            width: width,
            fill: fill,
          ),
          2 => shape(
            's',
            core.ShapeGeometry.line(
              core.PagePoint(x, y),
              core.PagePoint(x + w, y + h),
            ),
            kind: core.ShapeKind.arrow,
            width: width,
            heads: core.ArrowHeads.values[r.nextInt(3)],
          ),
          _ => shape(
            's',
            core.ShapeGeometry.rectangle(rr, rotation: r.nextDouble()),
            width: width,
            fill: fill,
          ),
        };
        final a = ui.Offset(
          x - 30 + r.nextDouble() * (w + 60),
          y - 30 + r.nextDouble() * (h + 60),
        );
        final b = r.nextInt(5) == 0
            ? a
            : a +
                  ui.Offset(
                    r.nextDouble() * 160 - 80,
                    r.nextDouble() * 160 - 80,
                  );
        final radius = 0.5 + r.nextDouble() * 12;
        // the dense reference: the smallest margin over points along a → b
        var margin = double.infinity;
        final n = ((b - a).distance / 0.02).ceil().clamp(1, 100000);
        for (var k = 0; k <= n; k++) {
          final p = ui.Offset.lerp(a, b, k / n)!;
          final g = shapeGeometryOf(o);
          var m = ObjectHitTest.outlineDistance(o, p) - (radius + g.width / 2);
          for (final head in g.heads) {
            m = math.min(m, ObjectHitTest.polygonDistance(head, p) - radius);
          }
          if (g.fill != null && ObjectHitTest.fillContains(o, p)) m = -1;
          margin = math.min(margin, m);
        }
        if (margin.abs() < 0.03) continue; // too close to call by sampling
        final got = ObjectHitTest.shapeTouchesCapsule(o, a, b, radius);
        expect(got, margin < 0, reason: 'pair $i: margin $margin');
        if (got) touched++;
        checked++;
      }
      expect(touched, greaterThan(300), reason: 'touched cases occur');
      expect(checked - touched, greaterThan(300), reason: 'missed cases occur');
    });
  });

  group('with the CORE fake store', () {
    late core.NoteStore store;
    late core.NoteSession session;
    late StreamSubscription<core.PageContentChange> sub;
    late InkPageController controller;
    late String pageId;

    InkPageContent inkContentOf(core.PageContent p) => InkPageContent.fromCore(
      page: p.page,
      strokes: p.strokes,
      revision: p.revision,
    );

    core.Stroke line(String id, double y, int createdAt) {
      final pts = segment(ui.Offset(20, y), ui.Offset(220, y));
      const stride = core.StrokePoints.stride;
      final data = Float32List(pts.length * stride);
      for (var i = 0; i < pts.length; i++) {
        data[i * stride] = pts[i].dx;
        data[i * stride + 1] = pts[i].dy;
        data[i * stride + 2] = core.kNominalWidthQ;
        data[i * stride + 5] = i * 10.0;
      }
      return interop.strokeFromData(
        data,
        id: id,
        pageId: pageId,
        style: _pen,
        createdAt: createdAt,
      );
    }

    setUp(() async {
      store = core_testing.createFakeNoteStore();
      final note = await store.library.createNote(title: 'T15 eraser');
      session = await store.openSession(note.id);
      pageId = session.pages.single.id;
      final loaded = await session.openPage(pageId);
      controller = createTestPageController(
        pageId: pageId,
        services: testInkCoreServices(idPrefix: 'ink'),
      )..updateContent(inkContentOf(loaded));
      sub = session
          .pageChanges(pageId)
          .listen((ch) => controller.updateContent(inkContentOf(ch.content)));
      session.execute(
        core.AddStrokes(
          pageId: pageId,
          strokes: [
            for (var k = 0; k < 5; k++) line('r$k', 100.0 + 40 * k, k + 1),
          ],
        ),
      );
      await session.flush();
    });

    tearDown(() async {
      await sub.cancel();
      controller.dispose();
      await session.close();
      await store.close();
    });

    test('one fast scrub = one command = one undo step', () async {
      final undoBefore = session.history.undoDepth;
      // fast vertical pass: 3 samples 120 pt apart cross rows 0–4
      final edit = _erase(controller, const [
        ui.Offset(100, 80),
        ui.Offset(100, 200),
        ui.Offset(100, 320),
      ]);
      expect(edit?.removedIds, {'r0', 'r1', 'r2', 'r3', 'r4'});
      session.execute(edit!.toCommand());
      expect(controller.pendingIds, isEmpty);
      expect(controller.content!.strokes, isEmpty);
      expect(session.history.undoDepth, undoBefore + 1);
      await session.undo();
      expect(
        [for (final s in controller.content!.strokes) s.id],
        ['r0', 'r1', 'r2', 'r3', 'r4'],
      );
    });
  });
}
