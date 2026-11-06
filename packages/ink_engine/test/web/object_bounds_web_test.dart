@TestOn('browser')
library;

// m5-7/03-ink T33 (9.1, 6.9.4 K-6): the shape geometry and the page object
// bounds invariant also hold in Chrome (CanvasKit paths and strokes, JS
// numbers) — the same bodies as the VM tests. The text boxes draw with the
// test font (C23-07).
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/testing.dart';

import '../unit/geometry/shape_path_test.dart' as shape_path;
import '../unit/model/object_bounds_invariant_test.dart' as object_bounds;

void main() {
  setUpAll(useInkTestFonts);
  group('shape_path_test', shape_path.main);
  group('object_bounds_invariant_test', object_bounds.main);
}
