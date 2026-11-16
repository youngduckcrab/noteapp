// Shared set-up of the settings tests (docs/plans/01-infra.md 9.1): the shell
// providers the settings sections read, over CountingNoteStore and
// FakeWebPlatform, on an iPad Pro 13" view.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/app/appearance.dart';
import 'package:noteapp/src/app/theme.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/providers.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:noteapp/src/settings/developer_mode.dart';

import '../fakes/counting_note_store.dart';
import '../fakes/fake_web_platform.dart';

/// iPad Pro 13" logical sizes at DPR 2 (contract 7.4.8).
const Size ipadPortrait = Size(1032, 1376);
const Size ipadLandscape = Size(1376, 1032);

void useIpadView(WidgetTester tester, {Size logical = ipadPortrait}) {
  tester.view
    ..physicalSize = logical * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

const BuildInfo testBuild = BuildInfo(
  version: '0.1.0',
  buildNumber: 42,
  gitSha: 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678',
  gitRef: 'main',
  channel: BuildChannel.live,
);

const RuntimeInfo testRuntime = RuntimeInfo(
  isWeb: true,
  renderer: WebRenderer.canvasKit,
  isStandalone: true,
  userAgent: 'FakeBrowser/1.0',
);

const StartupReport testReport = StartupReport(
  steps: [
    StartupStep(
      id: 'core',
      elapsed: Duration(milliseconds: 1234),
      outcome: StartupStepOutcome.ok,
    ),
    StartupStep(
      id: 'pdf',
      elapsed: Duration(milliseconds: 30),
      outcome: StartupStepOutcome.failedNonCritical,
    ),
  ],
  bootstrapElapsed: Duration(milliseconds: 1300),
  sinceNavigationStart: Duration(milliseconds: 1850),
  storage: StorageInfo(backend: StorageBackend.webOpfsShared),
);

/// Values behind the shell providers of one settings test.
final class SettingsHarness {
  SettingsHarness({
    CountingNoteStore? store,
    FakeWebPlatform? web,
    AppErrorLog? errorLog,
    this.build = testBuild,
    this.runtime = testRuntime,
    this.report = testReport,
    this.developerMode = true,
  }) : store = store ?? CountingNoteStore(),
       web = web ?? FakeWebPlatform(),
       errorLog = errorLog ?? AppErrorLog();

  final CountingNoteStore store;
  final FakeWebPlatform web;
  final AppErrorLog errorLog;
  final BuildInfo build;
  final RuntimeInfo runtime;
  final StartupReport report;

  /// (v2.14-ui) true: developer mode forced on (the diagnostics these tests
  /// read are developer-only now); false: the real switch
  /// (developerModeOverride — off until the 빌드 row is tapped 7 times).
  final bool developerMode;

  /// The root overrides the settings sections read (contract 7.3.3:
  /// noteStoreProvider + the shell providers + the feature packages' lists).
  /// UpdateChecker runs on [runtime]/[build]; tests that need it quiet pass a
  /// `local` build or `isWeb: false`.
  List<Override> overrides() => [
    noteStoreProvider.overrideWithValue(store),
    buildInfoProvider.overrideWithValue(build),
    runtimeInfoProvider.overrideWithValue(runtime),
    webPlatformProvider.overrideWithValue(web),
    appErrorLogProvider.overrideWithValue(errorLog),
    startupReportProvider.overrideWithValue(report),
    ...featureEditorOverrides(),
    ...featureLibraryOverrides(),
    // (v2.14-ui) As in the root overrides (app_bootstrapper), or forced on.
    if (developerMode)
      developerModeProvider.overrideWithValue(true)
    else
      developerModeOverride(),
  ];

  /// Pumps [child] in a material_ui MaterialApp (app theme, locale ko) under
  /// a ProviderScope with [overrides] + [extra]. Returns the container.
  ///
  /// (v2.14-ui) [followAppearance]: the MaterialApp takes theme / darkTheme
  /// / themeMode from appAppearanceProvider, as NoteApp does, so a '화면'
  /// change shows live.
  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget child, {
    List<Override> extra = const [],
    Size logical = ipadPortrait,
    bool followAppearance = false,
  }) async {
    useIpadView(tester, logical: logical);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...overrides(), ...extra],
        child: followAppearance
            ? Consumer(
                builder: (context, ref, _) {
                  final appearance = ref.watch(appAppearanceProvider);
                  return MaterialApp(
                    theme: buildAppTheme(style: appearance.style),
                    darkTheme: buildAppTheme(
                      style: appearance.style,
                      brightness: Brightness.dark,
                    ),
                    themeMode: appearance.themeMode,
                    locale: const Locale('ko'),
                    home: child,
                  );
                },
              )
            : MaterialApp(
                theme: buildAppTheme(),
                locale: const Locale('ko'),
                home: child,
              ),
      ),
    );
    return ProviderScope.containerOf(tester.element(find.byWidget(child)));
  }
}

/// [child] inside a Scaffold with a scrolling body (sections are Column-only).
Widget sectionPage(Widget child) => Scaffold(
  body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
);
