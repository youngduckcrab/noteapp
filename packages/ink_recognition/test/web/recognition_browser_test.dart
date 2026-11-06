// ink_recognition on dart2js (m5-7/05-library 8.1 B6-b, 9.3 G-1). R2-B6
// part: the web-safe entry point imports and runs in Chrome, the web gets the
// unsupported handwriting engine (the stub — L2-07) and never an indexer — even when
// a test overrides an available engine — and the HandwritingTrace body shared
// with the VM keeps 13-digit epoch ms exact. (L2-05) The line grouping body
// shared with the VM (shared/line_cases.dart — V9 on the same synthetic
// pages, lineAccuracy) gives the same numbers on dart2js. (L2-15) The
// conversion sheet on the web: the fixed sentence and [닫기]. L2-20 adds the
// remaining web cases (with useInkTestFonts in setUpAll).
// (L2-06) The shape fitter's V9 cases (shared/shape_cases.dart) on dart2js.
// (L2-18) The settings section on the web: the contract 7.4.2 sentence and a
// disabled handwriting group — even with an available engine. (L2-19) No
// A-4 lab entry on the web.
// (L2-20) setUpAll(useInkTestFonts) (C23-07); no ML Kit channel call on the
// web (a channel fake records none — 9.3 G-1); CallableMathRecognizer with
// a MockClient on dart2js; the direct copy's Clipboard.setData in the same
// synchronous stretch as run (the browser's user activation, 7.2.10); the
// math pad's preview lays out without loading the KaTeX fonts.
@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/math/callable_math_recognizer.dart';
import 'package:ink_recognition/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import '../shared/line_cases.dart';
import '../shared/shape_cases.dart';
import '../shared/trace_cases.dart';
import '../support/recognition_test_scope.dart';

const MethodChannel _mlkitChannel = MethodChannel(
  'google_mlkit_digital_ink_recognizer',
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ink_testing.useInkTestFonts();
  });

  test('runs on the web', () {
    expect(kIsWeb, isTrue);
  });

  test('recognitionOverrides(): the stub (unsupported handwriting), manual '
      'math, GeometricShapeFitter, no indexer (G-1)', () async {
    final container = ProviderContainer.test(overrides: recognitionOverrides());
    final hw = container.read(handwritingRecognizerProvider);
    expect(hw, isA<UnsupportedHandwritingRecognizer>());
    expect(hw.isAvailable, isFalse);
    expect(await hw.modelState('ko'), RecognitionModelState.unsupported);
    expect(
      container.read(mathRecognizerProvider),
      isA<ManualOnlyMathRecognizer>(),
    );
    expect(recognitionOverrides(), hasLength(3));
    expect(
      container.read(ink.inkShapeFitterProvider),
      isA<GeometricShapeFitter>(),
    );
    expect(container.read(handwritingIndexerProvider), isNull);
    expect(container.read(recognitionDevOverlayLinesProvider).value, [
      '손글씨 색인 없음 (이 기기에서 인식 불가)',
    ]);
  });

  test('no indexer on the web even with an available engine', () {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final recognizer = FakeHandwritingRecognizer();
    final container = ProviderContainer.test(
      overrides: [
        core.noteStoreProvider.overrideWithValue(store),
        handwritingRecognizerProvider.overrideWithValue(recognizer),
      ],
    );
    expect(container.read(handwritingIndexerProvider), isNull);
    expect(recognizer.calls, isEmpty);
  });

  test('testing.dart works on dart2js', () async {
    final fake = FakeHandwritingRecognizer();
    final out = await fake.recognizeLine(
      const HandwritingLineInput([]),
      languageTag: 'ko',
    );
    expect(out.first.text, '줄 1');
    final strokes = SyntheticHandwriting.lines(pageId: 'p1', lineCount: 3);
    expect(strokes.first.id, 'syn_1_l00_0000');
    final path = SyntheticShapes.rectanglePath(
      const Rect.fromLTWH(0, 0, 96, 48),
    );
    expect(path, hasLength(97));
    expect(path.last, path.first);
    final lines = groupIntoLines([
      for (final s in strokes) HandwritingTrace.fromStroke(s),
    ]);
    expect(lines, hasLength(3)); // 6.5: the three written lines
  });

  testWidgets('the settings section on the web: the fixed sentence, the '
      'handwriting group disabled (even with an available engine)', (
    tester,
  ) async {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          core.noteStoreProvider.overrideWithValue(store),
          handwritingRecognizerProvider.overrideWithValue(
            FakeHandwritingRecognizer(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: RecognitionSettingsSection()),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(
      find.text('이 기기(웹)에서는 손글씨 인식을 쓸 수 없어요. 안드로이드 앱에서 쓸 수 있어요.'),
      findsOneWidget,
    );
    final autoIndex = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('recog.settings.autoIndex')),
    );
    expect(autoIndex.onChanged, isNull);
    expect(find.text('이 기기에서는 자동 인식을 쓸 수 없어요'), findsOneWidget);
    // (P-B) the two model rows: 쓸 수 없음, no button.
    expect(find.text('쓸 수 없음'), findsNWidgets(2));
    expect(find.text('받기'), findsNothing);
    final consent = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('recog.settings.consent')),
    );
    expect(consent.onChanged, isNotNull);
    // (L2-19) no A-4 lab on the web (6.20, Q9), even with an engine.
    expect(find.byKey(const ValueKey('recog.settings.lab')), findsNothing);
  });

  testWidgets('the conversion sheet on the web (recognitionOverrides): the '
      'fixed sentence, [닫기], no primary, no line card (L2-15)', (tester) async {
    final host = await RecognitionHost.pump(
      tester,
      overrides: recognitionOverrides(),
    );
    for (final id in ['recog.toText', 'recog.copyText']) {
      final run = recognitionSelectionActions()
          .singleWhere((a) => a.id == id)
          .run(
            host.body,
            TargetLog().target(
              strokes: [
                glyphStroke('s1', 110, 110, 40),
                glyphStroke('s2', 160, 110, 40),
              ],
            ),
          );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recog.sheet.toText')), findsOneWidget);
      expect(
        find.text('이 기기(웹)에서는 손글씨 인식을 쓸 수 없어요. 안드로이드 앱에서 쓸 수 있어요.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('recog.sheet.primary')), findsNothing);
      expect(find.byKey(const ValueKey('recog.sheet.line.0')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('recog.sheet.cancel')));
      await tester.pumpAndSettle();
      await run;
    }
  });

  testWidgets('no ML Kit channel call on the web: engine calls, the '
      'settings section and the conversion sheet (G-1)', (tester) async {
    final calls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_mlkitChannel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_mlkitChannel, null));
    final host = await RecognitionHost.pump(
      tester,
      overrides: recognitionOverrides(),
    );
    final container = ProviderScope.containerOf(host.body);
    final engine = container.read(handwritingRecognizerProvider);
    for (final tag in ['ko', 'en']) {
      expect(await engine.modelState(tag), RecognitionModelState.unsupported);
      await expectLater(
        engine.ensureModel(tag),
        throwsA(isA<RecognizerUnsupported>()),
      );
    }
    await expectLater(
      engine.recognizeLine(
        HandwritingLineInput([
          HandwritingTrace(
            xs: Float32List.fromList([1, 2]),
            ys: Float32List.fromList([1, 2]),
            ts: Float64List.fromList([1762400000000, 1762400000008]),
          ),
        ]),
        languageTag: 'ko',
      ),
      throwsA(isA<RecognizerUnsupported>()),
    );
    final run = recognitionSelectionActions()
        .singleWhere((a) => a.id == 'recog.toText')
        .run(
          host.body,
          TargetLog().target(strokes: [glyphStroke('s1', 110, 110, 40)]),
        );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('recog.sheet.cancel')));
    await tester.pumpAndSettle();
    await run;
    expect(calls, isEmpty);
  });

  test('CallableMathRecognizer + MockClient on dart2js: the request and the '
      'answer', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode({
          'result': {
            'latex': r'\frac{2}{5}',
            'confidence': 1,
            'alternatives': ['2/5'],
            'engine': 'fake',
            'engineVersion': '1',
            'ms': 3,
          },
        }),
        200,
      );
    });
    final engine = CallableMathRecognizer(
      endpoint: Uri.parse('http://127.0.0.1:5001/demo/recognizeMath'),
      client: client,
      consent: () async => true,
      idTokenProvider: () async => 'id-token',
    );
    final result = await engine.recognize(
      MathInput(
        traces: [
          HandwritingTrace(
            xs: Float32List.fromList([10, 11, 12]),
            ys: Float32List.fromList([20, 21, 22]),
            ts: Float64List.fromList([
              1730800000000,
              1730800000008,
              1730800000016,
            ]),
          ),
        ],
      ),
    );
    expect(result.latex, r'\frac{2}{5}');
    expect(result.engineId, 'fake/1');
    expect(result.alternatives, ['2/5']);
    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.headers['Authorization'], 'Bearer id-token');
    final data =
        (jsonDecode(request.body) as Map<String, Object?>)['data']!
            as Map<String, Object?>;
    expect(data['v'], 1);
    final strokes = data['strokes']! as Map<String, Object?>;
    expect(strokes['t'], [
      [0, 8, 16],
    ]); // ms from the first point (6.11.3)
  });

  testWidgets('direct copy (6.13.6): Clipboard.setData is sent in the same '
      'synchronous stretch as run (user activation, 7.2.10)', (tester) async {
    final host = await RecognitionHost.pump(
      tester,
      overrides: recognitionOverrides(),
    );
    final platform = PlatformLog(tester);
    final run = recognitionSelectionActions()
        .singleWhere((a) => a.id == 'recog.copyText')
        .run(
          host.body,
          TargetLog().target(
            objects: [
              core_testing.PageObjectFixtures.textBox(
                pageId: kPageId,
                text: '안녕 hello',
              ),
            ],
          ),
        );
    expect(platform.clipboardTexts, ['안녕 hello']); // before any await
    await settle(tester, run);
    await tester.pump();
    expect(host.snackBars, ['복사했어요.']);
  });

  testWidgets('the math pad preview lays out on the web without loading the '
      'KaTeX fonts', (tester) async {
    final host = await RecognitionHost.pump(
      tester,
      overrides: recognitionOverrides(),
    );
    final run = recognitionInsertActions().single.run(
      host.body,
      TargetLog().target(areaPt: const Rect.fromLTWH(100, 100, 600, 400)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recog.sheet.mathPad')), findsOneWidget);
    expect(find.byKey(const ValueKey('recog.pad.canvas')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('recog.pad.latex')),
      r'\frac{a}{b}',
    );
    await tester.pumpAndSettle();
    final preview = find.byKey(const ValueKey('recog.pad.preview'));
    expect(preview, findsOneWidget);
    expect(tester.widget<ink.MathPreview>(preview).latex, r'\frac{a}{b}');
    final size = tester.getSize(preview);
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('recog.sheet.cancel')));
    await tester.pumpAndSettle();
    await run;
  });

  defineHandwritingTraceTests();
  defineLineCaseTests();
  defineShapeCaseTests(); // (L2-06) the same V9 on dart2js
}
