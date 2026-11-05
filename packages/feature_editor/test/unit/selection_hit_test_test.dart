// E-10: SelectionHitTest (04-editor 6.6.5) — handles, body, clamped moves.
import 'dart:ui';

import 'package:feature_editor/src/tools/selection_hit_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;

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
}
