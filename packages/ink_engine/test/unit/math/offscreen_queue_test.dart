// m5-7/03-ink 8.2 T36 (6.12.2): the raster host's queue and its wait for the
// glyph pictures, through the test seam OffscreenMathHost.debugExtraSvgLoader
// + test/support/delayed_svg_loader.dart (the native release path — a picture
// set later from another isolate — on the VM debug runner):
// - a picture 30 ms late is waited for (its pixels are in the raster);
// - one later than the settle cap (2,000 ms > mathSvgSettleMs) → null and a
//   counted failure (mathRasterFailed);
// - a second request while the first waits runs after it; the same request
//   while queued joins its job (every caller its own image);
// - a request never runs synchronously (a timer turn), also when made inside
//   paint (S-9); layout answers at once while a raster waits (two hosts);
// - invalid LaTeX / bad arguments → null.
// The bodies are shared with web/offscreen_math_web_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/testing.dart';

import '../../support/math_raster_cases.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadKatexFontsForTest);
  offscreenQueueCases();
  paintPhaseRequestCase();
}
