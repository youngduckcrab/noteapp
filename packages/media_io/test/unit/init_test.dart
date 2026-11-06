// media_io init_test (m5-7/06-pdf 4.2.1, 4.2.2, 8.1 T30, v2 8.2 T37 — 2nd-round contract
// 7.2.12): initializeMediaIo is idempotent, keeps the first config (a different one asserts) and
// prepares the platform without throwing; MediaIoConfig has value equality and range asserts;
// (T37) mediaIoOverrides() is exactly the two audio overrides — media_io's recorder and player
// with the given config (else MediaIoRuntime.config), read in a container WITHOUT a store
// without an exception (the store is read on first use), working once a store is there, and
// disposed with the container; the image import bodies before initializeMediaIo.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/media_io.dart';
import 'package:media_io/src/init.dart' show MediaIoRuntime;
import 'package:media_io/src/playback/playback_service.dart';
import 'package:media_io/src/record/recorder_engine_native.dart';
import 'package:media_io/src/record/recorder_service.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

void main() {
  group('initializeMediaIo', () {
    setUp(MediaIoRuntime.debugReset);
    tearDown(MediaIoRuntime.debugReset);

    test('idempotent; the first config stays', () async {
      expect(MediaIoRuntime.isInitialized, isFalse);
      expect(MediaIoRuntime.config, const MediaIoConfig());
      const config = MediaIoConfig(bitRate: 96000);
      await initializeMediaIo(config: config);
      expect(MediaIoRuntime.isInitialized, isTrue);
      expect(MediaIoRuntime.config, config);
      await initializeMediaIo(config: config);
      expect(MediaIoRuntime.config, config);
    });

    test('a different config asserts and the first stays', () async {
      await initializeMediaIo();
      await expectLater(
        initializeMediaIo(config: const MediaIoConfig(sampleRate: 48000)),
        throwsA(isA<AssertionError>()),
      );
      expect(MediaIoRuntime.config, const MediaIoConfig());
    });

    test('prepares the platform (Android FGS options) and never throws without platform features', () async {
      // the flutter_test default platform is android: FlutterForegroundTask.init runs
      // (sync, no channel call) — and a platform without features only shows later as
      // checkSupport() == unsupported
      await initializeMediaIo();
      expect(MediaIoRuntime.isInitialized, isTrue);
      MediaIoRuntime.debugReset();
      await initializeMediaIo(
        config: const MediaIoConfig(androidForegroundService: false),
      );
      expect(MediaIoRuntime.isInitialized, isTrue);
    });
  });

  group('MediaIoConfig', () {
    test('value equality over every field', () {
      expect(MediaIoConfig(bitRate: int.parse('64000')), const MediaIoConfig());
      expect(
        MediaIoConfig(bitRate: int.parse('64000')).hashCode,
        const MediaIoConfig().hashCode,
      );
      for (final other in const [
        MediaIoConfig(bitRate: 32000),
        MediaIoConfig(sampleRate: 22050),
        MediaIoConfig(allowNonAacOnWeb: false),
        MediaIoConfig(webDraftChunkMs: 250),
        MediaIoConfig(androidForegroundService: false),
      ]) {
        expect(other == const MediaIoConfig(), isFalse, reason: '$other');
      }
    });

    test('range asserts (4.2.1)', () {
      MediaIoConfig make({
        int bitRate = 64000,
        int sampleRate = 44100,
        int chunk = 1000,
      }) => MediaIoConfig(
        bitRate: bitRate,
        sampleRate: sampleRate,
        webDraftChunkMs: chunk,
      );
      expect(() => make(bitRate: 31999), throwsA(isA<AssertionError>()));
      expect(() => make(bitRate: 128001), throwsA(isA<AssertionError>()));
      expect(() => make(sampleRate: 16000), throwsA(isA<AssertionError>()));
      expect(() => make(chunk: 249), throwsA(isA<AssertionError>()));
      expect(() => make(chunk: 5001), throwsA(isA<AssertionError>()));
      expect(
        make(bitRate: 32000, sampleRate: 22050, chunk: 250).bitRate,
        32000,
      );
      expect(
        make(bitRate: 128000, sampleRate: 48000, chunk: 5000).webDraftChunkMs,
        5000,
      );
    });
  });

  group('mediaIoOverrides() (4.2.2 — T37)', () {
    setUp(MediaIoRuntime.debugReset);
    tearDown(MediaIoRuntime.debugReset);

    test('exactly the two audio overrides, with and without a config', () {
      expect(mediaIoOverrides(), hasLength(2));
      expect(
        mediaIoOverrides(config: const MediaIoConfig(bitRate: 96000)),
        hasLength(2),
      );
    });

    test('a container without a store reads both providers (the store is read on first use)', () {
      final container = ProviderContainer.test(overrides: mediaIoOverrides());
      final recorder = container.read(core.audioRecorderServiceProvider);
      final playback = container.read(core.audioPlaybackServiceProvider);
      expect(recorder, isA<MediaRecorderService>());
      expect(playback, isA<JustAudioPlaybackService>());
      expect(recorder.status.phase, core.RecorderPhase.idle);
      expect(recorder.offsetNowMs(), isNull);
      expect(playback.status.phase, core.PlaybackPhase.idle);
      expect(playback.positionMs(), 0);
      // VM = the native engine (record + file — T33), Web Locks: none
      final service = recorder as MediaRecorderService;
      expect(service.engine, isA<NativeRecorderEngine>());
      expect(service.devWriterState.locks, 'none');
      // No store was needed: the container really has none.
      expect(() => container.read(core.noteStoreProvider), throwsA(anything));
    });

    test('the given config, else the one of initializeMediaIo', () async {
      MediaRecorderService recorderOf(List<Override> overrides) =>
          ProviderContainer.test(overrides: overrides)
                  .read(core.audioRecorderServiceProvider)
              as MediaRecorderService;

      expect(
        recorderOf(
          mediaIoOverrides(config: const MediaIoConfig(bitRate: 96000)),
        ).config,
        const MediaIoConfig(bitRate: 96000),
      );
      expect(recorderOf(mediaIoOverrides()).config, const MediaIoConfig());
      await initializeMediaIo(
        config: const MediaIoConfig(webDraftChunkMs: 500),
      );
      expect(
        recorderOf(mediaIoOverrides()).config,
        const MediaIoConfig(webDraftChunkMs: 500),
      );
    });

    test('with a store: drafts and playback read it; the services go with the container', () async {
      final store = core_testing.createFakeNoteStore();
      final container = ProviderContainer(
        overrides: [
          core.noteStoreProvider.overrideWithValue(store),
          ...mediaIoOverrides(),
        ],
      );
      final recorder = container.read(core.audioRecorderServiceProvider);
      final playback = container.read(core.audioPlaybackServiceProvider);
      expect(await recorder.pendingDrafts(), isEmpty);
      // a missing recording asset fails the open with assetMissing, it does not throw
      final note = await store.library.createNote(title: 'n');
      final missing = core.Recording(
        id: store.ids.newId(),
        noteId: note.id,
        assetId: store.ids.newId(),
        startedAt: 1,
        durationMs: 1000,
        createdAt: 1,
        updatedAt: 1,
      );
      await playback.open(missing);
      expect(playback.status.phase, core.PlaybackPhase.failed);
      container.dispose();
      // disposed: a new start is refused
      await expectLater(
        recorder.start(recordingId: store.ids.newId(), noteId: note.id),
        throwsStateError,
      );
    });
  });

  group('other R2-B4 bodies', () {
    // (T35b) the image import bodies are real now: unit/image_import_test.dart,
    // unit/supported_sources_test.dart, web/image_codec_browser_test.dart.
    test('supportedImageSources() works before initializeMediaIo (T35b)', () {
      MediaIoRuntime.debugReset();
      // the flutter_test default platform is android
      expect(supportedImageSources(), {
        core.ImageImportSource.photos,
        core.ImageImportSource.camera,
      });
      expect(MediaIoRuntime.isInitialized, isFalse);
    });

    testWidgets(
      'importImageForNote needs the app ProviderScope (T35b — it fails before picking)',
      (tester) async {
        late BuildContext context;
        await tester.pumpWidget(
          Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        );
        for (final source in core.ImageImportSource.values) {
          await expectLater(
            importImageForNote(context, source),
            throwsA(anything),
            reason: '$source',
          );
        }
      },
    );

    test('mediaDevOverlayLinesProvider (T37 — 6.14 lines; dev_overlay_lines_test), disposed with the container', () {
      final container = ProviderContainer(overrides: mediaIoOverrides());
      final lines = container.read(mediaDevOverlayLinesProvider);
      expect(lines.value.first, startsWith('rec: idle'));
      expect(
        identical(lines, container.read(mediaDevOverlayLinesProvider)),
        isTrue,
      );
      container.dispose();
      expect(
        () => (lines as ChangeNotifier).addListener(() {}),
        throwsFlutterError,
      );
    });
  });
}
