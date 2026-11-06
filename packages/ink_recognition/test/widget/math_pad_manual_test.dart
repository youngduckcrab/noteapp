// L2-14 (m5-7/05-library 8.2, 6.14.1, 6.14.5, 6.14.6): the math pad's direct
// input path — with ManualOnlyMathRecognizer (the default engine) there is no
// handwriting area, the 'LaTeX로 직접 입력해요' notice shows and the field
// has the focus; typing updates the real INK MathPreview (size > 0 after
// loadKatexFontsForTest); invalid LaTeX → [넣기] disabled, the preview empty
// and its onError text under it; [넣기] → ONE AddObjects (default MathStyle,
// centred in the visible rect, engineId 'manual') → the sheet closes →
// done() once; [취소] → nothing; a read-only note → the notice.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/ui/math_pad_sheet.dart';
import 'package:ink_recognition/src/ui/recognition_sheet.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/recognition_test_scope.dart';

RecognitionAction get _pad => recognitionInsertActions().single;

Finder get _sheet => find.byKey(kMathPadSheetKey);
Finder get _field => find.byKey(kMathPadLatexKey);
Finder get _preview => find.byKey(kMathPadPreviewKey);
Finder get _primary => find.byKey(kSheetPrimaryKey);

bool _enabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_primary).onPressed != null;

/// The insert context's visible rect (page pt).
const Rect _visible = Rect.fromLTWH(100, 100, 600, 400); // centre (400, 300)

Future<({Future<void> run})> _open(
  WidgetTester tester,
  RecognitionHost host,
  TargetLog log,
) async {
  final pending = _pad.run(host.body, log.target(areaPt: _visible));
  await tester.pumpAndSettle();
  expect(_sheet, findsOneWidget);
  return (run: pending);
}

Future<void> _close(WidgetTester tester, Future<void> run) async {
  await tester.tap(find.byKey(kSheetCancelKey));
  await tester.pumpAndSettle();
  await run;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ink_testing.loadKatexFontsForTest();
  });

  late TargetLog log;
  setUp(() => log = TargetLog());

  testWidgets('ManualOnly: no handwriting area, the notice, the field has '
      'the focus, [넣기] disabled while empty', (tester) async {
    final host = await RecognitionHost.pump(tester);
    final run = (await _open(tester, host, log)).run;
    expect(find.text('수식 입력'), findsOneWidget);
    expect(find.text('넣기'), findsOneWidget);
    expect(find.byKey(const ValueKey('recog.pad.canvas')), findsNothing);
    expect(find.text('수식 인식 엔진이 연결되지 않아 LaTeX로 직접 입력해요.'), findsOneWidget);
    final editable = tester.widget<EditableText>(
      find.descendant(of: _field, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    expect(_preview, findsNothing);
    expect(_enabled(tester), isFalse);
    await _close(tester, run);
    expect(log.commands, isEmpty);
    expect(log.doneCalls, 0);
  });

  testWidgets('typing updates the real MathPreview (size > 0)', (tester) async {
    final host = await RecognitionHost.pump(tester);
    final run = (await _open(tester, host, log)).run;
    await tester.enterText(_field, r'\frac{a}{b}');
    await tester.pump();
    expect(tester.widget<ink.MathPreview>(_preview).latex, r'\frac{a}{b}');
    var size = tester.getSize(_preview);
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));
    await tester.enterText(_field, r'\sqrt{x^2 + 1}');
    await tester.pump();
    expect(tester.widget<ink.MathPreview>(_preview).latex, r'\sqrt{x^2 + 1}');
    size = tester.getSize(_preview);
    expect(size.width, greaterThan(0));
    expect(_enabled(tester), isTrue);
    await _close(tester, run);
  });

  testWidgets('invalid LaTeX: [넣기] disabled, preview empty, the onError '
      'text under it', (tester) async {
    final host = await RecognitionHost.pump(tester);
    final run = (await _open(tester, host, log)).run;
    const bad = r'\frac{a}{';
    await tester.enterText(_field, bad);
    await tester.pump(); // build → onError after the frame
    await tester.pump();
    expect(_enabled(tester), isFalse);
    expect(tester.getSize(_preview), Size.zero);
    expect(find.text(ink.InkMathRenderer.validate(bad)!), findsOneWidget);
    // too long (> 4,000 characters) is refused too
    await tester.enterText(_field, 'x' * 4001);
    await tester.pump();
    expect(_enabled(tester), isFalse);
    await _close(tester, run);
    expect(log.commands, isEmpty);
  });

  testWidgets('[넣기] → one AddObjects centred in the visible rect, '
      'engineId manual → closes → done() once', (tester) async {
    final host = await RecognitionHost.pump(tester);
    final run = (await _open(tester, host, log)).run;
    const latex = r'E = mc^2';
    await tester.enterText(_field, '  $latex ');
    await tester.pump();
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    await run;
    final cmd = log.commands.single as core.AddObjects;
    expect(cmd.pageId, kPageId);
    final m = cmd.objects.single as core.MathObject;
    expect(m.pageId, kPageId);
    expect(m.latex, latex);
    expect(m.engineId, 'manual');
    expect(m.style, const core.MathStyle());
    expect(m.frame.rotation, 0);
    expect(m.frame.center.x, closeTo(400, 1e-9));
    expect(m.frame.center.y, closeTo(300, 1e-9));
    final laid = ink.InkMathRenderer.layout(latex, fontSizePt: 18)!;
    expect(m.frame.rect.width, closeTo(laid.sizePt.width, 1e-9));
    expect(m.frame.rect.height, closeTo(laid.sizePt.height, 1e-9));
    expect(m.createdAt, kHostNow.millisecondsSinceEpoch);
    expect(m.updatedAt, kHostNow.millisecondsSinceEpoch);
    expect(core.isValidEntityId(m.id), isTrue);
    expect(log.doneCalls, 1);
  });

  testWidgets('[넣기] in a note session → undo depth + 1; one undo takes the '
      'formula away (9.3)', (tester) async {
    final host = await RecognitionHost.pump(tester);
    final doc = await SessionDoc.open(tester, host.store);
    final depth = doc.undoDepth;
    final run = _pad.run(host.body, doc.target(log, areaPt: _visible));
    await tester.pumpAndSettle();
    await tester.enterText(_field, r'E = mc^2');
    await tester.pump();
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    await run;
    expect(log.commands, hasLength(1));
    expect(doc.undoDepth, depth + 1);
    final added = (log.commands.single as core.AddObjects).objects.single;
    expect((await doc.content(tester)).objects.map((o) => o.id), [added.id]);
    await doc.undo(tester);
    expect(doc.undoDepth, depth);
    expect((await doc.content(tester)).objects, isEmpty);
    await doc.close(tester);
  });

  testWidgets('[취소] → no command, no done()', (tester) async {
    final host = await RecognitionHost.pump(tester);
    final run = (await _open(tester, host, log)).run;
    await tester.enterText(_field, 'x');
    await tester.pump();
    await _close(tester, run);
    expect(_sheet, findsNothing);
    expect(log.commands, isEmpty);
    expect(log.doneCalls, 0);
  });

  testWidgets('read-only note: 읽기 전용 … in the pad, which stays open', (
    tester,
  ) async {
    final host = await RecognitionHost.pump(tester);
    log.executeError = core.ReadOnlyNoteException('note-1');
    final run = (await _open(tester, host, log)).run;
    await tester.enterText(_field, 'x+1');
    await tester.pump();
    await tester.tap(_primary);
    await tester.pump();
    expect(find.text('읽기 전용 노트라 바꿀 수 없어요.'), findsOneWidget);
    expect(_sheet, findsOneWidget);
    await _close(tester, run);
    expect(log.commands, isEmpty);
    expect(log.doneCalls, 0);
  });

  testWidgets('the editor body gone before the pad closes → no done()', (
    tester,
  ) async {
    final host = await RecognitionHost.pump(tester);
    final run = (await _open(tester, host, log)).run;
    await tester.enterText(_field, 'y');
    await tester.pump();
    await host.unmountBody();
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    await run;
    expect(log.commands, hasLength(1)); // the write had started
    expect(log.doneCalls, 0);
  });
}
