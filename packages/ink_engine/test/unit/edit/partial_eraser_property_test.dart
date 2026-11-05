// T16 (03-ink 6.20 '성질' ①–⑤): 200 random strokes (five tools, tilt /
// azimuth / recording fields, dots) × random partial-eraser paths:
// ① every kept point is ≥ R + r − ε from the eraser path, ② kept + dropped
// crumbs + erased length = the original length (± 0.02 pt per cut), ③ no
// contact → null, ④ same input → same result (Chrome: web wrapper, same
// checksum), ⑤ fragment style / createdAt / recording fields = the original,
// version null, t inside the original range.
import 'package:flutter_test/flutter_test.dart';

import '../../support/partial_eraser_properties.dart';

void main() {
  test('6.20 properties ①–⑤ over 200 random cases', () {
    final checksum = checkPartialEraserProperties(200);
    expect(checksum, partialEraserChecksum50, reason: 'recorded VM checksum');
  });
}
