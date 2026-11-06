// m5-7/04-editor 6.6.5 (single object handles — pure math). (v2, E2-06 part
// 2) ObjectResize.cornerScale — the corners of a single object are drawn on
// its rotated frame (6.6.4), so their drag lands here first (review S-2 →
// EDITOR-M5). The edge / vertex / text width cases come with E2-08.
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
}
