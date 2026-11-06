// L2-17a (m5-7/05-library 8.2, 6.14.1–6.14.5, 6.11.3, 6.11.6): the math
// pad's handwriting path with an engine (FakeMathRecognizer — contract 7.6).
// The handwriting area is a temporary page (never stored) drawn through the
// real INK controller; a pen-up starts a 1 s pause (999 ms → no call, 1,000
// ms → one call), a new contact stops it and cancels the request in flight;
// the answer fills the field until the user edits it (then chips only); a
// chip puts its value back; RecognizerConsentRequired → the consent card
// ([동의하고 쓰기] → recog.mathConsent true + recognized again, [직접 입력] →
// the area hidden); the strokes are ShapeAssist.off; the store sees no
// change; the PNG goes along only with a page renderer.
// L2-22 (P-C, 6.14.7): the fixture mode (settings › 인식 › 품질 실험 [수식
// 고정 자료 만들기]) — the area shows whatever the engine, nothing is
// recognized, [고정 자료 복사] puts the 07-sync 6.9.1 line on the clipboard in
// the press (store changes 0, engine calls 0), then the area and the field
// are emptied for the next sample.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/l10n/recognition_strings.dart';
import 'package:ink_recognition/src/math/math_payload.dart';
import 'package:ink_recognition/src/settings/recognition_settings_keys.dart';
import 'package:ink_recognition/src/ui/math_pad_canvas.dart';
import 'package:ink_recognition/src/ui/math_pad_sheet.dart';
import 'package:ink_recognition/src/ui/recognition_sheet.dart';
import 'package:ink_recognition/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/recognition_test_scope.dart';

RecognitionAction get _pad => recognitionInsertActions().single;

Finder get _sheet => find.byKey(kMathPadSheetKey);
Finder get _canvas => find.byKey(kMathPadCanvasKey);
Finder get _field => find.byKey(kMathPadLatexKey);
Finder get _status => find.byKey(kMathPadStatusKey);
Finder get _primary => find.byKey(kSheetPrimaryKey);
Finder get _agree => find.byKey(kConsentAgreeKey);
Finder get _manual => find.byKey(kConsentManualKey);

const Rect _visible = Rect.fromLTWH(100, 100, 600, 400);

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(_field).controller!.text;

String _statusText(WidgetTester tester) => tester.widget<Text>(_status).data!;

List<String> _chips(WidgetTester tester) {
  final chips = <String>[];
  for (var i = 0; find.byKey(mathPadChipKey(i)).evaluate().isNotEmpty; i++) {
    final chip = tester.widget<ActionChip>(find.byKey(mathPadChipKey(i)));
    chips.add((chip.label as Text).data ?? '');
  }
  return chips;
}

/// The pad's temporary page id and its INK controller.
String _padPageId(WidgetTester tester) =>
    tester.widget<MathPadCanvas>(find.byType(MathPadCanvas)).pageId;

ink.InkPageController _controller(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MathPadCanvas)))
        .read(ink.inkPageControllerProvider(_padPageId(tester)));

int _strokeCount(WidgetTester tester) =>
    tester.widget<MathPadCanvas>(find.byType(MathPadCanvas)).ink.strokes.length;

int _pointer = 100;
int _clockMs = 0;

/// Puts the pen (or a finger) down at [from] (canvas-local) and leaves it
/// there; returns the gesture.
Future<TestGesture> _touch(
  WidgetTester tester,
  Offset from, {
  PointerDeviceKind kind = PointerDeviceKind.stylus,
}) async {
  final origin = tester.getTopLeft(_canvas) + const Offset(1, 1);
  final g = await tester.createGesture(pointer: _pointer++, kind: kind);
  await g.down(origin + from, timeStamp: Duration(milliseconds: _clockMs));
  return g;
}

/// Moves [g] through [path] (canvas-local) and lifts it.
Future<void> _finish(
  WidgetTester tester,
  TestGesture g,
  List<Offset> path,
) async {
  final origin = tester.getTopLeft(_canvas) + const Offset(1, 1);
  for (final p in path) {
    _clockMs += 8;
    await g.moveTo(origin + p, timeStamp: Duration(milliseconds: _clockMs));
  }
  _clockMs += 8;
  await g.up(timeStamp: Duration(milliseconds: _clockMs));
  await tester.pump();
}

/// One stroke from [from] through a small zig-zag (canvas-local).
Future<void> _stroke(
  WidgetTester tester, {
  Offset from = const Offset(40, 40),
  PointerDeviceKind kind = PointerDeviceKind.stylus,
}) async {
  final g = await _touch(tester, from, kind: kind);
  await _finish(tester, g, [
    for (var i = 1; i <= 8; i++) from + Offset(4.0 * i, i.isEven ? 6 : 0),
  ]);
}

Future<({RecognitionHost host, Future<void> run})> _open(
  WidgetTester tester,
  TargetLog log, {
  required MathRecognizer engine,
  List<Override> overrides = const [],
  core.NoteStore? store,
}) async {
  final host = await RecognitionHost.pump(
    tester,
    store: store,
    overrides: [mathRecognizerProvider.overrideWithValue(engine), ...overrides],
  );
  final run = _pad.run(host.body, log.target(areaPt: _visible));
  await tester.pumpAndSettle();
  expect(_sheet, findsOneWidget);
  return (host: host, run: run);
}

Future<void> _close(WidgetTester tester, Future<void> run) async {
  await tester.tap(find.byKey(kSheetCancelKey));
  await tester.pumpAndSettle();
  await run;
}

Future<List<FlutterErrorDetails>> _reports(Future<void> Function() body) async {
  final reported = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = reported.add;
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return reported;
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

/// An engine that throws something unexpected.
final class _BrokenEngine implements MathRecognizer {
  int calls = 0;

  @override
  String get engineId => 'broken';

  @override
  bool get isAvailable => true;

  @override
  Future<MathResult> recognize(MathInput input, {Future<void>? cancel}) async {
    calls++;
    throw StateError('engine bug');
  }
}

/// A page renderer that records what it was asked to draw.
final class _RecordingRenderer implements core.PageThumbnailRenderer {
  final List<(core.PageContent, int)> calls = [];
  final Uint8List bytes = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);

  @override
  Future<core.PageThumbnail?> render(
    core.PageContent content, {
    int maxSidePx = 512,
  }) async {
    calls.add((content, maxSidePx));
    return core.PageThumbnail(
      pageId: content.page.id,
      contentRevision: content.page.contentRevision,
      width: 500,
      height: 250,
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

  testWidgets('an engine: the handwriting area, the tools, 상태: 멈추면 '
      '인식해요, no direct-input notice', (tester) async {
    final engine = FakeMathRecognizer();
    final opened = await _open(tester, log, engine: engine);
    expect(_canvas, findsOneWidget);
    expect(find.byType(ink.InkPageView), findsOneWidget);
    expect(find.text('되돌리기'), findsOneWidget);
    expect(find.text('지우개'), findsOneWidget);
    expect(find.text('모두 지우기'), findsOneWidget);
    expect(_statusText(tester), '상태: 멈추면 인식해요');
    expect(find.text('수식 인식 엔진이 연결되지 않아 LaTeX로 직접 입력해요.'), findsNothing);
    expect(_padPageId(tester), startsWith('mathpad_'));
    // the area is 40% of the sheet (50% of 1032) = 206.4 px high
    expect(tester.getSize(_canvas).height, closeTo(1032 * 0.5 * 0.4, 0.01));
    await _close(tester, opened.run);
    expect(engine.calls, isEmpty);
  });

  testWidgets('pen-up → 999 ms no call, 1,000 ms one call with the strokes; '
      'the answer fills the field', (tester) async {
    final engine = FakeMathRecognizer(latex: r'\frac{a}{b}');
    final opened = await _open(tester, log, engine: engine);
    await _stroke(tester);
    expect(_strokeCount(tester), 1);
    await tester.pump(const Duration(milliseconds: 999));
    expect(engine.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(engine.calls, hasLength(1));
    final input = engine.calls.single;
    expect(input.traces, hasLength(1));
    expect(input.traces.single.xs.length, greaterThan(2));
    // pt = logical px of the area, from the area's top-left
    expect(input.traces.single.xs.first, closeTo(40, 1));
    expect(input.traces.single.ys.first, closeTo(40, 1));
    expect(input.png, isNull); // no page renderer
    await tester.pump();
    expect(_fieldText(tester), r'\frac{a}{b}');
    expect(_statusText(tester), '상태: 멈추면 인식해요');
    await _close(tester, opened.run);
  });

  testWidgets('a new contact stops the pause: no call while the pen is down, '
      '1 s again after it lifts', (tester) async {
    final engine = FakeMathRecognizer();
    final opened = await _open(tester, log, engine: engine);
    await _stroke(tester);
    await tester.pump(const Duration(milliseconds: 600));
    final g = await _touch(tester, const Offset(120, 40));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(engine.calls, isEmpty);
    await _finish(tester, g, const [Offset(130, 50), Offset(140, 44)]);
    await tester.pump(const Duration(milliseconds: 999));
    expect(engine.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(engine.calls, hasLength(1));
    expect(engine.calls.single.traces, hasLength(2));
    await _close(tester, opened.run);
  });

  testWidgets('a contact cancels the request in flight: its answer never '
      'lands, the next one does', (tester) async {
    final engine = FakeMathRecognizer(
      latex: 'x^2',
      latency: const Duration(seconds: 2),
    );
    final opened = await _open(tester, log, engine: engine);
    await _stroke(tester);
    await tester.pump(kMathPadPause);
    expect(engine.calls, hasLength(1));
    expect(_statusText(tester), '상태: 인식 중…');
    final g = await _touch(tester, const Offset(120, 40));
    await tester.pump();
    expect(_statusText(tester), '상태: 멈추면 인식해요');
    await tester.pump(const Duration(seconds: 3));
    expect(_fieldText(tester), isEmpty);
    await _finish(tester, g, const [Offset(130, 50)]);
    await tester.pump(kMathPadPause);
    expect(engine.calls, hasLength(2));
    await tester.pump(const Duration(seconds: 2));
    expect(_fieldText(tester), 'x^2');
    await _close(tester, opened.run);
  });

  testWidgets('6.14.4: after the user edits the field, answers are chips '
      'only; a chip puts its value back; [넣기] keeps the engine id', (
    tester,
  ) async {
    final engine = FakeMathRecognizer(latex: r'\frac{a}{b}')
      ..alternatives = [r'\frac{a}{6}', r'\frac{a}{b}', 'a/b', 'x', 'y'];
    final opened = await _open(tester, log, engine: engine);
    await _stroke(tester);
    await tester.pump(kMathPadPause);
    await tester.pump();
    expect(_fieldText(tester), r'\frac{a}{b}');
    // the answer is in the field: up to 3 other alternatives as chips
    expect(_chips(tester), [r'\frac{a}{6}', 'a/b', 'x']);

    await tester.enterText(_field, 'y+1');
    await tester.pump();
    await _stroke(tester, from: const Offset(150, 40));
    await tester.pump(kMathPadPause);
    await tester.pump();
    expect(engine.calls, hasLength(2));
    expect(_fieldText(tester), 'y+1'); // the user's value stays
    expect(_chips(tester), [r'\frac{a}{b}', r'\frac{a}{6}', 'a/b', 'x']);

    await tester.tap(find.byKey(mathPadChipKey(1)));
    await tester.pump();
    expect(_fieldText(tester), r'\frac{a}{6}');
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    await opened.run;
    final m =
        (log.commands.single as core.AddObjects).objects.single
            as core.MathObject;
    expect(m.latex, r'\frac{a}{6}');
    expect(m.engineId, 'fake/1'); // a chip is the engine's value
    expect(m.frame.center.x, closeTo(400, 1e-9));
    expect(m.frame.center.y, closeTo(300, 1e-9));
    expect(log.doneCalls, 1);
  });

  testWidgets('recognized and [넣기] in a note session → undo depth + 1 (the '
      'pad strokes never reach the note); one undo takes the formula away '
      '(9.3)', (tester) async {
    final host = await RecognitionHost.pump(
      tester,
      overrides: [
        mathRecognizerProvider.overrideWithValue(
          FakeMathRecognizer(latex: r'\sqrt{2}'),
        ),
      ],
    );
    final doc = await SessionDoc.open(tester, host.store);
    final depth = doc.undoDepth;
    final run = _pad.run(host.body, doc.target(log, areaPt: _visible));
    await tester.pumpAndSettle();
    await _stroke(tester);
    await _stroke(tester, from: const Offset(90, 40));
    await tester.pump(kMathPadPause);
    await tester.pump();
    expect(_fieldText(tester), r'\sqrt{2}');
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    await run;
    expect(log.commands, hasLength(1));
    expect(doc.undoDepth, depth + 1);
    var content = await doc.content(tester);
    expect(content.strokes, isEmpty);
    final m = content.objects.single as core.MathObject;
    expect(m.latex, r'\sqrt{2}');
    expect(m.engineId, 'fake/1');
    await doc.undo(tester);
    expect(doc.undoDepth, depth);
    content = await doc.content(tester);
    expect(content.objects, isEmpty);
    expect(content.strokes, isEmpty);
    await doc.close(tester);
  });

  testWidgets('an edited field → [넣기] keeps engineId manual; an emptied '
      'field takes the next answer again', (tester) async {
    final engine = FakeMathRecognizer(latex: 'x^2');
    final opened = await _open(tester, log, engine: engine);
    await _stroke(tester);
    await tester.pump(kMathPadPause);
    await tester.pump();
    expect(_fieldText(tester), 'x^2');
    await tester.enterText(_field, '');
    await tester.pump();
    await _stroke(tester, from: const Offset(150, 40));
    await tester.pump(kMathPadPause);
    await tester.pump();
    expect(_fieldText(tester), 'x^2'); // empty → not edited any more
    await tester.enterText(_field, 'x^3');
    await tester.pump();
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    await opened.run;
    final m =
        (log.commands.single as core.AddObjects).objects.single
            as core.MathObject;
    expect(m.latex, 'x^3');
    expect(m.engineId, 'manual');
  });

  testWidgets('an answer taken as is → [넣기] keeps its engine id', (
    tester,
  ) async {
    final engine = FakeMathRecognizer(latex: r'\sqrt{2}');
    final opened = await _open(tester, log, engine: engine);
    await _stroke(tester);
    await tester.pump(kMathPadPause);
    await tester.pump();
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    await opened.run;
    final m =
        (log.commands.single as core.AddObjects).objects.single
            as core.MathObject;
    expect(m.latex, r'\sqrt{2}');
    expect(m.engineId, 'fake/1');
    expect(log.doneCalls, 1);
  });

  testWidgets('before consent: the card over the area → [동의하고 쓰기] → '
      'recog.mathConsent true and recognized again', (tester) async {
    final store = createFixedClockStore();
    addTearDown(store.close);
    final engine = _ConsentGatedEngine(
      FakeMathRecognizer(latex: 'e^{i\\pi}'),
      () => store.settings.get(RecognitionSettingsKeys.mathConsent),
    );
    final opened = await _open(tester, log, engine: engine, store: store);
    expect(_agree, findsNothing);
    await _stroke(tester);
    await tester.pump(kMathPadPause);
    await tester.pump();
    expect(engine.refused, 1);
    expect(engine.inner.calls, isEmpty);
    expect(_agree, findsOneWidget);
    expect(_manual, findsOneWidget);
    expect(find.text('수식 인식에 외부 서비스를 써요'), findsOneWidget);
    expect(find.text(RecognitionStrings.consentBody), findsOneWidget);
    expect(_canvas, findsOneWidget); // the card lies over the area
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    await tester.tap(_agree);
    await tester.pump();
    await tester.pump();
    expect(
      await store.settings.get(RecognitionSettingsKeys.mathConsent),
      isTrue,
    );
    expect(engine.inner.calls, hasLength(1));
    expect(engine.inner.calls.single.traces, hasLength(1));
    await tester.pump();
    expect(_agree, findsNothing);
    expect(_fieldText(tester), 'e^{i\\pi}');
    await _close(tester, opened.run);
  });

  testWidgets('[직접 입력] on the consent card hides the area, focuses the '
      'field, recognizes nothing more', (tester) async {
    final store = createFixedClockStore();
    addTearDown(store.close);
    final engine = _ConsentGatedEngine(
      FakeMathRecognizer(),
      () => store.settings.get(RecognitionSettingsKeys.mathConsent),
    );
    final opened = await _open(tester, log, engine: engine, store: store);
    await _stroke(tester);
    await tester.pump(kMathPadPause);
    await tester.pump();
    await tester.tap(_manual);
    await tester.pump();
    expect(_canvas, findsNothing);
    expect(find.text('되돌리기'), findsNothing);
    final editable = tester.widget<EditableText>(
      find.descendant(of: _field, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    await tester.pump(const Duration(seconds: 5));
    expect(engine.refused, 1);
    expect(
      await store.settings.get(RecognitionSettingsKeys.mathConsent),
      isFalse,
    );
    await tester.enterText(_field, 'a+b');
    await tester.pump();
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    await opened.run;
    final m =
        (log.commands.single as core.AddObjects).objects.single
            as core.MathObject;
    expect(m.engineId, 'manual');
  });

  testWidgets('the temporary page is never stored: no store change for '
      'drawing, erasing, recognizing and inserting', (tester) async {
    final store = createFixedClockStore();
    addTearDown(store.close);
    final batches = <core.ChangeBatch>[];
    final sub = store.changes.listen(batches.add);
    addTearDown(sub.cancel);
    final engine = FakeMathRecognizer(latex: 'x');
    final opened = await _open(tester, log, engine: engine, store: store);
    await _stroke(tester);
    await _stroke(tester, from: const Offset(150, 40));
    await tester.tap(find.byKey(kMathPadUndoKey));
    await tester.pump(kMathPadPause);
    await tester.pump();
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    await opened.run;
    expect(log.commands, hasLength(1)); // only through the target
    expect(batches, isEmpty);
  });

  testWidgets('the strokes start with ShapeAssist.off (a held stroke never '
      'becomes a shape) on the temporary page', (tester) async {
    final fitter = ink_testing.FakeInkShapeFitter(
      fit: ink.InkShapeFit(
        kind: core.ShapeKind.ellipse,
        geometry: core.ShapeGeometry.ellipse(
          const core.PageRect(20, 30, 60, 50),
        ),
        score: 1,
      ),
      minPoints: 1,
    );
    final opened = await _open(
      tester,
      log,
      engine: FakeMathRecognizer(),
      overrides: [ink.inkShapeFitterProvider.overrideWithValue(fitter)],
    );
    final g = await _touch(tester, const Offset(40, 40));
    await tester.pump();
    final session = _controller(tester).activeSession;
    expect(session, isA<ink.StrokeSession>());
    expect((session! as ink.StrokeSession).shapeAssist, ink.ShapeAssist.off);
    await tester.pump(const Duration(seconds: 1)); // a long hold
    await _finish(tester, g, const [Offset(40, 41), Offset(41, 41)]);
    expect(fitter.calls, 0);
    final strokes = tester
        .widget<MathPadCanvas>(find.byType(MathPadCanvas))
        .ink
        .strokes;
    expect(strokes, hasLength(1));
    expect(strokes.single.pageId, _padPageId(tester));
    expect(strokes.single.style.tool, core.PenTool.ballpoint);
    await _close(tester, opened.run);
  });

  testWidgets('eraser, undo and clear change the strokes and restart the '
      'pause; an empty area clears the suggestions without a call', (
    tester,
  ) async {
    final engine = FakeMathRecognizer(latex: 'a')..alternatives = ['b'];
    final opened = await _open(tester, log, engine: engine);
    await _stroke(tester);
    await _stroke(tester, from: const Offset(200, 40));
    await _stroke(tester, from: const Offset(360, 40));
    expect(_strokeCount(tester), 3);
    await tester.pump(kMathPadPause);
    await tester.pump();
    expect(engine.calls, hasLength(1));
    expect(_chips(tester), ['b']);

    // eraser: a swipe through the first stroke only
    await tester.tap(find.byKey(kMathPadEraserKey));
    await tester.pump();
    final e = await _touch(tester, const Offset(50, 20));
    await _finish(tester, e, const [Offset(50, 40), Offset(50, 60)]);
    expect(_strokeCount(tester), 2);
    await tester.pump(const Duration(milliseconds: 999));
    expect(engine.calls, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(engine.calls, hasLength(2));
    expect(engine.calls.last.traces, hasLength(2));
    await tester.tap(find.byKey(kMathPadEraserKey)); // back to the pen
    await tester.pump();

    await tester.tap(find.byKey(kMathPadUndoKey));
    await tester.pump();
    expect(_strokeCount(tester), 1);
    await tester.pump(kMathPadPause);
    expect(engine.calls, hasLength(3));
    expect(engine.calls.last.traces, hasLength(1));

    await tester.tap(find.byKey(kMathPadClearKey));
    await tester.pump();
    expect(_strokeCount(tester), 0);
    await tester.pump(kMathPadPause);
    await tester.pump();
    expect(engine.calls, hasLength(3)); // nothing to recognize
    expect(_chips(tester), isEmpty);
    // undo / clear are disabled on an empty area
    expect(
      tester.widget<TextButton>(find.byKey(kMathPadClearKey)).onPressed,
      isNull,
    );
    await _close(tester, opened.run);
  });

  testWidgets('a finger draws until a pen came; after that fingers are '
      'ignored', (tester) async {
    final engine = FakeMathRecognizer();
    final opened = await _open(tester, log, engine: engine);
    await _stroke(tester, kind: PointerDeviceKind.touch);
    expect(_strokeCount(tester), 1);
    await _stroke(tester, from: const Offset(150, 40));
    expect(_strokeCount(tester), 2);
    await _stroke(
      tester,
      from: const Offset(260, 40),
      kind: PointerDeviceKind.touch,
    );
    expect(_strokeCount(tester), 2);
    await _close(tester, opened.run);
  });

  testWidgets('6.11.4 failures: the status line text, the area stays, not '
      'reported; an unexpected error → reported once', (tester) async {
    final cases = <RecognitionFailure, String>{
      RecognizerOffline(): '수식 인식 서버에 연결할 수 없어요. 인터넷 연결을 확인해 주세요.',
      RecognizerQuotaExceeded(): '오늘 쓸 수 있는 수식 인식 횟수를 다 썼어요.',
      RecognizerEngineError('unauthenticated', 'x'): '로그인한 뒤에 수식 인식을 쓸 수 있어요.',
      RecognizerEngineError('permission-denied', 'x'):
          '이 계정에서는 수식 인식을 쓸 수 없어요.',
      RecognizerEngineError('invalid-argument', 'x'): '이 필기는 수식으로 보낼 수 없어요.',
      RecognizerEngineError('internal', 'x'): '수식을 인식하지 못했어요. 다시 시도해 주세요.',
    };
    for (final MapEntry(key: failure, value: text) in cases.entries) {
      final engine = FakeMathRecognizer(failWith: failure);
      final reports = await _reports(() async {
        final opened = await _open(tester, log, engine: engine);
        await _stroke(tester);
        await tester.pump(kMathPadPause);
        await tester.pump();
        expect(_statusText(tester), text, reason: '$failure');
        expect(_canvas, findsOneWidget);
        // the next pause tries again
        await _stroke(tester, from: const Offset(150, 40));
        await tester.pump(kMathPadPause);
        expect(engine.calls, hasLength(2));
        await _close(tester, opened.run);
      });
      expect(reports, isEmpty, reason: '$failure');
    }

    final broken = _BrokenEngine();
    final reports = await _reports(() async {
      final opened = await _open(tester, log, engine: broken);
      await _stroke(tester);
      await tester.pump(kMathPadPause);
      await tester.pump();
      expect(_statusText(tester), '수식을 인식하지 못했어요. 다시 시도해 주세요.');
      await _close(tester, opened.run);
    });
    expect(broken.calls, 1);
    expect(reports, hasLength(1));
    expect(reports.single.library, 'ink_recognition');
  });

  testWidgets('with a page renderer: MathInput.png = its PNG of the strokes '
      'moved to an 8 pt margin, pngPxPerPt = px ÷ pt (6.11.3)', (tester) async {
    final renderer = _RecordingRenderer();
    final engine = FakeMathRecognizer();
    final opened = await _open(
      tester,
      log,
      engine: engine,
      overrides: [
        core.pageThumbnailRendererProvider.overrideWithValue(renderer),
      ],
    );
    await _stroke(tester, from: const Offset(60, 50));
    final stroke = tester
        .widget<MathPadCanvas>(find.byType(MathPadCanvas))
        .ink
        .strokes
        .single;
    await tester.pump(kMathPadPause);
    await tester.pump();
    expect(renderer.calls, hasLength(1));
    final (content, maxSide) = renderer.calls.single;
    expect(maxSide, 1024);
    final b = stroke.bounds;
    expect(content.page.size.width, closeTo(b.right - b.left + 16, 1e-6));
    expect(content.page.size.height, closeTo(b.bottom - b.top + 16, 1e-6));
    expect(content.page.background, const core.BlankBackground());
    final moved = content.strokes.single;
    expect(moved.pageId, content.page.id);
    expect(moved.points.x(0), closeTo(stroke.points.x(0) - b.left + 8, 1e-3));
    expect(moved.points.y(0), closeTo(stroke.points.y(0) - b.top + 8, 1e-3));
    final input = engine.calls.single;
    expect(input.png, same(renderer.bytes));
    expect(input.pngPxPerPt, closeTo(500 / content.page.size.width, 1e-9));
    await _close(tester, opened.run);
  });

  testWidgets('closing the pad while a request is in flight cancels it (no '
      'timer left, no command)', (tester) async {
    final engine = FakeMathRecognizer(latency: const Duration(seconds: 30));
    final opened = await _open(tester, log, engine: engine);
    await _stroke(tester);
    await tester.pump(kMathPadPause);
    expect(engine.calls, hasLength(1));
    await _close(tester, opened.run);
    expect(log.commands, isEmpty);
    expect(log.doneCalls, 0);
  });

  group('fixture mode (6.14.7, P-C)', () {
    Finder fixtureSheet() => find.byKey(kMathFixtureSheetKey);
    Finder copy() => find.byKey(kMathPadExportFixtureKey);
    bool copyEnabled(WidgetTester tester) =>
        tester.widget<FilledButton>(copy()).onPressed != null;

    Future<({RecognitionHost host, Future<void> open})> openFixture(
      WidgetTester tester, {
      List<Override> overrides = const [],
      core.NoteStore? store,
    }) async {
      final host = await RecognitionHost.pump(
        tester,
        store: store,
        overrides: overrides,
      );
      final open = openMathFixturePad(host.body);
      await tester.pumpAndSettle();
      expect(fixtureSheet(), findsOneWidget);
      return (host: host, open: open);
    }

    Future<void> closeFixture(WidgetTester tester, Future<void> open) async {
      await tester.tap(find.byKey(kSheetCancelKey));
      await tester.pumpAndSettle();
      await open;
      expect(fixtureSheet(), findsNothing);
    }

    testWidgets('no engine needed: the area, the tools, no status line, no '
        'direct-input notice; ≤ 90% of the screen; [닫기] closes', (
      tester,
    ) async {
      final opened = await openFixture(tester); // ManualOnly by default
      expect(_canvas, findsOneWidget);
      expect(find.byType(ink.InkPageView), findsOneWidget);
      expect(find.text('되돌리기'), findsOneWidget);
      expect(find.text('지우개'), findsOneWidget);
      expect(find.text('모두 지우기'), findsOneWidget);
      expect(_status, findsNothing);
      expect(_agree, findsNothing);
      expect(find.text(RecognitionStrings.manualOnly), findsNothing);
      expect(find.text(RecognitionStrings.mathFixtureEntry), findsOneWidget);
      expect(find.text(RecognitionStrings.close), findsOneWidget);
      expect(find.text(RecognitionStrings.mathFixtureCopy), findsOneWidget);
      expect(_primary, findsNothing); // the primary is recog.pad.exportFixture
      expect(_padPageId(tester), startsWith('mathfixture_'));
      expect(
        tester.widget<MathPadCanvas>(find.byType(MathPadCanvas)).noteId,
        'mathfixture',
      );
      expect(
        tester.getSize(fixtureSheet()).height,
        lessThanOrEqualTo(1032 * 0.9 + 0.01),
      );
      // the area is 40% of the sheet (90% of 1032)
      expect(tester.getSize(_canvas).height, closeTo(1032 * 0.9 * 0.4, 0.01));
      expect(copyEnabled(tester), isFalse);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await closeFixture(tester, opened.open);
    });

    testWidgets('[고정 자료 복사]: the 6.9.1 line on the clipboard in the '
        'press; no recognition, no store change; then emptied for the next '
        'sample', (tester) async {
      final store = createFixedClockStore();
      addTearDown(store.close);
      final batches = <core.ChangeBatch>[];
      final sub = store.changes.listen(batches.add);
      addTearDown(sub.cancel);
      final engine = FakeMathRecognizer(latex: 'wrong');
      final platform = PlatformLog(tester);
      final opened = await openFixture(
        tester,
        store: store,
        overrides: [mathRecognizerProvider.overrideWithValue(engine)],
      );
      await _stroke(tester);
      await _stroke(tester, from: const Offset(150, 40));
      await tester.pump(const Duration(seconds: 3));
      expect(engine.calls, isEmpty); // never recognized (6.14.7)
      expect(_fieldText(tester), isEmpty);
      expect(copyEnabled(tester), isFalse); // the answer is still missing

      await tester.enterText(_field, r' \frac{a+b}{c} ');
      await tester.pump();
      expect(copyEnabled(tester), isTrue);
      final strokes = tester
          .widget<MathPadCanvas>(find.byType(MathPadCanvas))
          .ink
          .strokes;
      expect(strokes, hasLength(2));

      await tester.tap(copy());
      expect(platform.clipboardTexts, hasLength(1)); // inside the press
      final line = platform.clipboardTexts.single!;
      expect(line, isNot(contains('\n')));
      final json = jsonDecode(line) as Map<String, Object?>;
      expect(json.keys.toList(), [
        'id',
        'tags',
        'expected',
        'strokes',
        'source',
      ]);
      // the fake store's clock: kHostNow = 2026-11-06 10:00:00
      expect(json['id'], 'user-20261106-100000');
      expect(json['tags'], isEmpty);
      expect(json['expected'], r'\frac{a+b}{c}');
      expect(json['source'], 'user-android-2026-11-06');
      final traces = [for (final s in strokes) HandwritingTrace.fromStroke(s)];
      expect(json['strokes'], jsonDecode(jsonEncode(mathStrokesOf(traces))));
      final ts = (json['strokes']! as Map)['t']! as List;
      expect((ts.first as List).first, 0);
      final xs = (json['strokes']! as Map)['x']! as List;
      expect(((xs.first as List).first as num).toDouble(), closeTo(40, 1));
      expect(((xs.last as List).first as num).toDouble(), closeTo(150, 1));

      await tester.pump();
      await tester.pump();
      expect(find.text(RecognitionStrings.mathFixtureCopied), findsOneWidget);
      expect(_strokeCount(tester), 0);
      expect(_fieldText(tester), isEmpty);
      expect(copyEnabled(tester), isFalse);
      expect(fixtureSheet(), findsOneWidget); // ready for the next sample

      // the next sample: the notice goes when the user writes the answer
      await _stroke(tester);
      await tester.enterText(_field, 'x^2');
      await tester.pump();
      expect(find.text(RecognitionStrings.mathFixtureCopied), findsNothing);
      await tester.tap(copy());
      expect(platform.clipboardTexts, hasLength(2));
      expect(
        (jsonDecode(platform.clipboardTexts.last!) as Map)['expected'],
        'x^2',
      );
      await tester.pump();
      await closeFixture(tester, opened.open);
      await tester.pump(const Duration(seconds: 3));
      expect(engine.calls, isEmpty);
      expect(batches, isEmpty);
    });

    testWidgets('disabled without strokes, with an empty field or LaTeX that '
        'does not parse', (tester) async {
      final platform = PlatformLog(tester);
      final opened = await openFixture(tester);
      await tester.enterText(_field, 'x^2');
      await tester.pump();
      expect(copyEnabled(tester), isFalse); // no stroke
      await _stroke(tester);
      expect(copyEnabled(tester), isTrue);
      await tester.enterText(_field, r'\frac{a');
      await tester.pump();
      expect(copyEnabled(tester), isFalse); // validate error
      await tester.enterText(_field, '   ');
      await tester.pump();
      expect(copyEnabled(tester), isFalse); // empty
      await tester.tap(copy());
      await tester.pump();
      expect(platform.clipboardTexts, isEmpty);
      await tester.enterText(_field, 'x');
      await tester.pump();
      await tester.tap(find.byKey(kMathPadUndoKey));
      await tester.pump();
      expect(copyEnabled(tester), isFalse); // undone: no stroke again
      await closeFixture(tester, opened.open);
    });

    testWidgets('the clipboard fails → 복사하지 못했어요. and the sample stays', (
      tester,
    ) async {
      final platform = PlatformLog(tester)
        ..reply = (call) async => call.method == 'Clipboard.setData'
            ? throw PlatformException(code: 'denied', message: 'no activation')
            : null;
      final opened = await openFixture(tester);
      await _stroke(tester);
      await tester.enterText(_field, 'y');
      await tester.pump();
      await tester.tap(copy());
      await tester.pump();
      await tester.pump();
      expect(platform.clipboardTexts, hasLength(1));
      expect(find.text(RecognitionStrings.copyFailed), findsOneWidget);
      expect(find.text(RecognitionStrings.mathFixtureCopied), findsNothing);
      expect(_strokeCount(tester), 1);
      expect(_fieldText(tester), 'y');
      expect(copyEnabled(tester), isTrue);
      await closeFixture(tester, opened.open);
    });

    testWidgets('the preview shows the answer; eraser and clear work as in '
        'the pad', (tester) async {
      final opened = await openFixture(tester);
      await tester.enterText(_field, r'\sqrt{2}');
      await tester.pumpAndSettle();
      final preview = find.byKey(kMathPadPreviewKey);
      expect(preview, findsOneWidget);
      expect(tester.getSize(preview).width, greaterThan(0));
      await _stroke(tester);
      await _stroke(tester, from: const Offset(150, 40));
      await tester.tap(find.byKey(kMathPadEraserKey));
      await tester.pump();
      await _stroke(tester, from: const Offset(150, 40)); // erases the second
      expect(_strokeCount(tester), 1);
      await tester.tap(find.byKey(kMathPadClearKey));
      await tester.pump();
      expect(_strokeCount(tester), 0);
      expect(copyEnabled(tester), isFalse);
      await closeFixture(tester, opened.open);
    });
  });
}
