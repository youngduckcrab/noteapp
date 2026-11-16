// AppModuleContext.resolveFeatures / featureOn (J5 — docs/plans/m5-7/
// 01-infra.md 4.6.2, 6.6; contract 7.3.3 '기능 스위치'): the build AND the
// developer-menu settings of the published NoteStore, the three keys read
// once (cached), a read slower than 500 ms or a failing read → the build
// values + one record (source: module), and no caching before CoreModule
// published the store. fake_async for the time limit.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/app/appearance.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/features/app_features.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:ui_kit/ui_kit.dart' show AppBrightnessMode, AppStyle;

import '../fakes/counting_note_store.dart';
import '../fakes/fake_settings_repository.dart';
import '../fakes/fake_web_platform.dart';

AppModuleContext _context({
  AppErrorLog? errorLog,
  AppFeatures compileTime = AppFeatures.all,
}) => AppModuleContext(
  buildInfo: BuildInfo.local,
  runtimeInfo: const RuntimeInfo(
    isWeb: true,
    renderer: WebRenderer.canvasKit,
    isStandalone: false,
  ),
  web: FakeWebPlatform(),
  ownerId: kLocalOwnerId,
  errorLog: errorLog ?? AppErrorLog(),
  compileTimeFeatures: compileTime,
);

/// A store whose settings go through a [FakeSettingsRepository].
(CountingNoteStore, FakeSettingsRepository) _store() {
  final store = CountingNoteStore();
  final settings = FakeSettingsRepository(store.inner.settings);
  store.settingsOverride = settings;
  return (store, settings);
}

const _keys = [
  'app.features.media',
  'app.features.recognition',
  'app.features.mathEngine',
];

void main() {
  test(
    'the build AND the menu; each key read once, the result cached',
    () async {
      final (store, settings) = _store();
      addTearDown(store.inner.close);
      await store.settings.set(AppFeatureKeys.media, false);
      final context = _context(
        compileTime: const AppFeatures(mathEngine: false),
      )..publish<NoteStore>(store);

      final first = await context.resolveFeatures();
      expect(
        first,
        const AppFeatures(media: false, recognition: true, mathEngine: false),
      );
      expect(await context.featureOn(AppFeature.media), isFalse);
      expect(await context.featureOn(AppFeature.recognition), isTrue);
      expect(await context.featureOn(AppFeature.mathEngine), isFalse);
      expect(identical(await context.resolveFeatures(), first), isTrue);
      expect(settings.reads, unorderedEquals(_keys));
      expect(settings.reads, hasLength(3));
    },
  );

  test('a menu value cannot switch on what the build switched off', () async {
    final (store, _) = _store();
    addTearDown(store.inner.close);
    await store.settings.set(AppFeatureKeys.recognition, true);
    final context = _context(compileTime: const AppFeatures(recognition: false))
      ..publish<NoteStore>(store);
    expect(await context.featureOn(AppFeature.recognition), isFalse);
    // mathEngine counts only together with recognition.
    expect(await context.featureOn(AppFeature.mathEngine), isFalse);
  });

  test('two calls at once share one read', () async {
    final (store, settings) = _store();
    addTearDown(store.inner.close);
    final context = _context()..publish<NoteStore>(store);
    final results = await Future.wait([
      context.featureOn(AppFeature.media),
      context.featureOn(AppFeature.recognition),
      context.resolveFeatures().then((f) => f.mathEngine),
    ]);
    expect(results, [true, true, true]);
    expect(settings.reads, hasLength(3));
  });

  test('no store yet → the build values, NOT cached: the first call after '
      'CoreModule published the store reads the menu', () async {
    final (store, settings) = _store();
    addTearDown(store.inner.close);
    await store.settings.set(AppFeatureKeys.media, false);
    final log = AppErrorLog();
    final context = _context(errorLog: log);

    expect(await context.resolveFeatures(), AppFeatures.all);
    expect(settings.reads, isEmpty);
    context.publish<NoteStore>(store);
    expect(await context.featureOn(AppFeature.media), isFalse);
    expect(settings.reads, hasLength(3));
    expect(log.records, isEmpty);
  });

  test('reads slower than 500 ms → the build values + one record (source: '
      'module); later calls do not read again', () {
    fakeAsync((async) {
      final (store, settings) = _store();
      settings.getDelay = const Duration(milliseconds: 501);
      final log = AppErrorLog();
      final context = _context(
        errorLog: log,
        compileTime: const AppFeatures(mathEngine: false),
      )..publish<NoteStore>(store);

      AppFeatures? result;
      unawaited(context.resolveFeatures().then((f) => result = f));
      async.elapse(const Duration(milliseconds: 499));
      expect(result, isNull);
      async.elapse(const Duration(milliseconds: 1));
      expect(result, const AppFeatures(mathEngine: false));
      expect(log.records, hasLength(1));
      expect(log.records.single.source, AppErrorSource.module);
      expect(log.records.single.summary, contains('TimeoutException'));

      AppFeatures? again;
      unawaited(context.resolveFeatures().then((f) => again = f));
      async.elapse(const Duration(seconds: 1));
      expect(again, same(result));
      expect(settings.reads, hasLength(3));
      expect(log.records, hasLength(1));
      unawaited(store.inner.close());
      async.flushMicrotasks();
    });
  });

  test('reads that finish just inside 500 ms are used', () {
    fakeAsync((async) {
      final (store, settings) = _store();
      settings.getDelay = const Duration(milliseconds: 499);
      final log = AppErrorLog();
      final context = _context(errorLog: log)..publish<NoteStore>(store);
      unawaited(store.settings.set(AppFeatureKeys.recognition, false));
      async.flushMicrotasks();
      AppFeatures? result;
      unawaited(context.resolveFeatures().then((f) => result = f));
      async.elapse(AppModuleContext.featureReadTimeout);
      expect(result, const AppFeatures(recognition: false));
      expect(log.records, isEmpty);
      unawaited(store.inner.close());
      async.flushMicrotasks();
    });
  });

  test('a failing read → the build values + one record', () async {
    final (store, settings) = _store();
    addTearDown(store.inner.close);
    settings.getError = StateError('settings table locked');
    final log = AppErrorLog();
    final context = _context(
      errorLog: log,
      compileTime: const AppFeatures(media: false),
    )..publish<NoteStore>(store);
    expect(await context.resolveFeatures(), const AppFeatures(media: false));
    expect(await context.featureOn(AppFeature.recognition), isTrue);
    expect(log.records, hasLength(1));
    expect(log.records.single.source, AppErrorSource.module);
    expect(log.records.single.summary, contains('settings table locked'));
  });

  group('(v2.14-ui) resolveAppearance: the 화면 settings before the first '
      'frame', () {
    test('reads the stored style and brightness', () async {
      final (store, settings) = _store();
      addTearDown(store.inner.close);
      await store.settings.set(AppearanceKeys.style, 'studio');
      await store.settings.set(AppearanceKeys.brightness, 'dark');
      final context = _context()..publish<NoteStore>(store);
      expect(
        await context.resolveAppearance(),
        const AppAppearance(
          style: AppStyle.studio,
          brightness: AppBrightnessMode.dark,
        ),
      );
      expect(
        settings.reads,
        unorderedEquals(['app.appearance.style', 'app.appearance.brightness']),
      );
    });

    test('no store → the defaults, no read', () async {
      final context = _context();
      expect(await context.resolveAppearance(), const AppAppearance());
    });

    test('a failing read → the defaults + one record', () async {
      final (store, settings) = _store();
      addTearDown(store.inner.close);
      settings.getError = StateError('settings table locked');
      final log = AppErrorLog();
      final context = _context(errorLog: log)..publish<NoteStore>(store);
      expect(await context.resolveAppearance(), const AppAppearance());
      expect(log.records, hasLength(1));
      expect(log.records.single.source, AppErrorSource.module);
    });
  });
}
