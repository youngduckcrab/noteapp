// (math pen, phase 1 — docs/plans/m5-7/research/math-pen-phase1.md 4.3, 6.2,
// 10, 11) recog's math pen session with a scripted engine, inside the small
// editor stand-in (RecognitionHost: ProviderScope → MaterialApp → body):
// - recognition starts 500 ms after the last update, never before; a new
//   contact cancels the request in flight; a late answer of an older group
//   is ignored (only the newest counts); answers are cached;
// - background conversion: a usable answer → ONE CompositeCommand
//   ('recog-math-pen') — formula left-aligned to the ink, about its height,
//   the strokes kept as ink; nothing usable / changed strokes / timeout →
//   no command; x^2 → x^2+1 when the group grows;
// - a reopened formula answers for its own strokes at once;
// - no engine: the bubble says so, the tap opens the LaTeX editor (typed by
//   hand → the same command); 고치기 opens the editor with the symbol row;
// - the bubble's states.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/actions/object_builders.dart';
import 'package:ink_recognition/src/math_pen/math_pen_bubble.dart';
import 'package:ink_recognition/src/math_pen/math_pen_session.dart';
import 'package:ink_recognition/src/ondevice/on_device_providers.dart';
import 'package:ink_recognition/src/ui/latex_editor_sheet.dart';
import 'package:ink_recognition/src/ui/recognition_sheet.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/recognition_test_scope.dart';

/// Answers by the number of traces (default 'x^{2}' for 3, 'x^{2}+1' for 6,
/// else 'n' + the count); each call can be held by [hold].
final class _Engine implements MathRecognizer {
  @override
  bool get isAvailable => true;

  @override
  String get engineId => 'test/1';

  String Function(int traces) answer = (n) => switch (n) {
    3 => 'x^{2}',
    6 => 'x^{2}+1',
    _ => 'n$n',
  };

  final List<int> calls = [];
  int cancelled = 0;

  /// When set, the next call waits for it (and ignores cancel when
  /// [ignoreCancel]).
  Completer<void>? hold;
  bool ignoreCancel = false;
  RecognitionFailure? failWith;

  @override
  Future<MathResult> recognize(MathInput input, {Future<void>? cancel}) async {
    calls.add(input.traces.length);
    final n = input.traces.length;
    final h = hold;
    hold = null;
    if (h != null) {
      var wasCancelled = false;
      final cancelled = cancel?.then((_) => wasCancelled = true);
      await Future.any([
        h.future,
        if (cancelled != null && !ignoreCancel) cancelled,
      ]);
      if (wasCancelled) {
        this.cancelled++;
        if (!ignoreCancel) throw RecognizerCancelled();
      }
    }
    final f = failWith;
    if (f != null) throw f;
    return MathResult(
      latex: answer(n),
      engineId: engineId,
      latency: Duration.zero,
    );
  }
}

/// The page: strokes by id; liveStrokes reads it.
final class _Page {
  final Map<String, core.Stroke> strokes = {};
  final List<core.EditCommand> commands = [];

  List<core.Stroke>? live(String pageId, List<String> ids) {
    final out = <core.Stroke>[];
    for (final id in ids) {
      final s = strokes[id];
      if (s == null) return null;
      out.add(s);
    }
    return out;
  }

  void execute(core.EditCommand command) {
    commands.add(command);
    if (command case core.CompositeCommand(:final commands)) {
      for (final c in commands) {
        if (c case core.RemoveElements(:final elementIds)) {
          elementIds.forEach(strokes.remove);
        }
      }
    }
  }
}

core.Stroke _glyph(String id, double x, {double y = 100, int createdAt = 1}) =>
    glyphStroke(id, x, y, 20, createdAt: createdAt);

RecognitionTarget _group(_Page page, List<core.Stroke> strokes) {
  for (final s in strokes) {
    page.strokes[s.id] = s;
  }
  Rect? r;
  for (final s in strokes) {
    final b = s.points.pointBounds;
    final x = Rect.fromLTRB(b.left, b.top, b.right, b.bottom);
    r = r == null ? x : r.expandToInclude(x);
  }
  return RecognitionTarget(
    noteId: kNoteId,
    pageId: kPageId,
    pageSize: core.PageSize.a4Portrait,
    strokes: strokes,
    areaPt: r!,
    execute: page.execute,
    done: () {},
  );
}

Future<(RecognitionHost, MathPenSession, _Page)> _pump(
  WidgetTester tester,
  MathRecognizer engine,
) async {
  final host = await RecognitionHost.pump(
    tester,
    overrides: [mathRecognizerProvider.overrideWithValue(engine)],
  );
  final page = _Page();
  final session = MathPenSession(
    RecognitionMathPenContext(
      noteId: kNoteId,
      execute: page.execute,
      liveStrokes: page.live,
      bodyContext: () => host.body,
    ),
  );
  addTearDown(session.dispose);
  return (host, session, page);
}

List<core.Stroke> _three() => [
  _glyph('a', 100),
  _glyph('b', 112),
  _glyph('c', 125, y: 90),
];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ink_testing.loadKatexFontsForTest();
  });

  testWidgets('recognition starts 500 ms after the last update; answers are '
      'cached by the strokes', (tester) async {
    final engine = _Engine();
    final (_, session, page) = await _pump(tester, engine);
    final g = _group(page, _three());
    session.update(g);
    expect(session.view.value, isA<MathPenWaiting>());
    await tester.pump(const Duration(milliseconds: 499));
    expect(engine.calls, isEmpty);
    session.update(g); // a new update restarts the wait
    await tester.pump(const Duration(milliseconds: 499));
    expect(engine.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(engine.calls, [3]);
    final view = session.view.value as MathPenAnswer;
    expect(view.usable, 'x^{2}');
    // Same strokes again (undo brought them back): the cache, no request.
    session.update(g);
    expect(session.view.value, isA<MathPenAnswer>());
    await tester.pump(const Duration(seconds: 1));
    expect(engine.calls, [3]);
    expect(kMathPenRecognizeDelay, const Duration(milliseconds: 500));
  });

  testWidgets('a new contact cancels the request in flight; a late answer '
      'of an older group is ignored', (tester) async {
    final engine = _Engine();
    final (_, session, page) = await _pump(tester, engine);
    final strokes = _three();
    final g1 = _group(page, strokes.take(2).toList());
    engine
      ..hold = Completer<void>()
      ..ignoreCancel = true; // the engine answers anyway
    final held = engine.hold!;
    session.update(g1);
    await tester.pump(kMathPenRecognizeDelay);
    expect(engine.calls, [2]);
    session.interrupt(); // the pen touches down again
    final g2 = _group(page, strokes);
    session.update(g2);
    held.complete(); // the old answer arrives late
    await tester.pump();
    expect(engine.cancelled, 1);
    expect(session.view.value, isA<MathPenWaiting>(), reason: 'n2 ignored');
    await tester.pump(kMathPenRecognizeDelay);
    await tester.pump();
    expect(engine.calls, [2, 3]);
    expect((session.view.value as MathPenAnswer).usable, 'x^{2}');
  });

  testWidgets('background conversion: ONE composite, formula left-aligned '
      'to the ink and about its height, the strokes kept as ink', (
    tester,
  ) async {
    final engine = _Engine();
    final (_, session, page) = await _pump(tester, engine);
    final strokes = _three();
    final g = _group(page, strokes);
    session.update(g);
    await tester.pump(kMathPenRecognizeDelay);
    await tester.pump();
    expect(await session.convert(g, interactive: false), isTrue);
    final c = page.commands.single as core.CompositeCommand;
    expect(c.label, kMathPenLabel);
    expect((c.commands[0] as core.RemoveElements).elementIds, ['a', 'b', 'c']);
    final math =
        (c.commands[1] as core.AddObjects).objects.single as core.MathObject;
    expect(math.latex, 'x^{2}');
    expect(math.engineId, 'test/1');
    expect(math.ink.map((s) => s.id), ['a', 'b', 'c']);
    expect(math.ink.first.points.contentEquals(strokes.first.points), isTrue);
    final ink = g.areaPt;
    expect(math.frame.rect.left, ink.left);
    expect(
      (math.frame.rect.top + math.frame.rect.bottom) / 2,
      closeTo(ink.center.dy, 0.01),
    );
    expect(math.frame.rect.height, closeTo(ink.height, ink.height * 0.35));
    expect(engine.calls, [3], reason: 'the cached answer, no new request');
  });

  testWidgets('background conversion without an answer asks once (its own '
      'request); nothing usable → no command; changed strokes → no command', (
    tester,
  ) async {
    final engine = _Engine()..answer = (_) => r'\frac{';
    final (_, session, page) = await _pump(tester, engine);
    final g = _group(page, _three());
    final first = session.convert(g, interactive: false);
    await tester.pump();
    expect(await first, isFalse);
    expect(engine.calls, [3]);
    expect(page.commands, isEmpty);

    engine.answer = (_) => 'y';
    final g2 = _group(page, [_glyph('d', 300)]);
    page.strokes['d'] = page.strokes['d']!.copyWith(updatedAt: 99); // edited
    final second = session.convert(g2, interactive: false);
    await tester.pump();
    expect(await second, isFalse);
    expect(page.commands, isEmpty);
  });

  testWidgets('background conversion gives up after 10 s', (tester) async {
    final engine = _Engine()..hold = Completer<void>();
    final (_, session, page) = await _pump(tester, engine);
    final g = _group(page, _three());
    bool? ok;
    unawaited(session.convert(g, interactive: false).then((v) => ok = v));
    await tester.pump(const Duration(seconds: 9));
    expect(ok, isNull);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(ok, isFalse);
    expect(engine.cancelled, 1);
    expect(page.commands, isEmpty);
    expect(kMathPenBackgroundTimeout, const Duration(seconds: 10));
  });

  testWidgets('continue writing: x^2 → x^2+1 (recognition on old + new)', (
    tester,
  ) async {
    final engine = _Engine();
    final (_, session, page) = await _pump(tester, engine);
    final x2 = _three();
    final g = _group(page, x2);
    expect(await session.convert(g, interactive: false), isTrue);
    final first =
        (page.commands.last as core.CompositeCommand).commands[1]
            as core.AddObjects;
    final formula = first.objects.single as core.MathObject;
    // Reopened: its ink with new ids, then "+1" (three more strokes).
    final reopened = [for (final s in formula.ink) s.copyWith(id: 'r-${s.id}')];
    final more = [_glyph('p', 140), _glyph('q', 145), _glyph('one', 160)];
    final g2 = _group(page, [...reopened, ...more]);
    session.update(
      _group(page, reopened),
      reopenedFrom: formula,
      reopenedStrokeIds: {for (final s in reopened) s.id},
    );
    // The reopened strokes alone answer at once (no request).
    expect((session.view.value as MathPenAnswer).usable, 'x^{2}');
    expect(engine.calls, [3]);
    session.update(
      g2,
      reopenedFrom: formula,
      reopenedStrokeIds: {for (final s in reopened) s.id},
    );
    await tester.pump(kMathPenRecognizeDelay);
    await tester.pump();
    expect(engine.calls, [3, 6]);
    expect(await session.convert(g2, interactive: false), isTrue);
    final again =
        ((page.commands.last as core.CompositeCommand).commands[1]
                    as core.AddObjects)
                .objects
                .single
            as core.MathObject;
    expect(again.latex, 'x^{2}+1');
    expect(again.ink, hasLength(6));
  });

  testWidgets('the bubble: 인식 중… (+ the last formula dimmed), the '
      'MathPreview of the answer, an unusable answer, a failure with 다시', (
    tester,
  ) async {
    var retried = 0;
    Future<void> show(MathPenView view) => tester.pumpWidget(
      ProviderScope(
        overrides: [mathModelManagerProvider.overrideWithValue(null)],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: MathPenBubble(
                view: view,
                onConvert: () {},
                onRetry: () => retried++,
              ),
            ),
          ),
        ),
      ),
    );
    const answer = MathResult(
      latex: 'x^{2}',
      engineId: 'e',
      latency: Duration.zero,
    );
    await show(const MathPenWaiting(previous: 'x'));
    expect(find.text('인식 중…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<ink.MathPreview>(find.byKey(MathPenBubbleKeys.preview))
          .latex,
      'x',
    );
    await show(const MathPenAnswer(answer, 'x^{2}'));
    final preview = find.byKey(MathPenBubbleKeys.preview);
    expect(tester.widget<ink.MathPreview>(preview).latex, 'x^{2}');
    expect(tester.getSize(preview).width, greaterThan(0));
    await show(
      const MathPenAnswer(
        MathResult(latex: r'\frac{', engineId: 'e', latency: Duration.zero),
        null,
      ),
    );
    expect(find.text('그릴 수 없는 결과예요. 눌러서 고쳐요.'), findsOneWidget);
    expect(find.text(r'\frac{'), findsOneWidget);
    await show(const MathPenFailed('수식을 인식하지 못했어요. 다시 시도해 주세요.'));
    await tester.tap(find.byKey(MathPenBubbleKeys.retry));
    expect(retried, 1);
    await show(const MathPenNeedsConsent());
    expect(find.text('외부 수식 인식 동의가 필요해요. 눌러서 확인해요.'), findsOneWidget);
  });

  testWidgets('failures show the 6.11.4 text; 다시 recognizes again', (
    tester,
  ) async {
    final engine = _Engine()..failWith = RecognizerOffline();
    final (_, session, page) = await _pump(tester, engine);
    final g = _group(page, _three());
    session.update(g);
    await tester.pump(kMathPenRecognizeDelay);
    await tester.pump();
    expect(
      (session.view.value as MathPenFailed).message,
      '수식 인식 서버에 연결할 수 없어요. 인터넷 연결을 확인해 주세요.',
    );
    engine.failWith = null;
    session.retry();
    await tester.pump(kMathPenRecognizeDelay);
    await tester.pump();
    expect((session.view.value as MathPenAnswer).usable, 'x^{2}');
    engine.failWith = RecognizerConsentRequired();
    final g2 = _group(page, [_glyph('k', 400)]);
    session.update(g2);
    await tester.pump(kMathPenRecognizeDelay);
    await tester.pump();
    expect(session.view.value, isA<MathPenNeedsConsent>());
  });

  testWidgets('no engine: the bubble says so with LaTeX로 입력 (no on-device '
      'button without a model manager); the tap opens the LaTeX editor; '
      'typed → the same command with the ink', (tester) async {
    final (host, session, page) = await _pump(
      tester,
      const ManualOnlyMathRecognizer(),
    );
    final g = _group(page, _three());
    session.update(g);
    expect(session.view.value, isA<MathPenNoEngine>());
    final bubble = MathPenBubble(
      view: session.view.value,
      onConvert: () {},
      onRetry: () {},
    );
    expect(bubble.view, isA<MathPenNoEngine>());
    final converting = session.convert(g, interactive: true);
    await tester.pumpAndSettle();
    expect(find.byKey(kLatexSheetKey), findsOneWidget);
    expect(find.text('수식 인식 엔진이 연결되지 않아 LaTeX로 직접 입력해요.'), findsOneWidget);
    expect(find.byKey(kLatexSymbolRowKey), findsOneWidget);
    await tester.enterText(find.byKey(kLatexFieldKey), 'x');
    await tester.tap(find.byKey(latexSymbolKey('pow')));
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(kLatexFieldKey));
    expect(field.controller!.text, 'x^{}');
    expect(field.controller!.selection.baseOffset, 3);
    await tester.enterText(find.byKey(kLatexFieldKey), 'x^{2}');
    await tester.pump(kLatexValidateDelay);
    await tester.tap(find.byKey(kSheetPrimaryKey));
    await tester.pumpAndSettle();
    expect(await converting, isTrue);
    final c = page.commands.single as core.CompositeCommand;
    expect(c.label, kMathPenLabel);
    final math =
        (c.commands[1] as core.AddObjects).objects.single as core.MathObject;
    expect(math.latex, 'x^{2}');
    expect(math.engineId, kManualMathEngineId);
    expect(math.ink, hasLength(3));
    expect(host.snackBars, isEmpty);
  });

  testWidgets('the no-engine bubble widget: off notice + LaTeX로 입력; '
      '기기에서 수식 인식 켜기 only with a model manager (opens the tile)', (
    tester,
  ) async {
    var converted = 0;
    Future<void> show({required bool manager}) => tester.pumpWidget(
      ProviderScope(
        key: ValueKey(manager),
        overrides: [
          if (!manager) mathModelManagerProvider.overrideWithValue(null),
          core.noteStoreProvider.overrideWithValue(createFixedClockStore()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MathPenBubble(
              view: const MathPenNoEngine(),
              onConvert: () => converted++,
              onRetry: () {},
            ),
          ),
        ),
      ),
    );
    await show(manager: false);
    expect(find.text('수식 인식이 꺼져 있어요.'), findsOneWidget);
    expect(find.byKey(MathPenBubbleKeys.enableOnDevice), findsNothing);
    await tester.tap(find.byKey(MathPenBubbleKeys.typeLatex));
    expect(converted, 1);
    await show(manager: true); // this VM has the native model manager
    expect(find.byKey(MathPenBubbleKeys.enableOnDevice), findsOneWidget);
    await tester.tap(find.byKey(MathPenBubbleKeys.enableOnDevice));
    await tester.pumpAndSettle();
    expect(find.byKey(MathPenBubbleKeys.onDeviceSheet), findsOneWidget);
    expect(find.text('기기에서 수식 인식'), findsOneWidget);
  });

  testWidgets('고치기: the LaTeX editor on the formula with the symbol row; '
      'one UpdateObjects keeps the ink', (tester) async {
    final (_, session, page) = await _pump(tester, _Engine());
    final ink = _three();
    final formula = core.MathObject(
      id: 'm',
      pageId: kPageId,
      frame: const core.ElementFrame(core.PageRect(100, 90, 140, 120)),
      latex: 'x^{3}',
      style: const core.MathStyle(),
      ink: ink,
      createdAt: 1,
    );
    final fixing = session.fix(
      RecognitionTarget(
        noteId: kNoteId,
        pageId: kPageId,
        pageSize: core.PageSize.a4Portrait,
        objects: [formula],
        areaPt: const Rect.fromLTRB(100, 90, 140, 120),
        execute: page.execute,
        done: () {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kLatexSymbolRowKey), findsOneWidget);
    final field = find.byKey(kLatexFieldKey);
    final controller = tester.widget<TextField>(field).controller!;
    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.tap(find.byKey(latexSymbolKey('frac')));
    await tester.pump();
    expect(controller.text, r'x^{\frac{}{}3}');
    await tester.enterText(field, 'x^{2}');
    await tester.pump(kLatexValidateDelay);
    await tester.tap(find.byKey(kSheetPrimaryKey));
    await tester.pumpAndSettle();
    await fixing;
    final update = page.commands.single as core.UpdateObjects;
    final edited = update.objects.single as core.MathObject;
    expect(edited.latex, 'x^{2}');
    expect(edited.ink, ink);
  });
}
