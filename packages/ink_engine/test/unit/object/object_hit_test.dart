// m5-7/03-ink 8.2 T37a (6.14, 4.10): hitTestObject.
// - Per kind: text boxes, formulas, images and unknown objects take the tap
//   inside their (rotated) frame within the tolerance; a shape on its outline
//   within tolerance + w / 2 (dashed / dotted: the whole centerline, gaps
//   included), on an arrow head within the tolerance, inside only when filled
//   (nonzero — a pentagram's center is inside; open polylines are never
//   filled). The ellipse distance is exact (= a dense brute force).
// - Order (4.10): annotation > ink (shapes) > underlay at the same point, the
//   larger z within a layer; hidden objects count, previews do not (neither a
//   new id nor a moved copy of a committed one), pending-removed objects do not
//   (until discardEdit). A rotated frame takes the tap within the tolerance in its
//   own axes, past its AABB + tolerance (the candidates reach tolerance·√2).
// - The object index: 300 random objects × 500 random points = a brute-force
//   scan with the same rule and order, also after updateContent adds, moves and
//   removes objects (the index follows the diff), and after a page reset.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/object/object_hit.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../../support/pixels.dart' show segment, strokeThrough;

const _pageId = 'p1';
const _red = 0xFFDD0000;

core.ShapeObject _shape(
  String id,
  core.ShapeGeometry geometry, {
  core.ShapeKind kind = core.ShapeKind.rectangle,
  double width = 4,
  int? fill,
  core.LineDash dash = core.LineDash.solid,
  core.ArrowHeads heads = core.ArrowHeads.none,
  int createdAt = 1,
}) => core.ShapeObject(
  id: id,
  pageId: _pageId,
  shapeKind: kind,
  geometry: geometry,
  style: core.ShapeStyle(
    strokeColorArgb: _red,
    strokeWidth: width,
    dash: dash,
    fillColorArgb: fill,
    arrowHeads: heads,
  ),
  createdAt: createdAt,
);

core.TextBoxObject _text(
  String id,
  core.PageRect rect, {
  double rotation = 0,
  int createdAt = 1,
}) => core.TextBoxObject(
  id: id,
  pageId: _pageId,
  frame: core.ElementFrame(rect, rotation: rotation),
  text: 'hello',
  style: const core.TextBoxStyle(),
  createdAt: createdAt,
);

InkPageContent _content(
  List<core.PageObject> objects, {
  int revision = 1,
  core.PageSize size = core.PageSize.a4Portrait,
}) => InkPageContent.fromCore(
  page: SyntheticInk.page(pageId: _pageId, size: size),
  strokes: const [],
  objects: objects,
  revision: revision,
);

bool _hits(core.PageObject o, double x, double y, {double tol = 0}) =>
    ObjectHitTest.hits(o, ui.Offset(x, y), tol);

/// The 4.10 order rank of an object (annotation > shapes > underlay).
int _rank(core.PageObject o) => switch (o) {
  core.ImageObject() => 0,
  core.ShapeObject() => 1,
  _ => 2,
};

/// Brute force: every object of [objects] that is hit, the topmost by layer then z.
core.PageObject? _bruteForce(
  List<core.PageObject> objects,
  ui.Offset p,
  double tol,
) {
  core.PageObject? best;
  for (final o in objects) {
    if (!ObjectHitTest.hits(o, p, tol)) continue;
    if (best == null) {
      best = o;
      continue;
    }
    final byRank = _rank(o).compareTo(_rank(best));
    if (byRank > 0 || (byRank == 0 && core.Stroke.compareOrder(o, best) > 0)) {
      best = o;
    }
  }
  return best;
}

core.PageObject _randomObject(math.Random r, int k) {
  final x = r.nextDouble() * 560, y = r.nextDouble() * 800;
  final w = 4 + r.nextDouble() * 120, h = 4 + r.nextDouble() * 90;
  final rect = core.PageRect(x, y, x + w, y + h);
  final rot = r.nextBool() ? 0.0 : (r.nextDouble() - 0.5) * math.pi;
  final id = 'o$k';
  final createdAt = r.nextInt(50);
  switch (r.nextInt(6)) {
    case 0:
      return _text(id, rect, rotation: rot, createdAt: createdAt);
    case 1:
      return PageObjectFixtures.image(
        pageId: _pageId,
        assetId: 'a$k',
        id: id,
        rect: rect,
        createdAt: createdAt,
      );
    case 2:
      return _shape(
        id,
        core.ShapeGeometry.ellipse(rect, rotation: rot),
        kind: core.ShapeKind.ellipse,
        width: 0.5 + r.nextDouble() * 8,
        fill: r.nextBool() ? 0xFF00AA00 : null,
        dash: core.LineDash.values[r.nextInt(3)],
        createdAt: createdAt,
      );
    case 3:
      return _shape(
        id,
        core.ShapeGeometry.line(
          core.PagePoint(x, y),
          core.PagePoint(x + w, y + h),
        ),
        kind: core.ShapeKind.arrow,
        width: 0.5 + r.nextDouble() * 6,
        heads: core.ArrowHeads.values[r.nextInt(3)],
        createdAt: createdAt,
      );
    case 4:
      return _shape(
        id,
        core.ShapeGeometry.star(rect),
        kind: core.ShapeKind.star,
        width: 0.5 + r.nextDouble() * 6,
        fill: r.nextBool() ? 0xFF00AA00 : null,
        dash: core.LineDash.values[r.nextInt(3)],
        createdAt: createdAt,
      );
    default:
      return PageObjectFixtures.math(
        pageId: _pageId,
        id: id,
        rect: rect,
        createdAt: createdAt,
      );
  }
}

void main() {
  group('per kind (ObjectHitTest)', () {
    test('frame kinds: inside the rotated frame within the tolerance', () {
      final rect = const core.PageRect(100, 100, 200, 140);
      final objects = <core.PageObject>[
        _text('t', rect),
        PageObjectFixtures.math(pageId: _pageId, id: 'm', rect: rect),
        PageObjectFixtures.image(
          pageId: _pageId,
          assetId: 'a',
          id: 'i',
          rect: rect,
        ),
        PageObjectFixtures.unknown(pageId: _pageId, id: 'u', rect: rect),
      ];
      for (final o in objects) {
        expect(_hits(o, 150, 120), isTrue, reason: '${o.type} inside');
        expect(_hits(o, 99, 120), isFalse, reason: '${o.type} 1 pt left');
        expect(_hits(o, 99, 120, tol: 1.01), isTrue, reason: '${o.type} tol');
        expect(_hits(o, 150, 145, tol: 4), isFalse, reason: '${o.type} below');
      }
      // rotated 90°: the frame stands up around its center (150, 120)
      final turned = _text('r', rect, rotation: math.pi / 2);
      expect(_hits(turned, 150, 165), isTrue);
      expect(_hits(turned, 190, 120), isFalse);
      // rotated 30°: a point just inside a local corner, one just outside
      final r30 = _text('r30', rect, rotation: math.pi / 6);
      final corners = r30.frame.corners;
      final c = r30.frame.center;
      for (final k in corners) {
        final toCenter = ui.Offset(c.x - k.x, c.y - k.y);
        final inward = toCenter / toCenter.distance;
        expect(
          ObjectHitTest.hits(r30, ui.Offset(k.x, k.y) + inward * 0.5, 0),
          isTrue,
        );
        expect(
          ObjectHitTest.hits(r30, ui.Offset(k.x, k.y) - inward * 2, 1),
          isFalse,
        );
      }
    });

    test(
      'an unfilled rectangle: the outline within tol + w / 2, not inside',
      () {
        final rect = _shape(
          'r',
          core.ShapeGeometry.rectangle(const core.PageRect(100, 100, 300, 200)),
        );
        expect(_hits(rect, 200, 150, tol: 4), isFalse, reason: 'empty inside');
        expect(_hits(rect, 200, 100), isTrue, reason: 'on the top edge');
        // w / 2 = 2, tol 3 → 5 pt from the edge
        expect(_hits(rect, 200, 95.01, tol: 3), isTrue);
        expect(_hits(rect, 200, 94.99, tol: 3), isFalse);
        expect(_hits(rect, 200, 104.99, tol: 3), isTrue, reason: 'inner side');
        expect(_hits(rect, 200, 105.01, tol: 3), isFalse);
        // the closing edge (left side) counts, the round join at a corner too
        expect(_hits(rect, 98.5, 150), isTrue);
        final d = 5 / math.sqrt2;
        expect(_hits(rect, 100 - d + 0.01, 100 - d + 0.01, tol: 3), isTrue);
        expect(_hits(rect, 100 - d - 0.05, 100 - d - 0.05, tol: 3), isFalse);
      },
    );

    test('a filled shape takes the tap inside (nonzero)', () {
      final filled = _shape(
        'f',
        core.ShapeGeometry.rectangle(const core.PageRect(100, 100, 300, 200)),
        fill: 0xFF00AA00,
      );
      expect(_hits(filled, 200, 150), isTrue);
      expect(_hits(filled, 320, 150, tol: 4), isFalse);
      // a pentagram drawn in one closed path: the center has winding 2 (nonzero:
      // inside — even-odd would leave it out)
      final c = const ui.Offset(400, 400);
      final star = [
        for (var k = 0; k < 5; k++)
          () {
            final a = -math.pi / 2 + k * 4 * math.pi / 5;
            return core.PagePoint(
              c.dx + 100 * math.cos(a),
              c.dy + 100 * math.sin(a),
            );
          }(),
      ];
      final pentagram = _shape(
        'p',
        core.PolylineGeometry(star, closed: true),
        kind: core.ShapeKind.star,
        fill: 0xFF00AA00,
      );
      expect(_hits(pentagram, c.dx, c.dy), isTrue);
      expect(
        ObjectHitTest.windingNumber([
          for (final p in star) ui.Offset(p.x, p.y),
        ], c).abs(),
        2,
      );
      final unfilled = _shape(
        'p2',
        core.PolylineGeometry(star, closed: true),
        kind: core.ShapeKind.star,
      );
      expect(_hits(unfilled, c.dx, c.dy, tol: 4), isFalse);
      // an open polyline is never filled (its fill color is ignored)
      final open = _shape(
        'o',
        core.PolylineGeometry(const [
          core.PagePoint(100, 500),
          core.PagePoint(300, 500),
          core.PagePoint(200, 650),
        ], closed: false),
        fill: 0xFF00AA00,
      );
      expect(_hits(open, 200, 540, tol: 4), isFalse);
      expect(_hits(open, 200, 500), isTrue);
    });

    test('ellipses: the exact distance, filled inside, rotation', () {
      final frame = core.ElementFrame(
        const core.PageRect(100, 100, 400, 220),
        rotation: 0.7,
      );
      // brute force: a 20 000-gon of the rotated ellipse
      final c = frame.center;
      final a = frame.rect.width / 2, b = frame.rect.height / 2;
      final cr = math.cos(frame.rotation), sr = math.sin(frame.rotation);
      final dense = [
        for (var k = 0; k <= 20000; k++)
          () {
            final t = 2 * math.pi * k / 20000;
            final x = a * math.cos(t), y = b * math.sin(t);
            return ui.Offset(c.x + x * cr - y * sr, c.y + x * sr + y * cr);
          }(),
      ];
      final r = math.Random(37);
      for (var i = 0; i < 400; i++) {
        final p = ui.Offset(
          c.x + (r.nextDouble() - 0.5) * 420,
          c.y + (r.nextDouble() - 0.5) * 420,
        );
        expect(
          ObjectHitTest.ellipseDistance(frame, p),
          closeTo(ObjectHitTest.polylineDistance(dense, p), 1e-3),
          reason: '$p',
        );
      }
      // the center and the axis points (the robust branches)
      final at = ui.Offset(c.x, c.y);
      expect(ObjectHitTest.ellipseDistance(frame, at), closeTo(b, 1e-9));
      final shape = _shape(
        'e',
        core.EllipseGeometry(frame),
        kind: core.ShapeKind.ellipse,
      );
      expect(ObjectHitTest.hits(shape, at, 4), isFalse, reason: 'unfilled');
      final filled = _shape(
        'ef',
        core.EllipseGeometry(frame),
        kind: core.ShapeKind.ellipse,
        fill: 0xFF00AA00,
      );
      expect(ObjectHitTest.hits(filled, at, 0), isTrue);
      // on the curve: the end of the major axis
      final end = ui.Offset(c.x + a * cr, c.y + a * sr);
      expect(ObjectHitTest.hits(shape, end, 0), isTrue);
      expect(
        ObjectHitTest.hits(shape, end + ui.Offset(cr, sr) * 6.01, 4),
        isFalse,
      );
      expect(
        ObjectHitTest.hits(shape, end + ui.Offset(cr, sr) * 5.99, 4),
        isTrue,
      );
      // a flat ellipse is a segment, a zero one a point
      final flat = core.ElementFrame(const core.PageRect(0, 50, 100, 50));
      expect(
        ObjectHitTest.ellipseDistance(flat, const ui.Offset(50, 60)),
        closeTo(10, 1e-9),
      );
      expect(
        ObjectHitTest.ellipseDistance(flat, const ui.Offset(103, 54)),
        closeTo(5, 1e-9),
      );
      final dot = core.ElementFrame(const core.PageRect(10, 10, 10, 10));
      expect(
        ObjectHitTest.ellipseDistance(dot, const ui.Offset(13, 14)),
        closeTo(5, 1e-9),
      );
    });

    test('dashed and dotted outlines count as a whole (gaps included)', () {
      for (final dash in [core.LineDash.dashed, core.LineDash.dotted]) {
        final line = _shape(
          'd',
          core.ShapeGeometry.line(
            const core.PagePoint(100, 100),
            const core.PagePoint(400, 100),
          ),
          kind: core.ShapeKind.line,
          dash: dash,
        );
        for (var x = 100.0; x <= 400; x += 0.5) {
          expect(_hits(line, x, 101.9), isTrue, reason: '$dash at $x');
        }
        expect(_hits(line, 250, 103), isFalse);
        final ellipse = _shape(
          'de',
          core.ShapeGeometry.ellipse(const core.PageRect(100, 300, 300, 400)),
          kind: core.ShapeKind.ellipse,
          dash: dash,
        );
        for (var k = 0; k < 64; k++) {
          final t = 2 * math.pi * k / 64;
          expect(
            _hits(ellipse, 200 + 100 * math.cos(t), 350 + 50 * math.sin(t)),
            isTrue,
            reason: '$dash ellipse at $k',
          );
        }
      }
    });

    test('arrow heads take the tap; the line ends at the head', () {
      // a 2 pt arrow from (100, 100) to (300, 100): L = 6, half angle 25°
      final arrow = _shape(
        'a',
        core.ShapeGeometry.line(
          const core.PagePoint(100, 100),
          const core.PagePoint(300, 100),
        ),
        kind: core.ShapeKind.arrow,
        width: 2,
        heads: core.ArrowHeads.both,
      );
      final l = arrow.style.arrowHeadLength;
      final half = l * math.sin(25 * math.pi / 180);
      // the head's back corners are farther from the line than w / 2
      expect(half, greaterThan(1));
      final back = 300 - l * math.cos(25 * math.pi / 180);
      expect(_hits(arrow, back + 0.2, 100 + half - 0.3), isTrue);
      expect(_hits(arrow, back + 0.2, 100 + half + 0.3), isFalse);
      expect(_hits(arrow, back + 0.2, 100 + half + 0.3, tol: 0.5), isTrue);
      // the start head too
      final front = 100 + l * math.cos(25 * math.pi / 180);
      expect(_hits(arrow, front - 0.2, 100 - half + 0.3), isTrue);
      // the apex
      expect(_hits(arrow, 300, 100), isTrue);
      expect(_hits(arrow, 300.5, 100), isFalse);
      expect(_hits(arrow, 300.5, 100, tol: 0.6), isTrue);
    });

    test('a dot shape, non-finite input and odd tolerances', () {
      final dot = _shape(
        'dot',
        core.ShapeGeometry.line(
          const core.PagePoint(50, 50),
          const core.PagePoint(50, 50),
        ),
        kind: core.ShapeKind.line,
      );
      expect(_hits(dot, 51.9, 50), isTrue);
      expect(_hits(dot, 52.1, 50), isFalse);
      final box = _text('t', const core.PageRect(0, 0, 10, 10));
      expect(
        ObjectHitTest.hits(box, const ui.Offset(double.nan, 5), 4),
        isFalse,
      );
      expect(
        ObjectHitTest.hits(box, const ui.Offset(double.infinity, 5), 4),
        isFalse,
      );
      expect(
        ObjectHitTest.hits(box, const ui.Offset(11, 5), double.nan),
        isFalse,
      );
      expect(ObjectHitTest.hits(box, const ui.Offset(11, 5), -3), isFalse);
      expect(ObjectHitTest.hits(box, const ui.Offset(10, 5), -3), isTrue);
    });
  });

  group('controller.hitTestObject', () {
    late InkPageController c;
    setUp(() => c = createTestPageController(pageId: _pageId));
    tearDown(() => c.dispose());

    test('annotation > shapes > underlay; the larger z within a layer', () {
      final image = PageObjectFixtures.image(
        pageId: _pageId,
        assetId: 'a',
        id: 'img',
        rect: const core.PageRect(100, 100, 300, 300),
        createdAt: 50, // newer than everything — the layer still wins
      );
      final lowShape = _shape(
        'sh-low',
        core.ShapeGeometry.rectangle(const core.PageRect(150, 150, 250, 250)),
        fill: 0xFF00AA00,
        createdAt: 2,
      );
      final highShape = _shape(
        'sh-high',
        core.ShapeGeometry.rectangle(const core.PageRect(180, 180, 280, 280)),
        fill: 0xFF0000AA,
        createdAt: 3,
      );
      final text = _text(
        'tx',
        const core.PageRect(200, 200, 260, 220),
        createdAt: 1,
      );
      final newer = _text(
        'tx2',
        const core.PageRect(240, 210, 290, 230),
        createdAt: 4,
      );
      c.updateContent(_content([image, lowShape, highShape, text, newer]));
      expect(c.hitTestObject(const ui.Offset(120, 120))?.id, 'img');
      expect(c.hitTestObject(const ui.Offset(160, 160))?.id, 'sh-low');
      expect(c.hitTestObject(const ui.Offset(200, 190))?.id, 'sh-high');
      expect(c.hitTestObject(const ui.Offset(210, 210))?.id, 'tx');
      expect(c.hitTestObject(const ui.Offset(250, 215))?.id, 'tx2');
      expect(c.hitTestObject(const ui.Offset(500, 500)), isNull);
      expect(c.hitTestObject(const ui.Offset(double.nan, 5)), isNull);
    });

    test('a rotated frame within the tolerance past its AABB', () {
      // a 100 pt square turned 45°: its corner is 70.7 pt right of the center, the
      // tolerance 8 in the frame's own axes reaches 82.0 pt — past bounds + 8
      final box = _text(
        'r45',
        const core.PageRect(100, 100, 200, 200),
        rotation: math.pi / 4,
      );
      c.updateContent(_content([box]));
      expect(box.bounds.right + 8, lessThan(231));
      expect(
        c.hitTestObject(const ui.Offset(231, 150), tolerance: 8)?.id,
        'r45',
      );
      expect(c.hitTestObject(const ui.Offset(233, 150), tolerance: 8), isNull);
    });

    test('strokes are not objects; an unfilled shape lets the tap through', () {
      final image = PageObjectFixtures.image(
        pageId: _pageId,
        assetId: 'a',
        id: 'img',
        rect: const core.PageRect(100, 100, 300, 300),
      );
      final frame = _shape(
        'frame',
        core.ShapeGeometry.rectangle(const core.PageRect(90, 90, 310, 310)),
        createdAt: 5,
      );
      c.updateContent(
        InkPageContent.fromCore(
          page: SyntheticInk.page(pageId: _pageId),
          strokes: [
            strokeThrough(
              segment(const ui.Offset(150, 200), const ui.Offset(250, 200)),
              core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
              id: 's1',
              createdAt: 9,
            ),
          ],
          objects: [image, frame],
          revision: 1,
        ),
      );
      expect(c.hitTestObject(const ui.Offset(200, 200))?.id, 'img');
      expect(c.hitTestObject(const ui.Offset(91, 200))?.id, 'frame');
      expect(c.hitTest(const ui.Offset(200, 200))?.id, 's1');
    });

    test('hidden objects count; previews never do', () {
      final text = _text('tx', const core.PageRect(100, 100, 200, 140));
      final shape = _shape(
        'sh',
        core.ShapeGeometry.rectangle(const core.PageRect(300, 100, 400, 200)),
        fill: 0xFF00AA00,
      );
      c.updateContent(_content([text, shape]));
      c.setHiddenObjectIds({'tx'});
      expect(c.hitTestObject(const ui.Offset(150, 120))?.id, 'tx');
      // a preview that moves the committed shape: the committed one is still hit,
      // the preview's place is not
      c.setPreviewObjects([
        shape.transformed(core.Affine2.translation(0, 300), scaleWidth: true),
        _text('new', const core.PageRect(100, 600, 200, 640)),
      ]);
      expect(c.hitTestObject(const ui.Offset(350, 150))?.id, 'sh');
      expect(c.hitTestObject(const ui.Offset(350, 450)), isNull);
      expect(c.hitTestObject(const ui.Offset(150, 620)), isNull);
    });

    test('pending-removed objects are skipped until the edit is dropped', () {
      final low = _shape(
        'low',
        core.ShapeGeometry.rectangle(const core.PageRect(100, 100, 300, 300)),
        fill: 0xFF00AA00,
        createdAt: 1,
      );
      final high = _shape(
        'high',
        core.ShapeGeometry.rectangle(const core.PageRect(150, 150, 250, 250)),
        fill: 0xFF0000AA,
        createdAt: 2,
      );
      c.updateContent(_content([low, high]));
      expect(c.hitTestObject(const ui.Offset(200, 200))?.id, 'high');
      final edit = c.select({'high'}).delete();
      expect(c.hitTestObject(const ui.Offset(200, 200))?.id, 'low');
      c.discardEdit(edit);
      expect(c.hitTestObject(const ui.Offset(200, 200))?.id, 'high');
    });

    test('the object index = a brute-force scan, also after updates', () {
      final r = math.Random(2037);
      var objects = [for (var k = 0; k < 300; k++) _randomObject(r, k)];
      var revision = 1;
      void check(String when) {
        for (var i = 0; i < 500; i++) {
          final p = ui.Offset(r.nextDouble() * 600, r.nextDouble() * 860);
          final tol = [0.0, 2.0, 4.0, 8.0][i % 4];
          expect(
            c.hitTestObject(p, tolerance: tol)?.id,
            _bruteForce(objects, p, tol)?.id,
            reason: '$when: $p tol $tol',
          );
        }
      }

      c.updateContent(_content(objects, revision: revision++));
      check('first content');
      // move 60, remove 40, add 50 (some on top, some below) — the index follows
      // the diff
      final moved = <core.PageObject>[
        for (var k = 0; k < objects.length; k++)
          if (k % 5 == 0)
            objects[k].transformed(
              core.Affine2.translation(
                r.nextDouble() * 80 - 40,
                r.nextDouble() * 80 - 40,
              ),
              scaleWidth: true,
            )
          else if (k % 7 != 3)
            objects[k],
      ];
      objects = [...moved, for (var k = 300; k < 350; k++) _randomObject(r, k)];
      c.updateContent(_content(objects, revision: revision++));
      check('after moves, removals and additions');
      // a page size change resets the index
      c.updateContent(
        _content(
          objects,
          revision: revision++,
          size: core.PageSize.letterPortrait,
        ),
      );
      check('after a reset');
    });
  });
}
