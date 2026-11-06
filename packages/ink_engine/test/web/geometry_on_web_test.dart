@TestOn('browser')
library;

// T07 (03-ink 8, 9.1): the outline tests and the K-1 bounds invariant also
// hold in Chrome (CanvasKit paths, JS numbers). v2 (m5-7/03-ink T27): the
// brush and tape cases of bounds_invariant_test and the square caps.
import 'package:flutter_test/flutter_test.dart';

import '../unit/geometry/outline_test.dart' as outline;
import '../unit/geometry/square_cap_test.dart' as square_cap;
import '../unit/model/bounds_invariant_test.dart' as bounds;

void main() {
  group('outline_test', outline.main);
  group('bounds_invariant_test', bounds.main);
  group('square_cap_test', square_cap.main);
}
