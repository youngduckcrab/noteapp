// T05 (03-ink 8, 6.7 F4): dot strokes.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/src/stroke/centerline.dart';

void main() {
  test('dot length = max(0.3 pt, 0.25 · width)', () {
    expect(dotLengthFor(1.6), closeTo(0.4, 1e-12));
    expect(dotLengthFor(0.5), 0.3);
    expect(dotLengthFor(12), 3.0);
  });

  test('shorter than the dot length → dot; longer → not', () {
    final tap = [
      CenterPoint(10, 10),
      CenterPoint(10.1, 10.05),
      CenterPoint(10.15, 10),
    ];
    expect(isDotStroke(tap, 1.6), isTrue);
    expect(isDotStroke([CenterPoint(5, 5)], 1.6), isTrue);
    expect(isDotStroke([CenterPoint(0, 0), CenterPoint(1, 0)], 1.6), isFalse);
    // a wide pen makes the same jiggle a dot
    final jiggle = [CenterPoint(0, 0), CenterPoint(1, 0), CenterPoint(0, 0)];
    expect(isDotStroke(jiggle, 1.6), isFalse);
    expect(isDotStroke(jiggle, 12), isTrue);
    expect(isDotStroke(const [], 1.6), isFalse);
  });

  test('the dot: mean position, the largest factor, t = 0', () {
    final pts = [
      CenterPoint(10, 10, factor: 0.9, tilt: 0.1, t: 0),
      CenterPoint(10.2, 10, factor: 1.3, tilt: 0.4, azimuth: 1, t: 8),
      CenterPoint(10.1, 10.3, factor: 1.1, tilt: 0.2, t: 16),
    ];
    final d = dotOf(pts);
    expect(d.x, closeTo(10.1, 1e-9));
    expect(d.y, closeTo(10.1, 1e-9));
    expect(d.factor, 1.3);
    expect(d.tilt, 0.4);
    expect(d.azimuth, 1);
    expect(d.t, 0);
    final single = dotOf([CenterPoint(3, 4, factor: 0.7, t: 5)]);
    expect((single.x, single.y, single.factor, single.t), (3, 4, 0.7, 0));
  });
}
