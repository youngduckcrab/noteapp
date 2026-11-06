// PdfModule (docs/plans/01-infra.md 4.5.9, 5.4, 9.1; contract 7.2.19 /
// 7.3.3): non-critical, initialize, overrides == pdfOverrides(), left out
// on failure; the default pdfIoOverrides() builds INK's background builders
// without throwing (PDF-2-2). Builder lists follow 2nd-round contract v2.2
// 7.2.9 / 7.2.12 / 7.3.3 (C2-20): INK's default [image, template], with PDF
// [pdf, image, template].
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/modules/pdf_module.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:pdf_io/pdf_io.dart';

import '../fakes/fake_web_platform.dart';

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
    expect(module.overrides(), same(list));
    expect(overridesCalls, 1);
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
}
