// E-15: WidthMapping (04-editor 6.9.4) — the bounds are
// core.StrokeStyle.minWidth / maxWidth, the round trip, the 0.1 snap and the
// documented examples.
import 'package:feature_editor/src/ui/pen/width_mapping.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;

void main() {
  test('bounds are the CORE width limits (0.1–30 pt), step 0.1', () {
    expect(WidthMapping.min, core.StrokeStyle.minWidth);
    expect(WidthMapping.max, core.StrokeStyle.maxWidth);
    expect(WidthMapping.min, 0.1);
    expect(WidthMapping.max, 30.0);
    expect(WidthMapping.step, 0.1);
    expect(WidthMapping.widthAt(0), WidthMapping.min);
    expect(WidthMapping.widthAt(1), WidthMapping.max);
    expect(WidthMapping.positionOf(WidthMapping.min), 0);
    expect(WidthMapping.positionOf(WidthMapping.max), 1);
  });

  test('width(t) = snap(0.1 + 29.9 t²): the 6.9.4 examples', () {
    expect(WidthMapping.widthAt(0.2), 1.3);
    expect(WidthMapping.widthAt(0.5), 7.6);
    expect(WidthMapping.widthAt(0.26), 2.1);
  });

  test('outside 0..1 and NaN clamp', () {
    expect(WidthMapping.widthAt(-1), WidthMapping.min);
    expect(WidthMapping.widthAt(2), WidthMapping.max);
    expect(WidthMapping.widthAt(double.nan), WidthMapping.min);
    expect(WidthMapping.positionOf(0), 0);
    expect(WidthMapping.positionOf(99), 1);
    expect(WidthMapping.positionOf(double.nan), 0);
  });

  test('every 0.1 step round-trips: widthAt(positionOf(w)) == w', () {
    for (var i = 1; i <= 300; i++) {
      final w = i / 10;
      expect(WidthMapping.widthAt(WidthMapping.positionOf(w)), w, reason: '$w');
    }
  });

  test('widthAt is monotonic and always on the 0.1 grid', () {
    var last = 0.0;
    for (var i = 0; i <= 1000; i++) {
      final w = WidthMapping.widthAt(i / 1000);
      expect(w, greaterThanOrEqualTo(last));
      expect((w * 10 - (w * 10).round()).abs(), lessThan(1e-9), reason: '$w');
      last = w;
    }
  });

  test('snap clamps to [0.1, 30] and rounds to 0.1', () {
    expect(WidthMapping.snap(2.44), 2.4);
    expect(WidthMapping.snap(2.46), 2.5);
    expect(WidthMapping.snap(12.34), 12.3);
    expect(WidthMapping.snap(0.04), 0.1);
    expect(WidthMapping.snap(-5), 0.1);
    expect(WidthMapping.snap(31), 30);
    expect(WidthMapping.snap(double.nan), 0.1);
    expect(WidthMapping.snap(double.infinity), 30);
  });
}
