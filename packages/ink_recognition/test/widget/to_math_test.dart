// L2-17b (m5-7/05-library 8.2, 6.15.3, 6.14.5, 6.11.3, 6.11.6): recog.toMath
// — the LaTeX editor sheet (recog.sheet.latex) opens at once with '인식 중…'
// and asks the math engine for the selection's input strokes; the answer
// fills the field (alternatives → chips; the user's edit wins — 6.14.4);
// [수식으로 바꾸기] → ONE CompositeCommand([RemoveElements(inputs),
// AddObjects([math])], 'recog-to-math') sized from the selection bounds →
// done(); ManualOnly / before consent / a failure → the 6.14.5 text and a
// read-only view of the chosen strokes; closing the sheet cancels the
// request.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/actions/object_builders.dart';
import 'package:ink_recognition/src/settings/recognition_settings_keys.dart';
import 'package:ink_recognition/src/ui/latex_editor_sheet.dart';
import 'package:ink_recognition/src/ui/math_pad_canvas.dart';
import 'package:ink_recognition/src/ui/recognition_sheet.dart';
import 'package:ink_recognition/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/recognition_test_scope.dart';

RecognitionAction get _toMath =>
    recognitionSelectionActions().singleWhere((a) => a.id == 'recog.toMath');

Finder get _sheet => find.byKey(kLatexSheetKey);
Finder get _field => find.byKey(kLatexFieldKey);
Finder get _status => find.byKey(kLatexStatusKey);
Finder get _strokesView => find.byKey(kMathStrokesViewKey);
Finder get _primary => find.byKey(kSheetPrimaryKey);
Finder get _agree => find.byKey(kConsentAgreeKey);
Finder get _manual => find.byKey(kConsentManualKey);

/// The selection: three ink strokes (two black, one red) and a highlighter
/// stroke (not a recognition input — it stays on the page).
final List<core.Stroke> _selection = _selectionOn(kPageId);

List<core.Stroke> _selectionOn(String pageId) => [
  glyphStroke('s1', 110, 110, 60, createdAt: 1, pageId: pageId),
  glyphStroke('s2', 180, 110, 60, createdAt: 2, pageId: pageId),
  glyphStroke(
    's3',
    250,
    110,
    60,
    colorArgb: 0xFFD32F2F,
    createdAt: 3,
    pageId: pageId,
  ),
  strokeOf(
    'h1',
    const [(100, 150), (390, 150)],
    tool: core.PenTool.highlighter,
    createdAt: 4,
    pageId: pageId,
  ),
];

/// The selection bounds EDITOR passes (target.areaPt).
const Rect _area = Rect.fromLTWH(100, 100, 300, 120);

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(_field).controller!.text;

String? _statusText(WidgetTester tester) => _status.evaluate().isEmpty
    ? null
    : tester.widget<SheetNotice>(_status).text;

bool _primaryEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_primary).onPressed != null;

List<String> _chips(WidgetTester tester) {
  final chips = <String>[];
  for (var i = 0; find.byKey(latexChipKey(i)).evaluate().isNotEmpty; i++) {
    final chip = tester.widget<ActionChip>(find.byKey(latexChipKey(i)));
    chips.add((chip.label as Text).data ?? '');
  }
  return chips;
}

Future<({RecognitionHost host, Future<void> run})> _open(
  WidgetTester tester,
  TargetLog log, {
  MathRecognizer? engine,
  List<Override> overrides = const [],
  core.NoteStore? store,
}) async {
  final host = await RecognitionHost.pump(
    tester,
    store: store,
    overrides: [
      if (engine != null) mathRecognizerProvider.overrideWithValue(engine),
      ...overrides,
    ],
  );
  final run = _toMath.run(
    host.body,
    log.target(strokes: _selection, areaPt: _area),
  );
  await tester.pump(); // the sheet opens at once
  await tester.pump(const Duration(milliseconds: 400)); // its animation
  expect(_sheet, findsOneWidget);
  return (host: host, run: run);
}

Future<void> _close(WidgetTester tester, Future<void> run) async {
  await tester.tap(find.byKey(kSheetCancelKey));
  await tester.pumpAndSettle();
  await run;
}

/// Lets an answer land (its microtasks, then a frame for the rebuild).
Future<void> _answered(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

/// Lets the 150 ms validation run.
Future<void> _validated(WidgetTester tester) async {
  await tester.pump(kLatexValidateDelay);
  await tester.pump();
}

/// An engine whose answer the test completes; records the cancel futures.
final class _ControlledEngine implements MathRecognizer {
  final List<MathInput> calls = [];
  final List<Future<void>?> cancels = [];
  final List<Completer<MathResult>> answers = [];
  int cancelled = 0;

  /// Thrown by the next call instead of waiting (then cleared).
  RecognitionFailure? failNext;

  @override
  String get engineId => 'controlled';

  @override
  bool get isAvailable => true;

  @override
  Future<MathResult> recognize(MathInput input, {Future<void>? cancel}) {
    calls.add(input);
    cancels.add(cancel);
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      return Future.error(failure);
    }
    final answer = Completer<MathResult>();
    answers.add(answer);
    unawaited(
      cancel?.then((_) {
        cancelled++;
        if (!answer.isCompleted) answer.completeError(RecognizerCancelled());
      }),
    );
    return answer.future;
  }

  void answer(String latex, {List<String> alternatives = const []}) =>
      answers.last.complete(
        MathResult(
          latex: latex,
          alternatives: alternatives,
          engineId: 'controlled/2',
          latency: Duration.zero,
        ),
      );
}

/// An engine that asks [consent] first, like CallableMathRecognizer (6.11.5).
final class _ConsentGatedEngine implements MathRecognizer {
  _ConsentGatedEngine(this.inner, this.consent);

  final FakeMathRecognizer inner;
  final Future<bool> Function() consent;
  int refused = 0;

  @override
  String get engineId => inner.engineId;

  @override
  bool get isAvailable => true;

  @override
  Future<MathResult> recognize(MathInput input, {Future<void>? cancel}) async {
    if (!await consent()) {
      refused++;
      throw RecognizerConsentRequired();
    }
    return inner.recognize(input, cancel: cancel);
  }
}

/// A page renderer that records what it was asked to draw.
final class _RecordingRenderer implements core.PageThumbnailRenderer {
  final List<core.PageContent> calls = [];
  final Uint8List bytes = Uint8List.fromList([137, 80, 78, 71, 9]);

  @override
  Future<core.PageThumbnail?> render(
    core.PageContent content, {
    int maxSidePx = 512,
  }) async {
    calls.add(content);
    return core.PageThumbnail(
      pageId: content.page.id,
      contentRevision: 0,
      width: 632,
      height: 272,
      mimeType: 'image/png',
      bytes: bytes,
    );
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ink_testing.loadKatexFontsForTest();
  });

  late TargetLog log;
  setUp(() => log = TargetLog());

  testWidgets('recognize → 수식으로 바꾸기 → one CompositeCommand sized from '
      'the selection bounds → done()', (tester) async {
    final engine = _ControlledEngine();
    final opened = await _open(tester, log, engine: engine);
    expect(find.text('수식으로 변환'), findsOneWidget);
    expect(find.text('수식으로 바꾸기'), findsOneWidget);
    expect(_statusText(tester), '인식 중…');
    expect(_strokesView, findsNothing);
    expect(_primaryEnabled(tester), isFalse); // empty field
    // only the recognition inputs, in page pt (not moved)
    final input = engine.calls.single;
    expect([for (final t in input.traces) t.strokeId], ['s1', 's2', 's3']);
    expect(input.traces.first.xs.first, 110);
    expect(input.traces.first.ys.first, 110);
    expect(input.png, isNull); // no page renderer

    engine.answer(r'\frac{a}{b}', alternatives: ['a/b', r'\frac{a}{b}']);
    await _answered(tester);
    expect(_fieldText(tester), r'\frac{a}{b}');
    expect(_chips(tester), ['a/b']);
    expect(_statusText(tester), isNull);
    await _validated(tester);
    expect(_primaryEnabled(tester), isTrue);

    await tester.tap(_primary);
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    await opened.run;
    final cmd = log.commands.single as core.CompositeCommand;
    expect(cmd.label, 'recog-to-math');
    final remove = cmd.commands[0] as core.RemoveElements;
    expect(remove.pageId, kPageId);
    expect(remove.elementIds, ['s1', 's2', 's3']); // the highlighter stays
    final add = cmd.commands[1] as core.AddObjects;
    final m = add.objects.single as core.MathObject;
    expect(m.latex, r'\frac{a}{b}');
    expect(m.engineId, 'controlled/2');
    final base = ink.InkMathRenderer.layout(r'\frac{a}{b}', fontSizePt: 18)!;
    final size = mathFontSizeFor(
      boundsHeightPt: _area.height,
      baseHeightPt: base.sizePt.height,
    );
    expect(m.style.fontSizePt, size);
    expect(m.style.colorArgb, 0xFF1A1A1A); // most inputs are black
    final laid = ink.InkMathRenderer.layout(r'\frac{a}{b}', fontSizePt: size)!;
    expect(m.frame.rect.width, closeTo(laid.sizePt.width, 1e-9));
    expect(m.frame.rect.height, closeTo(laid.sizePt.height, 1e-9));
    expect(m.frame.center.x, closeTo(_area.center.dx, 1e-9));
    expect(m.frame.center.y, closeTo(_area.center.dy, 1e-9));
    expect(m.frame.rotation, 0);
    expect(core.isValidEntityId(m.id), isTrue);
    expect(log.doneCalls, 1);
  });

  testWidgets('[수식으로 바꾸기] in a note session → undo depth + 1; one undo '
      'brings the strokes back and takes the formula away (9.3)', (
    tester,
  ) async {
    final host = await RecognitionHost.pump(
      tester,
      overrides: [
        mathRecognizerProvider.overrideWithValue(
          FakeMathRecognizer(latex: r'\frac{a}{b}'),
        ),
      ],
    );
    final doc = await SessionDoc.open(
      tester,
      host.store,
      strokes: _selectionOn,
    );
    final selection = (await doc.content(tester)).strokes;
    final depth = doc.undoDepth;
    final run = _toMath.run(
      host.body,
      doc.target(log, strokes: selection, areaPt: _area),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _answered(tester);
    await _validated(tester);
    expect(_fieldText(tester), r'\frac{a}{b}');
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    await run;
    expect(log.commands, hasLength(1));
    expect(doc.undoDepth, depth + 1);
    var content = await doc.content(tester);
    expect(content.strokes.map((s) => s.id), ['h1']);
    expect((content.objects.single as core.MathObject).latex, r'\frac{a}{b}');
    await doc.undo(tester);
    expect(doc.undoDepth, depth);
    content = await doc.content(tester);
    expect(
      content.strokes.map((s) => s.id),
      unorderedEquals(['s1', 's2', 's3', 'h1']),
    );
    expect(content.objects, isEmpty);
    await doc.close(tester);
  });

  testWidgets('ManualOnly: the notice, the read-only strokes view, typing → '
      'engineId manual', (tester) async {
    final opened = await _open(tester, log); // default engine: ManualOnly
    expect(_statusText(tester), '수식 인식 엔진이 연결되지 않아 LaTeX로 직접 입력해요.');
    expect(_strokesView, findsOneWidget);
    // the view draws the inputs moved to the area's top-left (+ 8 pt)
    final view = tester.widget<MathStrokesView>(find.byType(MathStrokesView));
    expect(view.page.id, startsWith('mathpad_'));
    expect(view.page.size, core.PageSize(_area.width + 16, _area.height + 16));
    expect([for (final s in view.strokes) s.id], ['s1', 's2', 's3']);
    expect(view.strokes.first.points.x(0), closeTo(110 - 100 + 8, 1e-3));
    final controller = ProviderScope.containerOf(
      tester.element(find.byType(MathStrokesView)),
    ).read(ink.inkPageControllerProvider(view.page.id));
    expect(controller.content?.strokes, hasLength(3));

    await tester.enterText(_field, 'x+y');
    await _validated(tester);
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    await opened.run;
    final cmd = log.commands.single as core.CompositeCommand;
    final m =
        (cmd.commands[1] as core.AddObjects).objects.single as core.MathObject;
    expect(m.latex, 'x+y');
    expect(m.engineId, 'manual');
    expect(log.doneCalls, 1);
  });

  testWidgets('closing the sheet cancels the request; nothing changes', (
    tester,
  ) async {
    final engine = _ControlledEngine();
    final opened = await _open(tester, log, engine: engine);
    expect(engine.cancels.single, isNotNull);
    expect(engine.cancelled, 0);
    await _close(tester, opened.run);
    expect(engine.cancelled, 1);
    expect(log.commands, isEmpty);
    expect(log.doneCalls, 0);
  });

  testWidgets('the user edits before the answer: the field stays, the answer '
      'is a chip; a chip → its value and the engine id', (tester) async {
    final engine = _ControlledEngine();
    final opened = await _open(tester, log, engine: engine);
    await tester.enterText(_field, 'z');
    await tester.pump();
    engine.answer('x^2', alternatives: ['x^3']);
    await _answered(tester);
    expect(_fieldText(tester), 'z');
    expect(_chips(tester), ['x^2', 'x^3']);
    await tester.tap(find.byKey(latexChipKey(1)));
    await _validated(tester);
    expect(_fieldText(tester), 'x^3');
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    await opened.run;
    final cmd = log.commands.single as core.CompositeCommand;
    final m =
        (cmd.commands[1] as core.AddObjects).objects.single as core.MathObject;
    expect(m.latex, 'x^3');
    expect(m.engineId, 'controlled/2');
  });

  testWidgets('an answer edited by hand → engineId manual', (tester) async {
    final engine = FakeMathRecognizer(latex: 'a+b');
    final opened = await _open(tester, log, engine: engine);
    await tester.pump();
    expect(_fieldText(tester), 'a+b');
    await tester.enterText(_field, 'a+c');
    await _validated(tester);
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    await opened.run;
    final cmd = log.commands.single as core.CompositeCommand;
    final m =
        (cmd.commands[1] as core.AddObjects).objects.single as core.MathObject;
    expect(m.engineId, 'manual');
  });

  testWidgets('before consent: the card + the strokes view → [동의하고 쓰기] '
      '→ recog.mathConsent true, recognized, the field filled', (tester) async {
    final store = createFixedClockStore();
    addTearDown(store.close);
    final engine = _ConsentGatedEngine(
      FakeMathRecognizer(latex: r'\sum_i i'),
      () => store.settings.get(RecognitionSettingsKeys.mathConsent),
    );
    final opened = await _open(tester, log, engine: engine, store: store);
    await tester.pump();
    expect(engine.refused, 1);
    expect(_agree, findsOneWidget);
    expect(_manual, findsOneWidget);
    expect(_strokesView, findsOneWidget);
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));

    await tester.tap(_agree);
    await tester.pump();
    await tester.pump();
    expect(
      await store.settings.get(RecognitionSettingsKeys.mathConsent),
      isTrue,
    );
    expect(engine.inner.calls, hasLength(1));
    await tester.pump();
    expect(_agree, findsNothing);
    expect(_strokesView, findsNothing);
    expect(_fieldText(tester), r'\sum_i i');
    await _close(tester, opened.run);
  });

  testWidgets('[직접 입력]: the card goes, the strokes view stays, the field '
      'has the focus', (tester) async {
    final store = createFixedClockStore();
    addTearDown(store.close);
    final engine = _ConsentGatedEngine(
      FakeMathRecognizer(),
      () => store.settings.get(RecognitionSettingsKeys.mathConsent),
    );
    final opened = await _open(tester, log, engine: engine, store: store);
    await tester.pump();
    await tester.tap(_manual);
    await tester.pump();
    expect(_agree, findsNothing);
    expect(_strokesView, findsOneWidget);
    final editable = tester.widget<EditableText>(
      find.descendant(of: _field, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    expect(engine.refused, 1);
    expect(engine.inner.calls, isEmpty);
    await _close(tester, opened.run);
  });

  testWidgets('a failure: its 6.11.4 text + [다시] + the strokes view; '
      '[다시] asks again', (tester) async {
    final engine = _ControlledEngine()..failNext = RecognizerOffline();
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    try {
      final opened = await _open(tester, log, engine: engine);
      await tester.pump();
      expect(_statusText(tester), '수식 인식 서버에 연결할 수 없어요. 인터넷 연결을 확인해 주세요.');
      expect(_strokesView, findsOneWidget);
      await tester.tap(find.text('다시'));
      await tester.pump();
      expect(engine.calls, hasLength(2));
      expect(_statusText(tester), '인식 중…');
      engine.answer('y');
      await _answered(tester);
      expect(_fieldText(tester), 'y');
      expect(_statusText(tester), isNull);
      expect(_strokesView, findsNothing);
      await _close(tester, opened.run);
    } finally {
      FlutterError.onError = previous;
    }
    expect(reported, isEmpty); // an expected failure
  });

  testWidgets('read-only note: the notice, the sheet stays, no done()', (
    tester,
  ) async {
    log.executeError = core.ReadOnlyNoteException('note-1');
    final opened = await _open(tester, log, engine: FakeMathRecognizer());
    await tester.pump();
    await _validated(tester);
    await tester.tap(_primary);
    await tester.pump();
    expect(find.text('읽기 전용 노트라 바꿀 수 없어요.'), findsOneWidget);
    expect(_sheet, findsOneWidget);
    await _close(tester, opened.run);
    expect(log.commands, isEmpty);
    expect(log.doneCalls, 0);
  });

  testWidgets('with a page renderer: MathInput.png of the inputs on the '
      'selection area + 8 pt margin (6.11.3)', (tester) async {
    final renderer = _RecordingRenderer();
    final engine = _ControlledEngine();
    final opened = await _open(
      tester,
      log,
      engine: engine,
      overrides: [
        core.pageThumbnailRendererProvider.overrideWithValue(renderer),
      ],
    );
    final content = renderer.calls.single;
    expect(
      content.page.size,
      core.PageSize(_area.width + 16, _area.height + 16),
    );
    expect([for (final s in content.strokes) s.id], ['s1', 's2', 's3']);
    expect(content.strokes.first.points.x(0), closeTo(18, 1e-3));
    final input = engine.calls.single;
    expect(input.png, same(renderer.bytes));
    expect(input.pngPxPerPt, closeTo(632 / (_area.width + 16), 1e-9));
    await _close(tester, opened.run);
  });
}
