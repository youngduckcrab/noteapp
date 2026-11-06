// media_io init_test (m5-7/06-pdf 4.2.1, 4.2.2, 8.1 T30 — 2nd-round contract 7.2.12, 7.6.2
// R2-B4): initializeMediaIo is idempotent and keeps the first config (a different one
// asserts); MediaIoConfig has value equality and range asserts; mediaIoOverrides() is the
// empty list, so a container that holds only it reads CORE's audio providers without an
// exception and gets CORE's defaults ('not supported'); the other R2-B4 bodies
// (supportedImageSources, importImageForNote, mediaDevOverlayLinesProvider).
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/media_io.dart';
import 'package:media_io/src/init.dart' show MediaIoRuntime;
import 'package:note_core/note_core.dart' as core;

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

    test(
      'completes at once and never throws without platform features',
      () async {
        final watch = Stopwatch()..start();
        await initializeMediaIo();
        expect(watch.elapsedMilliseconds, lessThan(1000));
      },
    );
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

  group('mediaIoOverrides() — R2-B4: no override, CORE defaults', () {
    test('the empty list, with and without a config', () {
      expect(mediaIoOverrides(), isEmpty);
      expect(
        mediaIoOverrides(config: const MediaIoConfig(bitRate: 96000)),
        isEmpty,
      );
    });

    test(
      'a container with only mediaIoOverrides() reads the audio ports',
      () async {
        final container = ProviderContainer.test(overrides: mediaIoOverrides());
        final recorder = container.read(core.audioRecorderServiceProvider);
        final playback = container.read(core.audioPlaybackServiceProvider);
        expect(recorder, isA<core.UnsupportedAudioRecorder>());
        expect(playback, isA<core.UnsupportedAudioPlayback>());
        expect(await recorder.checkSupport(), core.AudioSupport.unsupported);
        expect(await recorder.pendingDrafts(), isEmpty);
        // No store was needed: the container really has none.
        expect(() => container.read(core.noteStoreProvider), throwsA(anything));
      },
    );
  });

  group('other R2-B4 bodies', () {
    test('supportedImageSources() is empty', () {
      expect(supportedImageSources(), isEmpty);
    });

    testWidgets('importImageForNote → null for every source', (tester) async {
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
        expect(
          await importImageForNote(context, source),
          isNull,
          reason: '$source',
        );
      }
    });

    test('mediaDevOverlayLinesProvider: an empty list, disposed with the container', () {
      final container = ProviderContainer(overrides: mediaIoOverrides());
      final lines = container.read(mediaDevOverlayLinesProvider);
      expect(lines.value, isEmpty);
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
