// BootstrapApp: splash → app, startup error screen, retry, reset, reload
// (docs/plans/01-infra.md 4.5.4, 6.4, 9.1). Time is the tester's fake time.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/app/lifecycle_bridge.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/bootstrap/bootstrap_app.dart';
import 'package:noteapp/src/bootstrap/splash_view.dart';
import 'package:noteapp/src/bootstrap/startup_error_screen.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/modules/core_module.dart';
import 'package:noteapp/src/providers.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';

import '../fakes/counting_note_store.dart';
import '../fakes/fake_app_module.dart';
import '../fakes/fake_note_store_opener.dart';
import '../fakes/fake_web_platform.dart';

void _useIpadPortrait(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(2064, 2752)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

/// Creates one bootstrapper per attempt from [plans] (the last plan repeats)
/// and records `create:<n>` in [events].
final class _Attempts {
  _Attempts(this.plans, {FakeWebPlatform? web, List<String>? events})
    : web = web ?? FakeWebPlatform(),
      events = events ?? [];

  final List<List<AppModule> Function()> plans;
  final FakeWebPlatform web;
  final List<String> events;
  final AppErrorLog errorLog = AppErrorLog();
  final List<AppBootstrapper> created = [];

  AppBootstrapper create() {
    final index = created.length;
    final bootstrapper = AppBootstrapper(
      modules: plans[math.min(index, plans.length - 1)](),
      buildInfo: BuildInfo.local,
      runtimeInfo: RuntimeInfo.detect(web),
      web: web,
      errorLog: errorLog,
      ownerId: kLocalOwnerId,
    );
    created.add(bootstrapper);
    events.add('create:${index + 1}');
    return bootstrapper;
  }
}

final _failing = Provider<int>(
  (ref) => throw StateError('provider boom'),
  name: '_failingTestProvider',
);

/// The app after a successful start: shows its attempt's bootstrapper.
class _ProbeApp extends ConsumerWidget {
  const _ProbeApp(this.success);

  final BootstrapSuccess success;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(startupReportProvider);
    return MaterialApp(
      home: Scaffold(body: Text('app ready · ${report.steps.length} steps')),
    );
  }
}

Future<void> _pumpApp(WidgetTester tester, _Attempts attempts) async {
  _useIpadPortrait(tester);
  await tester.pumpWidget(
    BootstrapApp(
      createBootstrapper: attempts.create,
      errorLog: attempts.errorLog,
      appBuilder: _ProbeApp.new,
    ),
  );
}

final Finder _app = find.textContaining('app ready');

ProviderScope _scope(WidgetTester tester) =>
    tester.widget<ProviderScope>(find.byType(ProviderScope));

Future<void> _confirmReset(WidgetTester tester) async {
  await tester.tap(find.text(AppStrings.resetLocalData));
  await tester.pumpAndSettle();
  await tester.tap(find.text(AppStrings.proceed));
  await tester.pumpAndSettle();
  await tester.tap(find.text(AppStrings.erase));
}

void main() {
  testWidgets('splash with the stage label, then the app in a ProviderScope '
      'with the shell overrides', (tester) async {
    final attempts = _Attempts([
      () => [
        FakeAppModule(
          id: 'core',
          label: '노트 저장소 여는 중',
          startDelay: const Duration(seconds: 1),
        ),
      ],
    ]);
    await _pumpApp(tester, attempts);
    await tester.pump();

    expect(find.byType(SplashView), findsOneWidget);
    expect(find.text(AppStrings.appName), findsOneWidget);
    expect(find.text('노트 저장소 여는 중'), findsOneWidget);
    expect(_app, findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byType(SplashView), findsNothing);
    expect(find.text('app ready · 1 steps'), findsOneWidget);
    expect(_scope(tester).key, const ValueKey<int>(0));
    expect(
      find.descendant(
        of: find.byType(ProviderScope),
        matching: find.byType(AppLifecycleBridge),
      ),
      findsOneWidget,
    );

    final container = ProviderScope.containerOf(tester.element(_app));
    expect(
      container.read(appBootstrapperProvider),
      same(attempts.created.single),
    );
    expect(container.read(appErrorLogProvider), same(attempts.errorLog));
    expect(container.read(webPlatformProvider), same(attempts.web));
  });

  testWidgets('a slow stage shows "시간이 걸리고 있어요… (n초)"', (tester) async {
    final attempts = _Attempts([
      () => [FakeAppModule(id: 'core', startDelay: const Duration(seconds: 5))],
    ]);
    await _pumpApp(tester, attempts);
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.textContaining('시간이 걸리고 있어요'), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('시간이 걸리고 있어요… (3초)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('시간이 걸리고 있어요… (4초)'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(_app, findsOneWidget);
  });

  testWidgets('failure → error screen → 다시 시도 → shutdown, then a NEW '
      'bootstrapper → app', (tester) async {
    final events = <String>[];
    final attempts = _Attempts(events: events, [
      () => [
        FakeAppModule(id: 'a', events: events),
        FakeAppModule(id: 'b', startError: StateError('b'), events: events),
      ],
      () => [
        FakeAppModule(id: 'a', events: events),
        FakeAppModule(id: 'b', events: events),
      ],
    ]);
    await _pumpApp(tester, attempts);
    await tester.pumpAndSettle();

    expect(find.byType(StartupErrorScreen), findsOneWidget);
    expect(find.text(AppStrings.startupGeneric), findsOneWidget);
    expect(find.text(AppStrings.resetLocalData), findsNothing);
    expect(attempts.created, hasLength(1));

    await tester.tap(find.text(AppStrings.retry));
    await tester.pump();
    await tester.pump();
    expect(attempts.created, hasLength(2));
    expect(_app, findsOneWidget);
    expect(_scope(tester).key, const ValueKey<int>(1));
    expect(events, [
      'create:1',
      'start:a',
      'started:a',
      'start:b',
      'stop:a', // critical failure stops what started
      'create:2',
      'start:a',
      'started:a',
      'start:b',
      'started:b',
    ]);
  });

  testWidgets('the error screen gets the diagnostic text with the errors', (
    tester,
  ) async {
    final attempts = _Attempts([
      () => [FakeAppModule(id: 'core', startError: StateError('disk gone'))],
    ]);
    await _pumpApp(tester, attempts);
    await tester.pumpAndSettle();

    final screen = tester.widget<StartupErrorScreen>(
      find.byType(StartupErrorScreen),
    );
    expect(screen.failure.moduleId, 'core');
    expect(screen.diagnostics, startsWith('[필기노트 진단 정보]'));
    expect(screen.diagnostics, contains(BuildInfo.local.displayLabel));
    expect(screen.diagnostics, contains('disk gone'));
  });

  testWidgets('resettable failure → two confirms → shutdown → resetLocalData '
      '→ automatic retry', (tester) async {
    final events = <String>[];
    var erased = 0;
    final attempts = _Attempts(events: events, [
      () => [
        FakeAppModule(id: 'a', events: events),
        FakeAppModule(
          id: 'core',
          startError: const NoteStoreOpenException(
            NoteStoreOpenFailure.corrupted,
            'bad page',
          ),
          resettable: true,
          resetLocalData: () async {
            erased++;
            events.add('erase');
          },
          events: events,
        ),
      ],
      () => [FakeAppModule(id: 'core', events: events)],
    ]);
    await _pumpApp(tester, attempts);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.startupCorrupted), findsOneWidget);

    await _confirmReset(tester);
    await tester.pump();
    await tester.pump();
    expect(erased, 1);
    expect(_app, findsOneWidget);
    expect(events.sublist(events.indexOf('stop:a')), [
      'stop:a',
      'erase',
      'create:2',
      'start:core',
      'started:core',
    ]);
  });

  testWidgets('a failed reset stays on the error screen, shows the message '
      'and logs it', (tester) async {
    final attempts = _Attempts([
      () => [
        FakeAppModule(
          id: 'core',
          startError: const NoteStoreOpenException(
            NoteStoreOpenFailure.migrationFailed,
            'v3 → v4',
          ),
          resettable: true,
          resetLocalData: () async => throw StateError('store still open'),
        ),
      ],
      () => [FakeAppModule(id: 'core')],
    ]);
    await _pumpApp(tester, attempts);
    await tester.pumpAndSettle();
    final logged = attempts.errorLog.totalCount;

    await _confirmReset(tester);
    await tester.pumpAndSettle();
    expect(find.byType(StartupErrorScreen), findsOneWidget);
    expect(find.text(AppStrings.resetFailed), findsOneWidget);
    expect(attempts.created, hasLength(1));
    expect(attempts.errorLog.totalCount, logged + 1);
    final record = attempts.errorLog.records.last;
    expect(record.source, AppErrorSource.bootstrap);
    expect(record.details, 'resetLocalData failed');
    expect(record.summary, contains('store still open'));

    // Retry still works.
    await tester.tap(find.text(AppStrings.retry));
    await tester.pump();
    await tester.pump();
    expect(_app, findsOneWidget);
  });

  testWidgets('timeout → error screen → late result → 다시 시도 waits for the '
      'late cleanup before the next bootstrapper', (tester) async {
    final events = <String>[];
    final gate = Completer<void>();
    final attempts = _Attempts(events: events, [
      () => [
        FakeAppModule(
          id: 'core',
          label: '노트 저장소 여는 중',
          startTimeout: const Duration(seconds: 20),
          gate: gate,
          abandonDelay: const Duration(seconds: 1),
          events: events,
        ),
      ],
      () => [FakeAppModule(id: 'core', events: events)],
    ]);
    await _pumpApp(tester, attempts);
    await tester.pump(const Duration(seconds: 20));
    await tester.pump();
    expect(
      find.text(AppStrings.startupTimedOut('노트 저장소 여는 중')),
      findsOneWidget,
    );
    expect(find.text(AppStrings.resetLocalData), findsNothing);

    // The late result arrives, then the user retries at once.
    gate.complete();
    await tester.tap(find.text(AppStrings.retry));
    await tester.pump();
    expect(attempts.created, hasLength(1));
    expect(find.byType(SplashView), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(attempts.created, hasLength(2));
    expect(
      events.indexOf('abandoned:core'),
      lessThan(events.indexOf('create:2')),
    );
    expect(_app, findsOneWidget);
  });

  testWidgets('CoreModule: timeout → error screen → 다시 시도 → the late store '
      'is closed before the next open (openCount == 2 after closeCount == '
      '1)', (tester) async {
    final gate = Completer<NoteStore>();
    final late = CountingNoteStore();
    final store = CountingNoteStore();
    final first = fakeOpenNoteStore(gate: gate);
    var openCount = 0;
    int? lateClosesAtSecondOpen;
    final attempts = _Attempts([
      () => [
        CoreModule(
          open: (config) {
            openCount++;
            return first(config);
          },
        ),
      ],
      () => [
        CoreModule(
          open: (config) async {
            openCount++;
            lateClosesAtSecondOpen = late.closeCount;
            return store;
          },
        ),
      ],
    ]);
    await _pumpApp(tester, attempts);
    await tester.pump(const Duration(seconds: 20));
    await tester.pump();
    expect(
      find.text(AppStrings.startupTimedOut(CoreModule().label)),
      findsOneWidget,
    );
    expect(find.text(AppStrings.resetLocalData), findsNothing);

    await tester.tap(find.text(AppStrings.retry));
    await tester.pump(const Duration(milliseconds: 500));
    expect(attempts.created, hasLength(1));
    expect(openCount, 1);

    // The late store arrives while shutdown waits for the cleanup.
    gate.complete(late);
    await tester.pump();
    await tester.pump();
    expect(late.closeCount, 1);
    expect(attempts.created, hasLength(2));
    expect(openCount, 2);
    expect(lateClosesAtSecondOpen, 1);
    await tester.pump();
    expect(_app, findsOneWidget);
    expect(late.flushCount, 0);
    expect(store.closeCount, 0);
  });

  group('reload', () {
    List<AppModule> newerSchema() => [
      FakeAppModule(
        id: 'core',
        startError: const NoteStoreOpenException(
          NoteStoreOpenFailure.newerSchema,
          'schema 9',
        ),
        resettable: false,
        resetLocalData: () async {},
      ),
    ];

    testWidgets('newerSchema on the web offers 새로고침, not reset', (
      tester,
    ) async {
      final attempts = _Attempts([newerSchema]);
      await _pumpApp(tester, attempts);
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.startupNewerSchema), findsOneWidget);
      expect(find.text(AppStrings.resetLocalData), findsNothing);

      await tester.tap(find.text(AppStrings.reload));
      expect(attempts.web.reloadCount, 1);
    });

    testWidgets('off the web there is no 새로고침', (tester) async {
      final attempts = _Attempts([
        newerSchema,
      ], web: FakeWebPlatform(isSupported: false));
      await _pumpApp(tester, attempts);
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.reload), findsNothing);
    });
  });

  testWidgets('provider failures in the app reach the error log', (
    tester,
  ) async {
    final attempts = _Attempts([
      () => [FakeAppModule(id: 'core')],
    ]);
    _useIpadPortrait(tester);
    await tester.pumpWidget(
      BootstrapApp(
        createBootstrapper: attempts.create,
        errorLog: attempts.errorLog,
        appBuilder: (success) => Consumer(
          builder: (context, ref, _) {
            try {
              ref.read(_failing);
            } on Object {
              // Logged by AppProviderObserver.
            }
            return const Directionality(
              textDirection: TextDirection.ltr,
              child: Text('app ready'),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(_app, findsOneWidget);
    final record = attempts.errorLog.records.single;
    expect(record.source, AppErrorSource.provider);
    expect(record.summary, contains('provider boom'));
  });

  testWidgets('disposing BootstrapApp shuts the bootstrapper down', (
    tester,
  ) async {
    final events = <String>[];
    final attempts = _Attempts(events: events, [
      () => [FakeAppModule(id: 'core', events: events)],
    ]);
    await _pumpApp(tester, attempts);
    await tester.pump();
    await tester.pump();
    expect(_app, findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(events.last, 'stop:core');
  });

  testWidgets('runNoteApp runs BootstrapApp with the given bootstrapper and '
      'installs the global error handlers', (tester) async {
    final flutterOnError = FlutterError.onError;
    final platformOnError = PlatformDispatcher.instance.onError;
    final errorWidgetBuilder = ErrorWidget.builder;
    void restore() {
      FlutterError.onError = flutterOnError;
      PlatformDispatcher.instance.onError = platformOnError;
      ErrorWidget.builder = errorWidgetBuilder;
    }

    try {
      final attempts = _Attempts([
        () => [FakeAppModule(id: 'core', startError: StateError('no store'))],
      ]);
      _useIpadPortrait(tester);
      await runNoteApp(createBootstrapper: attempts.create);
      expect(FlutterError.onError, isNot(same(flutterOnError)));
      expect(PlatformDispatcher.instance.onError, isNot(same(platformOnError)));
      await tester.pump();
      await tester.pump();
      expect(find.byType(BootstrapApp), findsOneWidget);
      expect(find.byType(StartupErrorScreen), findsOneWidget);
      expect(attempts.created, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    } finally {
      restore();
    }
  });
}
