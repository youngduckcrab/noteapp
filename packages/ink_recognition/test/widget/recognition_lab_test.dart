// The A-4 lab (m5-7/05-library 8.2 L2-19, 6.20, review S-10, S-14): the
// settings entry (only with a handwriting engine), the 30 sentences in turn,
// per [인식] ko and en with the points moved plus ko in page coordinates
// (strategy B without an engine call), [인식] disabled until both models are
// ready (and with no ink), the summary CER per group, the JSON without
// strokes, a failure ending one sentence.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/l10n/recognition_strings.dart';
import 'package:ink_recognition/src/lab/lab_sentences.dart';
import 'package:ink_recognition/src/lab/recognition_lab_sheet.dart';
import 'package:ink_recognition/src/ports/line_origin.dart';
import 'package:ink_recognition/src/ports/model_admin.dart';
import 'package:ink_recognition/src/ui/math_pad_canvas.dart';
import 'package:ink_recognition/src/ui/recognition_sheet.dart'
    show kSheetCancelKey;
import 'package:ink_recognition/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/recognition_test_scope.dart';

/// A test engine with both origins: records ('moved' | 'page', tag) and
/// answers [answer]; models from [modelStates] (missing → ready).
final class _LabEngine
    implements
        HandwritingRecognizer,
        RecognizerModelAdmin,
        PageOriginLineRecognizer {
  _LabEngine(this.answer);

  /// (tag, page coordinates?) → the top text; null → no candidates.
  String? Function(String tag, bool page) answer;
  final List<(String, String)> calls = [];
  final Map<String, RecognitionModelState> modelStates = {};
  RecognitionFailure? failOn; // thrown by the next en call
  final StreamController<String> _changes = StreamController.broadcast();

  void modelArrived(String tag) {
    modelStates[tag] = RecognitionModelState.ready;
    _changes.add(tag);
  }

  @override
  String get engineId => 'lab-test/1';
  @override
  bool get isAvailable => true;
  @override
  bool get enforcesWifiOnly => true;
  @override
  Stream<String> get modelChanges => _changes.stream;
  @override
  Future<void> deleteModel(String languageTag) async {}
  @override
  Future<RecognitionModelState> modelState(String languageTag) async =>
      modelStates[languageTag] ?? RecognitionModelState.ready;
  @override
  Future<void> ensureModel(String languageTag, {bool wifiOnly = true}) async =>
      modelArrived(languageTag);

  Future<List<TextCandidate>> _answer(String tag, bool page) async {
    calls.add((page ? 'page' : 'moved', tag));
    final failure = failOn;
    if (failure != null && tag == 'en') {
      failOn = null;
      throw failure;
    }
    final text = answer(tag, page);
    return [if (text != null) TextCandidate(text, languageTag: tag)];
  }

  @override
  Future<List<TextCandidate>> recognizeLine(
    HandwritingLineInput line, {
    required String languageTag,
  }) => _answer(languageTag, false);

  @override
  Future<List<TextCandidate>> recognizeLineInPageCoordinates(
    HandwritingLineInput line, {
    required String languageTag,
  }) => _answer(languageTag, true);

  @override
  Future<void> dispose() async => _changes.close();
}

Finder get _entry => find.byKey(const ValueKey('recog.settings.lab'));
Finder get _sheet => find.byKey(RecognitionLabKeys.sheet);
Finder get _canvas => find.byKey(kMathPadCanvasKey);
Finder get _recognize => find.byKey(RecognitionLabKeys.recognize);

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<ButtonStyleButton>(button).onPressed != null;

String _text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

Future<void> _pumpSettings(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = kIpadPortrait;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createFixedClockStore();
  addTearDown(store.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        core.noteStoreProvider.overrideWithValue(store),
        ...overrides,
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
}

Future<void> _openLab(WidgetTester tester, HandwritingRecognizer engine) async {
  await _pumpSettings(
    tester,
    overrides: [handwritingRecognizerProvider.overrideWithValue(engine)],
  );
  await tester.ensureVisible(_entry);
  await tester.tap(_entry);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(_sheet, findsOneWidget);
}

int _pointer = 300;
int _clockMs = 0;

/// One stylus stroke in the lab's area.
Future<void> _write(WidgetTester tester) async {
  final origin = tester.getTopLeft(_canvas) + const Offset(1, 1);
  final g = await tester.createGesture(
    pointer: _pointer++,
    kind: PointerDeviceKind.stylus,
  );
  await g.down(
    origin + const Offset(40, 60),
    timeStamp: Duration(milliseconds: _clockMs),
  );
  for (var i = 1; i <= 8; i++) {
    _clockMs += 8;
    await g.moveTo(
      origin + Offset(40 + 6.0 * i, i.isEven ? 70 : 60),
      timeStamp: Duration(milliseconds: _clockMs),
    );
  }
  _clockMs += 8;
  await g.up(timeStamp: Duration(milliseconds: _clockMs));
  await tester.pump();
}

Future<void> _tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

/// Every key of every map in [json] (recursively).
Set<String> _keysOf(Object? json) => switch (json) {
  final Map<String, Object?> m => {
    ...m.keys,
    for (final v in m.values) ..._keysOf(v),
  },
  final List<Object?> l => {for (final v in l) ..._keysOf(v)},
  _ => const {},
};

void main() {
  testWidgets('no handwriting engine → no lab entry (the group stays for '
      'the math fixture entry — L2-22)', (tester) async {
    await _pumpSettings(tester); // default engine: unsupported
    expect(_entry, findsNothing);
    expect(find.text(RecognitionStrings.labEntry), findsNothing);
    expect(find.text(RecognitionStrings.labGroup), findsOneWidget);
    expect(
      find.byKey(const ValueKey('recog.settings.mathFixture')),
      findsOneWidget,
    );
  });

  testWidgets('the settings entry with a handwriting engine opens the lab at '
      '≤ 90% of the screen height; 44×44 targets; [닫기] closes', (tester) async {
    await _openLab(tester, FakeHandwritingRecognizer());
    final screen = tester.view.physicalSize.height;
    expect(tester.getSize(_sheet).height, lessThanOrEqualTo(screen * 0.9));
    expect(_text(tester, RecognitionLabKeys.target), kLabSentences[0].text);
    expect(_text(tester, RecognitionLabKeys.progress), '1/30 · 한국어');
    expect(find.byKey(const ValueKey('recog.lab.model.ko')), findsOneWidget);
    expect(find.byKey(const ValueKey('recog.lab.model.en')), findsOneWidget);
    // Both models ready but no ink yet → [인식] disabled.
    expect(find.byKey(RecognitionLabKeys.modelsNeeded), findsNothing);
    expect(_enabled(tester, _recognize), isFalse);
    await _write(tester);
    expect(_enabled(tester, _recognize), isTrue);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await tester.tap(find.byKey(kSheetCancelKey));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_sheet, findsNothing);
  });

  testWidgets('(S-10) a model not ready → notice and [인식] disabled; when it '
      'arrives (modelChanges) → enabled', (tester) async {
    final engine = _LabEngine((tag, _) => 'x')
      ..modelStates['en'] = RecognitionModelState.notDownloaded;
    await _openLab(tester, engine);
    await _write(tester);
    expect(find.byKey(RecognitionLabKeys.modelsNeeded), findsOneWidget);
    expect(find.text(RecognitionStrings.labModelsNeeded), findsOneWidget);
    expect(_enabled(tester, _recognize), isFalse);
    engine.modelArrived('en');
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(find.byKey(RecognitionLabKeys.modelsNeeded), findsNothing);
    expect(_enabled(tester, _recognize), isTrue);
    expect(engine.calls, isEmpty);
  });

  testWidgets('30 sentences in turn: ko + en moved, ko in page coordinates '
      'per [인식] (B needs no call); [다음] clears the area; the summary CER '
      'per group; the JSON has no strokes', (tester) async {
    var index = 0;
    final engine = _LabEngine((tag, page) {
      final target = kLabSentences[index].text;
      if (tag == 'en') {
        return kLabSentences[index].group == LabGroup.korean ? null : target;
      }
      // ko moved: right; ko in page coordinates: the last character lost.
      return page ? target.substring(0, target.length - 1) : target;
    });
    final platform = PlatformLog(tester);
    await _openLab(tester, engine);
    for (index = 0; index < kLabSentences.length; index++) {
      expect(
        _text(tester, RecognitionLabKeys.target),
        kLabSentences[index].text,
      );
      expect(
        tester.widget<MathPadCanvas>(find.byType(MathPadCanvas)).ink.isEmpty,
        isTrue,
        reason: 'sentence ${index + 1} starts with an empty area',
      );
      final before = engine.calls.length;
      await _write(tester);
      await _tapAndSettle(tester, _recognize);
      expect(engine.calls.sublist(before), [
        ('moved', 'ko'),
        ('moved', 'en'),
        ('page', 'ko'),
      ], reason: 'sentence ${index + 1}');
      expect(
        _text(tester, RecognitionLabKeys.result(LabMode.ko)),
        startsWith('A (ko) 0.0% · '),
      );
      if (index < kLabSentences.length - 1) {
        await _tapAndSettle(tester, find.byKey(RecognitionLabKeys.next));
      }
    }
    expect(engine.calls, hasLength(90));
    expect(_enabled(tester, find.byKey(RecognitionLabKeys.next)), isFalse);

    // Summary: A 0% everywhere; en has nothing in the Korean group (100%)
    // and is right elsewhere; B takes the ko list for Hangul tops (6.8).
    final korean = _text(tester, RecognitionLabKeys.summary(LabGroup.korean));
    expect(korean, startsWith('한국어 · 10/10문장 · A (ko) 0.0% · en 100.0% · '));
    expect(korean, contains('B (ko+en) 0.0%'));
    final english = _text(tester, RecognitionLabKeys.summary(LabGroup.english));
    expect(english, contains('A (ko) 0.0% · en 0.0%'));
    expect(english, isNot(contains('A · 페이지 좌표 0.0%')));
    for (final mode in LabMode.values) {
      expect(find.byKey(RecognitionLabKeys.latency(mode)), findsOneWidget);
    }
    expect(
      _text(tester, RecognitionLabKeys.engineLine),
      startsWith('lab-test/1 · ko ready · en ready · '),
    );

    // [이전] shows the earlier sentence's result again.
    await _tapAndSettle(tester, find.byKey(RecognitionLabKeys.previous));
    expect(_text(tester, RecognitionLabKeys.target), kLabSentences[28].text);
    expect(
      _text(tester, RecognitionLabKeys.result(LabMode.en)),
      endsWith(kLabSentences[28].text),
    );

    // [결과 JSON 복사]: Clipboard.setData inside the press; no strokes.
    await tester.ensureVisible(find.byKey(RecognitionLabKeys.copyJson));
    await tester.tap(find.byKey(RecognitionLabKeys.copyJson));
    expect(platform.clipboardTexts, hasLength(1));
    await tester.pump();
    await tester.pump();
    expect(find.text(RecognitionStrings.labCopied), findsOneWidget);
    final json =
        jsonDecode(platform.clipboardTexts.single!) as Map<String, Object?>;
    expect(json['kind'], 'recognition-lab');
    expect(json['engineId'], 'lab-test/1');
    expect(json['models'], {'ko': 'ready', 'en': 'ready'});
    final sentences = json['sentences']! as List<Object?>;
    expect(sentences, hasLength(30));
    final first = sentences.first! as Map<String, Object?>;
    expect(first['target'], kLabSentences[0].text);
    expect(first['lines'], 1);
    expect((first['text']! as Map)['ko'], kLabSentences[0].text);
    expect((first['cer']! as Map)['en'], 1.0);
    expect((first['ms']! as Map).keys, ['ko', 'en', 'mixed', 'koPage']);
    final summary = json['summary']! as Map<String, Object?>;
    expect(((summary['korean']! as Map)['cer']! as Map)['ko'], 0.0);
    expect((summary['mixed']! as Map)['sentences'], 10);
    final keys = _keysOf(json);
    for (final banned in ['strokes', 'points', 'xs', 'ys', 'ts', 'ink']) {
      expect(keys, isNot(contains(banned)), reason: banned);
    }
  });

  testWidgets('an engine without page coordinates: both ko passes go through '
      'recognizeLine', (tester) async {
    final engine = FakeHandwritingRecognizer(answer: (_) => '오늘');
    await _openLab(tester, engine);
    await _write(tester);
    await _tapAndSettle(tester, _recognize);
    expect([for (final c in engine.calls) c.$2], ['ko', 'en', 'ko']);
    expect(
      _text(tester, RecognitionLabKeys.result(LabMode.koPage)),
      endsWith('· 오늘'),
    );
  });

  testWidgets('a RecognitionFailure ends that sentence with its text; the '
      'next [인식] works', (tester) async {
    final engine = _LabEngine((tag, _) => '오늘 회의록을 정리했다')
      ..failOn = ModelNotReady('en');
    await _openLab(tester, engine);
    await _write(tester);
    await _tapAndSettle(tester, _recognize);
    expect(find.text('ModelNotReady(en)'), findsOneWidget);
    expect(engine.calls, [('moved', 'ko'), ('moved', 'en')]);
    expect(
      _text(tester, RecognitionLabKeys.summary(LabGroup.korean)),
      startsWith('한국어 · 0/10문장 · A (ko) —'),
    );
    await _tapAndSettle(tester, _recognize);
    expect(find.text('ModelNotReady(en)'), findsNothing);
    expect(
      _text(tester, RecognitionLabKeys.result(LabMode.ko)),
      startsWith('A (ko) 0.0%'),
    );
  });

  testWidgets('undo and clear empty the area; [인식] follows the ink', (
    tester,
  ) async {
    await _openLab(tester, FakeHandwritingRecognizer());
    await _write(tester);
    await _write(tester);
    final ink = tester.widget<MathPadCanvas>(find.byType(MathPadCanvas)).ink;
    expect(ink.strokes, hasLength(2));
    await _tapAndSettle(tester, find.byKey(RecognitionLabKeys.undo));
    expect(ink.strokes, hasLength(1));
    await _tapAndSettle(tester, find.byKey(RecognitionLabKeys.clear));
    expect(ink.isEmpty, isTrue);
    expect(_enabled(tester, _recognize), isFalse);
  });
}
