// Raster tile helpers for the T19 widget tests (03-ink 6.13 L3).
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkBaseStatsOf;

import 'pixels.dart';

/// Tiles made by [controller] so far.
int tilesMade(InkPageController controller) =>
    inkBaseStatsOf(controller).tilesMade;

/// Waits past the idle (300 ms) and zoom-settle (150 ms) waits, then pumps
/// frames until no more tiles are made and no frame is scheduled. Returns the
/// frames pumped after the wait.
Future<int> rasterAllTiles(
  WidgetTester tester,
  InkPageController controller, {
  int maxFrames = 400,
}) async {
  await tester.pump(const Duration(milliseconds: 400));
  var frames = 0;
  while (frames < maxFrames && tester.binding.hasScheduledFrame) {
    await tester.pump();
    frames++;
  }
  return frames;
}

/// Share of pixels whose channels differ by more than [tolerance] (0–1).
double differingShare(Pixels a, Pixels b, {int tolerance = 8}) {
  expect((a.width, a.height), (b.width, b.height));
  var differing = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final pa = a.at(x, y);
      final pb = b.at(x, y);
      for (var k = 0; k < 4; k++) {
        if ((pa[k] - pb[k]).abs() > tolerance) {
          differing++;
          break;
        }
      }
    }
  }
  return differing / (a.width * a.height);
}

/// Pixels that are not paper white (ink present).
int inkedPixels(Pixels p) {
  var n = 0;
  for (var y = 0; y < p.height; y++) {
    for (var x = 0; x < p.width; x++) {
      final c = p.at(x, y);
      if (c[0] < 200 || c[1] < 200 || c[2] < 200) n++;
    }
  }
  return n;
}

/// Mean absolute channel difference / 255 (0–1).
double meanDifference(Pixels a, Pixels b) {
  var sum = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final pa = a.at(x, y);
      final pb = b.at(x, y);
      for (var k = 0; k < 4; k++) {
        sum += (pa[k] - pb[k]).abs();
      }
    }
  }
  return sum / (a.width * a.height * 4 * 255);
}
