import 'dart:math' as math;

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

Matcher _near(double v) => closeTo(v, 1e-9);

void main() {
  group('PageRect', () {
    test('constructors and size', () {
      final r = PageRect.fromLTWH(10, 20, 30, 40);
      expect(r, const PageRect(10, 20, 40, 60));
      expect(r.width, 30);
      expect(r.height, 40);
      expect(PageRect.fromPoints(5, 9, 1, 2), const PageRect(1, 2, 5, 9));
      expect(PageRect.zero.isEmpty, isTrue);
      expect(const PageRect(0, 0, 1, 0).isEmpty, isTrue);
      expect(const PageRect(0, 0, 1, 1).isEmpty, isFalse);
    });

    test('overlaps counts touching edges', () {
      const a = PageRect(0, 0, 10, 10);
      expect(a.overlaps(const PageRect(10, 0, 20, 10)), isTrue);
      expect(a.overlaps(const PageRect(10.01, 0, 20, 10)), isFalse);
      expect(a.overlaps(const PageRect(2, 2, 3, 3)), isTrue);
      expect(a.containsPoint(10, 10), isTrue);
      expect(a.containsPoint(10.1, 5), isFalse);
    });

    test('inflate, expandToInclude, JSON', () {
      const a = PageRect(0, 0, 10, 10);
      expect(a.inflate(2), const PageRect(-2, -2, 12, 12));
      expect(
        a.expandToInclude(const PageRect(5, -3, 20, 4)),
        const PageRect(0, -3, 20, 10),
      );
      expect(a.toJson(), {'l': 0, 't': 0, 'r': 10, 'b': 10});
      expect(
        PageRect.fromJson({'l': 1, 't': 2.5, 'r': 3, 'b': 4}),
        const PageRect(1, 2.5, 3, 4),
      );
      expect(() => PageRect.fromJson({'l': 1}), throwsFormatException);
    });
  });

  group('Affine2', () {
    test('identity, translation, scaling with origin', () {
      expect(Affine2.identity.isIdentity, isTrue);
      expect(Affine2.translation(3, 4).apply(1, 1), (4.0, 5.0));
      final s = Affine2.scaling(2, 3, originX: 10, originY: 10);
      expect(s.apply(10, 10), (10.0, 10.0));
      expect(s.apply(11, 12), (12.0, 16.0));
      expect(s.uniformScale, _near(math.sqrt(6)));
    });

    test('rotation about an origin', () {
      final r = Affine2.rotation(math.pi / 2, originX: 1, originY: 1);
      final (x, y) = r.apply(2, 1);
      expect(x, _near(1));
      expect(y, _near(2));
      expect(r.rotation, _near(math.pi / 2));
      expect(r.uniformScale, _near(1));
    });

    test('then applies this first, then next', () {
      final t = Affine2.translation(5, 0);
      final s = Affine2.scaling(2, 2);
      final (x, y) = t.then(s).apply(1, 1);
      expect((x, y), (12.0, 2.0));
      final (x2, y2) = s.then(t).apply(1, 1);
      expect((x2, y2), (7.0, 2.0));
    });

    test('inverse', () {
      final m = Affine2.rotation(
        0.7,
        originX: 3,
        originY: -2,
      ).then(Affine2.scaling(1.5, 0.5));
      final inv = m.inverse()!;
      final (x, y) = m.apply(4, 9);
      final (bx, by) = inv.apply(x, y);
      expect(bx, _near(4));
      expect(by, _near(9));
      expect(const Affine2(1, 2, 2, 4, 0, 0).inverse(), isNull);
    });

    test('applyToRect = bounds of the 4 corners; JSON', () {
      final r = Affine2.rotation(math.pi / 4)
          .applyToRect(const PageRect(0, 0, 2, 2));
      expect(r.left, _near(-math.sqrt2));
      expect(r.right, _near(math.sqrt2));
      expect(r.top, _near(0));
      expect(r.bottom, _near(2 * math.sqrt2));
      const m = Affine2(1, 2, 3, 4, 5, 6);
      expect(m.toJson(), [1, 2, 3, 4, 5, 6]);
      expect(Affine2.fromJson([1, 2, 3, 4, 5, 6]), m);
      expect(() => Affine2.fromJson([1, 2]), throwsFormatException);
      expect(m.determinant, -2);
    });
  });
}
