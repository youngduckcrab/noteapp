// ElementFrame / PagePoint geometry (m5-7/02-core 6.2.1): corners, bounds, the rotation sign
// (= Affine2.rotation), exact similarity transforms, the non-uniform approximation, norm(θ),
// contains, normalized. The JSON part is test/shared/object_json_web_cases.dart (VM + Chrome).
// Web-safe.
import 'dart:math' as math;

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

Matcher _near(PagePoint p, [double eps = 1e-9]) => isA<PagePoint>()
    .having((q) => q.x, 'x', closeTo(p.x, eps))
    .having((q) => q.y, 'y', closeTo(p.y, eps));

Matcher _nearRect(PageRect r, [double eps = 1e-9]) => isA<PageRect>()
    .having((q) => q.left, 'left', closeTo(r.left, eps))
    .having((q) => q.top, 'top', closeTo(r.top, eps))
    .having((q) => q.right, 'right', closeTo(r.right, eps))
    .having((q) => q.bottom, 'bottom', closeTo(r.bottom, eps));

void main() {
  const box = PageRect(10, 20, 110, 70); // center (60, 45), 100 × 50

  group('PagePoint', () {
    test('transformed applies the affine map', () {
      expect(
        const PagePoint(1, 2).transformed(Affine2.translation(3, 4)),
        const PagePoint(4, 6),
      );
      expect(
        const PagePoint(2, 0).transformed(Affine2.rotation(math.pi / 2)),
        _near(const PagePoint(0, 2)),
      );
    });
  });

  group('center, corners, bounds', () {
    test('rotation 0: the rect corners exactly (tl, tr, br, bl)', () {
      const f = ElementFrame(box);
      expect(f.center, const PagePoint(60, 45));
      expect(f.corners, const [
        PagePoint(10, 20),
        PagePoint(110, 20),
        PagePoint(110, 70),
        PagePoint(10, 70),
      ]);
      expect(f.bounds, box);
    });

    test(
      'a positive angle turns clockwise on screen (y down), like Affine2',
      () {
        const f = ElementFrame(box, rotation: math.pi / 2);
        // tl (10, 20) is 50 left and 25 up of the center; a quarter turn clockwise puts it
        // 25 right and 50 up.
        expect(f.corners, [
          _near(const PagePoint(85, -5)),
          _near(const PagePoint(85, 95)),
          _near(const PagePoint(35, 95)),
          _near(const PagePoint(35, -5)),
        ]);
        final viaAffine = Affine2.rotation(
          math.pi / 2,
          originX: 60,
          originY: 45,
        );
        expect(
          f.corners.first,
          _near(const PagePoint(10, 20).transformed(viaAffine)),
        );
        expect(f.bounds, _nearRect(const PageRect(35, -5, 85, 95)));
      },
    );

    test('bounds is the AABB of the rotated corners', () {
      const f = ElementFrame(PageRect(0, 0, 10, 10), rotation: math.pi / 4);
      final h = 5 * math.sqrt2;
      expect(f.bounds, _nearRect(PageRect(5 - h, 5 - h, 5 + h, 5 + h)));
    });
  });

  group('transformed', () {
    test('identity and translation move the edges exactly', () {
      const f = ElementFrame(box, rotation: 0.3);
      expect(f.transformed(Affine2.identity), f);
      expect(
        f.transformed(Affine2.translation(0.1, -0.2)),
        const ElementFrame(
          PageRect(10 + 0.1, 20 - 0.2, 110 + 0.1, 70 - 0.2),
          rotation: 0.3,
        ),
      );
    });

    test('uniform scale and rotation are exact (similarity)', () {
      const f = ElementFrame(box, rotation: 0.2);
      final m = Affine2.scaling(
        2,
        2,
        originX: 0,
        originY: 0,
      ).then(Affine2.rotation(0.5)).then(Affine2.translation(7, -3));
      final t = f.transformed(m);
      expect(t.center, _near(f.center.transformed(m)));
      expect(t.rect.width, closeTo(200, 1e-9));
      expect(t.rect.height, closeTo(100, 1e-9));
      expect(t.rotation, closeTo(0.7, 1e-12));
      // Every corner of the result is the transformed corner.
      for (var i = 0; i < 4; i++) {
        expect(t.corners[i], _near(f.corners[i].transformed(m), 1e-9));
      }
      final half = f.transformed(
        Affine2.scaling(0.5, 0.5, originX: 60, originY: 45),
      );
      expect(half.rect, _nearRect(const PageRect(35, 32.5, 85, 57.5)));
    });

    test('rotation is folded into (-pi, pi]', () {
      const f = ElementFrame(box, rotation: 3);
      final t = f.transformed(Affine2.rotation(1, originX: 60, originY: 45));
      expect(t.rotation, closeTo(4 - 2 * math.pi, 1e-12));
      expect(t.rotation, greaterThan(-math.pi));
      expect(t.rotation, lessThanOrEqualTo(math.pi));
    });

    test('a non-uniform scale is approximated with s = sqrt|det|', () {
      const f = ElementFrame(box);
      final t = f.transformed(Affine2.scaling(4, 1, originX: 60, originY: 45));
      expect(t.center, _near(const PagePoint(60, 45)));
      expect(t.rect.width, closeTo(200, 1e-9)); // 100 × sqrt(4)
      expect(t.rect.height, closeTo(100, 1e-9)); // 50 × sqrt(4)
    });
  });

  group('contains', () {
    test('turned back by -rotation, with tolerance', () {
      const f = ElementFrame(box, rotation: math.pi / 2);
      expect(f.contains(const PagePoint(60, 45)), isTrue);
      expect(f.contains(const PagePoint(84, 90)), isTrue);
      expect(
        f.contains(const PagePoint(100, 45)),
        isFalse,
      ); // in the unrotated box only
      expect(f.contains(const PagePoint(87, 45)), isFalse);
      expect(f.contains(const PagePoint(87, 45), tolerance: 3), isTrue);
      const flat = ElementFrame(PageRect(0, 0, 100, 0));
      expect(flat.contains(const PagePoint(50, 0)), isTrue);
      expect(flat.contains(const PagePoint(50, 2)), isFalse);
      expect(flat.contains(const PagePoint(50, 2), tolerance: 2), isTrue);
    });
  });

  group('normalized', () {
    test(
      'folds the rotation; -pi and 3pi become pi; corners and bounds stay',
      () {
        for (final theta in [-math.pi, 3 * math.pi, 5.5, -7.0]) {
          final f = ElementFrame(box, rotation: theta);
          final n = f.normalized();
          expect(n.rotation, greaterThan(-math.pi), reason: '$theta');
          expect(n.rotation, lessThanOrEqualTo(math.pi), reason: '$theta');
          expect(n.rect, box);
          for (var i = 0; i < 4; i++) {
            expect(n.corners[i], _near(f.corners[i]), reason: '$theta #$i');
          }
          expect(n.bounds, _nearRect(f.bounds));
        }
        expect(
          const ElementFrame(box, rotation: -math.pi).normalized().rotation,
          math.pi,
        );
        expect(
          const ElementFrame(box, rotation: 3 * math.pi).normalized().rotation,
          closeTo(math.pi, 1e-12),
        );
        expect(
          const ElementFrame(box, rotation: 1).normalized(),
          const ElementFrame(box, rotation: 1),
        );
      },
    );

    test('sides are clamped to [0, maxSide] around the same center', () {
      const big = ElementFrame(PageRect(-10000, 0, 10000, 10));
      final n = big.normalized();
      expect(n.rect, const PageRect(-7200, 0, 7200, 10));
      const inverted = ElementFrame(PageRect(10, 10, 0, 20));
      expect(inverted.normalized().rect, const PageRect(5, 10, 5, 20));
      const ok = ElementFrame(PageRect(0, 0, 14400, 14400));
      expect(ok.normalized(), same(ok));
    });
  });
}
