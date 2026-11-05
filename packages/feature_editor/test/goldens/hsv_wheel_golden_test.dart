// E-14: the HSV wheel as EDITOR draws it (04-editor 6.9.5): hue sweep, white
// centre, black cover for the value, the marker. No text on screen (contract
// 7.4.8 golden rule).
@Tags(['golden'])
@TestOn('vm')
library;

import 'package:feature_editor/src/ui/color/hsv_wheel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _pumpWheel(WidgetTester tester, HSVColor hsv) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(260, 260) * 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: const ValueKey('wheel'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: HsvWheel(hsv: hsv, onChanged: (_) {}),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('full value, marker at hue 200 / saturation 0.6', (tester) async {
    await _pumpWheel(tester, HSVColor.fromAHSV(1, 200, 0.6, 1));
    await expectLater(
      find.byKey(const ValueKey('wheel')),
      matchesGoldenFile('hsv_wheel.png'),
    );
  });

  testWidgets('value 0.4 darkens the wheel, marker at hue 30 / saturation 1', (
    tester,
  ) async {
    await _pumpWheel(tester, HSVColor.fromAHSV(1, 30, 1, 0.4));
    await expectLater(
      find.byKey(const ValueKey('wheel')),
      matchesGoldenFile('hsv_wheel_value_40.png'),
    );
  });
}
