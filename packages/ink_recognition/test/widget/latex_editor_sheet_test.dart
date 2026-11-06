// L2-13 (m5-7/05-library 8.2, 6.15.1, 6.15.2, 6.12): the LaTeX editor that
// recog.editMath opens — the field filled with the formula, the real INK
// MathPreview (size > 0 after loadKatexFontsForTest), validation 150 ms after
// a change (error text under the field, [적용] disabled, the last valid
// preview dimmed), [적용] unchanged → no command, changed → ONE UpdateObjects
// (centre and rotation kept, engineId 'manual', laid out at the formula's
// font size), [LaTeX 복사] → the clipboard value sent inside onPressed, a
// read-only note → the notice with the sheet still open, [취소] → nothing.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/ui/latex_editor_sheet.dart';
import 'package:ink_recognition/src/ui/recognition_sheet.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/recognition_test_scope.dart';

final core.MathObject _math = core.MathObject(
  id: 'math-1',
  pageId: kPageId,
  frame: core.ElementFrame(
    core.PageRect.fromLTWH(200, 300, 60, 30),
    rotation: 0.3,
  ),
  latex: r'\frac{a}{b}',
  style: const core.MathStyle(fontSizePt: 24, colorArgb: 0xFF0044AA),
  engineId: 'fake/1',
  createdAt: 1730800000000,
);

RecognitionAction get _editMath =>
    recognitionSelectionActions().singleWhere((a) => a.id == 'recog.editMath');

Finder get _sheet => find.byKey(kLatexSheetKey);
Finder get _field => find.byKey(kLatexFieldKey);
Finder get _primary => find.byKey(kSheetPrimaryKey);

bool _enabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_primary).onPressed != null;

/// Opens the editor on [_math]; `run` = the run's Future (it completes when
/// the sheet closes).
Future<({Future<void> run})> _open(
  WidgetTester tester,
  RecognitionHost host,
  TargetLog log,
) async {
  final pending = _editMath.run(host.body, log.target(objects: [_math]));
  await tester.pumpAndSettle();
  expect(_sheet, findsOneWidget);
  return (run: pending);
}

Future<void> _type(WidgetTester tester, String latex) async {
  await tester.enterText(_field, latex);
  await tester.pump(kLatexValidateDelay);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ink_testing.loadKatexFontsForTest();
  });

  late TargetLog log;
  setUp(() => log = TargetLog());

  testWidgets('opens filled; the real MathPreview has a size', (tester) async {
    final host = await RecognitionHost.pump(tester);
    final pending = (await _open(tester, host, log)).run;
    expect(tester.widget<TextField>(_field).controller!.text, r'\frac{a}{b}');
    expect(find.text('수식 편집'), findsOneWidget);
    expect(find.text('적용'), findsOneWidget);
    expect(find.text('LaTeX 복사'), findsOneWidget);
    final preview = tester.widget<ink.MathPreview>(
      find.byKey(kLatexPreviewKey),
    );
    expect(preview.latex, r'\frac{a}{b}');
    final size = tester.getSize(find.byKey(kLatexPreviewKey));
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));
    expect(_enabled(tester), isTrue);
    await tester.tap(find.byKey(kSheetCancelKey));
    await tester.pumpAndSettle();
    await pending;
  });

  testWidgets('invalid LaTeX: checked 150 ms later → error under the field, '
      '[적용] disabled, the last valid preview dimmed', (tester) async {
    final host = await RecognitionHost.pump(tester);
    final pending = (await _open(tester, host, log)).run;
    await tester.enterText(_field, r'\frac{a}{');
    await tester.pump(const Duration(milliseconds: 149));
    expect(_enabled(tester), isFalse, reason: 'not checked yet');
    final error = ink.InkMathRenderer.validate(r'\frac{a}{')!;
    expect(find.text(error), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text(error), findsOneWidget);
    expect(_enabled(tester), isFalse);
    final preview = find.byKey(kLatexPreviewKey);
    expect(tester.widget<ink.MathPreview>(preview).latex, r'\frac{a}{b}');
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: preview, matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, 0.4);
    // fixed again → enabled, full preview
    await _type(tester, r'\frac{a}{c}');
    expect(find.text(error), findsNothing);
    expect(_enabled(tester), isTrue);
    expect(tester.widget<ink.MathPreview>(preview).latex, r'\frac{a}{c}');
    await tester.tap(find.byKey(kSheetCancelKey));
    await tester.pumpAndSettle();
    await pending;
    expect(log.commands, isEmpty);
  });

  testWidgets('[적용] unchanged (spaces trimmed) → closes, no command', (
    tester,
  ) async {
    final host = await RecognitionHost.pump(tester);
    final pending = (await _open(tester, host, log)).run;
    await _type(tester, r'  \frac{a}{b} ');
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    await pending;
    expect(log.commands, isEmpty);
    expect(log.doneCalls, 0);
  });

  testWidgets('[적용] changed → one UpdateObjects: same id, centre and '
      'rotation kept, laid out at its font size, engineId manual', (
    tester,
  ) async {
    final host = await RecognitionHost.pump(tester);
    final pending = (await _open(tester, host, log)).run;
    const latex = r'\sum_{i=1}^{n} i^2';
    await _type(tester, latex);
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    await pending;
    final cmd = log.commands.single as core.UpdateObjects;
    expect(cmd.pageId, kPageId);
    final m = cmd.objects.single as core.MathObject;
    expect(m.id, 'math-1');
    expect(m.latex, latex);
    expect(m.engineId, 'manual');
    expect(m.style, _math.style);
    expect(m.frame.rotation, 0.3);
    expect(m.frame.center.x, closeTo(_math.frame.center.x, 1e-9));
    expect(m.frame.center.y, closeTo(_math.frame.center.y, 1e-9));
    final laid = ink.InkMathRenderer.layout(latex, fontSizePt: 24)!;
    expect(m.frame.rect.width, closeTo(laid.sizePt.width, 1e-9));
    expect(m.frame.rect.height, closeTo(laid.sizePt.height, 1e-9));
    expect(m.updatedAt, kHostNow.millisecondsSinceEpoch);
    expect(log.doneCalls, 0, reason: 'the selection stays (same id)');
  });

  testWidgets('[적용] in a note session → undo depth + 1; one undo brings '
      'the old formula back (9.3)', (tester) async {
    final host = await RecognitionHost.pump(tester);
    final doc = await SessionDoc.open(
      tester,
      host.store,
      objects: (pageId) => [
        _math.copyTo(id: 'math-1', pageId: pageId, createdAt: 1730800000000),
      ],
    );
    final math = (await doc.content(tester)).objects.single as core.MathObject;
    final depth = doc.undoDepth;
    final pending = _editMath.run(host.body, doc.target(log, objects: [math]));
    await tester.pumpAndSettle();
    await _type(tester, r'\sqrt{x}');
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    await pending;
    expect(log.commands, hasLength(1));
    expect(doc.undoDepth, depth + 1);
    var content = await doc.content(tester);
    expect((content.objects.single as core.MathObject).latex, r'\sqrt{x}');
    await doc.undo(tester);
    expect(doc.undoDepth, depth);
    content = await doc.content(tester);
    final back = content.objects.single as core.MathObject;
    expect(back.id, 'math-1');
    expect(back.latex, r'\frac{a}{b}');
    await doc.close(tester);
  });

  testWidgets('[LaTeX 복사]: the field value sent inside onPressed; 복사했어요', (
    tester,
  ) async {
    final host = await RecognitionHost.pump(tester);
    final platform = PlatformLog(tester);
    final pending = (await _open(tester, host, log)).run;
    await _type(tester, r' x^2 ');
    tester.widget<OutlinedButton>(find.byKey(kSheetSecondaryKey)).onPressed!();
    expect(platform.clipboardTexts, ['x^2']); // before any microtask
    await tester.pump();
    expect(find.text('복사했어요.'), findsOneWidget);
    expect(_sheet, findsOneWidget, reason: 'copying keeps the sheet');
    await tester.tap(find.byKey(kSheetCancelKey));
    await tester.pumpAndSettle();
    await pending;
    expect(log.commands, isEmpty);
  });

  testWidgets('the clipboard refuses → 복사하지 못했어요 in the sheet', (tester) async {
    final host = await RecognitionHost.pump(tester);
    PlatformLog(tester).reply = (call) async =>
        call.method == 'Clipboard.setData'
        ? throw PlatformException(code: 'NotAllowedError')
        : null;
    final pending = (await _open(tester, host, log)).run;
    await tester.tap(find.byKey(kSheetSecondaryKey));
    await tester.pump();
    expect(find.text('복사하지 못했어요.'), findsOneWidget);
    await tester.tap(find.byKey(kSheetCancelKey));
    await tester.pumpAndSettle();
    await pending;
  });

  testWidgets('read-only note: 읽기 전용 … in the sheet, which stays open; '
      'copying still works', (tester) async {
    final host = await RecognitionHost.pump(tester);
    final platform = PlatformLog(tester);
    log.executeError = core.ReadOnlyNoteException('note-1');
    final pending = (await _open(tester, host, log)).run;
    await _type(tester, r'y^3');
    await tester.tap(_primary);
    await tester.pump();
    expect(find.text('읽기 전용 노트라 바꿀 수 없어요.'), findsOneWidget);
    expect(_sheet, findsOneWidget);
    expect(log.commands, isEmpty);
    await tester.tap(find.byKey(kSheetSecondaryKey));
    await tester.pump();
    expect(platform.clipboardTexts, ['y^3']);
    await tester.tap(find.byKey(kSheetCancelKey));
    await tester.pumpAndSettle();
    await pending;
  });

  testWidgets('[취소] → closes, nothing executed', (tester) async {
    final host = await RecognitionHost.pump(tester);
    final pending = (await _open(tester, host, log)).run;
    await _type(tester, r'z');
    await tester.tap(find.byKey(kSheetCancelKey));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    await pending;
    expect(log.commands, isEmpty);
  });
}
