// Helpers for the InkPageThumbnail widget tests (T20).
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/src/render/thumbnail.dart'
    show inkThumbnailRasterBusy;

/// Lets the stroke rasters started in the fake async zone finish: real
/// short waits (the engine answers Picture.toImage) and pumps (the fake zone
/// runs the completions), until none is on its way. No timing is asserted.
Future<void> settleThumbnails(WidgetTester tester) async {
  for (var i = 0; i < 500 && inkThumbnailRasterBusy; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump();
  }
  expect(inkThumbnailRasterBusy, isFalse, reason: 'thumbnail rasters done');
  await tester.pump();
}
