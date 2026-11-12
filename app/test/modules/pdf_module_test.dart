// PdfModule (docs/plans/01-infra.md 4.5.9, 5.4, 9.1; contract 7.2.19 /
// 7.3.3): non-critical, initialize, overrides == pdfOverrides(), left out
// on failure; the default pdfIoOverrides() builds INK's background builders
// without throwing (PDF-2-2). Builder lists follow 2nd-round contract v2.2
// 7.2.9 / 7.2.12 / 7.3.3 (C2-20): INK's default [image, template], with PDF
// [pdf, image, template].
// 2nd round (m5-7/01-infra 4.6.4, 6.5; J10): the pdf.searchIndexer idle task
// through the injection seam (a recording IndexerHandleReader — the indexer
// is a `final class`, no provider override fake), none when PDF failed, the
// default reader over a fake store, and the order in the real runner:
// media.recoverDrafts (0) → pdf.searchIndexer (10) → recognition.indexer
// (20) whatever the module order.
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_recognition/ink_recognition.dart' show RecognitionConfig;
import 'package:media_io/media_io.dart' show MediaIoConfig;
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/bootstrap/idle_tasks.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/modules/idle_indexers.dart';
import 'package:noteapp/src/modules/media_module.dart';
import 'package:noteapp/src/modules/pdf_module.dart';
import 'package:noteapp/src/modules/pdf_share.dart';
import 'package:noteapp/src/modules/recognition_module.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:pdf_io/pdf_io.dart';

import '../fakes/fake_app_module.dart';
import '../fakes/fake_web_platform.dart';
import '../fakes/idle_fakes.dart';

final _marker = Provider<String>(
  (ref) => 'default',
  name: '_pdfModuleTestMarker',
);

AppModuleContext _context() {
  final web = FakeWebPlatform();
  return AppModuleContext(
    buildInfo: BuildInfo.local,
    runtimeInfo: RuntimeInfo.detect(web),
    web: web,
    ownerId: kLocalOwnerId,
    errorLog: AppErrorLog(),
  );
}

Future<BootstrapSuccess> _boot(AppModule module, AppErrorLog log) async {
  final web = FakeWebPlatform();
  final bootstrapper = AppBootstrapper(
    modules: [module],
    buildInfo: BuildInfo.local,
    runtimeInfo: RuntimeInfo.detect(web),
    web: web,
    errorLog: log,
    ownerId: kLocalOwnerId,
  );
  addTearDown(bootstrapper.shutdown);
  return await bootstrapper.run() as BootstrapSuccess;
}

void main() {
  test('id, label, non-critical, 10 s timeout', () {
    final module = PdfModule();
    expect(PdfModule.moduleId, 'pdf');
    expect(module.id, 'pdf');
    expect(module.label, 'PDF 엔진 준비 중');
    expect(module.critical, isFalse);
    expect(module.startTimeout, const Duration(seconds: 10));
    expect(module.resetLocalData, isNull);
  });

  test('start calls initialize once; overrides() is pdfOverrides()', () async {
    var initialized = 0;
    var overridesCalls = 0;
    final list = <Override>[_marker.overrideWithValue('pdf')];
    final module = PdfModule(
      initialize: () async => initialized++,
      pdfOverrides: () {
        overridesCalls++;
        return list;
      },
    );
    await module.start(_context());
    expect(initialized, 1);
    final overrides = module.overrides();
    expect(overrides.first, same(list.single));
    expect(overridesCalls, 1);
    // Then the native share of the result sheet (pdfShareFilesProvider).
    expect(overrides, hasLength(2));
    expect(overrides.last.origin, same(pdfShareFilesProvider));
  });

  test('pdfShareFilesProvider = the share given (default: platformPdfShare '
      '— the VM / native one; null on the web)', () {
    Future<PdfOutputOutcome> share(List<PdfExportResult> results) async =>
        PdfOutputOutcome.done;
    final custom = ProviderContainer.test(
      overrides: PdfModule(pdfOverrides: () => [], share: share).overrides(),
    );
    expect(custom.read(pdfShareFilesProvider), same(share));
    final none = ProviderContainer.test(
      overrides: PdfModule(pdfOverrides: () => [], share: null).overrides(),
    );
    expect(none.read(pdfShareFilesProvider), isNull);
    final defaults = ProviderContainer.test(
      overrides: PdfModule(pdfOverrides: () => []).overrides(),
    );
    expect(defaults.read(pdfShareFilesProvider), same(platformPdfShare));
    expect(platformPdfShare, isNotNull);
  });

  test('a failed start: startup goes on, the PDF overrides are left out, '
      'one module record', () async {
    var overridesCalls = 0;
    final log = AppErrorLog();
    final success = await _boot(
      PdfModule(
        initialize: () async => throw StateError('pdfium missing'),
        pdfOverrides: () {
          overridesCalls++;
          return [_marker.overrideWithValue('pdf')];
        },
      ),
      log,
    );
    expect(
      success.report.steps.single.outcome,
      StartupStepOutcome.failedNonCritical,
    );
    expect(overridesCalls, 0);
    expect(log.records.single.source, AppErrorSource.module);
    expect(log.records.single.summary, contains('pdfium missing'));
    final container = ProviderContainer.test(overrides: success.overrides);
    expect(container.read(_marker), 'default');
    // INK's default (contract v2.2 7.2.9): defaultPageBackgroundBuilders =
    // [image, template].
    expect(container.read(ink.pageBackgroundBuildersProvider), [
      isA<ink.ImageBackgroundLayerBuilder>(),
      isA<ink.TemplateBackgroundLayerBuilder>(),
    ]);
  });

  test('default arguments: initializePdfIo + pdfIoOverrides() → INK reads '
      '[pdf, image, template] without an exception (PDF-2-2, contract v2.2 '
      '7.2.12 / 7.3.3)', () async {
    final log = AppErrorLog();
    final success = await _boot(PdfModule(), log);
    expect(success.report.steps.single.outcome, StartupStepOutcome.ok);
    expect(log.records, isEmpty);
    final container = ProviderContainer.test(overrides: success.overrides);
    expect(container.read(ink.pageBackgroundBuildersProvider), [
      isA<PdfBackgroundLayerBuilder>(),
      isA<ink.ImageBackgroundLayerBuilder>(),
      isA<ink.TemplateBackgroundLayerBuilder>(),
    ]);
  });

  group('pdf.searchIndexer idle task (2nd round 4.6.4 — injection seam)', () {
    test('one task, priority searchIndex, 3 s, queued', () {
      final tasks = PdfModule(indexer: RecordingIndexer().reader).idleTasks();
      expect(tasks.map((t) => t.id), ['pdf.searchIndexer']);
      expect(tasks.single.priority, AppIdlePriority.searchIndex);
      expect(tasks.single.delay, const Duration(seconds: 3));
      expect(tasks.single.immediate, isFalse);
    });

    test('the recording reader: start once, dispose once when the scope '
        'goes away', () async {
      final indexer = RecordingIndexer();
      final success = await _boot(
        PdfModule(initialize: () async {}, indexer: indexer.reader),
        AppErrorLog(),
      );
      final task = success.idleTasks.single;
      final context = FakeIdleContext();
      await task.run(context);
      expect((indexer.reads, indexer.starts, indexer.disposes), (1, 1, 0));
      await context.dispose();
      expect((indexer.reads, indexer.starts, indexer.disposes), (1, 1, 1));
    });

    test('a start() throw registers no dispose (the runner logs it)', () async {
      final indexer = RecordingIndexer(startError: StateError('no pool'));
      final context = FakeIdleContext();
      final task = PdfModule(indexer: indexer.reader).idleTasks().single;
      await expectLater(task.run(context), throwsStateError);
      expect(context.callbacks, isEmpty);
      await context.dispose();
      expect(indexer.disposes, 0);
    });

    test('the default reader (readPdfSearchIndexer) over a fake store: '
        'reads pdfSearchIndexerProvider (it needs noteStoreProvider) and '
        'hands out its start / dispose; the provider\'s own onDispose after '
        'the task\'s dispose does not throw', () async {
      final store = createFakeNoteStore();
      addTearDown(store.close);
      final container = ProviderContainer.test(
        overrides: [noteStoreProvider.overrideWithValue(store)],
      );
      final context = FakeIdleContext(container: container);
      expect(readPdfSearchIndexer(context), isNotNull);
      await PdfModule().idleTasks().single.run(context);
      expect(context.callbacks, hasLength(1));
      await context.dispose();
      // (H2) the real indexer's dispose a second time is safe (7.2.11).
      await readPdfSearchIndexer(context)!.dispose();
      container.dispose();
    });

    test('PDF failed to start: no idle task', () async {
      final indexer = RecordingIndexer();
      final success = await _boot(
        PdfModule(
          initialize: () async => throw StateError('pdfium missing'),
          indexer: indexer.reader,
        ),
        AppErrorLog(),
      );
      expect(success.idleTasks, isEmpty);
      expect(indexer.reads, 0);
    });

    testWidgets('in the runner: media.recoverDrafts → pdf.searchIndexer → '
        'recognition.indexer, one at a time, whatever the module order', (
      tester,
    ) async {
      final order = <String>[];
      IndexerHandle? reader(String name, AppIdleContext context) {
        order.add(name);
        return (start: () {}, dispose: () async {});
      }

      final log = AppErrorLog();
      late BootstrapSuccess success;
      await tester.runAsync(() async {
        final store = createFakeNoteStore();
        addTearDown(store.close);
        final web = FakeWebPlatform();
        final bootstrapper = AppBootstrapper(
          modules: [
            FakeAppModule(
              id: 'core',
              onStart: (c) => c.publish<NoteStore>(store),
            ),
            RecognitionModule(
              overridesFor: ({config = const RecognitionConfig()}) => const [],
              indexer: (c) => reader('recognition.indexer', c),
            ),
            PdfModule(
              initialize: () async {},
              pdfOverrides: () => const [],
              indexer: (c) => reader('pdf.searchIndexer', c),
            ),
            MediaModule(
              initialize: ({config = const MediaIoConfig()}) async {},
              mediaOverrides: ({config}) => [
                audioRecorderServiceProvider.overrideWithValue(
                  _OrderRecorder(order),
                ),
              ],
            ),
          ],
          buildInfo: BuildInfo.local,
          runtimeInfo: RuntimeInfo.detect(web),
          web: web,
          errorLog: log,
          ownerId: kLocalOwnerId,
        );
        addTearDown(bootstrapper.shutdown);
        success = await bootstrapper.run() as BootstrapSuccess;
      });
      expect(success.idleTasks.map((t) => t.id), [
        'recognition.indexer',
        'pdf.searchIndexer',
        'media.leaveGuard',
        'media.recoverDrafts',
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: success.overrides,
          child: AppIdleTaskRunner(
            tasks: success.idleTasks,
            errorLog: log,
            web: FakeWebPlatform(),
            child: const SizedBox(),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(order, [
        'media.recoverDrafts',
        'pdf.searchIndexer',
        'recognition.indexer',
      ]);
      expect(log.totalCount, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  });
}

/// A recorder that logs when the draft recovery asks for its drafts (none).
final class _OrderRecorder extends Fake implements AudioRecorderService {
  _OrderRecorder(this.order);

  final List<String> order;

  @override
  RecorderStatus get status => const RecorderStatus();

  @override
  Stream<RecorderStatus> get statusStream =>
      Stream<RecorderStatus>.value(const RecorderStatus());

  @override
  Future<List<RecordingDraft>> pendingDrafts() async {
    order.add('media.recoverDrafts');
    return const [];
  }
}
