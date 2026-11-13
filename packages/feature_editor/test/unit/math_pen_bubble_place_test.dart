// (math pen, review M2) Where the bubble goes (mathPenBubbleOffset): above
// the group's keep-away zone, below it at the top edge, beside it when
// zoomed in so far that neither fits, the far corner when nothing fits —
// always 8 px inside the area, never over the zone when there is room.
import 'dart:ui';

import 'package:feature_editor/src/ui/overlays/math_pen_layer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const area = Size(800, 600);
  const child = Size(200, 44);

  Rect placed(Rect anchor) => mathPenBubbleOffset(area, child, anchor) & child;

  void expectInside(Rect r) {
    expect(r.left, greaterThanOrEqualTo(8));
    expect(r.top, greaterThanOrEqualTo(8));
    expect(r.right, lessThanOrEqualTo(area.width - 8));
    expect(r.bottom, lessThanOrEqualTo(area.height - 8));
  }

  test('above the zone, left-aligned, 8 px gap', () {
    const zone = Rect.fromLTRB(300, 300, 400, 340);
    final r = placed(zone);
    expect(r.left, 300);
    expect(r.bottom, 300 - MathPenLayer.gap);
  });

  test('the top edge: below the zone', () {
    const zone = Rect.fromLTRB(300, 20, 400, 60);
    final r = placed(zone);
    expect(r.top, 60 + MathPenLayer.gap);
    expect(r.overlaps(zone), isFalse);
    expectInside(r);
  });

  test('the right edge: pulled inside, still above', () {
    const zone = Rect.fromLTRB(700, 300, 790, 340);
    final r = placed(zone);
    expect(r.right, area.width - 8);
    expect(r.bottom, 300 - MathPenLayer.gap);
    expectInside(r);
  });

  test('zoomed in (the zone fills the height): beside the zone, not on it', () {
    const zone = Rect.fromLTRB(100, 10, 400, 590);
    final r = placed(zone);
    expect(r.left, 400 + MathPenLayer.gap);
    expect(r.overlaps(zone), isFalse);
    expectInside(r);
    // On the right edge: left of it.
    const right = Rect.fromLTRB(500, 10, 790, 590);
    final l = placed(right);
    expect(l.right, 500 - MathPenLayer.gap);
    expect(l.overlaps(right), isFalse);
  });

  test('400 % zoom (the zone fills the area): the corner that covers it '
      'least, inside the area', () {
    const zone = Rect.fromLTRB(-50, -50, 700, 900);
    final r = placed(zone);
    expectInside(r);
    expect(r.left, area.width - child.width - 8); // the uncovered strip
  });
}
