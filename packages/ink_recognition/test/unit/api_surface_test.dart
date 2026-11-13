// Public surface of package:ink_recognition (contract m5-7/00-overview
// 7.2.11 and 7.6 '기반 단계 시험 도우미'; m5-7/05-library 4.2 export list,
// 4.3, 8.1 B6-b).
//
// Imports only the two entry points (plus the CORE / INK types they use) and
// uses every exported name in the call shapes of the contract block — a
// renamed, re-typed or missing name breaks the build. The test also checks the
// R2-B6 behaviour the contract row 7.6.2 fixes (defaults, placeholder
// section) — (L2-07) recognitionOverrides() now gives its 3 overrides with
// GeometricShapeFitter; (L2-10a) the indexer runs; (L2-12) the action lists
// hold the 4.4.4 actions. Names
// beyond the list are INFRA's R14. VM only: it reads the entry point files.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

/// The 4.2 export list (05-library) = the names of the contract block.
const List<String> kExportedNames = [
  'HandwritingTrace',
  'HandwritingLineInput',
  'TextCandidate',
  'RecognitionModelState',
  'RecognitionFailure',
  'RecognizerUnsupported',
  'ModelNotReady',
  'RecognizerOffline',
  'RecognizerQuotaExceeded',
  'RecognizerCancelled',
  'RecognizerConsentRequired',
  'RecognizerEngineError',
  'MathInput',
  'MathResult',
  'HandwritingRecognizer',
  'UnsupportedHandwritingRecognizer',
  'MathRecognizer',
  'ManualOnlyMathRecognizer',
  'groupIntoLines',
  // (math pen, phase 1)
  'RecognitionMathPen',
  'RecognitionMathPenContext',
  'RecognitionMathPenSession',
  'recognitionMathPen',
  'GeometricShapeFitter',
  'ShapeFitTuning',
  'handwritingRecognizerProvider',
  'mathRecognizerProvider',
  'RecognitionConfig',
  'recognitionOverrides',
  'handwritingIndexerProvider',
  'recognitionDevOverlayLinesProvider',
  'RecognitionTarget',
  'RecognitionAction',
  'recognitionSelectionActions',
  'recognitionInsertActions',
  'HandwritingIndexer',
  'HandwritingIndexerStatus',
  'HandwritingIndexerPhase',
  // (handwriting search — the library's search hint)
  'HandwritingSearchPhase',
  'HandwritingSearchStatus',
  'HandwritingSearchReadiness',
  'handwritingSearchReadinessProvider',
  'RecognitionSettingsSection',
];

/// The testing.dart names (contract 7.6, 05-library 4.3).
const List<String> kTestingNames = [
  'FakeHandwritingRecognizer',
  'FakeMathRecognizer',
  'SyntheticHandwriting',
  'SyntheticShapes',
];

/// Names in the `show` clauses of the export directives of [path] (the test
/// runs in the package directory).
List<String> _shownNames(String path) {
  final source = File(path).readAsStringSync();
  final names = <String>[];
  for (final m in RegExp(
    r'^export [^;]*?\bshow\b([^;]*);',
    multiLine: true,
  ).allMatches(source)) {
    names.addAll(
      m.group(1)!.split(',').map((n) => n.trim()).where((n) => n.isNotEmpty),
    );
  }
  return names;
}

/// A HandwritingRecognizer implemented outside the package (the port is an
/// interface — INFRA / tests can implement it).
final class _OutsideRecognizer implements HandwritingRecognizer {
  @override
  String get engineId => 'outside';
  @override
  bool get isAvailable => true;
  @override
  Future<RecognitionModelState> modelState(String languageTag) async =>
      RecognitionModelState.ready;
  @override
  Future<void> ensureModel(String languageTag, {bool wifiOnly = true}) async {}
  @override
  Future<List<TextCandidate>> recognizeLine(
    HandwritingLineInput line, {
    required String languageTag,
  }) async => [TextCandidate('a', languageTag: languageTag)];
  @override
  Future<void> dispose() async {}
}

final class _OutsideMathRecognizer implements MathRecognizer {
  @override
  String get engineId => 'outside';
  @override
  bool get isAvailable => true;
  @override
  Future<MathResult> recognize(MathInput input, {Future<void>? cancel}) async =>
      const MathResult(latex: 'x', engineId: 'outside', latency: Duration.zero);
}

String _failureName(RecognitionFailure f) => switch (f) {
  RecognizerUnsupported() => 'unsupported',
  ModelNotReady(:final languageTag) => 'model $languageTag',
  RecognizerOffline() => 'offline',
  RecognizerQuotaExceeded() => 'quota',
  RecognizerCancelled() => 'cancelled',
  RecognizerConsentRequired() => 'consent',
  RecognizerEngineError(:final code) => 'engine $code',
};

void main() {
  test('the export list has the 35 contract names + 4 math pen names + 4 '
      'search hint names, no duplicates', () {
    expect(kExportedNames, hasLength(43)); // 35 + 4 (math pen) + 4 (search)
    expect(kExportedNames.toSet(), hasLength(kExportedNames.length));
  });

  test('the entry points export exactly these names (show clauses)', () {
    expect(
      _shownNames('lib/ink_recognition.dart'),
      unorderedEquals(kExportedNames),
    );
    expect(_shownNames('lib/testing.dart'), unorderedEquals(kTestingNames));
    // Every export of the two entry points has a show clause.
    for (final path in ['lib/ink_recognition.dart', 'lib/testing.dart']) {
      final exports = RegExp(
        r'^export ',
        multiLine: true,
      ).allMatches(File(path).readAsStringSync()).length;
      final shows = RegExp(
        r'^export [^;]*\bshow\b',
        multiLine: true,
      ).allMatches(File(path).readAsStringSync()).length;
      expect(shows, exports, reason: path);
    }
  });

  group('inputs / outputs', () {
    test('HandwritingTrace and HandwritingLineInput constructors', () {
      final trace = HandwritingTrace(
        xs: Float32List.fromList([1, 2]),
        ys: Float32List.fromList([3, 4]),
        ts: Float64List.fromList([1730790000000, 1730790000008]),
        strokeId: 's1',
      );
      final Float32List xs = trace.xs;
      final Float32List ys = trace.ys;
      final Float64List ts = trace.ts;
      final String? id = trace.strokeId;
      expect((xs.length, ys.length, ts.length, id), (2, 2, 2, 's1'));
      expect(
        HandwritingTrace(
          xs: Float32List(0),
          ys: Float32List(0),
          ts: Float64List(0),
        ).strokeId,
        isNull,
      );

      final line = HandwritingLineInput([trace]);
      final List<HandwritingTrace> traces = line.traces;
      final String pre = line.preContext;
      final Size? area = line.writingAreaPt;
      expect((traces.single, pre, area), (trace, '', null));
      const withArea = HandwritingLineInput(
        [],
        preContext: '앞 글',
        writingAreaPt: Size(595, 24),
      );
      expect(withArea.preContext, '앞 글');
      expect(withArea.writingAreaPt, const Size(595, 24));
    });

    test('HandwritingTrace.fromStroke is a factory taking a core.Stroke', () {
      final stroke = core.Stroke(
        id: 'st1',
        pageId: 'p1',
        style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
        points: core.StrokePoints.fromList(const [core.StrokePoint(1, 2)]),
        createdAt: 1730790000000,
      );
      final HandwritingTrace trace = HandwritingTrace.fromStroke(stroke);
      expect(trace.strokeId, 'st1');
    });

    test('TextCandidate, RecognitionModelState', () {
      const c = TextCandidate('안녕', languageTag: 'ko');
      final String text = c.text;
      final double? score = c.score;
      final String tag = c.languageTag;
      expect((text, score, tag), ('안녕', null, 'ko'));
      expect(
        const TextCandidate('a', score: 0.5, languageTag: 'en').score,
        0.5,
      );
      expect(RecognitionModelState.values, [
        RecognitionModelState.notDownloaded,
        RecognitionModelState.downloading,
        RecognitionModelState.ready,
        RecognitionModelState.unsupported,
      ]);
    });

    test('RecognitionFailure is sealed over the 7 contract kinds', () {
      final failures = <RecognitionFailure>[
        RecognizerUnsupported(),
        ModelNotReady('ko'),
        RecognizerOffline(),
        RecognizerQuotaExceeded(),
        RecognizerCancelled(),
        RecognizerConsentRequired(),
        RecognizerEngineError('internal', 'boom'),
      ];
      expect(failures.map(_failureName), [
        'unsupported',
        'model ko',
        'offline',
        'quota',
        'cancelled',
        'consent',
        'engine internal',
      ]);
      for (final f in failures) {
        expect(f, isA<Exception>());
      }
      final e = RecognizerEngineError('c', 'm');
      final String code = e.code;
      final String message = e.message;
      expect((code, message), ('c', 'm'));
      final String tag = ModelNotReady('en').languageTag;
      expect(tag, 'en');
    });

    test('MathInput, MathResult', () {
      const input = MathInput(traces: []);
      final List<HandwritingTrace> traces = input.traces;
      final Uint8List? png = input.png;
      final double? pxPerPt = input.pngPxPerPt;
      expect(traces, isEmpty);
      expect((png, pxPerPt), (null, null));
      final withPng = MathInput(
        traces: const [],
        png: Uint8List.fromList([1, 2]),
        pngPxPerPt: 2,
      );
      expect(withPng.png, [1, 2]);
      expect(withPng.pngPxPerPt, 2);

      const result = MathResult(
        latex: r'x^2',
        engineId: 'fake/1',
        latency: Duration(milliseconds: 3),
      );
      final String latex = result.latex;
      final double? confidence = result.confidence;
      final List<String> alternatives = result.alternatives;
      final String engineId = result.engineId;
      final Duration latency = result.latency;
      expect(alternatives, isEmpty);
      expect(
        (latex, confidence, engineId, latency),
        (r'x^2', null, 'fake/1', const Duration(milliseconds: 3)),
      );
      const full = MathResult(
        latex: 'a',
        confidence: 1,
        alternatives: ['A'],
        engineId: 'e',
        latency: Duration.zero,
      );
      expect(full.confidence, 1);
      expect(full.alternatives, ['A']);
    });
  });

  group('engine ports and defaults', () {
    test('HandwritingRecognizer members (an outside implementation)', () async {
      final HandwritingRecognizer r = _OutsideRecognizer();
      final String id = r.engineId;
      final bool available = r.isAvailable;
      expect((id, available), ('outside', true));
      final RecognitionModelState state = await r.modelState('ko');
      expect(state, RecognitionModelState.ready);
      await r.ensureModel('ko');
      await r.ensureModel('ko', wifiOnly: false);
      final List<TextCandidate> candidates = await r.recognizeLine(
        const HandwritingLineInput([]),
        languageTag: 'ko',
      );
      expect(candidates.single.text, 'a');
      await r.dispose();
    });

    test('MathRecognizer members (an outside implementation)', () async {
      final MathRecognizer m = _OutsideMathRecognizer();
      expect((m.engineId, m.isAvailable), ('outside', true));
      final MathResult result = await m.recognize(
        const MathInput(traces: []),
        cancel: Future<void>.value(),
      );
      expect(result.latex, 'x');
    });

    test('UnsupportedHandwritingRecognizer (05-library 4.4.2)', () async {
      const HandwritingRecognizer r = UnsupportedHandwritingRecognizer();
      expect(r.engineId, 'unsupported');
      expect(r.isAvailable, isFalse);
      for (final tag in ['ko', 'en', 'xx']) {
        expect(await r.modelState(tag), RecognitionModelState.unsupported);
      }
      await expectLater(
        r.ensureModel('ko'),
        throwsA(isA<RecognizerUnsupported>()),
      );
      await expectLater(
        r.ensureModel('ko', wifiOnly: false),
        throwsA(isA<RecognizerUnsupported>()),
      );
      await expectLater(
        r.recognizeLine(const HandwritingLineInput([]), languageTag: 'ko'),
        throwsA(isA<RecognizerUnsupported>()),
      );
      await r.dispose(); // completes
      await r.dispose();
    });

    test('ManualOnlyMathRecognizer (05-library 4.4.2)', () async {
      const MathRecognizer m = ManualOnlyMathRecognizer();
      expect(m.engineId, 'manual');
      expect(m.isAvailable, isFalse);
      await expectLater(
        m.recognize(const MathInput(traces: [])),
        throwsA(isA<RecognizerUnsupported>()),
      );
    });
  });

  group('lines and shapes', () {
    test('groupIntoLines signature', () {
      const List<List<HandwritingTrace>> Function(
        List<HandwritingTrace> traces, {
        double gapFactor,
      })
      fn = groupIntoLines;
      expect(fn(const []), isEmpty);
      expect(groupIntoLines(const [], gapFactor: 1.5), isEmpty);
    });

    test('GeometricShapeFitter implements ink.InkShapeFitter', () {
      const fitter = GeometricShapeFitter();
      const ink.InkShapeFitter port = fitter;
      final ShapeFitTuning tuning = fitter.tuning;
      expect(tuning, const ShapeFitTuning());
      const tuned = GeometricShapeFitter(
        tuning: ShapeFitTuning(minDiagonalLogicalPx: 30),
      );
      expect(tuned.tuning.minDiagonalLogicalPx, 30);
      // (L2-06) The classifier is in: a closed square → a rectangle.
      final ink.InkShapeFit? fit = port.fit(const [
        Offset.zero,
        Offset(100, 0),
        Offset(100, 100),
        Offset(0, 100),
        Offset.zero,
      ], viewScale: 1);
      expect(fit?.kind, core.ShapeKind.rectangle);
      expect(fit!.score, inInclusiveRange(0, 1));
    });

    test('ShapeFitTuning defaults (05-library 4.4.5), ==, copyWith', () {
      const t = ShapeFitTuning();
      final int resample = t.resampleCount;
      final int smooth = t.smoothRadius;
      final double minDiag = t.minDiagonalLogicalPx;
      expect((resample, smooth, minDiag), (64, 2, 24));
      final doubles = <double>[
        t.lineMinStraightness,
        t.lineMaxDeviation,
        t.closedMaxGap,
        t.minTurnDeg,
        t.maxTurnDeg,
        t.ellipseMaxError,
        t.circleMinAxisRatio,
        t.rdpEpsilon,
        t.cornerMinTurnDeg,
        t.minEdgeFraction,
        t.rightAngleToleranceDeg,
        t.polygonMaxError,
        t.ellipseOverPolygonFactor,
        t.weakCornerTriangleDeg,
        t.weakCornerQuadDeg,
        t.weakCornerErrorFactor,
        t.axisSnapDeg,
        t.minScore,
      ];
      expect(doubles, [
        0.85,
        0.065,
        0.2,
        270,
        540,
        0.075,
        0.82,
        0.055,
        28,
        0.08,
        16,
        0.03,
        0.35,
        55,
        45,
        1.6,
        8,
        0.0,
      ]);
      expect(t, const ShapeFitTuning());
      expect(t.hashCode, const ShapeFitTuning().hashCode);
      final changed = t.copyWith(axisSnapDeg: 10, resampleCount: 32);
      expect(changed.axisSnapDeg, 10);
      expect(changed.resampleCount, 32);
      expect(changed.minScore, t.minScore);
      expect(changed, isNot(t));
      expect(t.copyWith(), t);
    });
  });

  group('providers', () {
    test('provider types, names and defaults', () {
      final container = ProviderContainer.test();
      final HandwritingRecognizer hw = container.read(
        handwritingRecognizerProvider,
      );
      final MathRecognizer math = container.read(mathRecognizerProvider);
      final HandwritingIndexer? indexer = container.read(
        handwritingIndexerProvider,
      );
      final ValueListenable<List<String>> lines = container.read(
        recognitionDevOverlayLinesProvider,
      );
      expect(hw, isA<UnsupportedHandwritingRecognizer>());
      expect(math, isA<ManualOnlyMathRecognizer>());
      expect(indexer, isNull);
      expect(lines.value, ['손글씨 색인 없음 (이 기기에서 인식 불가)']);
      expect(
        handwritingRecognizerProvider.name,
        'handwritingRecognizerProvider',
      );
      expect(mathRecognizerProvider.name, 'mathRecognizerProvider');
      expect(handwritingIndexerProvider.name, 'handwritingIndexerProvider');
      expect(
        recognitionDevOverlayLinesProvider.name,
        'recognitionDevOverlayLinesProvider',
      );
    });

    test('RecognitionConfig', () {
      const config = RecognitionConfig();
      final Uri? endpoint = config.mathEndpoint;
      final Future<String?> Function()? tokens = config.idTokenProvider;
      expect((endpoint, tokens), (null, null));
      Future<String?> token() async => 'id-token';
      final full = RecognitionConfig(
        mathEndpoint: Uri.parse('http://127.0.0.1:5001/demo/recognizeMath'),
        idTokenProvider: token,
      );
      expect(full.mathEndpoint!.path, '/demo/recognizeMath');
      expect(full.idTokenProvider, same(token));
    });

    test('recognitionOverrides() — (L2-07) exactly 3 overrides with or '
        'without config; the defaults stay the provider values (4.4.8)', () {
      final List<Override> overrides = recognitionOverrides();
      final List<Override> withConfig = recognitionOverrides(
        config: RecognitionConfig(mathEndpoint: Uri.parse('http://x/y')),
      );
      expect(overrides, hasLength(3));
      expect(withConfig, hasLength(3));
      final container = ProviderContainer.test(overrides: overrides);
      expect(
        container.read(ink.inkShapeFitterProvider),
        isA<GeometricShapeFitter>(),
      );
      // (L2-08) the VM is Android in tests → the ML Kit adapter (6.7.1);
      // nothing reaches the plugin before a call (3.4).
      final engine = container.read(handwritingRecognizerProvider);
      expect(engine.engineId, 'mlkit-digital-ink/19.0.0');
      expect(engine.isAvailable, isTrue);
      expect(
        container.read(mathRecognizerProvider),
        isA<ManualOnlyMathRecognizer>(),
      );
    });
  });

  group('editor actions', () {
    test('RecognitionTarget and RecognitionAction constructors', () async {
      final executed = <core.EditCommand>[];
      var done = 0;
      final target = RecognitionTarget(
        noteId: 'n1',
        pageId: 'p1',
        pageSize: core.PageSize.a4Portrait,
        areaPt: const Rect.fromLTWH(0, 0, 100, 50),
        execute: executed.add,
        done: () => done++,
      );
      final String noteId = target.noteId;
      final String pageId = target.pageId;
      final core.PageSize size = target.pageSize;
      final List<core.Stroke> strokes = target.strokes;
      final List<core.PageObject> objects = target.objects;
      final Rect area = target.areaPt;
      expect(strokes, isEmpty);
      expect(objects, isEmpty);
      expect(
        (noteId, pageId, size, area),
        (
          'n1',
          'p1',
          core.PageSize.a4Portrait,
          const Rect.fromLTWH(0, 0, 100, 50),
        ),
      );
      final void Function(core.EditCommand) execute = target.execute;
      final VoidCallback onDone = target.done;
      execute(const core.ClearPage(pageId: 'p1'));
      onDone();
      expect(executed.single, isA<core.ClearPage>());
      expect(done, 1);

      final withElements = RecognitionTarget(
        noteId: 'n1',
        pageId: 'p1',
        pageSize: core.PageSize.a4Portrait,
        strokes: [_stroke('s1', 'p1')],
        objects: [core_testing.PageObjectFixtures.math(pageId: 'p1')],
        areaPt: Rect.zero,
        execute: (_) {},
        done: () {},
      );
      expect(withElements.strokes, hasLength(1));
      expect(withElements.objects.single, isA<core.MathObject>());

      var runs = 0;
      final action = RecognitionAction(
        id: 'test.action',
        label: '시험',
        icon: Icons.functions,
        run: (context, t) async => runs++,
        isVisible: (t) => t.strokes.isNotEmpty,
      );
      final String id = action.id;
      final String label = action.label;
      final IconData icon = action.icon;
      final Future<void> Function(BuildContext, RecognitionTarget) run =
          action.run;
      final bool Function(RecognitionTarget)? isVisible = action.isVisible;
      expect((id, label, icon), ('test.action', '시험', Icons.functions));
      expect(isVisible!(target), isFalse);
      expect(isVisible(withElements), isTrue);
      expect(run, isNotNull);
      expect(runs, 0);
      const bare = RecognitionAction(
        id: 'a',
        label: 'b',
        icon: Icons.short_text,
        run: _noRun,
      );
      expect(bare.isVisible, isNull);
    });

    test('(L2-12) the action lists — 4.4.4 ids in order '
        '(unit/recognition_actions_test has the rest)', () {
      final List<RecognitionAction> selection = recognitionSelectionActions();
      final List<RecognitionAction> insert = recognitionInsertActions();
      expect(
        [for (final a in selection) a.id],
        ['recog.toText', 'recog.copyText', 'recog.toMath', 'recog.editMath'],
      );
      expect([for (final a in insert) a.id], ['recog.mathPad']);
    });
  });

  group('background indexing', () {
    test('HandwritingIndexer(store:, recognizer:, enabled:, foreground:) — '
        '(L2-10a) start() runs it, dispose() is idempotent', () async {
      final store = core_testing.createFakeNoteStore();
      addTearDown(store.close);
      final enabled = ValueNotifier<bool>(true);
      final foreground = ValueNotifier<bool>(true);
      addTearDown(enabled.dispose);
      addTearDown(foreground.dispose);
      final recognizer = FakeHandwritingRecognizer();

      final indexer = HandwritingIndexer(
        store: store,
        recognizer: recognizer,
        enabled: enabled,
        foreground: foreground,
      );
      final withoutForeground = HandwritingIndexer(
        store: store,
        recognizer: recognizer,
        enabled: enabled,
      );
      final ValueListenable<HandwritingIndexerStatus> status = indexer.status;
      expect(status.value, const HandwritingIndexerStatus());
      expect(status.value.phase, HandwritingIndexerPhase.off);

      indexer
        ..start()
        ..start();
      await pumpEventQueue();
      // recog.language 'ko' read, the fake model ready, nothing queued.
      expect(indexer.status.value.phase, HandwritingIndexerPhase.idle);
      expect(indexer.status.value.languageTag, 'ko');
      expect(recognizer.calls, isEmpty);

      final Future<void> first = indexer.dispose();
      await first;
      await indexer.dispose();
      indexer.start(); // after dispose: still nothing
      expect(indexer.status.value.phase, HandwritingIndexerPhase.off);
      await withoutForeground.dispose(); // never started: nothing to close
      expect(recognizer.disposed, isFalse); // the indexer never closes it
    });

    test('HandwritingIndexerPhase values, HandwritingIndexerStatus fields', () {
      expect(HandwritingIndexerPhase.values, [
        HandwritingIndexerPhase.off,
        HandwritingIndexerPhase.disabled,
        HandwritingIndexerPhase.waitingModel,
        HandwritingIndexerPhase.idle,
        HandwritingIndexerPhase.waitingInput,
        HandwritingIndexerPhase.recognizing,
        HandwritingIndexerPhase.paused,
      ]);
      const status = HandwritingIndexerStatus(
        phase: HandwritingIndexerPhase.recognizing,
        languageTag: 'ko',
        queuedPages: 3,
        indexedPages: 12,
        failedPages: 1,
        currentPageId: 'p9',
        lastError: 'model ko: not downloaded',
      );
      final HandwritingIndexerPhase phase = status.phase;
      final String? lang = status.languageTag;
      final int queued = status.queuedPages;
      final int indexed = status.indexedPages;
      final int failed = status.failedPages;
      final String? page = status.currentPageId;
      final String? error = status.lastError;
      expect(
        (phase, lang, queued, indexed, failed, page, error),
        (
          HandwritingIndexerPhase.recognizing,
          'ko',
          3,
          12,
          1,
          'p9',
          'model ko: not downloaded',
        ),
      );
      const defaults = HandwritingIndexerStatus();
      expect(
        (
          defaults.phase,
          defaults.languageTag,
          defaults.queuedPages,
          defaults.indexedPages,
          defaults.failedPages,
          defaults.currentPageId,
          defaults.lastError,
        ),
        (HandwritingIndexerPhase.off, null, 0, 0, 0, null, null),
      );
      expect(
        status,
        const HandwritingIndexerStatus(
          phase: HandwritingIndexerPhase.recognizing,
          languageTag: 'ko',
          queuedPages: 3,
          indexedPages: 12,
          failedPages: 1,
          currentPageId: 'p9',
          lastError: 'model ko: not downloaded',
        ),
      );
      expect(status, isNot(defaults));
    });

    test('HandwritingIndexerStatus.toString is the one-line overlay form '
        '(05-library 4.4.1, 6.19)', () {
      expect(const HandwritingIndexerStatus().toString(), 'off');
      expect(
        const HandwritingIndexerStatus(
          phase: HandwritingIndexerPhase.disabled,
          languageTag: 'ko',
        ).toString(),
        'disabled · ko',
      );
      expect(
        const HandwritingIndexerStatus(
          phase: HandwritingIndexerPhase.waitingModel,
          languageTag: 'ko',
        ).toString(),
        'waitingModel · ko',
      );
      expect(
        const HandwritingIndexerStatus(
          phase: HandwritingIndexerPhase.waitingModel,
          languageTag: 'ko',
          lastError: 'model ko: waiting for Wi-Fi',
        ).toString(),
        'waitingModel · ko · model ko: waiting for Wi-Fi',
      );
      expect(
        const HandwritingIndexerStatus(
          phase: HandwritingIndexerPhase.recognizing,
          languageTag: 'ko',
          queuedPages: 3,
          indexedPages: 12,
        ).toString(),
        'recognizing · ko · queue 3 · done 12 · failed 0',
      );
      expect(
        const HandwritingIndexerStatus(
          phase: HandwritingIndexerPhase.recognizing,
          languageTag: 'ko',
          queuedPages: 2,
          currentPageId: 'p1',
        ).toString(),
        'recognizing · ko · page p1 · queue 2 · done 0 · failed 0',
      );
      expect(
        const HandwritingIndexerStatus(
          phase: HandwritingIndexerPhase.idle,
          languageTag: 'ko',
          indexedPages: 4,
        ).toString(),
        'idle · ko · queue 0 · done 4 · failed 0',
      );
    });
  });

  testWidgets('RecognitionSettingsSection is a const ConsumerWidget '
      '(a Column body — rows: widget/settings_section_test.dart)', (
    tester,
  ) async {
    const section = RecognitionSettingsSection(key: ValueKey('recog'));
    expect(section, isA<ConsumerWidget>());
    expect(const RecognitionSettingsSection().key, isNull);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: section)),
        ),
      ),
    );
    final found = find.byKey(const ValueKey('recog'));
    expect(found, findsOneWidget);
    final column = tester.widget<Column>(
      find.descendant(of: found, matching: find.byType(Column)).first,
    );
    expect(column.mainAxisSize, MainAxisSize.min);
    expect(
      find.descendant(of: found, matching: find.byType(Scaffold)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  test('testing.dart names (contract 7.6) are importable', () {
    final hw = FakeHandwritingRecognizer();
    final math = FakeMathRecognizer();
    const HandwritingRecognizer Function() hwType =
        FakeHandwritingRecognizer.new;
    expect(hwType, isNotNull);
    expect(hw, isA<HandwritingRecognizer>());
    expect(math, isA<MathRecognizer>());
    final List<core.Stroke> strokes = SyntheticHandwriting.lines(pageId: 'p1');
    expect(strokes, isNotEmpty);
    final List<Offset> path = SyntheticShapes.rectanglePath(
      const Rect.fromLTWH(100, 100, 200, 100),
    );
    expect(path, isNotEmpty);
  });
}

Future<void> _noRun(BuildContext context, RecognitionTarget target) async {}

core.Stroke _stroke(String id, String pageId) => core.Stroke(
  id: id,
  pageId: pageId,
  style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
  points: core.StrokePoints.fromList(const [
    core.StrokePoint(10, 10),
    core.StrokePoint(20, 20, t: 8),
  ]),
  createdAt: 1730790000000,
);
