@TestOn('browser')
library;

// m5-7/03-ink 8.2 T37a·T37b (6.14, 6.15): the object hit rules (frames, shape
// outlines within tolerance + w / 2, heads, filled insides, the exact ellipse
// distance, the object index = a brute-force scan) and the eraser's capsule
// rule for shapes (= a dense sampling of the capsule on random pairs, exact
// contact, never text boxes) also hold in Chrome (JS numbers).
import 'package:flutter_test/flutter_test.dart';

import '../unit/edit/stroke_eraser_test.dart' as stroke_eraser;
import '../unit/object/object_hit_test.dart' as object_hit;

void main() {
  group('object_hit_test', object_hit.main);
  group('stroke_eraser_test', stroke_eraser.main);
}
