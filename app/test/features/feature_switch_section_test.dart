// FeatureSwitchSection — '기능 켜고 끄기' (J5 — docs/plans/m5-7/01-infra.md
// 4.6.1, 6.6, 6.17, 9.1): the switch wording ('녹음' — image import stays,
// D17), a switch the build turned off (disabled, '이 빌드에서 꺼져 있어요'),
// saving to AppFeatureKeys, '다시 시작하면 적용돼요' when the build AND the
// menu differ from this start, [다시 시작] (web: flush then reload; native:
// text only), blocked while recording, flush / save failures.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/features/app_features.dart';
import 'package:noteapp/src/features/feature_switch_section.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';

import '../fakes/counting_note_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../support/settings_harness.dart';

Widget _page({AppFeatures compileTime = AppFeatures.all}) => Scaffold(
  body: SingleChildScrollView(
    child: FeatureSwitchSection(compileTime: compileTime),
  ),
);

SwitchListTile _tile(WidgetTester tester, AppFeature feature) =>
    tester.widget<SwitchListTile>(
      find.byKey(FeatureSwitchSectionKeys.switchOf(feature)),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('wording: 녹음 (image import stays) · 인식 (with automatic shape '
      'correction) · 수식 엔진; all on, nothing to restart', (tester) async {
    final harness = SettingsHarness();
    addTearDown(harness.store.inner.close);
    await harness.pump(tester, _page());
    await _settle(tester);

    expect(find.text('녹음'), findsOneWidget);
    expect(find.text('녹음·녹음 패널. 이미지 넣기는 꺼지지 않아요'), findsOneWidget);
    expect(find.text('인식'), findsOneWidget);
    expect(find.text('손글씨·수식 인식, 자동 도형 보정'), findsOneWidget);
    expect(find.text('수식 엔진'), findsOneWidget);
    for (final feature in AppFeature.values) {
      expect(_tile(tester, feature).value, isTrue, reason: feature.name);
      expect(_tile(tester, feature).onChanged, isNotNull);
    }
    expect(find.byKey(FeatureSwitchSectionKeys.restartHint), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a switch the build turned off: disabled, off, '
      "'이 빌드에서 꺼져 있어요' — even when the menu key is on", (tester) async {
    final harness = SettingsHarness();
    addTearDown(harness.store.inner.close);
    const build = AppFeatures(media: false);
    await harness.pump(
      tester,
      _page(compileTime: build),
      extra: [appFeaturesProvider.overrideWithValue(build)],
    );
    await _settle(tester);

    final media = _tile(tester, AppFeature.media);
    expect(media.value, isFalse);
    expect(media.onChanged, isNull);
    expect(find.text(AppStrings.featureOffInBuild), findsOneWidget);
    expect(find.text(AppStrings.featureMediaHint), findsNothing);
    await tester.tap(
      find.byKey(FeatureSwitchSectionKeys.switchOf(AppFeature.media)),
    );
    await _settle(tester);
    expect(await harness.store.settings.get(AppFeatureKeys.media), isTrue);
    expect(find.byKey(FeatureSwitchSectionKeys.restartHint), findsNothing);
  });

  testWidgets('switching 녹음 off saves app.features.media = false and shows '
      "'다시 시작하면 적용돼요' + [다시 시작]; switching back hides it", (tester) async {
    final harness = SettingsHarness();
    addTearDown(harness.store.inner.close);
    await harness.pump(tester, _page());
    await _settle(tester);

    await tester.tap(
      find.byKey(FeatureSwitchSectionKeys.switchOf(AppFeature.media)),
    );
    await _settle(tester);
    expect(await harness.store.settings.get(AppFeatureKeys.media), isFalse);
    expect(_tile(tester, AppFeature.media).value, isFalse);
    expect(find.text(AppStrings.featureRestartToApply), findsOneWidget);
    expect(find.byKey(FeatureSwitchSectionKeys.restart), findsOneWidget);

    await tester.tap(
      find.byKey(FeatureSwitchSectionKeys.switchOf(AppFeature.media)),
    );
    await _settle(tester);
    expect(await harness.store.settings.get(AppFeatureKeys.media), isTrue);
    expect(find.byKey(FeatureSwitchSectionKeys.restartHint), findsNothing);
  });

  testWidgets('the menu already differs from this start (e.g. the start read '
      'timed out) → the hint without any tap', (tester) async {
    final harness = SettingsHarness();
    addTearDown(harness.store.inner.close);
    await harness.store.settings.set(AppFeatureKeys.recognition, false);
    await harness.pump(
      tester,
      _page(),
      extra: [appFeaturesProvider.overrideWithValue(AppFeatures.all)],
    );
    await _settle(tester);
    expect(_tile(tester, AppFeature.recognition).value, isFalse);
    expect(find.byKey(FeatureSwitchSectionKeys.restartHint), findsOneWidget);
  });

  testWidgets('수식 엔진 alone off while 인식 is off changes nothing that runs '
      '→ no hint', (tester) async {
    final harness = SettingsHarness();
    addTearDown(harness.store.inner.close);
    await harness.store.settings.set(AppFeatureKeys.recognition, false);
    await harness.pump(
      tester,
      _page(),
      extra: [
        appFeaturesProvider.overrideWithValue(
          const AppFeatures(recognition: false),
        ),
      ],
    );
    await _settle(tester);
    await tester.tap(
      find.byKey(FeatureSwitchSectionKeys.switchOf(AppFeature.mathEngine)),
    );
    await _settle(tester);
    expect(
      await harness.store.settings.get(AppFeatureKeys.mathEngine),
      isFalse,
    );
    expect(find.byKey(FeatureSwitchSectionKeys.restartHint), findsNothing);
  });

  testWidgets('[다시 시작] on the web: store.flush() then web.reload()', (
    tester,
  ) async {
    final harness = SettingsHarness();
    addTearDown(harness.store.inner.close);
    await harness.pump(tester, _page());
    await _settle(tester);
    await tester.tap(
      find.byKey(FeatureSwitchSectionKeys.switchOf(AppFeature.media)),
    );
    await _settle(tester);

    await tester.tap(find.byKey(FeatureSwitchSectionKeys.restart));
    await _settle(tester);
    expect(harness.store.flushCount, 1);
    expect(harness.web.reloadCount, 1);
    expect(harness.errorLog.totalCount, 0);
  });

  testWidgets('[다시 시작] while recording: the 6.17 message, no flush, no '
      'reload', (tester) async {
    final harness = SettingsHarness();
    addTearDown(harness.store.inner.close);
    final recorder = FakeAudioRecorder(store: harness.store);
    await harness.pump(
      tester,
      _page(),
      extra: [audioRecorderServiceProvider.overrideWithValue(recorder)],
    );
    await _settle(tester);
    await tester.tap(
      find.byKey(FeatureSwitchSectionKeys.switchOf(AppFeature.media)),
    );
    await _settle(tester);
    await tester.runAsync(
      () => recorder.start(recordingId: 'rec-1', noteId: 'note-1'),
    );
    expect(recorder.status.isActive, isTrue);

    await tester.tap(find.byKey(FeatureSwitchSectionKeys.restart));
    await _settle(tester);
    expect(find.text('녹음 중에는 새로 고칠 수 없어요. 녹음을 멈춘 뒤 눌러 주세요.'), findsOneWidget);
    expect(harness.store.flushCount, 0);
    expect(harness.web.reloadCount, 0);

    // Paused still counts as recording (status.isActive).
    await recorder.pause();
    await tester.tap(find.byKey(FeatureSwitchSectionKeys.restart));
    await _settle(tester);
    expect(harness.web.reloadCount, 0);
    await tester.runAsync(recorder.stop);
  });

  testWidgets('a flush that fails: no reload, the message, one record', (
    tester,
  ) async {
    final harness = SettingsHarness(
      store: CountingNoteStore(flushError: StateError('disk full')),
    );
    addTearDown(harness.store.inner.close);
    await harness.pump(tester, _page());
    await _settle(tester);
    await tester.tap(
      find.byKey(FeatureSwitchSectionKeys.switchOf(AppFeature.media)),
    );
    await _settle(tester);
    await tester.tap(find.byKey(FeatureSwitchSectionKeys.restart));
    await _settle(tester);
    expect(harness.web.reloadCount, 0);
    expect(find.text(AppStrings.featureFlushFailed), findsOneWidget);
    expect(harness.errorLog.totalCount, 1);
    expect(harness.errorLog.records.single.summary, contains('disk full'));
  });

  testWidgets('a flush slower than 2 s: no reload, the message', (
    tester,
  ) async {
    final harness = SettingsHarness(
      store: CountingNoteStore(flushDelay: const Duration(seconds: 3)),
    );
    addTearDown(harness.store.inner.close);
    await harness.pump(tester, _page());
    await _settle(tester);
    await tester.tap(
      find.byKey(FeatureSwitchSectionKeys.switchOf(AppFeature.media)),
    );
    await _settle(tester);
    await tester.tap(find.byKey(FeatureSwitchSectionKeys.restart));
    await tester.pump(FeatureSwitchSection.flushTimeout);
    await _settle(tester);
    expect(harness.web.reloadCount, 0);
    expect(find.text(AppStrings.featureFlushFailed), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('native: the hint says to close and reopen the app, no button', (
    tester,
  ) async {
    final harness = SettingsHarness(
      runtime: const RuntimeInfo(
        isWeb: false,
        renderer: WebRenderer.notWeb,
        isStandalone: false,
      ),
    );
    addTearDown(harness.store.inner.close);
    await harness.pump(tester, _page());
    await _settle(tester);
    await tester.tap(
      find.byKey(FeatureSwitchSectionKeys.switchOf(AppFeature.media)),
    );
    await _settle(tester);
    expect(
      find.textContaining(AppStrings.featureRestartNative),
      findsOneWidget,
    );
    expect(find.byKey(FeatureSwitchSectionKeys.restart), findsNothing);
  });

  testWidgets('a failing write: the message and one record (source manual)', (
    tester,
  ) async {
    final store = CountingNoteStore();
    store.settingsOverride = FakeSettingsRepository(
      store.inner.settings,
      setError: StateError('read-only database'),
    );
    final harness = SettingsHarness(store: store);
    addTearDown(store.inner.close);
    await harness.pump(tester, _page());
    await _settle(tester);
    await tester.tap(
      find.byKey(FeatureSwitchSectionKeys.switchOf(AppFeature.media)),
    );
    await _settle(tester);
    expect(find.text(AppStrings.featureSaveFailed), findsOneWidget);
    expect(harness.errorLog.totalCount, 1);
    expect(_tile(tester, AppFeature.media).value, isTrue);
  });

  testWidgets('landscape iPad: no overflow', (tester) async {
    final harness = SettingsHarness();
    addTearDown(harness.store.inner.close);
    await harness.pump(tester, _page(), logical: ipadLandscape);
    await _settle(tester);
    await tester.tap(
      find.byKey(FeatureSwitchSectionKeys.switchOf(AppFeature.media)),
    );
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });
}
