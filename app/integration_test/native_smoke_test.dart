// Android emulator smoke (docs/plans/m5-7/01-infra.md 6.10.5, 8.2 J21 —
// P-C): run by .github/workflows/android-emulator.yml (manual only) on an
// API 34 google_apis x86_64 emulator with
// `cd app && flutter test integration_test/native_smoke_test.dart`. The only
// automatic look at the native paths while there is no Android device (U2).
//
// The app starts the way runNoteApp starts it — productionModules() and
// AppFeatures.compileTime through AppBootstrapper — and the test reads the
// providers of the start:
//
//   ① native storage paths: openNoteStore with the two paths (J4, 6.9) →
//      one note → shut down → start again → the note is there;
//   ② the image import sources media_io offers (PDF 6.12: photos and camera
//      on Android) and the editor slot FeatureWiringModule filled with them;
//   ③ ML Kit (RecognitionModule's real recognizer): the 'en' model, then a
//      synthetic 'hi' — skipped when the model does not download;
//   ④ 2 s of recording from the emulator microphone (silent) → a recording
//      row of the note.
//
// The workflow installs a debug APK of the app with `adb install -g` before
// `flutter test`, so RECORD_AUDIO and POST_NOTIFICATIONS are granted (the
// permission dialog is outside Flutter); flutter test reinstalls with
// `adb install -r`, which keeps them.
//
// Not run by `ws test` or `flutter test` without a path (only test/ is
// theirs); analysed and formatted with the app (ws check R11).
library;

import 'dart:io' show File;
import 'dart:math' show cos, pi, sin;
import 'dart:typed_data';

import 'package:feature_editor/feature_editor.dart'
    show editorImageImporterProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:media_io/media_io.dart' show supportedImageSources;
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/features/app_features.dart';
import 'package:noteapp/src/modules/production_modules.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:noteapp/src/storage/native_storage_paths.dart';
import 'package:noteapp/src/web/web_platform.dart';

/// One start of the app: the bootstrapper, its root container and log.
final class _App {
  _App(this.bootstrapper, this.success, this.errorLog)
    : container = ProviderContainer(overrides: success.overrides);

  final AppBootstrapper bootstrapper;
  final BootstrapSuccess success;
  final AppErrorLog errorLog;
  final ProviderContainer container;

  NoteStore get store => container.read(noteStoreProvider);

  Future<void> stop() async {
    container.dispose();
    await bootstrapper.shutdown();
  }
}

/// The production start (runNoteApp's bootstrapper, without the widgets).
Future<_App> _start() async {
  final errorLog = AppErrorLog(capacity: 100);
  final web = createWebPlatform();
  final bootstrapper = AppBootstrapper(
    modules: productionModules(),
    buildInfo: BuildInfo.fromEnvironment(),
    runtimeInfo: RuntimeInfo.detect(web),
    web: web,
    errorLog: errorLog,
    ownerId: kLocalOwnerId,
    features: AppFeatures.compileTime,
  );
  final result = await bootstrapper.run();
  if (result is! BootstrapSuccess) {
    await bootstrapper.shutdown();
    fail('the start failed: $result — ${errorLog.records}');
  }
  expect(
    {for (final step in result.report.steps) step.id: step.outcome.name},
    {for (final step in result.report.steps) step.id: 'ok'},
    reason: '${errorLog.records}',
  );
  return _App(bootstrapper, result, errorLog);
}

/// A stroke of [points] (page pt), one sample every 8 ms from [startMs].
HandwritingTrace _trace(List<(double, double)> points, double startMs) =>
    HandwritingTrace(
      xs: Float32List.fromList([for (final (x, _) in points) x]),
      ys: Float32List.fromList([for (final (_, y) in points) y]),
      ts: Float64List.fromList([
        for (var i = 0; i < points.length; i++) startMs + 8.0 * i,
      ]),
    );

List<(double, double)> _line(
  (double, double) from,
  (double, double) to, {
  int steps = 16,
}) => [
  for (var i = 0; i <= steps; i++)
    (
      from.$1 + (to.$1 - from.$1) * i / steps,
      from.$2 + (to.$2 - from.$2) * i / steps,
    ),
];

/// A hand-shaped 'hi' (y down, x-height 30 pt): 'h' in one stroke (the
/// ascender down, back up, the arch, the leg down), then the stem and the
/// dot of 'i'.
List<HandwritingTrace> _syntheticHi() {
  const t0 = 1700000000000.0;
  final h = [
    ..._line((10, 0), (10, 60), steps: 30),
    ..._line((10, 58), (10, 40), steps: 9),
    for (var i = 1; i <= 16; i++)
      (22 - 12 * cos(pi * i / 16), 40 - 12 * sin(pi * i / 16)),
    ..._line((34, 42), (34, 60), steps: 9),
  ];
  final stem = _line((48, 32), (48, 60), steps: 14);
  final dot = _line((48, 20), (48.6, 20.6), steps: 2);
  return [
    _trace(h, t0),
    _trace(stem, t0 + 8.0 * h.length + 160),
    _trace(dot, t0 + 8.0 * (h.length + stem.length) + 320),
  ];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('① native storage paths: openNoteStore → one note → start '
      'again → the note is there', (tester) async {
    final paths = await resolveNativeStoragePaths();
    expect(paths, isNotNull);
    final title = 'native smoke ${DateTime.now().microsecondsSinceEpoch}';

    final first = await _start();
    final NoteId noteId;
    try {
      // CORE opened the file database at the path the shell resolved.
      expect(File(paths!.databasePath).existsSync(), isTrue, reason: '$paths');
      noteId = (await first.store.library.createNote(title: title)).id;
      await first.store.flush();
      expect(first.errorLog.records, isEmpty);
    } finally {
      await first.stop();
    }

    final second = await _start();
    try {
      final note = await second.store.library.getNote(noteId);
      expect(note, isNotNull);
      expect(note!.title, title);
      expect(second.errorLog.records, isEmpty);
    } finally {
      await second.stop();
    }
  });

  testWidgets('② image import sources: media_io → the editor slot', (
    tester,
  ) async {
    final app = await _start();
    try {
      final sources = supportedImageSources();
      expect(
        sources,
        containsAll(const {ImageImportSource.photos, ImageImportSource.camera}),
      );
      expect(app.container.read(editorImageImporterProvider)?.sources, sources);
    } finally {
      await app.stop();
    }
  });

  testWidgets('③ ML Kit: the en model, then a synthetic "hi" (skipped when '
      'the model does not download)', (tester) async {
    final app = await _start();
    try {
      final recognizer = app.container.read(handwritingRecognizerProvider);
      expect(recognizer.isAvailable, isTrue);
      expect(recognizer.engineId, startsWith('mlkit-digital-ink/'));
      try {
        await recognizer
            .ensureModel('en', wifiOnly: false)
            .timeout(const Duration(minutes: 4));
      } on Object catch (error) {
        markTestSkipped('ML Kit en model did not download: $error');
        return;
      }
      expect(await recognizer.modelState('en'), RecognitionModelState.ready);
      final candidates = await recognizer.recognizeLine(
        HandwritingLineInput(
          _syntheticHi(),
          writingAreaPt: const Size(200, 80),
        ),
        languageTag: 'en',
      );
      expect(candidates, isNotEmpty);
      expect([
        for (final c in candidates.take(3)) c.text.trim().toLowerCase(),
      ], contains('hi'));
      expect(candidates.first.languageTag, 'en');
    } finally {
      await app.stop();
    }
  });

  testWidgets('④ recording: 2 s from the emulator microphone → a recording '
      'row', (tester) async {
    final app = await _start();
    try {
      final store = app.store;
      final note = await store.library.createNote(title: 'native recording');
      final recorder = app.container.read(audioRecorderServiceProvider);
      // RECORD_AUDIO was granted at install (adb install -g).
      expect(await recorder.checkSupport(), AudioSupport.supported);
      final recordingId = app.container.read(idGeneratorProvider).newId();
      await recorder.start(recordingId: recordingId, noteId: note.id);
      expect(recorder.status.phase, RecorderPhase.recording);
      await Future<void>.delayed(const Duration(seconds: 2));
      final recording = await recorder.stop();
      expect(recording, isNotNull);
      expect(recording!.id, recordingId);
      expect(recording.noteId, note.id);
      expect(recording.durationMs, greaterThan(0));
      expect(recorder.status.phase, RecorderPhase.idle);
      expect(
        [for (final r in await store.recordings.recordingsOf(note.id)) r.id],
        [recordingId],
      );
      expect(app.errorLog.records, isEmpty);
    } finally {
      await app.stop();
    }
  });
}
