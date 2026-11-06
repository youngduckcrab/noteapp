// Copied from pdf_io/test/support/ipad.dart (m5-7/06-pdf 9.1 — media_io keeps its own copy).
// Screen size and tap-target checks for the UI flow tests (contract 7.4.8; 06-pdf 9.1):
// iPad Pro 13" logical 1032×1376 portrait / 1376×1032 landscape at DPR 2, and every
// tappable element at least 44×44 (iOSTapTargetGuideline) with a label
// (labeledTapTargetGuideline).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// iPad Pro 13" logical sizes (contract 7.4.8).
const Size ipad13Portrait = Size(1032, 1376);
const Size ipad13Landscape = Size(1376, 1032);

/// Sets the test view to an iPad Pro 13" ([landscape] → 1376×1032) at DPR 2; reset on
/// tearDown.
void useIpad13(WidgetTester tester, {bool landscape = false}) {
  final logical = landscape ? ipad13Landscape : ipad13Portrait;
  tester.view
    ..devicePixelRatio = 2
    ..physicalSize = logical * 2;
  addTearDown(tester.view.reset);
}

/// [WidgetTester.pumpWidget] on an iPad Pro 13" view (portrait unless [landscape]).
Future<void> pumpOnIpad(
  WidgetTester tester,
  Widget app, {
  bool landscape = false,
}) async {
  useIpad13(tester, landscape: landscape);
  await tester.pumpWidget(app);
}

/// What is on screen now meets the 44×44 tap-target and the labeled-tap-target guidelines
/// (they read the semantics tree, which testWidgets turns on by default).
Future<void> expectTapTargetGuidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
}
