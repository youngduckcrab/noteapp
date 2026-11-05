// UpdateBanner (docs/plans/01-infra.md 4.5.7, 6.11 step 5, 9.1): shown only
// for UpdateAvailable, [나중에] → dismiss, [새로고침] → flush then reload,
// 해요체 text. It lives in MaterialApp.builder, above the Navigator.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/providers.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:noteapp/src/update/update_banner.dart';
import 'package:noteapp/src/update/update_checker.dart';

import '../fakes/fake_app_module.dart';
import '../fakes/fake_web_platform.dart';

final String _localSha = 'a' * 40;
final String _remoteSha = 'b2c3d4e${'f' * 33}';

BuildInfo _build(String sha, int buildNumber) => BuildInfo(
  version: '0.1.0',
  buildNumber: buildNumber,
  gitSha: sha,
  gitRef: 'main',
  channel: BuildChannel.live,
);

const _bannerText = '새 버전이 나왔어요 (#43 · b2c3d4e). 새로고침하면 적용돼요.';

/// A page below the banner that counts its initState calls.
class _Page extends StatefulWidget {
  const _Page();

  static int created = 0;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  void initState() {
    super.initState();
    _Page.created++;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Builder(
      builder: (context) =>
          Text('page top inset ${MediaQuery.paddingOf(context).top}'),
    ),
  );
}

final class _Harness {
  _Harness(this.web, this.module, this.container);

  final FakeWebPlatform web;
  final FakeAppModule module;
  final ProviderContainer container;

  UpdateStatus get status => container.read(updateCheckerProvider);
}

/// Pumps a material_ui MaterialApp whose builder is UpdateBanner (as in
/// NoteApp) on an iPad Pro 13" portrait view with a 24 pt top inset. The
/// served build_info.json has [remoteSha]; the first check is after 1 s.
Future<_Harness> _pump(
  WidgetTester tester, {
  String? remoteSha,
  BuildInfo? local,
  bool isWeb = true,
}) async {
  tester.view
    ..physicalSize = const Size(2064, 2752)
    ..devicePixelRatio = 2
    ..padding = const FakeViewPadding(top: 48);
  addTearDown(tester.view.reset);
  _Page.created = 0;

  final info = local ?? _build(_localSha, 42);
  final runtime = RuntimeInfo(
    isWeb: isWeb,
    renderer: isWeb ? WebRenderer.canvasKit : WebRenderer.notWeb,
    isStandalone: false,
  );
  final web = FakeWebPlatform(
    buildInfoJson: jsonEncode(_build(remoteSha ?? _localSha, 43).toJson()),
  );
  final module = FakeAppModule(
    id: 'core',
    hiddenDelay: const Duration(milliseconds: 200),
  );
  final bootstrapper = AppBootstrapper(
    modules: [module],
    buildInfo: info,
    runtimeInfo: runtime,
    web: web,
    errorLog: AppErrorLog(),
    ownerId: kLocalOwnerId,
  );
  await bootstrapper.run();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        buildInfoProvider.overrideWithValue(info),
        runtimeInfoProvider.overrideWithValue(runtime),
        webPlatformProvider.overrideWithValue(web),
        appBootstrapperProvider.overrideWithValue(bootstrapper),
        updateCheckConfigProvider.overrideWithValue(
          const UpdateCheckConfig(initialDelay: Duration(seconds: 1)),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('ko'),
        builder: (context, child) => UpdateBanner(child: child!),
        home: const _Page(),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(UpdateBanner)),
  );
  return _Harness(web, module, container);
}

/// Runs the first check (initialDelay 1 s).
Future<void> _firstCheck(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

void main() {
  testWidgets('no banner while unknown or up to date', (tester) async {
    final h = await _pump(tester);
    expect(h.status, isA<UpdateUnknown>());
    expect(find.byType(MaterialBanner), findsNothing);
    await _firstCheck(tester);
    expect(h.status, isA<UpdateUpToDate>());
    expect(find.byType(MaterialBanner), findsNothing);
    expect(find.text('page top inset 24.0'), findsOneWidget);
  });

  testWidgets('no banner when disabled (local build, off the web)', (
    tester,
  ) async {
    for (final (local, isWeb) in [
      (BuildInfo.local, true),
      (_build(_localSha, 42), false),
    ]) {
      final h = await _pump(
        tester,
        remoteSha: _remoteSha,
        local: local,
        isWeb: isWeb,
      );
      await _firstCheck(tester);
      expect(h.status, isA<UpdateDisabled>());
      expect(find.byType(MaterialBanner), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('UpdateAvailable → banner with the build number and short sha, '
      'two plain text buttons, page state kept, top inset moves to the '
      'banner', (tester) async {
    final h = await _pump(tester, remoteSha: _remoteSha);
    expect(_Page.created, 1);
    await _firstCheck(tester);
    expect(h.status, isA<UpdateAvailable>());

    expect(find.byType(MaterialBanner), findsOneWidget);
    expect(find.text(_bannerText), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MaterialBanner),
        matching: find.byType(TextButton),
      ),
      findsNWidgets(2),
    );
    expect(find.widgetWithText(TextButton, '나중에'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '새로고침'), findsOneWidget);
    // Above the Navigator: no Overlay around the banner, no tooltips.
    expect(
      find.ancestor(
        of: find.byType(MaterialBanner),
        matching: find.byType(Overlay),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(MaterialBanner),
        matching: find.byType(Tooltip),
      ),
      findsNothing,
    );

    // The banner sits below the 24 pt inset; the page no longer gets it.
    expect(tester.getTopLeft(find.byType(MaterialBanner)).dy, 24);
    expect(find.text('page top inset 0.0'), findsOneWidget);
    final bannerBottom = tester.getBottomLeft(find.byType(MaterialBanner)).dy;
    expect(tester.getTopLeft(find.byType(Scaffold)).dy, bannerBottom);
    // The page below was not rebuilt from scratch.
    expect(_Page.created, 1);
  });

  testWidgets('[나중에] → dismissed, banner gone, page state kept', (
    tester,
  ) async {
    final h = await _pump(tester, remoteSha: _remoteSha);
    await _firstCheck(tester);
    await tester.tap(find.widgetWithText(TextButton, '나중에'));
    await tester.pump();
    expect(h.status, isA<UpdateDismissed>());
    expect(find.byType(MaterialBanner), findsNothing);
    expect(find.text('page top inset 24.0'), findsOneWidget);
    expect(_Page.created, 1);
    expect(h.web.reloadCount, 0);

    // The same build stays hidden on the next check.
    await tester.pump(const Duration(minutes: 10));
    await tester.pump();
    expect(h.web.fetchCount, 2);
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('[새로고침] → flush (notifyAppHidden) then reload', (tester) async {
    final h = await _pump(tester, remoteSha: _remoteSha);
    await _firstCheck(tester);
    await tester.tap(find.widgetWithText(TextButton, '새로고침'));
    await tester.pump();
    expect(h.module.hiddenCalls, 1);
    expect(h.web.reloadCount, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(h.web.reloadCount, 1);
  });

  test('banner text is 해요체 (계약 7.4.5)', () {
    final text = AppStrings.updateAvailable(43, 'b2c3d4e');
    expect(text, _bannerText);
    final plain = text.replaceAll(RegExp(r'\s*\([^)]*\)'), '');
    expect(plain, '새 버전이 나왔어요. 새로고침하면 적용돼요.');
    for (final sentence in plain.split(RegExp(r'(?<=\.)\s+'))) {
      expect(sentence, endsWith('요.'), reason: sentence);
    }
    expect(AppStrings.later, '나중에');
    expect(AppStrings.reload, '새로고침');
  });
}
