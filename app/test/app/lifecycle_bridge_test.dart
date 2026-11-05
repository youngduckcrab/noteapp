// AppLifecycleBridge (docs/plans/01-infra.md 4.5.6, 6.4, 9.1): app hidden →
// AppBootstrapper.notifyAppHidden(), at most once per second.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/app/lifecycle_bridge.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/providers.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:noteapp/src/web/web_platform.dart';

import '../fakes/fake_app_module.dart';
import '../fakes/fake_web_platform.dart';

final class _Harness {
  _Harness(this.module, this.web);

  final FakeAppModule module;
  final FakeWebPlatform web;

  int get hiddenCalls => module.hiddenCalls;
}

Future<_Harness> _pump(WidgetTester tester) async {
  final module = FakeAppModule(id: 'core');
  final web = FakeWebPlatform();
  final bootstrapper = AppBootstrapper(
    modules: [module],
    buildInfo: BuildInfo.local,
    runtimeInfo: RuntimeInfo.detect(web),
    web: web,
    errorLog: AppErrorLog(),
    ownerId: kLocalOwnerId,
  );
  await bootstrapper.run();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appBootstrapperProvider.overrideWithValue(bootstrapper),
        webPlatformProvider.overrideWithValue(web),
      ],
      child: const AppLifecycleBridge(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Text('child'),
        ),
      ),
    ),
  );
  addTearDown(
    () => tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    ),
  );
  return _Harness(module, web);
}

Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  tester.binding.handleAppLifecycleStateChanged(state);
  await tester.pump();
}

void main() {
  testWidgets('shows its child', (tester) async {
    await _pump(tester);
    expect(find.text('child'), findsOneWidget);
  });

  testWidgets('hidden → one call; inactive alone → none', (tester) async {
    final h = await _pump(tester);
    await _lifecycle(tester, AppLifecycleState.inactive);
    expect(h.hiddenCalls, 0);
    await _lifecycle(tester, AppLifecycleState.hidden);
    expect(h.hiddenCalls, 1);
  });

  testWidgets('paused → one call (hide and pause within 1 s count once)', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _lifecycle(tester, AppLifecycleState.inactive);
    await _lifecycle(tester, AppLifecycleState.hidden);
    await _lifecycle(tester, AppLifecycleState.paused);
    expect(h.hiddenCalls, 1);
  });

  testWidgets('detached after the quiet second → another call', (tester) async {
    final h = await _pump(tester);
    await _lifecycle(tester, AppLifecycleState.inactive);
    await _lifecycle(tester, AppLifecycleState.hidden);
    await _lifecycle(tester, AppLifecycleState.paused);
    expect(h.hiddenCalls, 1);
    await tester.pump(const Duration(seconds: 1));
    await _lifecycle(tester, AppLifecycleState.detached);
    expect(h.hiddenCalls, 2);
  });

  testWidgets('web hidden → one call; repeats within 1 s are dropped; '
      'visible never calls', (tester) async {
    final h = await _pump(tester);
    h.web.emitVisibility(WebVisibility.visible);
    await tester.pump();
    expect(h.hiddenCalls, 0);

    h.web.emitVisibility(WebVisibility.hidden);
    await tester.pump();
    expect(h.hiddenCalls, 1);

    await tester.pump(const Duration(milliseconds: 500));
    h.web
      ..emitVisibility(WebVisibility.hidden) // pagehide right after
      ..emitVisibility(WebVisibility.visible);
    await tester.pump(const Duration(milliseconds: 499));
    expect(h.hiddenCalls, 1);

    await tester.pump(const Duration(milliseconds: 1));
    h.web.emitVisibility(WebVisibility.hidden);
    await tester.pump();
    expect(h.hiddenCalls, 2);
  });

  testWidgets('after dispose nothing is called', (tester) async {
    final h = await _pump(tester);
    await tester.pumpWidget(const SizedBox());
    h.web.emitVisibility(WebVisibility.hidden);
    await _lifecycle(tester, AppLifecycleState.inactive);
    await _lifecycle(tester, AppLifecycleState.hidden);
    expect(h.hiddenCalls, 0);
  });
}
