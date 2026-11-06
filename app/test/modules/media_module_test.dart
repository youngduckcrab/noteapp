// MediaModule (docs/plans/m5-7/01-infra.md 4.6.4, 6.4, 6.5.2, 6.6, 6.7,
// 6.17; contract 7.2.4 / 7.2.12 / 7.3.3 — recording only, D17). R2-B8a:
// start, contribution, fallback contribution, onStartAbandoned, switched off
// → nothing, the two idle tasks registered. J7: media.recoverDrafts over
// drafts made by CORE's FakeAudioRecorder.abandon() (a closed tab) — 0, 1,
// 2 oldest first, one failing, one inside the 'recently updated' window —
// and media.leaveGuard (recorder status → WebPlatform.setLeaveGuard, set
// right after the first frame, before the 3 s delay, even behind a long
// recovery task; off again on clean-up).
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
import '../fakes/idle_fakes.dart';

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

  group(
    'media.recoverDrafts (6.5.2 — drafts of FakeAudioRecorder.abandon())',
    _recoveryTests,
  );

  group('media.leaveGuard (6.17)', _leaveGuardTests);

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

/// A fake store whose clock moves only by [advance] (no real time — the
/// 'recently updated' window of pendingDrafts() is measured on store.clock).
final class _Clocked {
  _Clocked() : _time = FakeAsync() {
    store = createFakeNoteStore(
      clock: _time.getClock(DateTime.utc(2026, 11, 6, 9)),
    );
  }

  final FakeAsync _time;
  late final NoteStore store;

  void advance(Duration duration) => _time.elapseBlocking(duration);
}

/// A closed tab: recorder A starts, records [length], then is dropped with
/// FakeAudioRecorder.abandon() — the draft stays in [store].
Future<void> _abandonedDraft(
  NoteStore store,
  NoteId noteId,
  RecordingId recordingId, {
  Duration length = const Duration(seconds: 3),
}) async {
  final a = FakeAudioRecorder(store: store);
  await a.start(recordingId: recordingId, noteId: noteId);
  a.advance(length);
  await a.abandon();
}

/// Recorder B of the next start, seen through the AudioRecorderService
/// interface: logs the recordingIds it is asked to recover, can hand
/// pendingDrafts() newest first and can make one recovery throw.
final class _RecorderB implements AudioRecorderService {
  _RecorderB(this.inner, {this.newestFirst = false, this.failing});

  final FakeAudioRecorder inner;
  final bool newestFirst;
  final RecordingId? failing;
  final List<RecordingId> recoverCalls = [];
  final Map<String, RecordingId> _byDraft = {};

  @override
  Future<List<RecordingDraft>> pendingDrafts() async {
    final drafts = await inner.pendingDrafts();
    for (final d in drafts) {
      _byDraft[d.draftId] = d.recordingId;
    }
    return newestFirst ? drafts.reversed.toList() : drafts;
  }

  @override
  Future<Recording?> recoverDraft(String draftId) async {
    final recordingId = _byDraft[draftId]!;
    recoverCalls.add(recordingId);
    if (recordingId == failing) throw StateError('broken draft $recordingId');
    return inner.recoverDraft(draftId);
  }

  @override
  RecorderStatus get status => inner.status;
  @override
  Stream<RecorderStatus> get statusStream => inner.statusStream;
  @override
  Future<AudioSupport> checkSupport({bool requestPermission = false}) =>
      inner.checkSupport(requestPermission: requestPermission);
  @override
  Future<void> start({
    required RecordingId recordingId,
    required NoteId noteId,
  }) => inner.start(recordingId: recordingId, noteId: noteId);
  @override
  Future<void> pause() => inner.pause();
  @override
  Future<void> resume() => inner.resume();
  @override
  Future<Recording?> stop() => inner.stop();
  @override
  Future<void> cancel() => inner.cancel();
  @override
  int? offsetNowMs() => inner.offsetNowMs();
}

/// A MediaModule whose injected overrides put [recorder] behind
/// audioRecorderServiceProvider (X28 — the module's own override is the only
/// audio override), started by the bootstrapper; returns its idle tasks and
/// a context over the success overrides.
Future<(List<AppIdleTask>, FakeIdleContext)> _startedMedia(
  NoteStore store,
  AudioRecorderService recorder,
  AppErrorLog log,
) async {
  final media = MediaModule(
    initialize: ({MediaIoConfig config = const MediaIoConfig()}) async {},
    mediaOverrides: ({MediaIoConfig? config}) => [
      audioRecorderServiceProvider.overrideWithValue(recorder),
    ],
    recordingPanel: _panel,
  );
  final bootstrapper = _bootstrapper([_core(store), media], log);
  addTearDown(bootstrapper.shutdown);
  final success = await bootstrapper.run() as BootstrapSuccess;
  final container = ProviderContainer.test(overrides: success.overrides);
  final context = FakeIdleContext(container: container, errorLog: log);
  addTearDown(context.dispose);
  return (success.idleTasks, context);
}

AppIdleTask _task(List<AppIdleTask> tasks, String id) =>
    tasks.singleWhere((t) => t.id == id);

/// The note's recordings as (id, title, durationMs), oldest first.
Future<List<(String, String?, int)>> _recordings(
  NoteStore store,
  NoteId noteId,
) async {
  final list = [...await store.recordings.recordingsOf(noteId)]
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  return [for (final r in list) (r.id, r.title, r.durationMs)];
}

void _recoveryTests() {
  late _Clocked clocked;
  late NoteStore store;
  late NoteId noteId;
  setUp(() async {
    clocked = _Clocked();
    store = clocked.store;
    noteId = (await store.library.createNote(title: '녹음')).id;
  });
  tearDown(() => store.close());

  Future<_RecorderB> recover({
    bool newestFirst = false,
    RecordingId? failing,
    AppErrorLog? log,
  }) async {
    final b = _RecorderB(
      FakeAudioRecorder(store: store),
      newestFirst: newestFirst,
      failing: failing,
    );
    final errorLog = log ?? AppErrorLog();
    final (tasks, context) = await _startedMedia(store, b, errorLog);
    await _task(tasks, 'media.recoverDrafts').run(context);
    return b;
  }

  test('no drafts → nothing recovered, nothing logged', () async {
    final log = AppErrorLog();
    final b = await recover(log: log);
    expect(b.recoverCalls, isEmpty);
    expect(await _recordings(store, noteId), isEmpty);
    expect(log.totalCount, 0);
  });

  test('one abandoned draft older than the 10 s window → one recording with '
      'the original recordingId, titled 복구된 녹음, draft gone', () async {
    await _abandonedDraft(store, noteId, 'rec-closed-tab');
    clocked.advance(const Duration(seconds: 11));
    final log = AppErrorLog();
    final b = await recover(log: log);
    expect(b.recoverCalls, ['rec-closed-tab']);
    expect(await _recordings(store, noteId), [
      ('rec-closed-tab', '복구된 녹음', 3000),
    ]);
    expect(await store.recordingDrafts.listDrafts(), isEmpty);
    expect(log.totalCount, 0);
  });

  test('two drafts → both, oldest first (startedAt), even when '
      'pendingDrafts() lists the newest first', () async {
    await _abandonedDraft(store, noteId, 'rec-early');
    clocked.advance(const Duration(minutes: 5));
    await _abandonedDraft(
      store,
      noteId,
      'rec-late',
      length: const Duration(seconds: 2),
    );
    clocked.advance(const Duration(seconds: 11));
    final b = await recover(newestFirst: true);
    expect(b.recoverCalls, ['rec-early', 'rec-late']);
    expect(await _recordings(store, noteId), [
      ('rec-early', '복구된 녹음', 3000),
      ('rec-late', '복구된 녹음', 2000),
    ]);
  });

  test('a failing draft → one record (source module, its draft id), the '
      'next draft is still recovered', () async {
    await _abandonedDraft(store, noteId, 'rec-broken');
    clocked.advance(const Duration(seconds: 1));
    await _abandonedDraft(store, noteId, 'rec-good');
    clocked.advance(const Duration(seconds: 11));
    final brokenDraft = (await store.recordingDrafts.listDrafts())
        .singleWhere((d) => d.recordingId == 'rec-broken')
        .draftId;
    final log = AppErrorLog();
    final b = await recover(failing: 'rec-broken', log: log);
    expect(b.recoverCalls, ['rec-broken', 'rec-good']);
    expect(await _recordings(store, noteId), [('rec-good', '복구된 녹음', 3000)]);
    final record = log.records.single;
    expect(record.source, AppErrorSource.module);
    expect(record.summary, startsWith('recoverDraft $brokenDraft failed'));
    expect(record.summary, contains('broken draft rec-broken'));
    // The failed draft stays for the next start.
    expect(
      (await store.recordingDrafts.listDrafts()).map((d) => d.recordingId),
      ['rec-broken'],
    );
  });

  test(
    'a draft updated inside the window (another tab may still record) '
    'is not recovered — pendingDrafts() decides, the shell follows it',
    () async {
      await _abandonedDraft(store, noteId, 'rec-old');
      clocked.advance(const Duration(seconds: 30));
      await _abandonedDraft(store, noteId, 'rec-other-tab');
      clocked.advance(const Duration(seconds: 9));
      final b = await recover();
      expect(b.recoverCalls, ['rec-old']);
      expect(await _recordings(store, noteId), [('rec-old', '복구된 녹음', 3000)]);
      expect(
        (await store.recordingDrafts.listDrafts()).map((d) => d.recordingId),
        ['rec-other-tab'],
      );

      // Past the window, the next start recovers it.
      clocked.advance(const Duration(seconds: 2));
      final next = await recover();
      expect(next.recoverCalls, ['rec-other-tab']);
    },
  );
}

void _leaveGuardTests() {
  late NoteStore store;
  late NoteId noteId;
  late FakeAudioRecorder recorder;
  setUp(() async {
    store = createFakeNoteStore();
    noteId = (await store.library.createNote(title: '녹음')).id;
    recorder = FakeAudioRecorder(store: store);
  });
  tearDown(() => store.close());

  test(
    'recorder status → setLeaveGuard(status.isActive): on while recording '
    'or paused, off when stopped; clean-up cancels and turns it off',
    () async {
      final log = AppErrorLog();
      final (tasks, context) = await _startedMedia(store, recorder, log);
      final web = context.web as FakeWebPlatform;
      await _task(tasks, 'media.leaveGuard').run(context);
      await pumpEventQueue();
      expect(web.leaveGuardCalls, [false]); // the current status on listen

      await recorder.start(recordingId: 'rec-1', noteId: noteId);
      await pumpEventQueue();
      expect(web.leaveGuard, isTrue);
      await recorder.pause();
      await pumpEventQueue();
      expect(web.leaveGuard, isTrue, reason: 'paused is still a recording');
      await recorder.resume();
      recorder.advance(const Duration(seconds: 2));
      await recorder.stop();
      await pumpEventQueue();
      expect(web.leaveGuard, isFalse);

      await recorder.start(recordingId: 'rec-2', noteId: noteId);
      await pumpEventQueue();
      expect(web.leaveGuard, isTrue);
      await context.dispose();
      expect(web.leaveGuard, isFalse);
      final calls = web.leaveGuardCalls.length;
      await recorder.cancel();
      await pumpEventQueue();
      expect(web.leaveGuardCalls, hasLength(calls), reason: 'unsubscribed');
      expect(log.totalCount, 0);
    },
  );

  testWidgets('in the runner: set right after the first frame — before the '
      '3 s delay of the queued tasks and while a long (25 s) recovery task '
      'ahead of media.recoverDrafts is still running', (tester) async {
    final log = AppErrorLog();
    late List<AppIdleTask> tasks;
    late List<Override> overrides;
    await tester.runAsync(() async {
      final media = MediaModule(
        initialize: ({MediaIoConfig config = const MediaIoConfig()}) async {},
        mediaOverrides: ({MediaIoConfig? config}) => [
          audioRecorderServiceProvider.overrideWithValue(recorder),
        ],
        recordingPanel: _panel,
      );
      final bootstrapper = _bootstrapper([_core(store), media], log);
      final success = await bootstrapper.run() as BootstrapSuccess;
      tasks = success.idleTasks;
      overrides = success.overrides;
      addTearDown(bootstrapper.shutdown);
    });
    final ran = <String>[];
    var longDone = false;
    final longRecovery = AppIdleTask(
      id: 'test.longRecovery',
      priority: AppIdlePriority.dataProtection,
      delay: Duration.zero,
      run: (_) async {
        ran.add('test.longRecovery');
        await Future<void>.delayed(const Duration(seconds: 25));
        longDone = true;
      },
    );
    final web = FakeWebPlatform();
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: AppIdleTaskRunner(
          tasks: [longRecovery, ...tasks],
          errorLog: log,
          web: web,
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pump(Duration.zero);
    expect(web.leaveGuardCalls, [false]);
    expect(ran, ['test.longRecovery']);

    await tester.runAsync(
      () => recorder.start(recordingId: 'rec-1', noteId: noteId),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(web.leaveGuard, isTrue);
    expect(longDone, isFalse);

    await tester.pump(const Duration(seconds: 25));
    expect(longDone, isTrue);
    await tester.runAsync(recorder.cancel);
    await tester.pump(Duration.zero);
    expect(web.leaveGuard, isFalse);

    // Root scope gone → the guard's clean-up runs (off, unsubscribed).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(web.leaveGuardCalls.last, isFalse);
    expect(log.totalCount, 0);
  });
}
