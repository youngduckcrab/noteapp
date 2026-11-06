// RecognitionSettingsSection (m5-7/05-library 8.2 L2-18, 6.18, 6.19;
// contract 7.2.11 — a const ConsumerWidget; 1차 7.4.11 section rules):
// a body only (a Column — no Scaffold, no title, no scroll) at the parent's
// width; every recog.* key is stored at once; a value from another device
// shows; without an available engine the fixed sentence and a disabled
// handwriting group (the web sentence: web/recognition_browser_test.dart);
// the 6.19 status line follows the indexer; the math engine row; iPad's
// 'asks first' note; inputs disabled while the settings load; tap targets.
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

import '../support/recognition_test_scope.dart';

/// The section as INFRA mounts it: Scaffold → scroll → at most 720 wide.
Future<core.NoteStore> _pump(
  WidgetTester tester, {
  List<Override> overrides = const [],
  Size size = kIpadPortrait,
}) async {
  tester.view.physicalSize = size;
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
      '한국어',
      'English',
      RecognitionStrings.wifiOnlyTitle,
      RecognitionStrings.autoIndexTitle,
      RecognitionStrings.mathGroup,
      RecognitionStrings.mathEngineTitle,
      RecognitionStrings.consentSwitch,
      RecognitionStrings.consentBody,
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    // An available engine: no fixed sentence, everything enabled.
    expect(find.byKey(RecognitionSettingsUiKeys.unsupported), findsNothing);
    expect(_switchEnabled(tester, RecognitionSettingsUiKeys.autoIndex), isTrue);
    expect(_switchEnabled(tester, RecognitionSettingsUiKeys.wifiOnly), isTrue);
  });

  testWidgets('defaults, then every key is stored at once', (tester) async {
    final store = await _pump(
      tester,
      overrides: [_engine(FakeHandwritingRecognizer())],
    );
    expect(_language(tester), 'ko');
    expect(_switchOn(tester, RecognitionSettingsUiKeys.wifiOnly), isTrue);
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
