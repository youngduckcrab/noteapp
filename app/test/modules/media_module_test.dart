// MediaModule (docs/plans/m5-7/01-infra.md 4.6.4, 6.4, 6.6, 6.7; contract
// 7.2.12 / 7.3.3 — recording only, D17). R2-B8a: start, contribution,
// fallback contribution, onStartAbandoned, switched off → nothing, the two
// idle tasks registered. Draft recovery and the leave guard bodies: J7.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:feature_editor/feature_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_io/media_io.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/bootstrap/idle_tasks.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/features/app_features.dart';
import 'package:noteapp/src/modules/media_module.dart';
import 'package:noteapp/src/modules/media_wiring.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';

import '../fakes/fake_app_module.dart';
import '../fakes/fake_web_platform.dart';

final _marker = Provider<String>((ref) => 'default', name: '_mediaTestMarker');

Widget _panel(BuildContext context, EditorPanelContext panel) =>
    const SizedBox();

final class _Calls {
  final List<MediaIoConfig> initialized = [];
  final List<MediaIoConfig?> overrides = [];
  final Override override = _marker.overrideWithValue('media');
}

MediaModule _media(
  _Calls calls, {
  Future<void> Function()? initialize,
  MediaIoConfig config = const MediaIoConfig(),
}) => MediaModule(
  initialize: ({MediaIoConfig config = const MediaIoConfig()}) async {
    calls.initialized.add(config);
    await initialize?.call();
  },
  mediaOverrides: ({MediaIoConfig? config}) {
    calls.overrides.add(config);
    return [calls.override];
  },
  recordingPanel: _panel,
  config: config,
);

AppBootstrapper _bootstrapper(
  List<AppModule> modules,
  AppErrorLog log, {
  AppFeatures features = AppFeatures.all,
}) {
  final web = FakeWebPlatform();
  return AppBootstrapper(
    modules: modules,
    buildInfo: BuildInfo.local,
    runtimeInfo: RuntimeInfo.detect(web),
    web: web,
    errorLog: log,
    ownerId: kLocalOwnerId,
    features: features,
  );
}

/// A 'core' that publishes [store] (resolveFeatures reads its settings).
FakeAppModule _core(NoteStore store) =>
    FakeAppModule(id: 'core', onStart: (c) => c.publish<NoteStore>(store));

void main() {
  test('id, label, non-critical, 5 s timeout; default arguments are the '
      'media_io functions', () {
    final module = MediaModule();
    expect(MediaModule.moduleId, 'media');
    expect(module.id, 'media');
    expect(module.label, '녹음 준비 중');
    expect(module.critical, isFalse);
    expect(module.startTimeout, const Duration(seconds: 5));
    expect(module.fallbackContribution()!.recordingPanel, mediaRecordingPanel);
  });

  test('start: initialize(config) once, then one contribution — the '
      'recording panel and the media dev section; overrides = '
      'mediaOverrides(config)', () async {
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final calls = _Calls();
    const config = MediaIoConfig(bitRate: 96000);
    final media = _media(calls, config: config);
    final log = AppErrorLog();
    final bootstrapper = _bootstrapper([_core(store), media], log);
    addTearDown(bootstrapper.shutdown);
    final success = await bootstrapper.run() as BootstrapSuccess;

    expect(success.report.steps.last.outcome, StartupStepOutcome.ok);
    expect(calls.initialized, [config]);
    expect(calls.overrides, [config]);
    expect(success.overrides, contains(same(calls.override)));
    final contribution = success.contributions.single;
    expect(contribution.moduleId, 'media');
    expect(contribution.recordingPanel, _panel);
    expect(contribution.devOverlaySections, [mediaDevOverlaySection]);
    expect(contribution.selectionMenuItems, isEmpty);
    expect(contribution.insertMenuItems, isEmpty);
    expect(contribution.settingsSections, isEmpty);
    expect(log.totalCount, 0);
  });

  test('idle tasks: media.leaveGuard (immediate) and media.recoverDrafts '
      '(data protection, 3 s)', () {
    final tasks = MediaModule().idleTasks();
    expect(tasks.map((t) => (t.id, t.priority, t.immediate)), [
      ('media.leaveGuard', AppIdlePriority.dataProtection, true),
      ('media.recoverDrafts', AppIdlePriority.dataProtection, false),
    ]);
    expect(tasks.last.delay, const Duration(seconds: 3));
  });

  test('start failed: no overrides, no idle tasks; the fallback contribution '
      '(recording panel only) stays — the panel reads the default '
      'UnsupportedAudioRecorder', () async {
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final calls = _Calls();
    final log = AppErrorLog();
    final bootstrapper = _bootstrapper([
      _core(store),
      _media(calls, initialize: () async => throw StateError('no codec')),
    ], log);
    addTearDown(bootstrapper.shutdown);
    final success = await bootstrapper.run() as BootstrapSuccess;

    expect(
      success.report.steps.last.outcome,
      StartupStepOutcome.failedNonCritical,
    );
    expect(calls.overrides, isEmpty);
    expect(success.idleTasks, isEmpty);
    final contribution = success.contributions.single;
    expect(contribution.recordingPanel, _panel);
    expect(contribution.devOverlaySections, isEmpty);
    final container = ProviderContainer.test(overrides: success.overrides);
    expect(container.read(_marker), 'default');
    expect(
      container.read(audioRecorderServiceProvider),
      isA<UnsupportedAudioRecorder>(),
    );
    expect(log.records.single.source, AppErrorSource.module);
  });

  test('start past 5 s: timedOut, fallback only; the late start\'s '
      'contribution is dropped and onStartAbandoned logs "media started '
      'late — ignored"', () {
    fakeAsync((async) {
      final store = createFakeNoteStore();
      final calls = _Calls();
      final gate = Completer<void>();
      final log = AppErrorLog();
      final bootstrapper = _bootstrapper([
        _core(store),
        _media(calls, initialize: () => gate.future),
      ], log);
      BootstrapSuccess? success;
      unawaited(
        bootstrapper.run().then((r) => success = r as BootstrapSuccess),
      );
      async.elapse(const Duration(seconds: 5));
      expect(success!.report.steps.last.outcome, StartupStepOutcome.timedOut);
      expect(success!.contributions.single.devOverlaySections, isEmpty);
      expect(calls.overrides, isEmpty);

      gate.complete();
      async.flushMicrotasks();
      expect(log.records.map((r) => r.summary), [
        startsWith('TimeoutException'),
        'late contribution of media ignored',
        'media started late — ignored',
      ]);
      expect(success!.contributions, hasLength(1));
      unawaited(bootstrapper.shutdown());
      async.elapse(const Duration(seconds: 3));
      unawaited(store.close());
      async.flushMicrotasks();
    });
  });

  test('a start that never finishes: onStartAbandoned gives up after 10 s '
      'without a record', () {
    fakeAsync((async) {
      final calls = _Calls();
      final log = AppErrorLog();
      final media = _media(calls, initialize: () => Completer<void>().future);
      final bootstrapper = _bootstrapper([media], log);
      unawaited(bootstrapper.run());
      async.elapse(const Duration(seconds: 5));
      var abandoned = false;
      unawaited(media.onStartAbandoned().then((_) => abandoned = true));
      async.elapse(const Duration(seconds: 9));
      expect(abandoned, isFalse);
      async.elapse(const Duration(seconds: 1));
      expect(abandoned, isTrue);
      expect(log.records.map((r) => r.summary), [
        startsWith('TimeoutException'),
      ]);
      unawaited(bootstrapper.shutdown());
      async.elapse(const Duration(seconds: 15));
    });
  });

  group('switched off → no start, no overrides, no contribution (no '
      'fallback either), no idle tasks', () {
    Future<void> expectOff(
      AppFeatures build,
      Future<void> Function(NoteStore store) menu,
    ) async {
      final store = createFakeNoteStore();
      addTearDown(store.close);
      await menu(store);
      final calls = _Calls();
      final bootstrapper = _bootstrapper(
        [_core(store), _media(calls)],
        AppErrorLog(),
        features: build,
      );
      addTearDown(bootstrapper.shutdown);
      final success = await bootstrapper.run() as BootstrapSuccess;
      expect(success.report.steps.last.outcome, StartupStepOutcome.skipped);
      expect(calls.initialized, isEmpty);
      expect(calls.overrides, isEmpty);
      expect(success.contributions, isEmpty);
      expect(success.idleTasks, isEmpty);
    }

    test('by the build (FEATURE_MEDIA=false)', () async {
      await expectOff(const AppFeatures(media: false), (_) async {});
    });

    test('by the developer menu (app.features.media = false)', () async {
      await expectOff(
        AppFeatures.all,
        (store) => store.settings.set(AppFeatureKeys.media, false),
      );
    });
  });

  test('mediaRecordingPanel passes the panel context to RecordingPanel', () {
    final tapToSeek = ValueNotifier<bool>(true);
    addTearDown(tapToSeek.dispose);
    void setTapToSeek(bool value) {}
    void close() {}
    final widget = mediaRecordingPanel(
      _FakeBuildContext(),
      EditorPanelContext(
        noteId: 'n1',
        tapToSeek: tapToSeek,
        setTapToSeek: setTapToSeek,
        close: close,
      ),
    );
    expect(widget, isA<RecordingPanel>());
    final panel = widget as RecordingPanel;
    expect(panel.noteId, 'n1');
    expect(panel.tapToSeek, same(tapToSeek));
    expect(panel.onTapToSeekChanged, setTapToSeek);
    expect(panel.onClose, close);
  });
}

final class _FakeBuildContext extends Fake implements BuildContext {}
