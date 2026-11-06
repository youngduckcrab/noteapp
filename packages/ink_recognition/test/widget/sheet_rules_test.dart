// m5-7/05-library 6.12, contract 7.4.10 — every recognition sheet on iPad 13"
// landscape / portrait and a compact width: height ≤ 50% of the screen, tap
// targets ≥ 44×44 (iOS guideline), no overflow, still usable with the
// keyboard up. L2-13: the LaTeX editor; L2-14: the math pad (direct input);
// L2-17a: the math pad with an engine (handwriting area + tools);
// L2-15 adds the conversion sheet (the package-side twin of INFRA V5 opening
// each slot).
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/ui/latex_editor_sheet.dart';
import 'package:ink_recognition/src/ui/math_pad_canvas.dart';
import 'package:ink_recognition/src/ui/math_pad_sheet.dart';
import 'package:ink_recognition/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/testing.dart' as core_testing;

import '../support/recognition_test_scope.dart';

/// A compact width (an iPad split view / a phone).
const Size kCompact = Size(375, 667);

const Map<String, Size> _sizes = {
  '13" landscape': kIpadLandscape,
  '13" portrait': kIpadPortrait,
  'compact': kCompact,
};

/// A sheet under test: how to open it, its key and the host's overrides
/// (the engines it needs).
typedef SheetCase = ({
  String name,
  Key key,
  List<Override> Function() overrides,
  Future<void> Function(BuildContext body, TargetLog log) open,
});

List<Override> _none() => const [];

final List<SheetCase> _sheets = [
  (
    name: 'LaTeX editor (recog.editMath)',
    key: kLatexSheetKey,
    overrides: _none,
    open: (body, log) => recognitionSelectionActions()
        .singleWhere((a) => a.id == 'recog.editMath')
        .run(
          body,
          log.target(
            objects: [
              core_testing.PageObjectFixtures.math(
                pageId: kPageId,
                latex: r'\int_0^1 x^2\,dx = \frac{1}{3}',
              ),
            ],
          ),
        ),
  ),
  (
    name: 'math pad (recog.mathPad, direct input)',
    key: kMathPadSheetKey,
    overrides: _none,
    open: (body, log) => recognitionInsertActions().single.run(
      body,
      log.target(areaPt: const Rect.fromLTWH(0, 0, 800, 600)),
    ),
  ),
  (
    name: 'math pad (recog.mathPad, engine — handwriting area)',
    key: kMathPadSheetKey,
    overrides: () => [
      mathRecognizerProvider.overrideWithValue(FakeMathRecognizer()),
    ],
    open: (body, log) => recognitionInsertActions().single.run(
      body,
      log.target(areaPt: const Rect.fromLTWH(0, 0, 800, 600)),
    ),
  ),
];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ink_testing.loadKatexFontsForTest();
  });

  for (final sheet in _sheets) {
    for (final MapEntry(key: sizeName, value: size) in _sizes.entries) {
      testWidgets('${sheet.name} on $sizeName: ≤ 50% high, 44×44 targets, '
          'no overflow', (tester) async {
        final host = await RecognitionHost.pump(
          tester,
          size: size,
          overrides: sheet.overrides(),
        );
        final log = TargetLog();
        final pending = sheet.open(host.body, log);
        await tester.pumpAndSettle();
        expect(find.byKey(sheet.key), findsOneWidget);
        final canvas = find.byKey(kMathPadCanvasKey);
        if (canvas.evaluate().isNotEmpty) {
          // 6.14.1: 40% of the sheet's height, at least 140 px
          expect(
            tester.getSize(canvas).height,
            closeTo(
              (size.height * 0.5 * 0.4).clamp(140, double.infinity),
              0.01,
            ),
          );
        }
        final rect = tester.getRect(find.byType(BottomSheet));
        expect(rect.height, lessThanOrEqualTo(size.height * 0.5 + 0.01));
        expect(rect.bottom, closeTo(size.height, 0.01));
        expect(
          tester.getRect(find.byKey(sheet.key)).height,
          lessThanOrEqualTo(size.height * 0.5 + 0.01),
        );
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        Navigator.of(tester.element(find.byKey(sheet.key))).pop();
        await tester.pumpAndSettle();
        await pending;
      });
    }

    testWidgets('${sheet.name} with the keyboard up: lifted above it, no '
        'overflow, the field still reachable', (tester) async {
      final host = await RecognitionHost.pump(
        tester,
        overrides: sheet.overrides(),
      );
      final log = TargetLog();
      final pending = sheet.open(host.body, log);
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byKey(sheet.key),
        matching: find.byType(TextField),
      );
      expect(field, findsWidgets);
      await tester.tap(field.first);
      tester.view.viewInsets = const FakeViewPadding(bottom: 400);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      const keyboardTop = 1032.0 - 400;
      final content = tester.getRect(find.byKey(sheet.key));
      expect(content.bottom, closeTo(keyboardTop, 0.01));
      expect(content.height, lessThanOrEqualTo(1032 * 0.5 + 0.01));
      final fieldRect = tester.getRect(field.first);
      expect(fieldRect.top, greaterThanOrEqualTo(content.top));
      expect(fieldRect.bottom, lessThanOrEqualTo(keyboardTop));
      Navigator.of(tester.element(find.byKey(sheet.key))).pop();
      await tester.pumpAndSettle();
      await pending;
    });
  }
}
