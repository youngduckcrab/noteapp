// RecognitionModule (docs/plans/m5-7/01-infra.md 4.6.4, 6.4, 6.6, 6.7;
// contract 7.2.11 / 7.3.3 X31 · X32). R2-B8a: config (4 combinations),
// contribution, the recognition.indexer idle task through the injection
// seam (start once, dispose once), switched off → nothing.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/bootstrap/idle_tasks.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/features/app_features.dart';
import 'package:noteapp/src/modules/recognition_module.dart';
import 'package:noteapp/src/modules/recognition_wiring.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';

import '../fakes/fake_app_module.dart';
import '../fakes/fake_web_platform.dart';
import '../fakes/idle_fakes.dart';

final _marker = Provider<String>((ref) => 'default', name: '_recogTestMarker');

RecognitionAction _action(String id) => RecognitionAction(
  id: id,
  label: id,
  icon: Icons.text_fields,
  run: (context, target) async {},
);

final class _Rig {
  _Rig({
    this.mathEndpoint = '',
    List<RecognitionAction>? selection,
    List<RecognitionAction>? insert,
    RecordingIndexer? indexer,
  }) : indexer = indexer ?? RecordingIndexer(),
       selection = selection ?? const [],
       insert = insert ?? const [];

  final String mathEndpoint;
  final List<RecognitionAction> selection;
  final List<RecognitionAction> insert;
  final RecordingIndexer indexer;
  final List<RecognitionConfig> configs = [];
  final Override override = _marker.overrideWithValue('recognition');
  final AppErrorLog log = AppErrorLog();

  late final RecognitionModule module = RecognitionModule(
    overridesFor: ({RecognitionConfig config = const RecognitionConfig()}) {
      configs.add(config);
      return [override];
    },
    selectionActions: () => selection,
    insertActions: () => insert,
    indexer: indexer.reader,
    mathEndpoint: mathEndpoint,
  );

  Future<BootstrapSuccess> boot({
    AppFeatures features = AppFeatures.all,
    Future<void> Function(NoteStore store)? menu,
  }) async {
    final store = createFakeNoteStore();
    addTearDown(store.close);
    await menu?.call(store);
    final web = FakeWebPlatform();
    final bootstrapper = AppBootstrapper(
      modules: [
        FakeAppModule(id: 'core', onStart: (c) => c.publish<NoteStore>(store)),
        module,
      ],
      buildInfo: BuildInfo.local,
      runtimeInfo: RuntimeInfo.detect(web),
      web: web,
      errorLog: log,
      ownerId: kLocalOwnerId,
      features: features,
    );
    addTearDown(bootstrapper.shutdown);
    return await bootstrapper.run() as BootstrapSuccess;
  }
}

void main() {
  test('id, label, non-critical, 3 s timeout', () {
    final module = RecognitionModule();
    expect(RecognitionModule.moduleId, 'recognition');
    expect(module.id, 'recognition');
    expect(module.label, '인식 준비 중');
    expect(module.critical, isFalse);
    expect(module.startTimeout, const Duration(seconds: 3));
  });

  group('config: mathEndpoint only with the math engine on and '
      'MATH_ENDPOINT set', () {
    const url = 'http://127.0.0.1:5001/demo-noteapp/us-central1/recognizeMath';
    final cases = {
      'math on, endpoint set': (AppFeatures.all, url, Uri.parse(url)),
      'math on, no endpoint': (AppFeatures.all, '', null),
      'math off (build), endpoint set': (
        const AppFeatures(mathEngine: false),
        url,
        null,
      ),
      'math off (build), no endpoint': (
        const AppFeatures(mathEngine: false),
        '',
        null,
      ),
    };
    for (final MapEntry(key: name, value: (features, endpoint, expected))
        in cases.entries) {
      test(name, () async {
        final rig = _Rig(mathEndpoint: endpoint);
        final success = await rig.boot(features: features);
        expect(success.report.steps.last.outcome, StartupStepOutcome.ok);
        expect(rig.configs, [RecognitionConfig(mathEndpoint: expected)]);
        expect(rig.module.config.idTokenProvider, isNull);
        expect(rig.log.totalCount, 0);
      });
    }

    test('math off by the developer menu', () async {
      final rig = _Rig(mathEndpoint: url);
      await rig.boot(
        menu: (store) => store.settings.set(AppFeatureKeys.mathEngine, false),
      );
      expect(rig.configs, [const RecognitionConfig()]);
    });

    for (final bad in [
      'not a url',
      'ftp://host/x',
      '/relative/path',
      'http://',
    ]) {
      test('"$bad" → null + one record', () async {
        final rig = _Rig(mathEndpoint: bad);
        await rig.boot();
        expect(rig.configs, [const RecognitionConfig()]);
        final record = rig.log.records.single;
        expect(record.source, AppErrorSource.module);
        expect(record.summary, contains('MATH_ENDPOINT'));
        expect(record.details, bad);
      });
    }
  });

  test('contribution: selection / insert items in the actions\' order, the '
      'recog.settings section, the recog.indexer dev section; overrides = '
      'overridesFor(config)', () async {
    final rig = _Rig(
      selection: [_action('recog.toText'), _action('recog.toMath')],
      insert: [_action('recog.mathPad')],
    );
    final success = await rig.boot();
    final contribution = success.contributions.single;
    expect(contribution.moduleId, 'recognition');
    expect(contribution.selectionMenuItems.map((i) => (i.id, i.label)), [
      ('recog.toText', 'recog.toText'),
      ('recog.toMath', 'recog.toMath'),
    ]);
    expect(contribution.insertMenuItems.map((i) => i.id), ['recog.mathPad']);
    expect(contribution.recordingPanel, isNull);
    expect(contribution.devOverlaySections, [recognitionIndexerSection]);
    final section = contribution.settingsSections.single;
    expect(
      (section.id, section.title, section.group),
      ('recog.settings', '인식', null),
    );
    expect(
      section.builder(_FakeBuildContext()),
      isA<RecognitionSettingsSection>(),
    );
    expect(success.overrides, contains(same(rig.override)));
  });

  test('default arguments: the R2-B6 actions (none yet) and the real '
      'recognitionOverrides() — the shape fitter override', () async {
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final web = FakeWebPlatform();
    final bootstrapper = AppBootstrapper(
      modules: [
        FakeAppModule(id: 'core', onStart: (c) => c.publish<NoteStore>(store)),
        RecognitionModule(),
      ],
      buildInfo: BuildInfo.local,
      runtimeInfo: RuntimeInfo.detect(web),
      web: web,
      errorLog: AppErrorLog(),
      ownerId: kLocalOwnerId,
    );
    addTearDown(bootstrapper.shutdown);
    final success = await bootstrapper.run() as BootstrapSuccess;
    final contribution = success.contributions.single;
    expect(
      contribution.selectionMenuItems.map((i) => i.id),
      recognitionSelectionActions().map((a) => a.id),
    );
    expect(
      contribution.insertMenuItems.map((i) => i.id),
      recognitionInsertActions().map((a) => a.id),
    );
    expect(
      success.overrides.map((o) => o.origin),
      contains(ink.inkShapeFitterProvider),
    );
  });

  group('recognition.indexer idle task (injection seam — no provider '
      'override)', () {
    test('priority recognition, queued', () {
      final task = _Rig().module.idleTasks().single;
      expect(task.id, 'recognition.indexer');
      expect(task.priority, AppIdlePriority.recognition);
      expect(task.immediate, isFalse);
    });

    test('start once; dispose once when the scope goes away', () async {
      final rig = _Rig();
      final success = await rig.boot();
      final context = FakeIdleContext();
      await success.idleTasks.single.run(context);
      expect((rig.indexer.starts, rig.indexer.disposes), (1, 0));
      await context.dispose();
      expect((rig.indexer.starts, rig.indexer.disposes), (1, 1));
    });

    test('reader null (web / no recognizer) → nothing started, nothing '
        'registered', () async {
      final rig = _Rig(indexer: RecordingIndexer(available: false));
      final success = await rig.boot();
      final context = FakeIdleContext();
      await success.idleTasks.single.run(context);
      expect(rig.indexer.reads, 1);
      expect(rig.indexer.starts, 0);
      expect(context.callbacks, isEmpty);
    });

    test('the default reader on the VM fake store: the provider is null '
        '(UnsupportedHandwritingRecognizer) → nothing', () async {
      final store = createFakeNoteStore();
      addTearDown(store.close);
      final container = ProviderContainer.test(
        overrides: [noteStoreProvider.overrideWithValue(store)],
      );
      final context = FakeIdleContext(container: container);
      await RecognitionModule().idleTasks().single.run(context);
      expect(context.callbacks, isEmpty);
    });
  });

  group('switched off → no start, no overrides, no contribution, no idle '
      'tasks', () {
    test('by the build (FEATURE_RECOGNITION=false)', () async {
      final rig = _Rig(selection: [_action('recog.toText')]);
      final success = await rig.boot(
        features: const AppFeatures(recognition: false),
      );
      expect(success.report.steps.last.outcome, StartupStepOutcome.skipped);
      expect(rig.configs, isEmpty);
      expect(success.contributions, isEmpty);
      expect(success.idleTasks, isEmpty);
      expect(success.overrides, isNot(contains(same(rig.override))));
    });

    test('by the developer menu (app.features.recognition = false)', () async {
      final rig = _Rig();
      final success = await rig.boot(
        menu: (store) => store.settings.set(AppFeatureKeys.recognition, false),
      );
      expect(success.report.steps.last.outcome, StartupStepOutcome.skipped);
      expect(rig.configs, isEmpty);
    });
  });
}

final class _FakeBuildContext extends Fake implements BuildContext {}
