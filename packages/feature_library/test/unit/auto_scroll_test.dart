// EdgeAutoScroller.velocityFor (05-library 6.10.4, 8 L15): d = distance to
// the nearer edge; d = 0 → 1200, 28 → 600, 56 → 0, outside → 1200 (negative
// = up).
import 'package:feature_library/src/dnd/edge_auto_scroller.dart';
import 'package:feature_library/src/ui/layout/library_metrics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Rect;

void main() {
  // top 100, bottom 600.
  const viewport = Rect.fromLTWH(0, 100, 300, 500);

  double v(double y) => EdgeAutoScroller.velocityFor(y, viewport);

  test('the defaults are 56 px and 1200 px/s', () {
    expect(LibraryMetrics.dragAutoScrollZone, 56);
    expect(LibraryMetrics.dragAutoScrollMaxSpeed, 1200);
  });

  test('table: d = 0 / 28 / 56 at both edges', () {
    final cases = <double, double>{
      100: -1200, // top edge, d = 0
      128: -600, // d = 28
      156: 0, // d = 56
      600: 1200, // bottom edge, d = 0
      572: 600, // d = 28
      544: 0, // d = 56
    };
    cases.forEach((y, expected) {
      expect(v(y), closeTo(expected, 1e-9), reason: 'y = $y');
    });
  });

  test('outside the viewport: full speed toward it', () {
    expect(v(99), -1200);
    expect(v(-500), -1200);
    expect(v(601), 1200);
    expect(v(5000), 1200);
  });

  test('the middle does not scroll; speed grows toward the edge', () {
    expect(v(350), 0);
    expect(v(157), 0);
    expect(v(130).abs(), lessThan(v(110).abs()));
    expect(v(590), greaterThan(v(560)));
  });

  test('zone and maxSpeed are parameters', () {
    expect(
      EdgeAutoScroller.velocityFor(110, viewport, zone: 20, maxSpeed: 100),
      closeTo(-50, 1e-9),
    );
    expect(
      EdgeAutoScroller.velocityFor(700, viewport, zone: 20, maxSpeed: 100),
      100,
    );
  });

  test('a viewport shorter than two zones uses the nearer edge', () {
    const short = Rect.fromLTWH(0, 0, 100, 60);
    expect(EdgeAutoScroller.velocityFor(10, short), lessThan(0));
    expect(EdgeAutoScroller.velocityFor(50, short), greaterThan(0));
  });
}
