// E-10: SelectionHitTest (04-editor 6.6.5) — handles, body, clamped moves.
// (v2, E2-06 — m5-7/04-editor 6.6.4) rotated frames: the 8 handle positions
// and their hits on a turned quad, the rotate handle (outside the top edge's
// middle, along its outward normal) and the rotated body.
import 'dart:math' as math;
import 'dart:ui';

import 'package:feature_editor/src/tools/selection_hit_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;

/// [r] turned by [radians] about its centre (screen — clockwise positive).
SelectionQuad _turned(Rect r, double radians) {
  final c = r.center;
  Offset turn(Offset p) {
    final d = p - c;
    return c +
        Offset(
          d.dx * math.cos(radians) - d.dy * math.sin(radians),
          d.dx * math.sin(radians) + d.dy * math.cos(radians),
        );
  }

  return SelectionQuad(
    turn(r.topLeft),
    turn(r.topRight),
    turn(r.bottomRight),
    turn(r.bottomLeft),
  );
}

Matcher _near(Offset expected) => isA<Offset>()
    .having((o) => o.dx, 'dx', closeTo(expected.dx, 1e-9))
    .having((o) => o.dy, 'dy', closeTo(expected.dy, 1e-9));

void main() {
  const frame = Rect.fromLTWH(100, 200, 300, 160);

  group('hitHandle', () {
    test('each corner within 22 px hits its handle', () {
      expect(
        SelectionHitTest.hitHandle(frame, frame.topLeft),
        ink.SelectionHandle.topLeft,
      );
      expect(
        SelectionHitTest.hitHandle(
          frame,
          frame.topRight + const Offset(15, -15),
        ),
        ink.SelectionHandle.topRight,
      );
      expect(
        SelectionHitTest.hitHandle(
          frame,
          frame.bottomRight + const Offset(-22, 0),
        ),
        ink.SelectionHandle.bottomRight,
      );
      expect(
        SelectionHitTest.hitHandle(
          frame,
          frame.bottomLeft + const Offset(0, 22),
        ),
        ink.SelectionHandle.bottomLeft,
      );
    });

    test('farther than 22 px, or an edge middle → no handle', () {
      expect(
        SelectionHitTest.hitHandle(
          frame,
          frame.topLeft + const Offset(-16, -16),
        ),
        isNull, // 22.6 px
      );
      expect(
        SelectionHitTest.hitHandle(
          frame,
          frame.topLeft + const Offset(22.5, 0),
        ),
        isNull,
      );
      expect(SelectionHitTest.hitHandle(frame, frame.topCenter), isNull);
      expect(SelectionHitTest.hitHandle(frame, frame.center), isNull);
    });

    test('M1 shows the four corners only', () {
      expect(SelectionHitTest.cornerHandles, [
        ink.SelectionHandle.topLeft,
        ink.SelectionHandle.topRight,
        ink.SelectionHandle.bottomRight,
        ink.SelectionHandle.bottomLeft,
      ]);
      expect(SelectionHitTest.handleVisualRadius, 6);
      expect(SelectionHitTest.handleHitRadius, 22);
      expect(SelectionHitTest.bodyInflate, 8);
    });

    test('a small frame: the nearest corner wins', () {
      const small = Rect.fromLTWH(50, 50, 10, 10);
      expect(
        SelectionHitTest.hitHandle(small, const Offset(52, 51)),
        ink.SelectionHandle.topLeft,
      );
      expect(
        SelectionHitTest.hitHandle(small, const Offset(59, 59)),
        ink.SelectionHandle.bottomRight,
      );
      expect(
        SelectionHitTest.hitHandle(small, const Offset(58, 52)),
        ink.SelectionHandle.topRight,
      );
    });

    test('handle positions are the frame corners', () {
      for (final h in SelectionHitTest.cornerHandles) {
        final p = SelectionHitTest.handlePosition(frame, h);
        expect(SelectionHitTest.hitHandle(frame, p), h);
      }
    });
  });

  group('hitBody', () {
    test('inside the frame inflated by 8 px', () {
      expect(SelectionHitTest.hitBody(frame, frame.center), isTrue);
      expect(
        SelectionHitTest.hitBody(
          frame,
          Offset(frame.left - 7.9, frame.center.dy),
        ),
        isTrue,
      );
      expect(
        SelectionHitTest.hitBody(
          frame,
          Offset(frame.center.dx, frame.bottom + 7.9),
        ),
        isTrue,
      );
    });

    test('outside the inflated frame', () {
      expect(
        SelectionHitTest.hitBody(
          frame,
          Offset(frame.left - 8.1, frame.center.dy),
        ),
        isFalse,
      );
      expect(
        SelectionHitTest.hitBody(frame, Offset(frame.center.dx, frame.top - 9)),
        isFalse,
      );
      expect(SelectionHitTest.hitBody(frame, Offset.zero), isFalse);
    });
  });

  group('clampTranslation', () {
    const page = Size(595.2756, 841.8898);
    const bounds = Rect.fromLTWH(100, 100, 80, 40); // centre (140, 120)

    test('a move that keeps the centre on the page is unchanged', () {
      const delta = Offset(200, 300);
      expect(SelectionHitTest.clampTranslation(bounds, delta, page), delta);
      expect(
        SelectionHitTest.clampTranslation(
          bounds,
          const Offset(-140, -120),
          page,
        ),
        const Offset(-140, -120), // centre exactly on the corner
      );
    });

    test('the centre stops at the page edges', () {
      final left = SelectionHitTest.clampTranslation(
        bounds,
        const Offset(-500, 0),
        page,
      );
      expect(left, const Offset(-140, 0));
      final down = SelectionHitTest.clampTranslation(
        bounds,
        const Offset(30, 2000),
        page,
      );
      expect(down.dx, 30);
      expect(down.dy, closeTo(page.height - 120, 1e-9));
      final corner = SelectionHitTest.clampTranslation(
        bounds,
        const Offset(9000, -9000),
        page,
      );
      expect((bounds.center + corner).dx, closeTo(page.width, 1e-9));
      expect((bounds.center + corner).dy, 0);
    });

    test('bounds larger than the page still only keep the centre inside', () {
      const big = Rect.fromLTWH(-100, -100, 800, 1000);
      final d = SelectionHitTest.clampTranslation(
        big,
        const Offset(1000, 1000),
        page,
      );
      final centre = big.center + d;
      expect(centre.dx, closeTo(page.width, 1e-9));
      expect(centre.dy, closeTo(page.height, 1e-9));
    });
  });

  group('(v2) SelectionQuad — rotated frames (6.6.4)', () {
    const box = Rect.fromLTWH(200, 300, 240, 120); // centre (320, 360)

    test('fromRect: the corners, the 8 handle positions, angle 0', () {
      final quad = SelectionQuad.fromRect(box);
      expect(quad.corners, [
        box.topLeft,
        box.topRight,
        box.bottomRight,
        box.bottomLeft,
      ]);
      for (final h in SelectionHitTest.allHandles) {
        expect(
          quad.handlePosition(h),
          SelectionHitTest.handlePosition(box, h),
          reason: '$h',
        );
      }
      expect(quad.angle, 0);
      expect(quad.center, box.center);
      expect(quad.width, 240);
      expect(quad.height, 120);
      expect(quad.bounds, box);
      expect(
        quad.shift(const Offset(5, 6)),
        SelectionQuad.fromRect(box.shift(const Offset(5, 6))),
      );
    });

    test('8 directions on frames turned 0°, 30°, 90°, 150°, −45°: every '
        'handle sits on the turned frame and hits itself', () {
      for (final degrees in [0, 30, 90, 150, -45]) {
        final a = degrees * math.pi / 180;
        final quad = _turned(box, a);
        expect(quad.angle, closeTo(a, 1e-9), reason: '$degrees°');
        expect(quad.center.dx, closeTo(box.center.dx, 1e-9));
        expect(quad.center.dy, closeTo(box.center.dy, 1e-9));
        final c = box.center;
        // The handle positions are the unturned ones turned about the centre.
        for (final h in SelectionHitTest.allHandles) {
          final flat = SelectionHitTest.handlePosition(box, h) - c;
          final expected =
              c +
              Offset(
                flat.dx * math.cos(a) - flat.dy * math.sin(a),
                flat.dx * math.sin(a) + flat.dy * math.cos(a),
              );
          expect(
            quad.handlePosition(h),
            _near(expected),
            reason: '$h $degrees°',
          );
          expect(
            SelectionHitTest.hitFrameHandle(
              quad,
              expected,
              handles: SelectionHitTest.allHandles,
            ),
            FrameHandle.resize(h),
            reason: '$h $degrees°',
          );
        }
        // Only the shown handles hit: with corners only, an edge middle hits
        // nothing (the frame is large).
        expect(
          SelectionHitTest.hitFrameHandle(
            quad,
            quad.handlePosition(ink.SelectionHandle.right),
            rotatable: false,
          ),
          isNull,
        );
      }
    });

    test('a turned corner is hit within 22 px of its turned place, not at '
        'the unturned one', () {
      final quad = _turned(box, math.pi / 6);
      final br = quad.handlePosition(ink.SelectionHandle.bottomRight);
      expect(
        SelectionHitTest.hitFrameHandle(quad, br + const Offset(15, -15)),
        const FrameHandle.resize(ink.SelectionHandle.bottomRight),
      );
      expect(
        SelectionHitTest.hitFrameHandle(quad, br + const Offset(16, 16)),
        isNull, // 22.6 px
      );
      // The axis-aligned corner is far from every turned handle.
      expect(SelectionHitTest.hitFrameHandle(quad, box.bottomRight), isNull);
    });

    test('the rotate handle: 28 px outside the top edge\'s middle along its '
        'outward normal, turned with the frame', () {
      final flat = SelectionQuad.fromRect(box);
      expect(flat.rotateHandleBase, box.topCenter);
      expect(
        flat.rotateHandlePosition,
        box.topCenter - const Offset(0, SelectionHitTest.rotateHandleOffset),
      );
      expect(SelectionHitTest.rotateHandleOffset, 28);
      for (final degrees in [30, 90, 180, -60]) {
        final a = degrees * math.pi / 180;
        final quad = _turned(box, a);
        final c = box.center;
        // Above the centre by h/2 + 28 before turning.
        const up = -(60 + SelectionHitTest.rotateHandleOffset);
        final expected = c + Offset(-up * math.sin(a), up * math.cos(a));
        expect(quad.rotateHandlePosition, _near(expected), reason: '$degrees°');
        expect(
          SelectionHitTest.hitFrameHandle(quad, expected),
          const FrameHandle.rotate(),
          reason: '$degrees°',
        );
        expect(
          SelectionHitTest.hitFrameHandle(quad, expected, rotatable: false),
          isNull,
        );
      }
    });

    test(
      'a flat frame (a horizontal line) still has its rotate handle above',
      () {
        const line = SelectionQuad(
          Offset(100, 200),
          Offset(300, 200),
          Offset(300, 200),
          Offset(100, 200),
        );
        expect(line.height, 0);
        expect(
          line.rotateHandlePosition,
          _near(const Offset(200, 200 - SelectionHitTest.rotateHandleOffset)),
        );
        expect(line.containsInflated(const Offset(200, 207), 8), isTrue);
        expect(line.containsInflated(const Offset(200, 209), 8), isFalse);
      },
    );

    test(
      'a small frame: the nearest handle wins, the rotate handle included',
      () {
        final quad = SelectionQuad.fromRect(
          const Rect.fromLTWH(50, 50, 10, 10),
        );
        expect(
          SelectionHitTest.hitFrameHandle(quad, const Offset(51, 51)),
          const FrameHandle.resize(ink.SelectionHandle.topLeft),
        );
        // The rotate handle at (55, 22): above the top-left / top-right ones.
        expect(
          SelectionHitTest.hitFrameHandle(quad, const Offset(55, 30)),
          const FrameHandle.rotate(),
        );
      },
    );

    test(
      'the body of a turned frame: inside the turned box inflated by 8 px',
      () {
        final quad = _turned(box, math.pi / 4);
        final c = box.center;
        expect(SelectionHitTest.hitQuadBody(quad, c), isTrue);
        // Along the turned local x axis: 120 + 7.9 inside, 120 + 8.1 outside.
        const u = Offset(math.sqrt1_2, math.sqrt1_2);
        expect(SelectionHitTest.hitQuadBody(quad, c + u * 127.9), isTrue);
        expect(SelectionHitTest.hitQuadBody(quad, c + u * 128.1), isFalse);
        // The unturned box's bottom-left corner is outside the turned body.
        expect(
          SelectionHitTest.hitQuadBody(
            quad,
            box.bottomLeft + const Offset(2, -2),
          ),
          isFalse,
        );
        // The axis-aligned case equals the 1st-round hitBody.
        final flat = SelectionQuad.fromRect(box);
        for (final p in [
          box.center,
          Offset(box.left - 7.9, box.center.dy),
          Offset(box.left - 8.1, box.center.dy),
          Offset(box.center.dx, box.bottom + 7.9),
          Offset(box.center.dx, box.top - 9),
        ]) {
          expect(
            SelectionHitTest.hitQuadBody(flat, p),
            SelectionHitTest.hitBody(box, p),
            reason: '$p',
          );
        }
      },
    );

    test('FrameHandle values', () {
      expect(const FrameHandle.rotate().isRotate, isTrue);
      expect(const FrameHandle.rotate().resize, isNull);
      expect(
        const FrameHandle.resize(ink.SelectionHandle.top).isRotate,
        isFalse,
      );
      expect(
        const FrameHandle.resize(ink.SelectionHandle.top),
        const FrameHandle.resize(ink.SelectionHandle.top),
      );
      expect(
        const FrameHandle.resize(ink.SelectionHandle.top),
        isNot(const FrameHandle.rotate()),
      );
      expect(
        SelectionHitTest.allHandles.toSet(),
        ink.SelectionHandle.values.toSet(),
      );
      expect(SelectionHitTest.edgeHandles, hasLength(4));
    });
  });

  group('(E2-08) vertex handles', () {
    test('FrameHandle.vertex: its index, neither rotate nor resize; isCorner '
        '/ isEdge', () {
      const v = FrameHandle.vertex(2);
      expect(v.vertex, 2);
      expect(v.isVertex, isTrue);
      expect(v.isRotate, isFalse);
      expect(v.resize, isNull);
      expect(v.isCorner, isFalse);
      expect(v.isEdge, isFalse);
      expect(v, const FrameHandle.vertex(2));
      expect(v, isNot(const FrameHandle.vertex(1)));
      expect(v, isNot(const FrameHandle.rotate()));
      expect(v.hashCode, const FrameHandle.vertex(2).hashCode);
      expect(const FrameHandle.rotate().isVertex, isFalse);
      expect(
        const FrameHandle.resize(ink.SelectionHandle.topLeft).isCorner,
        isTrue,
      );
      expect(const FrameHandle.resize(ink.SelectionHandle.left).isEdge, isTrue);
      expect(
        const FrameHandle.resize(ink.SelectionHandle.left).isCorner,
        isFalse,
      );
    });

    test('hitFrameHandle: the nearest vertex within 22 px, by index; '
        'vertices and handles compete by distance', () {
      // A line (100,100) → (300,100): the quad (a, b, b, a).
      const a = Offset(100, 100), b = Offset(300, 100);
      const line = SelectionQuad(a, b, b, a);
      expect(
        SelectionHitTest.hitFrameHandle(
          line,
          const Offset(110, 105),
          handles: const [],
          rotatable: false,
          vertices: const [a, b],
        ),
        const FrameHandle.vertex(0),
      );
      expect(
        SelectionHitTest.hitFrameHandle(
          line,
          const Offset(295, 92),
          handles: const [],
          rotatable: false,
          vertices: const [a, b],
        ),
        const FrameHandle.vertex(1),
      );
      expect(
        SelectionHitTest.hitFrameHandle(
          line,
          const Offset(200, 100),
          handles: const [],
          rotatable: false,
          vertices: const [a, b],
        ),
        isNull,
      );
      // The line's body: the segment inflated by 8 px in its own axes.
      expect(
        SelectionHitTest.hitQuadBody(line, const Offset(200, 107)),
        isTrue,
      );
      expect(
        SelectionHitTest.hitQuadBody(line, const Offset(200, 110)),
        isFalse,
      );
      expect(SelectionHitTest.hitQuadBody(line, const Offset(95, 100)), isTrue);
      // A vertex closer than a corner wins.
      final box = SelectionQuad.fromRect(const Rect.fromLTRB(0, 0, 100, 100));
      expect(
        SelectionHitTest.hitFrameHandle(
          box,
          const Offset(9, 9),
          vertices: const [Offset(10, 10)],
        ),
        const FrameHandle.vertex(0),
      );
      expect(
        SelectionHitTest.hitFrameHandle(
          box,
          const Offset(1, 1),
          vertices: const [Offset(10, 10)],
        ),
        const FrameHandle.resize(ink.SelectionHandle.topLeft),
      );
    });
  });
}
