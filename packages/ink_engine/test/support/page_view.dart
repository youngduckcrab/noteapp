// InkPageView helpers for the widget tests (T10): pump a page view at the top
// left of a test surface and read the pixels it paints.
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';

import 'pixels.dart';

/// The key of the RepaintBoundary around the view pumped by [pumpPageView].
final pageViewKey = GlobalKey(debugLabel: 'page view');

/// Pumps [controller]'s InkPageView, [width] logical px wide, at the top left
/// of a [surface] (logical px) test view with [devicePixelRatio].
Future<void> pumpPageView(
  WidgetTester tester,
  InkPageController controller, {
  double width = 600,
  Size surface = const Size(700, 900),
  double devicePixelRatio = 1,
  double ancestorScale = 1,
  bool isScaling = false,
  Rect? visiblePageRect,
  bool showBackground = true,
}) async {
  tester.view
    ..devicePixelRatio = devicePixelRatio
    ..physicalSize = surface * devicePixelRatio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    pageViewApp(
      controller,
      width: width,
      ancestorScale: ancestorScale,
      isScaling: isScaling,
      visiblePageRect: visiblePageRect,
      showBackground: showBackground,
    ),
  );
}

/// The widget tree of [pumpPageView] (for re-pumping with other arguments).
Widget pageViewApp(
  InkPageController controller, {
  double width = 600,
  double ancestorScale = 1,
  bool isScaling = false,
  Rect? visiblePageRect,
  bool showBackground = true,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: RepaintBoundary(
      key: pageViewKey,
      child: SizedBox(
        width: width,
        child: InkPageView(
          controller: controller,
          ancestorScale: ancestorScale,
          isScaling: isScaling,
          visiblePageRect: visiblePageRect,
          showBackground: showBackground,
        ),
      ),
    ),
  ),
);

/// The pixels of the RepaintBoundary [key] (device pixels).
Future<Pixels> capturePixels(WidgetTester tester, {Key? key}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(key ?? pageViewKey),
  );
  final px = await tester.runAsync(() async {
    final image = await boundary.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    try {
      return Pixels(image.width, image.height, (await image.toByteData())!);
    } finally {
      image.dispose();
    }
  });
  return px!;
}
