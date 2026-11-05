@TestOn('browser')
library;

// The app shell booting in a real browser (docs/plans/01-infra.md 9.1 I11):
// BootstrapApp with fake modules and the browser WebPlatform shows the
// library placeholder; a failing critical module shows the startup error
// screen; the production modules (CoreModule over CORE's fake store, PdfModule,
// FeatureWiringModule) reach the production LibraryScreen. Compiled with
// dart2js by `ws test --platform chrome`, so any runtime dart:io use fails.

import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/app/note_app.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/bootstrap/bootstrap_app.dart';
import 'package:noteapp/src/bootstrap/startup_error_screen.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/modules/core_module.dart';
import 'package:noteapp/src/modules/feature_wiring_module.dart';
import 'package:noteapp/src/modules/pdf_module.dart';
import 'package:noteapp/src/providers.dart';
import 'package:noteapp/src/routing/screen_builders.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:noteapp/src/web/web_platform.dart';

import '../fakes/counting_note_store.dart';
import '../fakes/fake_app_module.dart';
import '../fakes/fake_note_store_opener.dart';

/// iPad Pro 13" portrait, logical 1032×1376 at DPR 2 (contract 7.4.8).
void _useIpadPortrait(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(2064, 2752)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

/// Pumps BootstrapApp over [modules] with the browser WebPlatform.
Future<AppErrorLog> _boot(
  WidgetTester tester,
  List<AppModule> Function() modules,
) async {
  _useIpadPortrait(tester);
  final web = createWebPlatform();
  expect(web.isSupported, isTrue);
  final errorLog = AppErrorLog();
  await tester.pumpWidget(
    BootstrapApp(
      errorLog: errorLog,
      createBootstrapper: () => AppBootstrapper(
        modules: modules(),
        buildInfo: BuildInfo.local,
        runtimeInfo: RuntimeInfo.detect(web),
        web: web,
        errorLog: errorLog,
        ownerId: kLocalOwnerId,
      ),
    ),
  );
  // Module start-up runs on real futures (no timers in the fakes).
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return errorLog;
}

void main() {
  testWidgets('fake modules → NoteApp → library placeholder', (tester) async {
    final errorLog = await _boot(
      tester,
      () => [
        FakeAppModule(
          id: 'core',
          overrides: [
            appScreenBuildersProvider.overrideWithValue(
              AppScreenBuilders.placeholders(),
            ),
          ],
        ),
        FakeAppModule(id: 'extra', critical: false),
      ],
    );
    expect(find.byType(NoteApp), findsOneWidget);
    expect(find.textContaining(RegExp(r'^library #\d+$')), findsOneWidget);
    expect(find.text('folderId: (root)'), findsOneWidget);
    expect(errorLog.totalCount, 0);

    // The shell knows it runs on the web.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NoteApp)),
    );
    final runtime = container.read(runtimeInfoProvider);
    expect(runtime.isWeb, isTrue);
    expect(runtime.renderer, isNot(WebRenderer.notWeb));
  });

  testWidgets('a failing critical module → startup error screen', (
    tester,
  ) async {
    final errorLog = await _boot(
      tester,
      () => [FakeAppModule(id: 'core', startError: StateError('boom'))],
    );
    expect(find.byType(StartupErrorScreen), findsOneWidget);
    expect(find.text(AppStrings.startupFailedTitle), findsOneWidget);
    expect(find.text(AppStrings.retry), findsOneWidget);
    expect(errorLog.totalCount, 1);
  });

  testWidgets('production modules over CORE fake store → LibraryScreen', (
    tester,
  ) async {
    final store = CountingNoteStore();
    await _boot(
      tester,
      () => [
        CoreModule(open: fakeOpenNoteStore(store: store).call),
        PdfModule(),
        FeatureWiringModule(),
      ],
    );
    expect(find.byType(NoteApp), findsOneWidget);
    expect(find.byType(LibraryScreen), findsOneWidget);
  });
}
