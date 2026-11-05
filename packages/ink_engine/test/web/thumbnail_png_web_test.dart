@TestOn('browser')
library;

// T20 (03-ink 6.17, 9.1): the thumbnail renderer in Chrome — CanvasKit
// Picture.toImage → PNG → decode, sizes, pageId / revision, still renderer
// background and null rules, paper color, yields, pencil grain.
import 'package:flutter_test/flutter_test.dart';

import '../widget/thumbnail_renderer_test.dart' as renderer;

void main() {
  group('thumbnail_renderer_test', renderer.main);
}
