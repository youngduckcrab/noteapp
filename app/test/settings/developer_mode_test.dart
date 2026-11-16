// (v2.14-ui, UI stage 1 — m5-7/01-infra 'UI 정리 1단계') Developer mode: the
// developer-only settings stay out of sight until the 빌드 row in 앱 정보 is
// tapped 7 times (snack bar '개발자 모드를 켰어요' / '껐어요'); the developer
// overlay (⌘⇧D) and ?dev=1 still bring them; CORE's developerModeProvider
// follows the shell's switch (developerModeOverride).
import 'package:feature_editor/feature_editor.dart' show editorSettingsProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/settings/about_section.dart';
import 'package:noteapp/src/settings/developer_mode.dart';
import 'package:noteapp/src/settings/settings_screen.dart';
import 'package:noteapp/src/settings/settings_sections.dart';
import 'package:noteapp/src/settings/storage_section.dart';

import '../support/settings_harness.dart';

Future<void> _tapBuildRow(WidgetTester tester, int times) async {
  final row = find.byKey(AboutSection.buildRowKey);
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  for (var i = 0; i < times; i++) {
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

List<String> _ids(ProviderContainer c) => [
  for (final s in c.read(settingsSectionsProvider)) s.id,
];

const _devIds = ['editor.developer', 'app.features', 'app.v1Copy'];

/// The two sections with developer-only rows, in one scroll view.
const Widget _sections = Scaffold(
  body: SingleChildScrollView(
    child: Column(children: [StorageSection(), AboutSection()]),
  ),
);

void main() {
  testWidgets('off at first: no developer sections, a short storage table, '
      'no renderer / startup / 진단 정보 복사; 7 taps on 빌드 turn it on, 7 more '
      'turn it off', (tester) async {
    final harness = SettingsHarness(developerMode: false);
    final container = await harness.pump(tester, _sections);
    await tester.pumpAndSettle();
    expect(container.read(developerModeProvider), isFalse);
    expect(_ids(container), isNot(anyElement(isIn(_devIds))));
    expect(_ids(container), contains('app.about'));
    final storage = find.byType(StorageSection, skipOffstage: false);
    for (final hidden in [
      AppStrings.storageBackend,
      AppStrings.storageFailures,
      AppStrings.aboutRenderer,
      AppStrings.aboutStartup,
      AppStrings.copyDiagnostics,
    ]) {
      expect(find.text(hidden, skipOffstage: false), findsNothing);
    }
    expect(
      find.descendant(
        of: storage,
        matching: find.text(AppStrings.storageUsage, skipOffstage: false),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('storage-assets'), skipOffstage: false),
      findsOneWidget,
    );

    // Six taps: nothing yet.
    await _tapBuildRow(tester, 6);
    expect(find.text(AppStrings.developerModeOn), findsNothing);
    expect(container.read(developerModeProvider), isFalse);
    // The 7th.
    await _tapBuildRow(tester, 1);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text(AppStrings.developerModeOn), findsOneWidget);
    expect(container.read(developerModeProvider), isTrue);
    expect(
      await tester.runAsync(
        () => harness.store.settings.get(AppDeveloperModeKeys.enabled),
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(_ids(container), containsAll(_devIds));
    expect(
      find.text(AppStrings.storageBackend, skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text(AppStrings.copyDiagnostics, skipOffstage: false),
      findsOneWidget,
    );

    await _tapBuildRow(tester, 7);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.developerModeOff), findsOneWidget);
    expect(container.read(developerModeProvider), isFalse);
    expect(_ids(container), isNot(contains('editor.developer')));
  });

  testWidgets('the developer overlay (⌘⇧D / the 개발자 표시 switch) also '
      'counts as developer mode', (tester) async {
    final harness = SettingsHarness(developerMode: false);
    final container = await harness.pump(
      tester,
      SettingsScreen(onClose: () {}),
    );
    await tester.pumpAndSettle();
    expect(container.read(developerModeProvider), isFalse);
    container.read(editorSettingsProvider.notifier).setShowDevOverlay(true);
    await tester.pumpAndSettle();
    expect(container.read(appDeveloperModeProvider), isTrue);
    expect(container.read(developerModeProvider), isTrue);
    expect(_ids(container), containsAll(_devIds));
    expect(find.byIcon(Icons.arrow_back), findsOneWidget); // ← 뒤로
    container.read(editorSettingsProvider.notifier).setShowDevOverlay(false);
    await tester.pumpAndSettle();
    expect(container.read(developerModeProvider), isFalse);
    await tester.pump(const Duration(seconds: 2)); // debounced writes
  });

  testWidgets('(review) from the 4th tap the 빌드 row counts the taps left',
      (tester) async {
    final harness = SettingsHarness(developerMode: false);
    await harness.pump(tester, _sections);
    await tester.pumpAndSettle();
    await _tapBuildRow(tester, 3);
    expect(find.textContaining('번 남았어요'), findsNothing);
    await _tapBuildRow(tester, 1);
    expect(find.text(AppStrings.developerModeTapsLeft(3)), findsOneWidget);
    await _tapBuildRow(tester, 2);
    expect(find.text(AppStrings.developerModeTapsLeft(1)), findsOneWidget);
    expect(AppStrings.developerModeTapsLeft(1), '개발자 모드까지 1번 남았어요');
    await _tapBuildRow(tester, 1);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.developerModeOn), findsOneWidget);
  });

  testWidgets('(review) turning the stored switch off while the developer '
      'overlay keeps developer mode on says so, not 껐어요', (tester) async {
    final harness = SettingsHarness(developerMode: false);
    final container = await harness.pump(tester, _sections);
    await tester.pumpAndSettle();
    await _tapBuildRow(tester, 7); // stored on
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    container.read(editorSettingsProvider.notifier).setShowDevOverlay(true);
    await tester.pumpAndSettle();
    await _tapBuildRow(tester, 7); // stored off, overlay still on
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.developerModeOff), findsNothing);
    expect(find.text(AppStrings.developerModeStillOn), findsOneWidget);
    expect(container.read(developerModeProvider), isTrue);
    expect(
      await tester.runAsync(
        () => harness.store.settings.get(AppDeveloperModeKeys.enabled),
      ),
      isFalse,
    );
    container.read(editorSettingsProvider.notifier).setShowDevOverlay(false);
    await tester.pump(const Duration(seconds: 2)); // debounced writes
  });

  test('?dev=1 counts too; the stored switch is a device setting', () {
    final container = ProviderContainer.test(
      overrides: [
        appDevUrlFlagProvider.overrideWithValue(true),
        noteStoreProvider.overrideWithValue(SettingsHarness().store),
        developerModeOverride(),
      ],
    );
    expect(container.read(developerModeProvider), isTrue);
    expect(AppDeveloperModeKeys.enabled.scope, SettingScope.device);
    expect(AppDeveloperModeKeys.enabled.name, 'app.developerMode');
  });

  test('DeveloperModeTapCounter: 7 taps each within 2 s; a pause starts '
      'again', () {
    var now = DateTime(2026, 11, 16, 10);
    final counter = DeveloperModeTapCounter(now: () => now);
    void step(Duration d) => now = now.add(d);
    for (var i = 0; i < 6; i++) {
      expect(counter.tap(), isFalse);
      step(const Duration(milliseconds: 500));
    }
    step(const Duration(seconds: 3)); // too slow: the run restarts
    for (var i = 0; i < 6; i++) {
      expect(counter.tap(), isFalse);
      step(const Duration(milliseconds: 500));
    }
    expect(counter.tap(), isTrue);
    expect(counter.count, 0);
  });
}
