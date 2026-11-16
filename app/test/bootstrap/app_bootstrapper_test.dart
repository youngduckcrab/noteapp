// AppBootstrapper, AppModuleContext, StaticOverridesModule
// (docs/plans/01-infra.md 4.5.4, 6.4, 9.1). Time is fake (fake_async).
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/bootstrap/idle_tasks.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/features/app_features.dart';
import 'package:noteapp/src/providers.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:noteapp/src/settings/settings_sections.dart';

import '../fakes/counting_note_store.dart';
import '../fakes/fake_app_module.dart';
import '../fakes/fake_web_platform.dart';

final _a = Provider<String>((ref) => 'a default', name: '_testA');
final _b = Provider<String>((ref) => 'b default', name: '_testB');
final _c = Provider<String>((ref) => 'c default', name: '_testC');

final class _Harness {
  _Harness(
    List<AppModule> modules, {
    FakeWebPlatform? web,
    AppFeatures features = AppFeatures.all,
  }) : web = web ?? FakeWebPlatform() {
    bootstrapper = AppBootstrapper(
      modules: modules,
      buildInfo: BuildInfo.local,
      runtimeInfo: RuntimeInfo.detect(this.web),
      web: this.web,
      errorLog: errorLog,
      ownerId: kLocalOwnerId,
      features: features,
    );
  }

  final FakeWebPlatform web;
  final AppErrorLog errorLog = AppErrorLog();
  late final AppBootstrapper bootstrapper;
}

/// Starts [future] and returns a getter for its value once it completed.
T? Function() _watch<T>(Future<T> future) {
  T? value;
  unawaited(future.then((v) => value = v));
  return () => value;
}

BootstrapSuccess _success(BootstrapResult? result) =>
    result! as BootstrapSuccess;

BootstrapFailure _failure(BootstrapResult? result) =>
    result! as BootstrapFailure;

// 1차 six + appFeaturesProvider + initialAppearanceProvider (v2.14-ui) +
// developerModeOverride (v2.14-ui) + shellContributionsProvider (2nd round).
const _shellOverrideCount = 10;

void main() {
  group('AppModuleContext', () {
    AppModuleContext context() => AppModuleContext(
      buildInfo: BuildInfo.local,
      runtimeInfo: RuntimeInfo.detect(FakeWebPlatform()),
      web: FakeWebPlatform(),
      ownerId: kLocalOwnerId,
      errorLog: AppErrorLog(),
    );

    test('publish / require / maybe by type', () {
      final ctx = context();
      expect(ctx.maybe<String>(), isNull);
      expect(ctx.require<String>, throwsStateError);

      ctx.publish<String>('value');
      expect(ctx.require<String>(), 'value');
      expect(ctx.maybe<String>(), 'value');
      expect(ctx.maybe<int>(), isNull);
      expect(() => ctx.publish<String>('again'), throwsStateError);
      expect(ctx.require<String>(), 'value');
    });

    test('recordOutcome / outcomeOf / isStarted', () {
      final ctx = context();
      expect(ctx.outcomeOf('core'), isNull);
      expect(ctx.isStarted('core'), isFalse);

      ctx
        ..recordOutcome('core', StartupStepOutcome.ok)
        ..recordOutcome('pdf', StartupStepOutcome.failedNonCritical);
      expect(ctx.outcomeOf('core'), StartupStepOutcome.ok);
      expect(ctx.isStarted('core'), isTrue);
      expect(ctx.outcomeOf('pdf'), StartupStepOutcome.failedNonCritical);
      expect(ctx.isStarted('pdf'), isFalse);
      expect(
        () => ctx.recordOutcome('core', StartupStepOutcome.timedOut),
        throwsStateError,
      );
    });
  });

  test('StaticOverridesModule: overrides only, 1 s timeout, critical', () {
    final override = _a.overrideWithValue('static');
    final module = StaticOverridesModule(
      id: 'wiring',
      label: '연결하는 중',
      overrides: [override],
    );
    expect(module.id, 'wiring');
    expect(module.label, '연결하는 중');
    expect(module.critical, isTrue);
    expect(module.startTimeout, const Duration(seconds: 1));
    expect(module.overrides(), [same(override)]);
    expect(module.resetLocalData, isNull);
    expect(module.canResetAfter(StateError('x')), isFalse);
  });

  group('run', () {
    test('starts modules in order; labels change; shell overrides first, '
        'then module overrides in module order', () {
      fakeAsync((async) {
        final events = <String>[];
        final oa = _a.overrideWithValue('A');
        final ob = _b.overrideWithValue('B');
        final oc = _c.overrideWithValue('C');
        final modules = [
          FakeAppModule(
            id: 'a',
            label: 'A 여는 중',
            overrides: [oa],
            startDelay: const Duration(milliseconds: 100),
            events: events,
          ),
          FakeAppModule(id: 'b', label: 'B 여는 중', events: events),
          FakeAppModule(
            id: 'c',
            label: 'C 여는 중',
            overrides: [ob, oc],
            events: events,
          ),
        ];
        final h = _Harness(modules);
        final labels = <String>[];
        h.bootstrapper.stageLabel.addListener(
          () => labels.add(h.bootstrapper.stageLabel.value),
        );

        final result = _watch(h.bootstrapper.run());
        async.flushMicrotasks();
        expect(events, ['start:a']);
        expect(result(), isNull);

        async.elapse(const Duration(milliseconds: 100));
        expect(events, [
          'start:a',
          'started:a',
          'start:b',
          'started:b',
          'start:c',
          'started:c',
        ]);
        expect(labels, ['A 여는 중', 'B 여는 중', 'C 여는 중']);

        final success = _success(result());
        expect(success.startedModules, modules);
        expect(success.overrides, hasLength(_shellOverrideCount + 3));
        expect(success.overrides.skip(_shellOverrideCount), [
          same(oa),
          same(ob),
          same(oc),
        ]);
        expect(modules.map((m) => m.overridesCalls), [1, 1, 1]);
        expect(success.report.steps.map((s) => (s.id, s.outcome, s.error)), [
          ('a', StartupStepOutcome.ok, null),
          ('b', StartupStepOutcome.ok, null),
          ('c', StartupStepOutcome.ok, null),
        ]);
        expect(h.errorLog.totalCount, 0);

        // Shell overrides carry the bootstrapper's own instances.
        final container = ProviderContainer.test(overrides: success.overrides);
        expect(container.read(buildInfoProvider), same(BuildInfo.local));
        expect(container.read(webPlatformProvider), same(h.web));
        expect(
          container.read(runtimeInfoProvider),
          same(h.bootstrapper.runtimeInfo),
        );
        expect(container.read(appErrorLogProvider), same(h.errorLog));
        expect(container.read(startupReportProvider), same(success.report));
        expect(container.read(appBootstrapperProvider), same(h.bootstrapper));
        expect(container.read(appFeaturesProvider), AppFeatures.all);
        expect(container.read(shellContributionsProvider), isEmpty);
        expect(container.read(_a), 'A');
        expect(container.read(_b), 'B');
        expect(container.read(_c), 'C');
      });
    });

    test('each outcome is recorded before the next module starts', () {
      fakeAsync((async) {
        final seen = <String, Object?>{};
        final h = _Harness([
          FakeAppModule(id: 'core'),
          FakeAppModule(
            id: 'pdf',
            critical: false,
            startError: StateError('pdf down'),
          ),
          FakeAppModule(
            id: 'featureWiring',
            onStart: (ctx) {
              seen['core'] = ctx.isStarted('core');
              seen['pdf'] = ctx.isStarted('pdf');
              seen['pdfOutcome'] = ctx.outcomeOf('pdf');
              seen['self'] = ctx.outcomeOf('featureWiring');
            },
          ),
        ]);
        final result = _watch(h.bootstrapper.run());
        async.flushMicrotasks();
        expect(result(), isA<BootstrapSuccess>());
        expect(seen, {
          'core': true,
          'pdf': false,
          'pdfOutcome': StartupStepOutcome.failedNonCritical,
          'self': null,
        });
      });
    });

    test('critical failure: started modules stop in reverse order, the rest '
        'never starts, BootstrapFailure', () {
      fakeAsync((async) {
        final events = <String>[];
        final error = StateError('b broke');
        final modules = [
          FakeAppModule(id: 'a', events: events),
          FakeAppModule(id: 'x', events: events),
          FakeAppModule(
            id: 'b',
            label: 'B 여는 중',
            startError: error,
            events: events,
          ),
          FakeAppModule(id: 'c', events: events),
        ];
        final h = _Harness(modules);
        final result = _watch(h.bootstrapper.run());
        async.flushMicrotasks();

        final failure = _failure(result());
        expect(events, [
          'start:a',
          'started:a',
          'start:x',
          'started:x',
          'start:b',
          'stop:x',
          'stop:a',
        ]);
        expect(failure.moduleId, 'b');
        expect(failure.moduleLabel, 'B 여는 중');
        expect(failure.error, same(error));
        expect(failure.resetLocalData, isNull);
        expect(failure.userMessage, isNotEmpty);
        expect(failure.report.steps.map((s) => (s.id, s.outcome)), [
          ('a', StartupStepOutcome.ok),
          ('x', StartupStepOutcome.ok),
          ('b', StartupStepOutcome.failedCritical),
        ]);
        expect(failure.report.steps.last.error, same(error));
        expect(modules.last.started, 0);
        expect(h.errorLog.records.single.source, AppErrorSource.bootstrap);
        expect(h.errorLog.records.single.fatal, isTrue);

        // shutdown() later does not stop them a second time.
        final done = _watch(h.bootstrapper.shutdown().then((_) => true));
        async.flushMicrotasks();
        expect(done(), isTrue);
        expect(modules.map((m) => m.stopped), [1, 1, 0, 0]);
      });
    });

    test(
      'resetLocalData is offered only when canResetAfter(error) is true',
      () {
        fakeAsync((async) {
          Future<void> reset() async {}
          final error = StateError('corrupt');

          BootstrapFailure failWith({required bool resettable}) {
            final module = FakeAppModule(
              id: 'core',
              startError: error,
              resetLocalData: reset,
              resettable: resettable,
            );
            final result = _watch(_Harness([module]).bootstrapper.run());
            async.flushMicrotasks();
            expect(module.resetQueries, [same(error)]);
            return _failure(result());
          }

          expect(failWith(resettable: true).resetLocalData, same(reset));
          expect(failWith(resettable: false).resetLocalData, isNull);

          // No reset function: canResetAfter is not even asked.
          final plain = FakeAppModule(
            id: 'core',
            startError: error,
            resettable: true,
          );
          final result = _watch(_Harness([plain]).bootstrapper.run());
          async.flushMicrotasks();
          expect(_failure(result()).resetLocalData, isNull);
        });
      },
    );

    test('non-critical failure: success, logged, overrides left out', () {
      fakeAsync((async) {
        final oa = _a.overrideWithValue('A');
        final ob = _b.overrideWithValue('B');
        final pdf = FakeAppModule(
          id: 'pdf',
          critical: false,
          startError: StateError('pdf down'),
          overrides: [ob],
        );
        final h = _Harness([
          FakeAppModule(id: 'core', overrides: [oa]),
          pdf,
          FakeAppModule(id: 'featureWiring'),
        ]);
        final result = _watch(h.bootstrapper.run());
        async.flushMicrotasks();

        final success = _success(result());
        expect(success.overrides.skip(_shellOverrideCount), [same(oa)]);
        expect(pdf.overridesCalls, 0);
        expect(success.startedModules.map((m) => m.id), [
          'core',
          'featureWiring',
        ]);
        expect(
          success.report.steps[1].outcome,
          StartupStepOutcome.failedNonCritical,
        );
        expect(success.report.steps[1].error, isA<StateError>());
        final record = h.errorLog.records.single;
        expect(record.source, AppErrorSource.module);
        expect(record.summary, contains('pdf down'));
        expect(record.fatal, isFalse);
      });
    });

    test('critical timeout: timedOut step, onStartAbandoned once, failure '
        'with a TimeoutException and the module label in the message', () {
      fakeAsync((async) {
        final gate = Completer<void>();
        final core = FakeAppModule(
          id: 'core',
          label: '노트 저장소 여는 중',
          startTimeout: const Duration(seconds: 20),
          gate: gate,
        );
        final h = _Harness([core, FakeAppModule(id: 'later')]);
        final result = _watch(h.bootstrapper.run());

        async.elapse(const Duration(seconds: 19));
        expect(result(), isNull);
        expect(core.abandonedCalls, 0);

        async.elapse(const Duration(seconds: 1));
        final failure = _failure(result());
        expect(failure.moduleId, 'core');
        expect(failure.error, isA<TimeoutException>());
        expect(failure.userMessage, contains('노트 저장소 여는 중'));
        expect(
          failure.report.steps.single.outcome,
          StartupStepOutcome.timedOut,
        );
        expect(core.abandonedCalls, 1);
        expect(core.overridesCalls, 0);

        // The late completion changes nothing.
        gate.complete();
        async.flushMicrotasks();
        expect(core.overridesCalls, 0);
        expect(core.abandonedCalls, 1);
        expect(failure.report.steps, hasLength(1));
      });
    });

    test('non-critical timeout: success, timedOut step, abandoned once', () {
      fakeAsync((async) {
        final pdf = FakeAppModule(
          id: 'pdf',
          critical: false,
          gate: Completer<void>(),
          overrides: [_b.overrideWithValue('B')],
        );
        final h = _Harness([pdf, FakeAppModule(id: 'featureWiring')]);
        final result = _watch(h.bootstrapper.run());
        async.elapse(const Duration(seconds: 10));

        final success = _success(result());
        expect(success.report.steps.first.outcome, StartupStepOutcome.timedOut);
        expect(success.report.steps.first.error, isA<TimeoutException>());
        expect(success.overrides, hasLength(_shellOverrideCount));
        expect(pdf.abandonedCalls, 1);
        expect(h.errorLog.records.single.source, AppErrorSource.module);
      });
    });

    test('isSlow turns true after 3 s of one stage and resets at the next', () {
      fakeAsync((async) {
        final h = _Harness([
          FakeAppModule(id: 'slow', startDelay: const Duration(seconds: 4)),
          FakeAppModule(id: 'fast', startDelay: const Duration(seconds: 2)),
        ]);
        final slowValues = <bool>[];
        h.bootstrapper.isSlow.addListener(
          () => slowValues.add(h.bootstrapper.isSlow.value),
        );
        unawaited(h.bootstrapper.run());

        async.elapse(const Duration(milliseconds: 2999));
        expect(h.bootstrapper.isSlow.value, isFalse);
        async.elapse(const Duration(milliseconds: 1));
        expect(h.bootstrapper.isSlow.value, isTrue);
        async.elapse(const Duration(seconds: 1));
        expect(h.bootstrapper.stageLabel.value, 'fast 준비하는 중');
        expect(h.bootstrapper.isSlow.value, isFalse);
        async.elapse(const Duration(seconds: 2));
        expect(h.bootstrapper.isSlow.value, isFalse);
        expect(slowValues, [true, false]);
      });
    });

    test('run() twice returns the same future; modules start once', () {
      fakeAsync((async) {
        final module = FakeAppModule(id: 'core');
        final h = _Harness([module]);
        final first = h.bootstrapper.run();
        final second = h.bootstrapper.run();
        expect(identical(first, second), isTrue);
        async.flushMicrotasks();
        expect(module.started, 1);
      });
    });

    test('report: storage is the published NoteStore.storageInfo, '
        'sinceNavigationStart from the web platform; no persist-related '
        'store calls', () {
      fakeAsync((async) {
        const info = StorageInfo(
          backend: StorageBackend.webOpfsShared,
          persistGranted: true,
        );
        final store = CountingNoteStore(
          inner: createFakeNoteStore(storageInfo: info),
        );
        final h = _Harness([
          FakeAppModule(
            id: 'core',
            onStart: (ctx) => ctx.publish<NoteStore>(store),
          ),
        ], web: FakeWebPlatform()..millisecondsSinceNavigationStart = 1234.5);
        final result = _watch(h.bootstrapper.run());
        async.flushMicrotasks();

        final report = _success(result()).report;
        expect(report.storage, same(info));
        expect(
          report.sinceNavigationStart,
          const Duration(microseconds: 1234500),
        );
        expect(report.bootstrapElapsed, greaterThanOrEqualTo(Duration.zero));
        expect(store.refreshCount, 0);
        expect(store.flushCount, 0);
        expect(store.closeCount, 0);
      });
    });

    test('report: no store → storage null; no navigation timing → null', () {
      fakeAsync((async) {
        final h = _Harness([
          FakeAppModule(id: 'core'),
        ], web: FakeWebPlatform()..millisecondsSinceNavigationStart = null);
        final result = _watch(h.bootstrapper.run());
        async.flushMicrotasks();
        final report = _success(result()).report;
        expect(report.storage, isNull);
        expect(report.sinceNavigationStart, isNull);
      });
    });
  });

  group('notifyAppHidden', () {
    test('calls started modules in parallel, 500 ms each, logs failures', () {
      fakeAsync((async) {
        final quick = FakeAppModule(
          id: 'quick',
          hiddenDelay: const Duration(milliseconds: 400),
        );
        final stuck = FakeAppModule(
          id: 'stuck',
          hiddenDelay: const Duration(seconds: 5),
        );
        final broken = FakeAppModule(
          id: 'broken',
          hiddenError: StateError('flush failed'),
        );
        final skipped = FakeAppModule(
          id: 'skipped',
          critical: false,
          startError: StateError('not started'),
        );
        final h = _Harness([quick, stuck, broken, skipped]);
        unawaited(h.bootstrapper.run());
        async.flushMicrotasks();
        final logged = h.errorLog.totalCount; // the skipped module

        final done = _watch(h.bootstrapper.notifyAppHidden().then((_) => true));
        async.flushMicrotasks();
        expect([quick, stuck, broken].map((m) => m.hiddenCalls), [1, 1, 1]);
        expect(skipped.hiddenCalls, 0);

        async.elapse(const Duration(milliseconds: 499));
        expect(done(), isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(done(), isTrue);

        final records = h.errorLog.records.skip(logged).toList();
        expect(records, hasLength(2));
        expect(
          records.map((r) => r.source),
          everyElement(AppErrorSource.module),
        );
        expect(
          records.map((r) => r.details),
          containsAll([contains('"broken"'), contains('"stuck"')]),
        );
        async.elapse(const Duration(seconds: 5));
      });
    });

    test('before run() nothing is called', () {
      fakeAsync((async) {
        final module = FakeAppModule(id: 'core');
        final h = _Harness([module]);
        final done = _watch(h.bootstrapper.notifyAppHidden().then((_) => true));
        async.flushMicrotasks();
        expect(done(), isTrue);
        expect(module.hiddenCalls, 0);
      });
    });
  });

  group('shutdown', () {
    test('stops started modules in reverse order, 2 s each', () {
      fakeAsync((async) {
        final events = <String>[];
        final modules = [
          FakeAppModule(id: 'a', events: events),
          FakeAppModule(
            id: 'b',
            events: events,
            stopDelay: const Duration(seconds: 10),
          ),
          FakeAppModule(id: 'c', events: events, stopError: StateError('x')),
        ];
        final h = _Harness(modules);
        unawaited(h.bootstrapper.run());
        async.flushMicrotasks();
        events.clear();

        final done = _watch(h.bootstrapper.shutdown().then((_) => true));
        async.flushMicrotasks();
        expect(events, ['stop:c', 'stop:b']);
        async.elapse(const Duration(seconds: 2));
        expect(events, ['stop:c', 'stop:b', 'stop:a']);
        async.flushMicrotasks();
        expect(done(), isTrue);
        expect(h.errorLog.records.map((r) => r.details), [
          contains('"c" stop'),
          contains('"b" stop'),
        ]);

        // Again: same future, nothing stopped twice.
        unawaited(h.bootstrapper.shutdown());
        async.elapse(const Duration(seconds: 10));
        expect(modules.map((m) => m.stopped), [1, 1, 1]);
      });
    });

    test('waits for a late-start cleanup that takes 1 s', () {
      fakeAsync((async) {
        final core = FakeAppModule(
          id: 'core',
          startTimeout: const Duration(seconds: 20),
          gate: Completer<void>(),
          abandonDelay: const Duration(seconds: 1),
        );
        final h = _Harness([core]);
        unawaited(h.bootstrapper.run());
        async.elapse(const Duration(seconds: 20));
        expect(core.abandonedCalls, 1);
        final logged = h.errorLog.totalCount;

        final done = _watch(h.bootstrapper.shutdown().then((_) => true));
        async.elapse(const Duration(milliseconds: 999));
        expect(done(), isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(done(), isTrue);
        expect(core.events.last, 'abandoned:core');
        expect(h.errorLog.totalCount, logged);
      });
    });

    test('gives up on a late-start cleanup after 2 s and logs it', () {
      fakeAsync((async) {
        final core = FakeAppModule(
          id: 'core',
          startTimeout: const Duration(seconds: 20),
          gate: Completer<void>(),
          abandonDelay: const Duration(seconds: 5),
        );
        final h = _Harness([core]);
        unawaited(h.bootstrapper.run());
        // The cleanup started at 20 s and ends at 25 s.
        async.elapse(const Duration(seconds: 20));
        final logged = h.errorLog.totalCount;

        final done = _watch(h.bootstrapper.shutdown().then((_) => true));
        async.elapse(const Duration(milliseconds: 1999));
        expect(done(), isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(done(), isTrue);
        expect(core.events.last, 'abandon:core');
        expect(h.errorLog.totalCount, logged + 1);
        expect(h.errorLog.records.last.source, AppErrorSource.module);
        expect(h.errorLog.records.last.summary, contains('TimeoutException'));
        async.elapse(const Duration(seconds: 5));
      });
    });

    test('called during run(): waits for run, then stops', () {
      fakeAsync((async) {
        final events = <String>[];
        final h = _Harness([
          FakeAppModule(
            id: 'core',
            startDelay: const Duration(seconds: 1),
            events: events,
          ),
        ]);
        final result = _watch(h.bootstrapper.run());
        final done = _watch(h.bootstrapper.shutdown().then((_) => true));
        async.flushMicrotasks();
        expect(done(), isNull);
        async.elapse(const Duration(seconds: 1));
        expect(result(), isA<BootstrapSuccess>());
        expect(done(), isTrue);
        expect(events, ['start:core', 'started:core', 'stop:core']);
      });
    });
  });

  group('2nd round (01-infra 4.6.2, 6.4)', () {
    AppIdleTask task(String id, {int priority = 10}) =>
        AppIdleTask(id: id, priority: priority, run: (_) async {});

    test('isEnabled false → skipped: no start, no overrides, no idle tasks, '
        'no contribution, no error record', () {
      fakeAsync((async) {
        final media = FakeAppModule(
          id: 'media',
          critical: false,
          enabled: (_) async => false,
          overrides: [_b.overrideWithValue('B')],
          idleTasks: [task('media.recoverDrafts', priority: 0)],
          fallback: const ShellContribution(moduleId: 'media'),
          onStart: (c) =>
              c.contribute(const ShellContribution(moduleId: 'media')),
        );
        final h = _Harness([FakeAppModule(id: 'core'), media]);
        final result = _watch(h.bootstrapper.run());
        async.flushMicrotasks();

        final success = _success(result());
        expect(success.report.steps.map((s) => (s.id, s.outcome, s.error)), [
          ('core', StartupStepOutcome.ok, null),
          ('media', StartupStepOutcome.skipped, null),
        ]);
        expect(media.enabledCalls, 1);
        expect(media.started, 0);
        expect(media.overridesCalls, 0);
        expect(media.idleTasksCalls, 0);
        expect(success.overrides, hasLength(_shellOverrideCount));
        expect(success.idleTasks, isEmpty);
        expect(success.contributions, isEmpty);
        expect(success.startedModules.map((m) => m.id), ['core']);
        expect(h.errorLog.totalCount, 0);
      });
    });

    test('isEnabled throwing or taking > 1 s counts as enabled (logged)', () {
      fakeAsync((async) {
        final throwing = FakeAppModule(
          id: 'a',
          critical: false,
          enabled: (_) async => throw StateError('settings broken'),
        );
        final slow = FakeAppModule(
          id: 'b',
          critical: false,
          enabled: (_) =>
              Future.delayed(const Duration(seconds: 2), () => false),
        );
        final h = _Harness([throwing, slow]);
        final result = _watch(h.bootstrapper.run());
        async.elapse(const Duration(seconds: 1));

        final success = _success(result());
        expect(success.report.steps.map((s) => s.outcome), [
          StartupStepOutcome.ok,
          StartupStepOutcome.ok,
        ]);
        expect([throwing.started, slow.started], [1, 1]);
        expect(h.errorLog.records.map((r) => (r.source, r.details)), [
          (
            AppErrorSource.module,
            'module "a" isEnabled failed; treated as enabled',
          ),
          (
            AppErrorSource.module,
            'module "b" isEnabled failed; treated as enabled',
          ),
        ]);
        async.elapse(const Duration(seconds: 2));
      });
    });

    test('idle tasks: started modules only, module order, idleTasks() once '
        'after overrides()', () {
      fakeAsync((async) {
        final pdf = FakeAppModule(
          id: 'pdf',
          critical: false,
          idleTasks: [task('pdf.searchIndexer')],
        );
        final media = FakeAppModule(
          id: 'media',
          critical: false,
          startError: StateError('no mic'),
          idleTasks: [task('media.recoverDrafts', priority: 0)],
        );
        final recognition = FakeAppModule(
          id: 'recognition',
          critical: false,
          idleTasks: [task('recognition.indexer', priority: 20)],
        );
        final h = _Harness([
          FakeAppModule(id: 'core'),
          pdf,
          media,
          recognition,
        ]);
        final result = _watch(h.bootstrapper.run());
        async.flushMicrotasks();

        final success = _success(result());
        expect(success.idleTasks.map((t) => t.id), [
          'pdf.searchIndexer',
          'recognition.indexer',
        ]);
        expect([pdf, media, recognition].map((m) => m.idleTasksCalls), [
          1,
          0,
          1,
        ]);
        expect(() => success.idleTasks.add(task('x')), throwsUnsupportedError);
      });
    });

    test('a module that contributed and then failed: its contribution is '
        'dropped, its fallback contribution takes the place', () {
      fakeAsync((async) {
        const own = ShellContribution(moduleId: 'media');
        const fallback = ShellContribution(moduleId: 'media');
        final h = _Harness([
          FakeAppModule(
            id: 'recognition',
            critical: false,
            onStart: (c) =>
                c.contribute(const ShellContribution(moduleId: 'recognition')),
          ),
          FakeAppModule(
            id: 'media',
            critical: false,
            startError: StateError('no mic'),
            fallback: fallback,
            onStart: (c) => c.contribute(own),
          ),
          FakeAppModule(
            id: 'pdf',
            critical: false,
            startError: StateError('no pdfium'),
            onStart: (c) =>
                c.contribute(const ShellContribution(moduleId: 'pdf')),
          ),
        ]);
        final result = _watch(h.bootstrapper.run());
        async.flushMicrotasks();

        final success = _success(result());
        expect(success.contributions.map((c) => c.moduleId), [
          'recognition',
          'media',
        ]);
        expect(success.contributions[1], same(fallback));
        final container = ProviderContainer.test(overrides: success.overrides);
        expect(
          container.read(shellContributionsProvider),
          success.contributions,
        );
      });
    });

    test('a skipped module gets no fallback contribution', () {
      fakeAsync((async) {
        final h = _Harness([
          FakeAppModule(
            id: 'media',
            critical: false,
            enabled: (_) async => false,
            fallback: const ShellContribution(moduleId: 'media'),
          ),
        ]);
        final result = _watch(h.bootstrapper.run());
        async.flushMicrotasks();
        expect(_success(result()).contributions, isEmpty);
      });
    });

    test('late contribution after a timeout is ignored and logged once; only '
        'the fallback contribution stays', () {
      fakeAsync((async) {
        late AppModuleContext seen;
        const fallback = ShellContribution(moduleId: 'media');
        final gate = Completer<void>();
        final h = _Harness([
          FakeAppModule(
            id: 'media',
            critical: false,
            startTimeout: const Duration(seconds: 5),
            gate: gate,
            fallback: fallback,
            onStart: (c) => seen = c,
          ),
          FakeAppModule(id: 'featureWiring', critical: false),
        ]);
        final result = _watch(h.bootstrapper.run());
        async.elapse(const Duration(seconds: 5));
        final success = _success(result());
        expect(success.report.steps.first.outcome, StartupStepOutcome.timedOut);
        expect(success.contributions, [same(fallback)]);
        final recordsBefore = h.errorLog.totalCount;

        // The late start finishes and contributes — twice, even.
        gate.complete();
        async.flushMicrotasks();
        seen.contribute(const ShellContribution(moduleId: 'media'));
        seen.contribute(const ShellContribution(moduleId: 'media'));
        expect(seen.contributions, [same(fallback)]);
        expect(success.contributions, [same(fallback)]);
        final late = h.errorLog.records.skip(recordsBefore).toList();
        expect(late.map((r) => (r.source, r.summary)), [
          (AppErrorSource.module, 'late contribution of media ignored'),
        ]);
      });
    });

    test('contribute twice during one start → StateError', () {
      final ctx = AppModuleContext(
        buildInfo: BuildInfo.local,
        runtimeInfo: RuntimeInfo.detect(FakeWebPlatform()),
        web: FakeWebPlatform(),
        ownerId: kLocalOwnerId,
        errorLog: AppErrorLog(),
      );
      ctx.contribute(const ShellContribution(moduleId: 'media'));
      expect(
        () => ctx.contribute(const ShellContribution(moduleId: 'media')),
        throwsStateError,
      );
      // Not visible before the outcome is recorded.
      expect(ctx.contributions, isEmpty);
      ctx.recordOutcome('media', StartupStepOutcome.ok);
      expect(ctx.contributions.map((c) => c.moduleId), ['media']);
    });

    test('features: the build AND the developer menu of the published store; '
        'BootstrapSuccess.features and appFeaturesProvider', () async {
      final store = createFakeNoteStore();
      addTearDown(store.close);
      await store.settings.set(AppFeatureKeys.recognition, false);
      final seen = <AppFeatures>[];
      final h = _Harness([
        FakeAppModule(id: 'core', onStart: (c) => c.publish<NoteStore>(store)),
        FakeAppModule(
          id: 'media',
          critical: false,
          enabled: (c) async {
            seen.add(await c.resolveFeatures());
            return c.featureOn(AppFeature.media);
          },
        ),
      ], features: const AppFeatures(mathEngine: false));
      final success = _success(await h.bootstrapper.run());
      const expected = AppFeatures(recognition: false, mathEngine: false);
      expect(seen, [expected]);
      expect(success.features, expected);
      expect(success.report.steps.last.outcome, StartupStepOutcome.ok);
      final container = ProviderContainer.test(overrides: success.overrides);
      expect(container.read(appFeaturesProvider), expected);
      await h.bootstrapper.shutdown();
    });

    test('features without a store: the build values', () async {
      final h = _Harness([
        FakeAppModule(id: 'x'),
      ], features: const AppFeatures(media: false));
      final success = _success(await h.bootstrapper.run());
      expect(success.features, const AppFeatures(media: false));
      expect(h.errorLog.totalCount, 0);
    });
  });

  group('BootstrapFailure', () {
    BootstrapFailure failure(Object error, {String label = '노트 저장소 여는 중'}) =>
        BootstrapFailure(
          report: const StartupReport(
            steps: [],
            bootstrapElapsed: Duration.zero,
          ),
          moduleId: 'core',
          moduleLabel: label,
          error: error,
          stackTrace: StackTrace.empty,
        );

    test('offersReload only for NoteStoreOpenException(newerSchema)', () {
      for (final reason in NoteStoreOpenFailure.values) {
        expect(
          failure(NoteStoreOpenException(reason, 'x')).offersReload,
          reason == NoteStoreOpenFailure.newerSchema,
          reason: reason.name,
        );
      }
      expect(failure(TimeoutException('t')).offersReload, isFalse);
      expect(failure(StateError('s')).offersReload, isFalse);
    });
  });
}
