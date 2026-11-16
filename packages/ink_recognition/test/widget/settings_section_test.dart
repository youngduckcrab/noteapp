// RecognitionSettingsSection (m5-7/05-library 8.2 L2-18, 6.18, 6.19;
// contract 7.2.11 — a const ConsumerWidget; 1차 7.4.11 section rules):
// a body only (a Column — no Scaffold, no title, no scroll) at the parent's
// width; every recog.* key is stored at once; a value from another device
// shows; without an available engine the fixed sentence and a disabled
// handwriting group (the web sentence: web/recognition_browser_test.dart);
// the 6.19 status line follows the indexer; the math engine row; iPad's
// 'asks first' note; inputs disabled while the settings load; tap targets.
// (P-B) The '인식 모델' rows: the states (준비됨 · 받지 않음 · 받는 중 ·
// 와이파이 대기 · 쓸 수 없음 · 받지 못했어요), [지우기] → deleteModel, Android
// [받기] → ensureModel(wifiOnly: recog.modelWifiOnly) and after 5 s the
// two-press [지금 셀룰러로 받기] → wifiOnly: false, iPad's two-press [받기],
// a failed download reported once, and '자동 인식' turned on with the model
// missing → Android ensureModel once / iPad [받기] emphasised.
// (L2-22, P-C) '품질 실험' [수식 고정 자료 만들기] with or without an engine
// (the web: browser test) → the math pad's fixture mode.
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/l10n/recognition_strings.dart';
import 'package:ink_recognition/src/settings/recognition_settings_keys.dart';
import 'package:ink_recognition/src/settings/recognition_settings_section.dart'
    show RecognitionSettingsUiKeys, indexerStatusText;
import 'package:ink_recognition/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/model_engine.dart';
import '../support/recognition_test_scope.dart';

/// The section as INFRA mounts it: Scaffold → scroll → at most 720 wide.
/// [autoIndex] is stored first (default false: these cases start from '자동
/// 인식' off, as a user who turned it off; null leaves it unset — the
/// default, on).
Future<core.NoteStore> _pump(
  WidgetTester tester, {
  List<Override> overrides = const [],
  Size size = kIpadPortrait,
  bool? autoIndex = false,
  bool developerMode = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createFixedClockStore();
  addTearDown(store.close);
  if (autoIndex != null) {
    await store.settings.set(RecognitionSettingsKeys.autoIndex, autoIndex);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        core.noteStoreProvider.overrideWithValue(store),
        // (v2.14-ui) 품질 실험 shows only in developer mode.
        core.developerModeProvider.overrideWithValue(developerMode),
        ...overrides,
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(width: 720, child: RecognitionSettingsSection()),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return store;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

Override _engine(HandwritingRecognizer recognizer) =>
    handwritingRecognizerProvider.overrideWithValue(recognizer);

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(RecognitionSettingsSection)),
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _settle(tester);
}

bool _switchOn(WidgetTester tester, ValueKey<String> key) =>
    tester.widget<SwitchListTile>(find.byKey(key)).value;

bool _switchEnabled(WidgetTester tester, ValueKey<String> key) =>
    tester.widget<SwitchListTile>(find.byKey(key)).onChanged != null;

String? _language(WidgetTester tester) => tester
    .widget<RadioGroup<String>>(
      find.descendant(
        of: find.byKey(RecognitionSettingsUiKeys.language),
        matching: find.byType(RadioGroup<String>),
      ),
    )
    .groupValue;

String _status(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(RecognitionSettingsUiKeys.status)).data!;

Finder _row(String tag) => find.byKey(RecognitionSettingsUiKeys.model(tag));

Finder _inRow(String tag, String text) =>
    find.descendant(of: _row(tag), matching: find.text(text));

/// The row shows [status] and exactly the buttons [buttons].
void _expectRow(String tag, String status, List<String> buttons) {
  expect(_inRow(tag, status), findsOneWidget, reason: '$tag: $status');
  final shown = [
    for (final e
        in find
            .descendant(
              of: _row(tag),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            )
            .evaluate())
      ((e.widget as ButtonStyleButton).child! as Text).data,
  ];
  expect(shown, buttons, reason: '$tag buttons');
}

/// Captures FlutterError reports inside [body] (restored before the test
/// ends — testWidgets checks FlutterError.onError).
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

void main() {
  group('indexerStatusText (6.19)', () {
    test('every phase', () {
      const s = HandwritingIndexerStatus.new;
      expect(indexerStatusText(null), '이 기기에서는 자동 인식을 쓸 수 없어요');
      expect(indexerStatusText(s()), '이 기기에서는 자동 인식을 쓸 수 없어요');
      expect(
        indexerStatusText(
          s(phase: HandwritingIndexerPhase.disabled, languageTag: 'ko'),
        ),
        '상태: 꺼져 있어요',
      );
      expect(
        indexerStatusText(
          s(
            phase: HandwritingIndexerPhase.waitingModel,
            languageTag: 'ko',
            lastError: 'model ko: not downloaded',
          ),
        ),
        '상태: 인식 모델을 기다리는 중이에요',
      );
      expect(
        indexerStatusText(
          s(
            phase: HandwritingIndexerPhase.waitingModel,
            languageTag: 'ko',
            lastError: 'model ko: waiting for Wi-Fi',
          ),
        ),
        '상태: 인식 모델을 기다리는 중이에요 · 와이파이 대기',
      );
      expect(
        indexerStatusText(
          s(
            phase: HandwritingIndexerPhase.idle,
            queuedPages: 0,
            indexedPages: 12,
          ),
        ),
        '상태: 대기 중 · 인식한 페이지 12',
      );
      expect(
        indexerStatusText(
          s(
            phase: HandwritingIndexerPhase.waitingInput,
            queuedPages: 3,
            indexedPages: 12,
          ),
        ),
        '상태: 필기가 멈추길 기다리는 중 · 남은 페이지 3',
      );
      expect(
        indexerStatusText(
          s(
            phase: HandwritingIndexerPhase.recognizing,
            queuedPages: 2,
            currentPageId: 'p',
          ),
        ),
        '상태: 인식 중 · 남은 페이지 2',
      );
      expect(
        indexerStatusText(s(phase: HandwritingIndexerPhase.paused)),
        '상태: 앱이 뒤에 있어 멈췄어요',
      );
    });
  });

  testWidgets('a const ConsumerWidget body: a Column, no Scaffold, no title, '
      'no scroll, the parent width', (tester) async {
    const section = RecognitionSettingsSection();
    expect(section, isA<ConsumerWidget>());
    await _pump(tester, overrides: [_engine(FakeHandwritingRecognizer())]);
    final found = find.byType(RecognitionSettingsSection);
    for (final type in [Scaffold, Scrollable, AppBar]) {
      expect(
        find.descendant(of: found, matching: find.byType(type)),
        findsNothing,
        reason: '$type',
      );
    }
    expect(find.text('인식'), findsNothing); // INFRA draws the title
    expect(
      find.descendant(of: found, matching: find.byType(Column)).first,
      findsOneWidget,
    );
    expect(tester.getSize(found).width, 720);
    for (final text in [
      RecognitionStrings.handwritingGroup,
      RecognitionStrings.languageTitle,
      RecognitionStrings.modelTitle,
      RecognitionStrings.wifiOnlyTitle,
      RecognitionStrings.autoIndexTitle,
      RecognitionStrings.mathGroup,
      RecognitionStrings.mathEngineTitle,
      RecognitionStrings.consentSwitch,
      RecognitionStrings.consentBody,
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    // 한국어 · English: the language choice and the model row.
    expect(find.text('한국어'), findsNWidgets(2));
    expect(find.text('English'), findsNWidgets(2));
    // An available engine: no fixed sentence, everything enabled.
    expect(find.byKey(RecognitionSettingsUiKeys.unsupported), findsNothing);
    expect(_switchEnabled(tester, RecognitionSettingsUiKeys.autoIndex), isTrue);
    expect(_switchEnabled(tester, RecognitionSettingsUiKeys.wifiOnly), isTrue);
  });

  testWidgets('defaults, then every key is stored at once', (tester) async {
    final store = await _pump(
      tester,
      overrides: [_engine(FakeHandwritingRecognizer())],
      autoIndex: null,
    );
    expect(_language(tester), 'ko');
    expect(_switchOn(tester, RecognitionSettingsUiKeys.wifiOnly), isTrue);
    // (handwriting search) U16 changed: on by default, nothing stored.
    expect(_switchOn(tester, RecognitionSettingsUiKeys.autoIndex), isTrue);
    await _tap(tester, find.byKey(RecognitionSettingsUiKeys.autoIndex));
    expect(
      await store.settings.get(RecognitionSettingsKeys.autoIndex),
      isFalse,
    );
    expect(_switchOn(tester, RecognitionSettingsUiKeys.autoIndex), isFalse);
    expect(_switchOn(tester, RecognitionSettingsUiKeys.consent), isFalse);

    await _tap(tester, find.byKey(RecognitionSettingsUiKeys.languageOf('en')));
    expect(await store.settings.get(RecognitionSettingsKeys.language), 'en');
    expect(_language(tester), 'en');

    await _tap(tester, find.byKey(RecognitionSettingsUiKeys.wifiOnly));
    expect(
      await store.settings.get(RecognitionSettingsKeys.modelWifiOnly),
      isFalse,
    );
    expect(_switchOn(tester, RecognitionSettingsUiKeys.wifiOnly), isFalse);

    await _tap(tester, find.byKey(RecognitionSettingsUiKeys.autoIndex));
    expect(await store.settings.get(RecognitionSettingsKeys.autoIndex), isTrue);
    expect(_switchOn(tester, RecognitionSettingsUiKeys.autoIndex), isTrue);

    await _tap(tester, find.byKey(RecognitionSettingsUiKeys.consent));
    expect(
      await store.settings.get(RecognitionSettingsKeys.mathConsent),
      isTrue,
    );
    expect(_switchOn(tester, RecognitionSettingsUiKeys.consent), isTrue);

    await _tap(tester, find.byKey(RecognitionSettingsUiKeys.languageOf('ko')));
    expect(await store.settings.get(RecognitionSettingsKeys.language), 'ko');
  });

  testWidgets('a value from another device shows', (tester) async {
    final store = await _pump(
      tester,
      overrides: [_engine(FakeHandwritingRecognizer())],
    );
    await store.settings.set(RecognitionSettingsKeys.language, 'en');
    await store.settings.set(RecognitionSettingsKeys.mathConsent, true);
    await store.settings.set(RecognitionSettingsKeys.autoIndex, true);
    await store.settings.set(RecognitionSettingsKeys.modelWifiOnly, false);
    await _settle(tester);
    expect(_language(tester), 'en');
    expect(_switchOn(tester, RecognitionSettingsUiKeys.consent), isTrue);
    expect(_switchOn(tester, RecognitionSettingsUiKeys.autoIndex), isTrue);
    expect(_switchOn(tester, RecognitionSettingsUiKeys.wifiOnly), isFalse);

    // An unknown stored language shows as 한국어 (4.4.3).
    await store.settings.set(RecognitionSettingsKeys.language, 'fr');
    await _settle(tester);
    expect(_language(tester), 'ko');
  });

  testWidgets('no available engine (desktop; the web: browser test) → the '
      'fixed sentence, the handwriting group disabled, math still works', (
    tester,
  ) async {
    final store = await _pump(tester); // default: Unsupported
    expect(
      find.descendant(
        of: find.byKey(RecognitionSettingsUiKeys.unsupported),
        matching: find.text(RecognitionStrings.unsupported),
      ),
      findsOneWidget,
    );
    expect(find.text(RecognitionStrings.webUnsupported), findsNothing);
    expect(
      _switchEnabled(tester, RecognitionSettingsUiKeys.autoIndex),
      isFalse,
    );
    expect(_switchEnabled(tester, RecognitionSettingsUiKeys.wifiOnly), isFalse);
    expect(
      tester
          .widget<RadioListTile<String>>(
            find.byKey(RecognitionSettingsUiKeys.languageOf('en')),
          )
          .enabled,
      isFalse,
    );
    expect(_status(tester), '이 기기에서는 자동 인식을 쓸 수 없어요');

    await _tap(tester, find.byKey(RecognitionSettingsUiKeys.languageOf('en')));
    await _tap(tester, find.byKey(RecognitionSettingsUiKeys.autoIndex));
    expect(await store.settings.get(RecognitionSettingsKeys.language), 'ko');
    expect(
      await store.settings.get(RecognitionSettingsKeys.autoIndex),
      isFalse,
    );

    // Math does not need the handwriting engine.
    expect(_switchEnabled(tester, RecognitionSettingsUiKeys.consent), isTrue);
    await _tap(tester, find.byKey(RecognitionSettingsUiKeys.consent));
    expect(
      await store.settings.get(RecognitionSettingsKeys.mathConsent),
      isTrue,
    );
  });

  testWidgets('(v2.14-ui) outside developer mode: no 품질 실험 group', (
    tester,
  ) async {
    await _pump(
      tester,
      overrides: [_engine(FakeHandwritingRecognizer())],
      developerMode: false,
    );
    expect(find.text(RecognitionStrings.labGroup), findsNothing);
    expect(find.byKey(RecognitionSettingsUiKeys.lab), findsNothing);
    expect(find.byKey(RecognitionSettingsUiKeys.mathFixture), findsNothing);
    // The rest of the section is still there.
    expect(find.byKey(RecognitionSettingsUiKeys.consent), findsOneWidget);
  });

  for (final (name, overrides) in [
    ('no engine', const <Override>[]),
    (
      'with engines',
      [
        _engine(FakeHandwritingRecognizer()),
        mathRecognizerProvider.overrideWithValue(FakeMathRecognizer()),
      ],
    ),
  ]) {
    testWidgets('품질 실험 [수식 고정 자료 만들기] ($name) → the math pad in '
        'its fixture mode (6.14.7)', (tester) async {
      await _pump(tester, overrides: overrides);
      expect(find.text(RecognitionStrings.labGroup), findsOneWidget);
      final entry = find.byKey(RecognitionSettingsUiKeys.mathFixture);
      expect(entry, findsOneWidget);
      expect(
        find.descendant(
          of: entry,
          matching: find.text(RecognitionStrings.mathFixtureEntry),
        ),
        findsOneWidget,
      );
      expect(tester.widget<ButtonStyleButton>(entry).onPressed, isNotNull);
      // the A-4 lab only with a handwriting engine (L2-19)
      expect(
        find.byKey(RecognitionSettingsUiKeys.lab),
        overrides.isEmpty ? findsNothing : findsOneWidget,
      );
      await tester.ensureVisible(entry);
      await tester.pump();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('recog.sheet.mathFixture')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('recog.pad.canvas')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('recog.pad.exportFixture')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('recog.sheet.cancel')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('recog.sheet.mathFixture')),
        findsNothing,
      );
    });
  }

  testWidgets('the status line follows the indexer (6.19)', (tester) async {
    await _pump(tester, overrides: [_engine(FakeHandwritingRecognizer())]);
    // Not started yet (INFRA's idle task starts it).
    expect(_status(tester), '이 기기에서는 자동 인식을 쓸 수 없어요');

    final indexer = _container(tester).read(handwritingIndexerProvider)!;
    indexer.start();
    await _settle(tester);
    expect(_status(tester), '상태: 꺼져 있어요');

    await _tap(tester, find.byKey(RecognitionSettingsUiKeys.autoIndex));
    expect(indexer.status.value.phase, HandwritingIndexerPhase.idle);
    expect(_status(tester), '상태: 대기 중 · 인식한 페이지 0');

    await _tap(tester, find.byKey(RecognitionSettingsUiKeys.autoIndex));
    expect(_status(tester), '상태: 꺼져 있어요');
  });

  testWidgets('the status line while the model waits for Wi-Fi', (
    tester,
  ) async {
    final recognizer = _WaitingForWifi();
    final store = await _pump(tester, overrides: [_engine(recognizer)]);
    await store.settings.set(RecognitionSettingsKeys.autoIndex, true);
    _container(tester).read(handwritingIndexerProvider)!.start();
    await _settle(tester);
    expect(_status(tester), '상태: 인식 모델을 기다리는 중이에요 · 와이파이 대기');
  });

  testWidgets('the math engine row', (tester) async {
    await _pump(tester);
    expect(
      find.descendant(
        of: find.byKey(RecognitionSettingsUiKeys.mathEngine),
        matching: find.text(RecognitionStrings.mathEngineManual),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the math engine row with an engine', (tester) async {
    await _pump(
      tester,
      overrides: [
        mathRecognizerProvider.overrideWithValue(FakeMathRecognizer()),
      ],
    );
    expect(
      find.descendant(
        of: find.byKey(RecognitionSettingsUiKeys.mathEngine),
        matching: find.text(RecognitionStrings.mathEngineServer),
      ),
      findsOneWidget,
    );
  });

  testWidgets('iPad (the engine does not enforce Wi-Fi) → the asks-first note '
      'under the Wi-Fi switch', (tester) async {
    final ios = FakeHandwritingRecognizer()..enforcesWifiOnly = false;
    await _pump(tester, overrides: [_engine(ios)]);
    expect(
      find.descendant(
        of: find.byKey(RecognitionSettingsUiKeys.wifiOnly),
        matching: find.text(RecognitionStrings.wifiOnlyAskFirst),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Android → no asks-first note', (tester) async {
    await _pump(tester, overrides: [_engine(FakeHandwritingRecognizer())]);
    expect(find.text(RecognitionStrings.wifiOnlyAskFirst), findsNothing);
  });

  testWidgets('while the settings load: disabled at opacity 0.38', (
    tester,
  ) async {
    final never = StreamController<core.SettingsSnapshot>();
    addTearDown(never.close);
    await _pump(
      tester,
      overrides: [
        _engine(FakeHandwritingRecognizer()),
        core.settingsSnapshotProvider.overrideWith((ref) => never.stream),
      ],
    );
    final section = find.byType(RecognitionSettingsSection);
    expect(
      tester
          .widget<Opacity>(
            find.descendant(of: section, matching: find.byType(Opacity)).first,
          )
          .opacity,
      0.38,
    );
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .descendant(of: section, matching: find.byType(IgnorePointer))
                .first,
          )
          .ignoring,
      isTrue,
    );
  });

  for (final (name, size) in [
    ('portrait', kIpadPortrait),
    ('landscape', kIpadLandscape),
  ]) {
    testWidgets('tap targets ≥ 44×44 and no overflow ($name)', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        size: size,
        overrides: [_engine(FakeHandwritingRecognizer())],
      );
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  }

  group('model rows (P-B)', () {
    testWidgets('준비됨 [지우기] → deleteModel → 받지 않음 [받기]', (tester) async {
      final engine = ControlledModelEngine()
        ..states['ko'] = RecognitionModelState.ready;
      await _pump(tester, overrides: [_engine(engine)]);
      _expectRow('ko', '준비됨', ['지우기']);
      _expectRow('en', '받지 않음', ['받기']);

      await _tap(tester, _inRow('ko', '지우기'));
      expect(engine.deleteCalls, ['ko']);
      _expectRow('ko', '받지 않음', ['받기']);
      expect(engine.ensureCalls, isEmpty);
    });

    testWidgets('no model admin → 준비됨 without [지우기]', (tester) async {
      await _pump(tester, overrides: [_engine(_WaitingForWifi())]);
      _expectRow('ko', '받지 않음', ['받기']);
    });

    testWidgets('Android [받기] → ensureModel(wifiOnly: true) → 받는 중… → '
        'done → 준비됨', (tester) async {
      final engine = ControlledModelEngine();
      await _pump(tester, overrides: [_engine(engine)]);
      await _tap(tester, _inRow('en', '받기'));
      expect(engine.ensureCalls, [('en', true)]);
      _expectRow('en', '받는 중…', []);
      _expectRow('ko', '받지 않음', ['받기']);

      engine.finish();
      await _settle(tester);
      _expectRow('en', '준비됨', ['지우기']);
      // The Wi-Fi wait timer ended with the download.
      await tester.pump(const Duration(seconds: 6));
      _expectRow('en', '준비됨', ['지우기']);
    });

    testWidgets('Android: still running after 5 s → 와이파이에 연결되면 받아요. '
        '[지금 셀룰러로 받기] → two presses → ensureModel(wifiOnly: false); '
        'the first to finish ends it', (tester) async {
      final engine = ControlledModelEngine();
      await _pump(tester, overrides: [_engine(engine)]);
      await _tap(tester, _inRow('ko', '받기'));
      await tester.pump(const Duration(milliseconds: 4999));
      _expectRow('ko', '받는 중…', []);
      await tester.pump(const Duration(milliseconds: 1));
      _expectRow('ko', '와이파이에 연결되면 받아요.', ['지금 셀룰러로 받기']);
      expect(
        find.byKey(RecognitionSettingsUiKeys.modelCellular('ko')),
        findsOneWidget,
      );

      await _tap(
        tester,
        find.byKey(RecognitionSettingsUiKeys.modelCellular('ko')),
      );
      _expectRow('ko', '와이파이에 연결되면 받아요.', [
        '셀룰러 데이터로 받아요(약 20MB). 한 번 더 누르면 받아요.',
      ]);
      expect(engine.ensureCalls, [('ko', true)]);

      await _tap(
        tester,
        find.byKey(RecognitionSettingsUiKeys.modelCellular('ko')),
      );
      expect(engine.ensureCalls, [('ko', true), ('ko', false)]);
      _expectRow('ko', '받는 중…', []);

      engine.finish(1); // the cellular one
      await _settle(tester);
      _expectRow('ko', '준비됨', ['지우기']);
      engine.finish(0); // the Wi-Fi one, later: nothing changes
      await _settle(tester);
      _expectRow('ko', '준비됨', ['지우기']);
    });

    testWidgets('Wi-Fi only off → ensureModel(wifiOnly: false), no Wi-Fi '
        'wait', (tester) async {
      final engine = ControlledModelEngine();
      final store = await _pump(tester, overrides: [_engine(engine)]);
      await store.settings.set(RecognitionSettingsKeys.modelWifiOnly, false);
      await _settle(tester);
      await _tap(tester, _inRow('ko', '받기'));
      expect(engine.ensureCalls, [('ko', false)]);
      await tester.pump(const Duration(seconds: 6));
      _expectRow('ko', '받는 중…', []);
      engine.finish();
      await _settle(tester);
      _expectRow('ko', '준비됨', ['지우기']);
    });

    testWidgets('iPad: [받기] first press → the cellular warning (no '
        'download), the second → ensureModel; no Wi-Fi wait', (tester) async {
      final engine = ControlledModelEngine(enforcesWifiOnly: false);
      await _pump(tester, overrides: [_engine(engine)]);
      await _tap(tester, _inRow('ko', '받기'));
      _expectRow('ko', '받지 않음', ['셀룰러 데이터로 받을 수 있어요(약 20MB). 한 번 더 누르면 받아요.']);
      expect(engine.ensureCalls, isEmpty);
      await _tap(
        tester,
        _inRow('ko', '셀룰러 데이터로 받을 수 있어요(약 20MB). 한 번 더 누르면 받아요.'),
      );
      expect(engine.ensureCalls, [('ko', false)]);
      await tester.pump(const Duration(seconds: 6));
      _expectRow('ko', '받는 중…', []);
      engine.finish();
      await _settle(tester);
      _expectRow('ko', '준비됨', ['지우기']);
    });

    testWidgets('iPad with Wi-Fi only off → one press', (tester) async {
      final engine = ControlledModelEngine(enforcesWifiOnly: false);
      final store = await _pump(tester, overrides: [_engine(engine)]);
      await store.settings.set(RecognitionSettingsKeys.modelWifiOnly, false);
      await _settle(tester);
      await _tap(tester, _inRow('en', '받기'));
      expect(engine.ensureCalls, [('en', false)]);
    });

    testWidgets('a failed download → reported once, 받지 못했어요 [다시] → '
        '[다시] downloads again', (tester) async {
      final engine = ControlledModelEngine();
      await _pump(tester, overrides: [_engine(engine)]);
      await _tap(tester, _inRow('ko', '받기'));
      final reports = await _reports(() async {
        engine.fail(RecognizerEngineError('download-failed', 'no'));
        await _settle(tester);
      });
      _expectRow('ko', '받지 못했어요', ['다시']);
      expect(reports, hasLength(1));
      expect(reports.single.library, 'ink_recognition');

      final later = await _reports(() async {
        await _tap(tester, _inRow('ko', '다시'));
        expect(engine.ensureCalls, [('ko', true), ('ko', true)]);
        _expectRow('ko', '받는 중…', []);
        engine.finish();
        await _settle(tester);
      });
      _expectRow('ko', '준비됨', ['지우기']);
      expect(later, isEmpty);
    });

    testWidgets('unsupported model, no engine → 쓸 수 없음 without a button', (
      tester,
    ) async {
      final engine = ControlledModelEngine()
        ..states['en'] = RecognitionModelState.unsupported;
      await _pump(tester, overrides: [_engine(engine)]);
      _expectRow('en', '쓸 수 없음', []);
      _expectRow('ko', '받지 않음', ['받기']);
    });

    testWidgets('no engine (Unsupported) → both rows 쓸 수 없음', (tester) async {
      await _pump(tester);
      _expectRow('ko', '쓸 수 없음', []);
      _expectRow('en', '쓸 수 없음', []);
    });

    testWidgets('another device / the indexer downloads → modelChanges → the '
        'row follows', (tester) async {
      final engine = ControlledModelEngine();
      await _pump(tester, overrides: [_engine(engine)]);
      unawaited(engine.ensureModel('ko')); // e.g. the indexer
      await _settle(tester);
      engine.finish();
      await _settle(tester);
      _expectRow('ko', '준비됨', ['지우기']);
    });

    testWidgets('자동 인식 on (Android, model missing) → ensureModel once', (
      tester,
    ) async {
      final engine = FakeHandwritingRecognizer()
        ..modelStates['ko'] = RecognitionModelState.notDownloaded;
      final store = await _pump(tester, overrides: [_engine(engine)]);
      await _tap(tester, find.byKey(RecognitionSettingsUiKeys.autoIndex));
      expect(engine.ensureModelCalls, 1);
      expect(
        await store.settings.get(RecognitionSettingsKeys.autoIndex),
        isTrue,
      );
      _expectRow('ko', '준비됨', ['지우기']);

      // Off and on again with the model ready → no download.
      await _tap(tester, find.byKey(RecognitionSettingsUiKeys.autoIndex));
      await _tap(tester, find.byKey(RecognitionSettingsUiKeys.autoIndex));
      expect(engine.ensureModelCalls, 1);
    });

    testWidgets('자동 인식 on (Android) follows recog.language and Wi-Fi only', (
      tester,
    ) async {
      final engine = ControlledModelEngine();
      final store = await _pump(tester, overrides: [_engine(engine)]);
      await store.settings.set(RecognitionSettingsKeys.language, 'en');
      await _settle(tester);
      await _tap(tester, find.byKey(RecognitionSettingsUiKeys.autoIndex));
      expect(engine.ensureCalls, [('en', true)]);
      _expectRow('en', '받는 중…', []);
      _expectRow('ko', '받지 않음', ['받기']);
      engine.finish();
      await _settle(tester);
    });

    testWidgets('자동 인식 on (iPad, model missing) → no download; the row\'s '
        '[받기] is emphasised until a download starts', (tester) async {
      final engine = ControlledModelEngine(enforcesWifiOnly: false);
      await _pump(tester, overrides: [_engine(engine)]);
      Finder filled(String tag) =>
          find.descendant(of: _row(tag), matching: find.byType(FilledButton));
      expect(filled('ko'), findsNothing);
      await _tap(tester, find.byKey(RecognitionSettingsUiKeys.autoIndex));
      expect(engine.ensureCalls, isEmpty);
      expect(filled('ko'), findsOneWidget);
      expect(filled('en'), findsNothing);

      await _tap(tester, _inRow('ko', '받기'));
      await _tap(
        tester,
        _inRow('ko', '셀룰러 데이터로 받을 수 있어요(약 20MB). 한 번 더 누르면 받아요.'),
      );
      expect(engine.ensureCalls, [('ko', false)]);
      expect(filled('ko'), findsNothing);
      engine.finish();
      await _settle(tester);
    });

    testWidgets('model rows: tap targets ≥ 44×44 with every button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final engine = ControlledModelEngine()
        ..states['ko'] = RecognitionModelState.ready;
      await _pump(tester, overrides: [_engine(engine)]);
      await _tap(tester, _inRow('en', '받기'));
      await tester.pump(const Duration(seconds: 5));
      await _tap(
        tester,
        find.byKey(RecognitionSettingsUiKeys.modelCellular('en')),
      );
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      handle.dispose();
      engine.finish();
      await _settle(tester);
    });
  });
}

/// Available; the model is not downloaded; a download waits for Wi-Fi.
final class _WaitingForWifi implements HandwritingRecognizer {
  final Completer<void> _download = Completer<void>();

  @override
  String get engineId => 'waiting';
  @override
  bool get isAvailable => true;
  @override
  Future<RecognitionModelState> modelState(String languageTag) async =>
      RecognitionModelState.notDownloaded;
  @override
  Future<void> ensureModel(String languageTag, {bool wifiOnly = true}) =>
      _download.future;
  @override
  Future<List<TextCandidate>> recognizeLine(
    HandwritingLineInput line, {
    required String languageTag,
  }) async => const [];
  @override
  Future<void> dispose() async {}
}
