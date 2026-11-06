// m5-7/04-editor 6.6.5 (single object handles — pure math). (v2, E2-06 part
// 2) ObjectResize.cornerScale — the corners of a single object are drawn on
// its rotated frame (6.6.4), so their drag lands here first (review S-2 →
// EDITOR-M5). (E2-08) the edge / vertex / text width cases: a polyline edge
// scales the points on one axis, a turned ellipse's edge changes its local
// rect (the angle kept), the text width stops at 40 pt, every side stops at
// its minimum, a line's end point snaps its angle (15° within ±3° — the test
// angles stay ≥ 1° from the borders, review S-12(f)).
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:feature_editor/src/tools/object_resize.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

core.PagePoint _apply(core.Affine2 m, core.PagePoint p) => p.transformed(m);

void main() {
  const deg30 = math.pi / 6;
  // A 200 × 100 image frame turned 30° about its centre (400, 300).
  const frame = core.ElementFrame(
    core.PageRect(300, 250, 500, 350),
    rotation: deg30,
  );

  group('cornerScale', () {
    test('a 30° image (200 × 100): dragging the bottom-right corner along '
        'the diagonal keeps the rotated top-left corner (1e-9), the 2:1 '
        'ratio and the rotation', () {
      final corners = frame.corners;
      final o = corners[0], c = corners[2];
      final diagonal = Offset(c.x - o.x, c.y - o.y);
      final delta = diagonal / diagonal.distance * 40; // 40 pt outwards
      final m = ObjectResize.cornerScale(
        frame,
        ink.SelectionHandle.bottomRight,
        delta,
      );
      final fixed = _apply(m, o);
      expect(fixed.x, closeTo(o.x, 1e-9));
      expect(fixed.y, closeTo(o.y, 1e-9));
      final moved = _apply(m, c);
      expect(moved.x, closeTo(c.x + delta.dx, 1e-9));
      expect(moved.y, closeTo(c.y + delta.dy, 1e-9));
      expect(m.rotation, closeTo(0, 1e-12)); // a pure scale
      final image = PageObjectFixtures.image(
        pageId: 'p',
        assetId: 'a',
      ).copyWith(frame: frame);
      final after = image.transformed(m).frame;
      expect(after.rotation, closeTo(deg30, 1e-12));
      final w = after.rect.right - after.rect.left;
      final h = after.rect.bottom - after.rect.top;
      expect(w / h, closeTo(2, 1e-9));
      final s = (diagonal.distance + 40) / diagonal.distance;
      expect(w, closeTo(200 * s, 1e-9));
      expect(after.corners[0].x, closeTo(o.x, 1e-9));
      expect(after.corners[0].y, closeTo(o.y, 1e-9));
    });

    test('a delta perpendicular to the diagonal → scale 1', () {
      final corners = frame.corners;
      final o = corners[3], c = corners[1]; // top-right from bottom-left
      final d = Offset(c.x - o.x, c.y - o.y);
      final normal = Offset(-d.dy, d.dx) / d.distance * 30;
      final m = ObjectResize.cornerScale(
        frame,
        ink.SelectionHandle.topRight,
        normal,
      );
      expect(m.isIdentity, isTrue);
    });

    test('dragging past the opposite corner stops at the minimum size', () {
      final m = ObjectResize.cornerScale(
        frame,
        ink.SelectionHandle.bottomRight,
        const Offset(-900, -900),
        minWidth: ObjectResize.minImageSidePt,
        minHeight: ObjectResize.minImageSidePt,
      );
      // 16 pt on the short side (100 pt) → s = 0.16.
      expect(m.uniformScale, closeTo(0.16, 1e-12));
      final o = frame.corners[0];
      final fixed = _apply(m, o);
      expect(fixed.x, closeTo(o.x, 1e-9));
      expect(fixed.y, closeTo(o.y, 1e-9));
      // The default minimum (4 pt).
      final small = ObjectResize.cornerScale(
        frame,
        ink.SelectionHandle.topLeft,
        const Offset(900, 900),
      );
      expect(small.uniformScale, closeTo(0.04, 1e-12));
      // Text boxes: 40 pt wide.
      expect(ObjectResize.minimumOf(PageObjectFixtures.textBox(pageId: 'p')), (
        width: 40.0,
        height: 4.0,
      ));
      expect(
        ObjectResize.minimumOf(
          PageObjectFixtures.image(pageId: 'p', assetId: 'a'),
        ),
        (width: 16.0, height: 16.0),
      );
      expect(ObjectResize.minimumOf(PageObjectFixtures.shape(pageId: 'p')), (
        width: 4.0,
        height: 4.0,
      ));
    });

    test('never above ElementFrame.maxSide', () {
      final m = ObjectResize.cornerScale(
        frame,
        ink.SelectionHandle.bottomRight,
        const Offset(1e6, 1e6),
      );
      expect(m.uniformScale, closeTo(core.ElementFrame.maxSide / 200, 1e-9));
    });

    test('rotation 0: the same as SelectionGeometry.resize(keepAspect: true) '
        'on the frame rect', () {
      const flat = core.ElementFrame(core.PageRect(100, 120, 260, 200));
      const rect = Rect.fromLTRB(100, 120, 260, 200);
      for (final handle in const [
        ink.SelectionHandle.topLeft,
        ink.SelectionHandle.topRight,
        ink.SelectionHandle.bottomRight,
        ink.SelectionHandle.bottomLeft,
      ]) {
        for (final delta in const [
          Offset(30, 12),
          Offset(-20, 5),
          Offset(8, -40),
        ]) {
          final mine = ObjectResize.cornerScale(flat, handle, delta);
          final ink0 = ink.SelectionGeometry.resize(
            bounds: rect,
            handle: handle,
            delta: delta,
            keepAspect: true,
          );
          for (final p in const [
            core.PagePoint(100, 120),
            core.PagePoint(260, 200),
            core.PagePoint(180, 150),
          ]) {
            final a = _apply(mine, p), b = _apply(ink0, p);
            expect(a.x, closeTo(b.x, 1e-9), reason: '$handle $delta');
            expect(a.y, closeTo(b.y, 1e-9), reason: '$handle $delta');
          }
        }
      }
    });

    test('an edge handle or a frame without size → identity', () {
      expect(
        ObjectResize.cornerScale(
          frame,
          ink.SelectionHandle.top,
          const Offset(10, 10),
        ).isIdentity,
        isTrue,
      );
      expect(
        ObjectResize.cornerScale(
          const core.ElementFrame(core.PageRect(10, 10, 10, 10)),
          ink.SelectionHandle.bottomRight,
          const Offset(10, 10),
        ).isIdentity,
        isTrue,
      );
    });
  });

  group('resize (edges, E2-08)', () {
    test('a polyline (rectangle) edge: the points scale on that axis only, '
        'the opposite side stays', () {
      final rect = PageObjectFixtures.shape(pageId: 'p'); // 100,100 – 300,220
      final points = (rect.geometry as core.PolylineGeometry).points;
      final right =
          ObjectResize.resize(
                rect,
                ink.SelectionHandle.right,
                const Offset(50, 17), // the y part is ignored
                keepAspect: false,
              )!
              as core.ShapeObject;
      expect(right.id, rect.id);
      expect(right.shapeKind, core.ShapeKind.rectangle);
      final moved = (right.geometry as core.PolylineGeometry).points;
      expect(moved, hasLength(points.length));
      for (var i = 0; i < points.length; i++) {
        expect(moved[i].x, closeTo(100 + (points[i].x - 100) * 1.25, 1e-9));
        expect(moved[i].y, closeTo(points[i].y, 1e-9));
      }
      expect(right.frame.rect.left, closeTo(100, 1e-9));
      expect(right.frame.rect.right, closeTo(350, 1e-9));
      expect(right.style, rect.style); // the width is not scaled (an edit)

      final top =
          ObjectResize.resize(
                rect,
                ink.SelectionHandle.top,
                const Offset(5, -30),
                keepAspect: false,
              )!
              as core.ShapeObject;
      final up = (top.geometry as core.PolylineGeometry).points;
      for (var i = 0; i < points.length; i++) {
        expect(up[i].x, closeTo(points[i].x, 1e-9));
        expect(up[i].y, closeTo(220 + (points[i].y - 220) * 150 / 120, 1e-9));
      }
    });

    test('a pentagon edge scales every vertex (anchor + (x − anchor)·s)', () {
      final pentagon = PageObjectFixtures.shape(
        pageId: 'p',
        kind: core.ShapeKind.polygon,
      );
      final box = pentagon.frame.rect;
      final points = (pentagon.geometry as core.PolylineGeometry).points;
      final out =
          ObjectResize.resize(
                pentagon,
                ink.SelectionHandle.left,
                const Offset(-40, 0),
                keepAspect: false,
              )!
              as core.ShapeObject;
      final w = box.right - box.left;
      final s = (w + 40) / w;
      final moved = (out.geometry as core.PolylineGeometry).points;
      for (var i = 0; i < points.length; i++) {
        expect(
          moved[i].x,
          closeTo(box.right + (points[i].x - box.right) * s, 1e-9),
        );
        expect(moved[i].y, closeTo(points[i].y, 1e-9));
      }
      expect(out.shapeKind, core.ShapeKind.polygon);
    });

    test('a 30° ellipse: an edge changes the local rect, the angle and the '
        'opposite side stay', () {
      final ellipse = PageObjectFixtures.shape(
        pageId: 'p',
        kind: core.ShapeKind.ellipse,
      ).copyWith(geometry: const core.EllipseGeometry(frame));
      const u = Offset(0.8660254037844387, 0.5); // cos 30°, sin 30°
      const v = Offset(-0.5, 0.8660254037844387);
      final out =
          ObjectResize.resize(
                ellipse,
                ink.SelectionHandle.right,
                u * 40 +
                    v * 15, // 40 pt along the ellipse's x, 15 across (ignored)
                keepAspect: false,
              )!
              as core.ShapeObject;
      final f = (out.geometry as core.EllipseGeometry).ellipseFrame;
      expect(f.rotation, closeTo(deg30, 1e-12));
      expect(f.rect.right - f.rect.left, closeTo(240, 1e-9));
      expect(f.rect.bottom - f.rect.top, closeTo(100, 1e-9));
      // The left side's middle (rotated) stays put.
      Offset leftMiddle(core.ElementFrame e) {
        final c = e.corners;
        return Offset((c[0].x + c[3].x) / 2, (c[0].y + c[3].y) / 2);
      }

      final before = leftMiddle(frame), after = leftMiddle(f);
      expect(after.dx, closeTo(before.dx, 1e-9));
      expect(after.dy, closeTo(before.dy, 1e-9));
      expect(out.frame, f); // ShapeObject.frame = the ellipse frame

      final bottom =
          ObjectResize.resize(
                ellipse,
                ink.SelectionHandle.bottom,
                v * -30,
                keepAspect: false,
              )!
              as core.ShapeObject;
      final g = (bottom.geometry as core.EllipseGeometry).ellipseFrame;
      expect(g.rect.bottom - g.rect.top, closeTo(70, 1e-9));
      expect(g.rect.right - g.rect.left, closeTo(200, 1e-9));
      expect(g.rotation, closeTo(deg30, 1e-12));
      final topBefore = frame.corners[0], topAfter = g.corners[0];
      expect(topAfter.x, closeTo(topBefore.x, 1e-9));
      expect(topAfter.y, closeTo(topBefore.y, 1e-9));
    });

    test('an image (aspect unlocked): an edge resizes its frame freely; '
        'keepAspect scales the other side about the dragged axis', () {
      final image = PageObjectFixtures.image(
        pageId: 'p',
        assetId: 'a',
      ).copyWith(frame: const core.ElementFrame(core.PageRect(0, 0, 200, 100)));
      final free =
          ObjectResize.resize(
                image,
                ink.SelectionHandle.right,
                const Offset(100, 0),
                keepAspect: false,
              )!
              as core.ImageObject;
      expect(free.frame.rect, const core.PageRect(0, 0, 300, 100));
      expect(free.assetId, 'a');
      final kept =
          ObjectResize.resize(
                image,
                ink.SelectionHandle.right,
                const Offset(100, 0),
                keepAspect: true,
              )!
              as core.ImageObject;
      expect(kept.frame.rect.left, closeTo(0, 1e-9));
      expect(kept.frame.rect.right, closeTo(300, 1e-9));
      expect(kept.frame.rect.top, closeTo(-25, 1e-9));
      expect(kept.frame.rect.bottom, closeTo(125, 1e-9));
    });

    test('the sides stop at their minimum (4 pt; image 16 pt; a side already '
        'shorter does not shrink) and at ElementFrame.maxSide', () {
      final rect = PageObjectFixtures.shape(pageId: 'p');
      final thin = ObjectResize.resize(
        rect,
        ink.SelectionHandle.right,
        const Offset(-1000, 0),
        keepAspect: false,
      )!;
      expect(thin.frame.rect.left, closeTo(100, 1e-9));
      expect(thin.frame.rect.right, closeTo(104, 1e-9));
      final image = PageObjectFixtures.image(
        pageId: 'p',
        assetId: 'a',
      ).copyWith(frame: const core.ElementFrame(core.PageRect(0, 0, 200, 100)));
      final low = ObjectResize.resize(
        image,
        ink.SelectionHandle.top,
        const Offset(0, 1000),
        keepAspect: false,
      )!;
      expect(low.frame.rect.bottom, closeTo(100, 1e-9));
      expect(low.frame.rect.top, closeTo(84, 1e-9)); // 16 pt
      final tiny = image.copyWith(
        frame: const core.ElementFrame(core.PageRect(0, 0, 10, 10)),
      );
      final still = ObjectResize.resize(
        tiny,
        ink.SelectionHandle.right,
        const Offset(-5, 0),
        keepAspect: false,
      )!;
      expect(still.frame.rect.right, closeTo(10, 1e-9));
      final huge = ObjectResize.resize(
        image,
        ink.SelectionHandle.right,
        const Offset(1e6, 0),
        keepAspect: false,
      )!;
      expect(
        huge.frame.rect.right - huge.frame.rect.left,
        closeTo(core.ElementFrame.maxSide, 1e-6),
      );
    });

    test('handles that do not apply → null', () {
      final unknown = PageObjectFixtures.unknown(pageId: 'p');
      final math0 = PageObjectFixtures.math(pageId: 'p');
      final text = PageObjectFixtures.textBox(pageId: 'p');
      final line = PageObjectFixtures.shape(
        pageId: 'p',
        kind: core.ShapeKind.line,
        rect: const core.PageRect(100, 100, 300, 100), // flat
      );
      expect(
        ObjectResize.resize(
          unknown,
          ink.SelectionHandle.right,
          const Offset(10, 0),
          keepAspect: false,
        ),
        isNull,
      );
      expect(
        ObjectResize.resize(
          math0,
          ink.SelectionHandle.right,
          const Offset(10, 0),
          keepAspect: false,
        ),
        isNull,
      );
      for (final edge in const [
        ink.SelectionHandle.top,
        ink.SelectionHandle.bottom,
      ]) {
        expect(
          ObjectResize.resize(
            text,
            edge,
            const Offset(0, 10),
            keepAspect: false,
          ),
          isNull,
        );
      }
      expect(
        ObjectResize.resize(
          line,
          ink.SelectionHandle.bottom,
          const Offset(0, 10),
          keepAspect: false,
        ),
        isNull,
      );
    });
  });

  group('resizeTextWidth · withMeasuredHeight (E2-08)', () {
    test('the width follows the side, at least 40 pt; the other side, the '
        'height and the text stay', () {
      final box = PageObjectFixtures.textBox(pageId: 'p'); // 100,300 – 400,340
      final wider = ObjectResize.resizeTextWidth(
        box,
        ink.SelectionHandle.right,
        const Offset(60, 9),
      );
      expect(wider.frame.rect, const core.PageRect(100, 300, 460, 340));
      expect(wider.text, box.text);
      expect(wider.style, box.style);
      final narrow = ObjectResize.resizeTextWidth(
        box,
        ink.SelectionHandle.left,
        const Offset(500, 0),
      );
      expect(narrow.frame.rect.right, closeTo(400, 1e-9));
      expect(
        narrow.frame.rect.right - narrow.frame.rect.left,
        closeTo(ObjectResize.minTextWidthPt, 1e-9),
      );
      expect(
        ObjectResize.resizeTextWidth(
          box,
          ink.SelectionHandle.top,
          const Offset(0, 50),
        ),
        same(box),
      );
    });

    test('a 30° box: the width along its own axis, the left side kept', () {
      final box = PageObjectFixtures.textBox(pageId: 'p')
          .copyWith(frame: frame);
      const u = Offset(0.8660254037844387, 0.5);
      final out = ObjectResize.resizeTextWidth(
        box,
        ink.SelectionHandle.right,
        u * 50,
      );
      expect(out.frame.rotation, closeTo(deg30, 1e-12));
      expect(out.frame.rect.right - out.frame.rect.left, closeTo(250, 1e-9));
      final a = frame.corners, b = out.frame.corners;
      for (final i in const [0, 3]) {
        expect(b[i].x, closeTo(a[i].x, 1e-9));
        expect(b[i].y, closeTo(a[i].y, 1e-9));
      }
    });

    test('withMeasuredHeight: at least one line, the (rotated) top edge '
        'kept', () {
      final box = PageObjectFixtures.textBox(pageId: 'p'); // height 40
      final taller = ObjectResize.withMeasuredHeight(box, 90);
      expect(taller.frame.rect, const core.PageRect(100, 300, 400, 390));
      final line = box.style.fontSizePt * box.style.lineHeight;
      final short = ObjectResize.withMeasuredHeight(box, 1);
      expect(
        short.frame.rect.bottom - short.frame.rect.top,
        closeTo(line, 1e-9),
      );
      final turned = box.copyWith(frame: frame);
      final grown = ObjectResize.withMeasuredHeight(turned, 160);
      expect(grown.frame.rotation, closeTo(deg30, 1e-12));
      expect(
        grown.frame.rect.bottom - grown.frame.rect.top,
        closeTo(160, 1e-9),
      );
      for (final i in const [0, 1]) {
        expect(grown.frame.corners[i].x, closeTo(frame.corners[i].x, 1e-9));
        expect(grown.frame.corners[i].y, closeTo(frame.corners[i].y, 1e-9));
      }
    });
  });

  group('moveVertex (E2-08)', () {
    final line = PageObjectFixtures.shape(
      pageId: 'p',
      kind: core.ShapeKind.line,
      rect: const core.PageRect(100, 100, 200, 100), // (100,100) → (200,100)
    );

    core.PagePoint endAt(double degrees, double length) {
      final a = degrees * math.pi / 180;
      return core.PagePoint(
        100 + math.cos(a) * length,
        100 + math.sin(a) * length,
      );
    }

    Offset deltaTo(core.PagePoint target) =>
        Offset(target.x - 200, target.y - 100);

    test('a line end point at 14° → snapped to 15° (the length kept); 20° '
        'stays', () {
      final snapped = ObjectResize.moveVertex(line, 1, deltaTo(endAt(14, 150)));
      final p = (snapped.geometry as core.PolylineGeometry).points;
      expect(p[0], const core.PagePoint(100, 100));
      final want = endAt(15, 150);
      expect(p[1].x, closeTo(want.x, 1e-9));
      expect(p[1].y, closeTo(want.y, 1e-9));
      expect(snapped.shapeKind, core.ShapeKind.line);
      expect(snapped.id, line.id);

      final free = ObjectResize.moveVertex(line, 1, deltaTo(endAt(20, 150)));
      final q = (free.geometry as core.PolylineGeometry).points;
      final at20 = endAt(20, 150);
      expect(q[1].x, closeTo(at20.x, 1e-9));
      expect(q[1].y, closeTo(at20.y, 1e-9));

      final noSnap = ObjectResize.moveVertex(
        line,
        1,
        deltaTo(endAt(14, 150)),
        snapAngle: false,
      );
      final r = (noSnap.geometry as core.PolylineGeometry).points;
      final at14 = endAt(14, 150);
      expect(r[1].x, closeTo(at14.x, 1e-9));
      expect(r[1].y, closeTo(at14.y, 1e-9));
    });

    test('the start point of an arrow snaps about the end point', () {
      final arrow = PageObjectFixtures.shape(
        pageId: 'p',
        kind: core.ShapeKind.arrow,
        rect: const core.PageRect(100, 100, 200, 100),
      );
      // Move (100,100) to 46° from (200,100) seen backwards: angle from the
      // other end = 180° + 46°.
      final a = (180 + 46) * math.pi / 180;
      final target = Offset(200 + math.cos(a) * 100, 100 + math.sin(a) * 100);
      final out = ObjectResize.moveVertex(
        arrow,
        0,
        target - const Offset(100, 100),
      );
      final p = (out.geometry as core.PolylineGeometry).points;
      final want = (180 + 45) * math.pi / 180;
      expect(p[0].x, closeTo(200 + math.cos(want) * 100, 1e-9));
      expect(p[0].y, closeTo(100 + math.sin(want) * 100, 1e-9));
      expect(out.style.arrowHeads, core.ArrowHeads.end);
    });

    test('a polygon vertex moves by the delta (no snapping), shapeKind and '
        'the other points kept; a bad index or an ellipse → unchanged', () {
      final triangle = PageObjectFixtures.shape(
        pageId: 'p',
        kind: core.ShapeKind.triangle,
      );
      final points = (triangle.geometry as core.PolylineGeometry).points;
      final out = ObjectResize.moveVertex(triangle, 0, const Offset(13, -7));
      final moved = (out.geometry as core.PolylineGeometry).points;
      expect(moved[0].x, closeTo(points[0].x + 13, 1e-12));
      expect(moved[0].y, closeTo(points[0].y - 7, 1e-12));
      expect(moved.sublist(1), points.sublist(1));
      expect(out.shapeKind, core.ShapeKind.triangle);
      expect((out.geometry as core.PolylineGeometry).closed, isTrue);
      expect(
        ObjectResize.moveVertex(triangle, 9, const Offset(1, 1)),
        same(triangle),
      );
      final ellipse = PageObjectFixtures.shape(
        pageId: 'p',
        kind: core.ShapeKind.ellipse,
      );
      expect(
        ObjectResize.moveVertex(ellipse, 0, const Offset(1, 1)),
        same(ellipse),
      );
    });

    test('isEndpointShape: a line / an arrow with two points only', () {
      expect(ObjectResize.isEndpointShape(line), isTrue);
      expect(
        ObjectResize.isEndpointShape(
          PageObjectFixtures.shape(pageId: 'p', kind: core.ShapeKind.arrow),
        ),
        isTrue,
      );
      expect(
        ObjectResize.isEndpointShape(PageObjectFixtures.shape(pageId: 'p')),
        isFalse,
      );
    });
  });
}
