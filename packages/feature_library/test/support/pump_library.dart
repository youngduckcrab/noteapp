// test/support/pump_library.dart — 05-library 5.7 / 9.1 (L0).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'test_sizes.dart';

/// Sets the test view to [size] logical px at DPR 2 (reset on tear-down).
void setTestSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = TestSizes.devicePixelRatio;
  tester.view.physicalSize = size * TestSizes.devicePixelRatio;
  addTearDown(tester.view.reset);
}

/// Pumps [home] inside ProviderScope(overrides: [overrides]) and a
/// material_ui MaterialApp at [size] (DPR 2). LIBRARY strings and dates do not
/// depend on the locale, so no localization delegates are set.
Future<void> pumpLibrary(
  WidgetTester tester, {
  required List<Override> overrides,
  required Widget home,
  Size size = TestSizes.ipad13Landscape,
}) async {
  setTestSize(tester, size);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(debugShowCheckedModeBanner: false, home: home),
    ),
  );
}
