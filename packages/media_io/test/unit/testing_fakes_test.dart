// The VM platform fakes of package:media_io/testing.dart (m5-7/06-pdf 4.3.2, 8.1 T30 basic
// behaviour, 8.2 T38 completion): plain `extends` so `XPlatform.instance = fake` passes the
// token check; installFakeMediaPlatforms installs the three fakes and media_io's hooks (a temp
// directory, no foreground service) and dispose() restores everything; the record fake's
// scripted permission / encoders / states and the file stop() finishes; the player's load /
// seek / speed / failure; the picker's queue. (T38) With the fakes alone, the REAL services of
// mediaIoOverrides() record → stop → a recording row → open → play, and importImageForNote
// stores an image asset; dispose() after that restores the instances and deletes the temp
// directory with the recording and play-cache files in it.
//
// Real async (dart:io file writes and the native engine's file reads do not finish inside
// fake_async). The recorder service's clock is a real Stopwatch, so the record test waits a
// few milliseconds before stop (a stop at 0 ms keeps nothing — 6.6.3); nothing asserts on time.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_io/media_io.dart';
import 'package:media_io/src/testing/test_hooks.dart';
import 'package:media_io/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:record_platform_interface/record_platform_interface.dart';

import '../support/ipad.dart';

/// Lets [future] finish in widget-test fake time (the import's store writes are microtasks).
Future<T> _settled<T>(WidgetTester tester, Future<T> future) async {
  T? value;
  Object? error;
  StackTrace? stack;
  var done = false;
  unawaited(
    future.then(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object e, StackTrace st) {
        error = e;
        stack = st;
        done = true;
      },
    ),
  );
  for (var i = 0; i < 20 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(done, isTrue, reason: 'the future did not finish');
  if (error != null) Error.throwWithStackTrace(error!, stack!);
  return value as T;
}

Uint8List _audioBytes(int n) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 7 + 3) & 0xFF));

/// Waits until [playback] reaches [phase].
Future<void> _until(
  core.AudioPlaybackService playback,
  core.PlaybackPhase phase,
) async {
  if (playback.status.phase == phase) return;
  await playback.statusStream.firstWhere((s) => s.phase == phase);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('installFakeMediaPlatforms: instances and hooks; dispose restores (idempotent)', () {
    final before = (
      record: RecordPlatform.instance,
      player: JustAudioPlatform.instance,
      picker: ImagePickerPlatform.instance,
    );
    final fakes = installFakeMediaPlatforms(micPermission: false);
    expect(identical(RecordPlatform.instance, fakes.record), isTrue);
    expect(identical(JustAudioPlatform.instance, fakes.player), isTrue);
    expect(identical(ImagePickerPlatform.instance, fakes.picker), isTrue);
    expect(fakes.record.permission, isFalse);
    final dir = fakes.directory!;
    expect(Directory(dir).existsSync(), isTrue);
    expect(MediaTestHooks.directory, dir);
    expect(MediaTestHooks.noForegroundService, isTrue);

    fakes.dispose();
    fakes.dispose();
    expect(identical(RecordPlatform.instance, before.record), isTrue);
    expect(identical(JustAudioPlatform.instance, before.player), isTrue);
    expect(identical(ImagePickerPlatform.instance, before.picker), isTrue);
    expect(MediaTestHooks.directory, isNull);
    expect(MediaTestHooks.noForegroundService, isFalse);
    expect(Directory(dir).existsSync(), isFalse);
  });

  test(
    'FakeRecordPlatform: permission, encoders, states, the stopped file',
    () async {
      final fakes = installFakeMediaPlatforms();
      addTearDown(fakes.dispose);
      final record = fakes.record;
      const id = 'r1';
      await record.create(id);
      final states = <RecordState>[];
      final sub = record.onStateChanged(id).listen(states.add);
      addTearDown(sub.cancel);
      expect(await record.hasPermission(id, request: false), isTrue);
      expect(await record.isEncoderSupported(id, AudioEncoder.aacLc), isTrue);
      expect(await record.isEncoderSupported(id, AudioEncoder.wav), isFalse);

      final path = '${fakes.directory}/rec/a.m4a';
      await record.start(
        id,
        const RecordConfig(bitRate: 64000, numChannels: 1),
        path: path,
      );
      expect(await record.isRecording(id), isTrue);
      await record.pause(id);
      expect(await record.isPaused(id), isTrue);
      record.emitState(RecordState.record); // e.g. the system resumed
      record.fileBytes = Uint8List.fromList([1, 2, 3]);
      expect(await record.stop(id), path);
      expect(File(path).readAsBytesSync(), [1, 2, 3]);
      expect(await record.isRecording(id), isFalse);
      await pumpEventQueue();
      expect(states, [
        RecordState.record,
        RecordState.pause,
        RecordState.record,
        RecordState.stop,
      ]);
      expect(record.calls, [
        'create',
        'hasPermission(request: false)',
        'isEncoderSupported(aacLc)',
        'isEncoderSupported(wav)',
        'start(aacLc, 64000, 44100, 1, $path)',
        'isRecording',
        'pause',
        'isPaused',
        'stop',
        'isRecording',
      ]);
      await record.dispose(id);
    },
  );

  test('FakeJustAudioPlatform: load duration, seek, speed, completion, a failed load', () async {
    final player = FakeJustAudioPlatform(
      defaultDuration: const Duration(seconds: 3),
    );
    final p = await player.init(InitRequest(id: 'p1'));
    final events = <PlaybackEventMessage>[];
    final sub = p.playbackEventMessageStream.listen(events.add);
    addTearDown(sub.cancel);
    player.durations['file:///a.m4a'] = const Duration(milliseconds: 1500);

    final loaded = await p.load(
      LoadRequest(
        audioSourceMessage: ProgressiveAudioSourceMessage(
          id: 's1',
          uri: 'file:///a.m4a',
        ),
      ),
    );
    expect(loaded.duration, const Duration(milliseconds: 1500));
    await p.setSpeed(SetSpeedRequest(speed: 1.5));
    await p.seek(SeekRequest(position: const Duration(milliseconds: 700)));
    await p.play(PlayRequest());
    player.setPosition(const Duration(milliseconds: 900));
    player.complete();
    await p.pause(PauseRequest());
    await pumpEventQueue();
    expect(events.first.processingState, ProcessingStateMessage.ready);
    expect(events.last.processingState, ProcessingStateMessage.completed);
    expect(events.last.updatePosition, const Duration(milliseconds: 1500));

    player.failNextLoad();
    await expectLater(
      p.load(
        LoadRequest(
          audioSourceMessage: ProgressiveAudioSourceMessage(
            id: 's2',
            uri: 'blob:x',
          ),
        ),
      ),
      throwsA(isA<PlatformException>()),
    );
    final again = await p.load(
      LoadRequest(
        audioSourceMessage: ProgressiveAudioSourceMessage(
          id: 's3',
          uri: 'blob:x',
        ),
      ),
    );
    expect(again.duration, const Duration(seconds: 3));
    await player.disposePlayer(DisposePlayerRequest(id: 'p1'));
    expect(player.calls, [
      'init',
      'load:file:///a.m4a',
      'speed:1.5',
      'seek:700',
      'play',
      'pause',
      'load:blob:x',
      'load:blob:x',
      'disposePlayer',
    ]);
  });

  test('FakeImagePickerPlatform: queued picks, null = cancel, empty queue = cancel', () async {
    final picker = FakeImagePickerPlatform()
      ..enqueue(Uint8List.fromList([9, 8]), name: 'a.png')
      ..enqueue(null);
    final first = await picker.getImageFromSource(source: ImageSource.gallery);
    expect(first!.name, 'a.png');
    expect(await first.readAsBytes(), [9, 8]);
    expect(await picker.getImageFromSource(source: ImageSource.camera), isNull);
    expect(
      await picker.getImageFromSource(source: ImageSource.gallery),
      isNull,
    );
    expect(picker.sources, [
      ImageSource.gallery,
      ImageSource.camera,
      ImageSource.gallery,
    ]);
  });

  test('registerMediaWebPlugins on the VM does nothing', () {
    final before = JustAudioPlatform.instance;
    registerMediaWebPlugins();
    registerMediaWebPlugins();
    expect(identical(JustAudioPlatform.instance, before), isTrue);
  });

  group('the real mediaIoOverrides() services on the fakes alone (T38)', () {
    test('record → stop → a recording row → open → play; dispose restores and deletes the temp directory', () async {
      final before = (
        record: RecordPlatform.instance,
        player: JustAudioPlatform.instance,
        picker: ImagePickerPlatform.instance,
      );
      final fakes = installFakeMediaPlatforms();
      final store = core_testing.createFakeNoteStore();
      final container = ProviderContainer(
        overrides: [
          core.noteStoreProvider.overrideWithValue(store),
          ...mediaIoOverrides(),
        ],
      );
      var disposed = false;
      addTearDown(() async {
        if (!disposed) {
          container.dispose();
          fakes.dispose();
        }
        await store.close();
      });
      final dir = fakes.directory!;
      final dirUri = Uri.directory(dir).toString();
      final recorder = container.read(core.audioRecorderServiceProvider);
      final playback = container.read(core.audioPlaybackServiceProvider);

      // ① record → stop (record's platform is the fake; the file goes to the temp directory)
      expect(await recorder.checkSupport(), core.AudioSupport.supported);
      final note = await store.library.createNote(title: 'Lecture');
      final id = store.ids.newId();
      await recorder.start(recordingId: id, noteId: note.id);
      expect(recorder.status.phase, core.RecorderPhase.recording);
      final start = fakes.record.calls.singleWhere(
        (c) => c.startsWith('start('),
      );
      expect(start, startsWith('start(aacLc, 64000, '));
      expect(start, contains(dir));
      final bytes = _audioBytes(4096);
      fakes.record.fileBytes = bytes;
      // the service's clock is a real Stopwatch — a stop at 0 ms keeps nothing (6.6.3)
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final recording = await recorder.stop();
      expect(recorder.status.phase, core.RecorderPhase.idle);

      // ② the recording row and its asset (the native length is the decoder's — the fake
      //    player's default 2 s, 6.6.4)
      expect(recording, isNotNull);
      expect(recording!.id, id);
      expect(recording.noteId, note.id);
      expect(recording.durationMs, 2000);
      expect(await store.recordings.recordingsOf(note.id), [recording]);
      expect(await store.assets.readBytes(recording.assetId), bytes);
      expect(
        (await store.assets.getAsset(recording.assetId))!.mimeType,
        'audio/mp4',
      );
      expect(await store.recordingDrafts.listDrafts(), isEmpty);

      // ③ open → play → the end (just_audio's platform is the fake; the play cache is in the
      //    temp directory)
      await playback.open(recording);
      expect(playback.status.phase, core.PlaybackPhase.ready);
      expect(playback.status.recordingId, id);
      expect(playback.status.durationMs, 2000);
      await playback.play();
      await _until(playback, core.PlaybackPhase.playing);
      fakes.player.complete();
      await _until(playback, core.PlaybackPhase.completed);
      expect(playback.positionMs(), 2000);
      final loads = [
        for (final c in fakes.player.calls)
          if (c.startsWith('load:')) c.substring('load:'.length),
      ];
      // the stop path's length probe (the recording file), then the open (the play cache)
      expect(loads, hasLength(2));
      expect(loads, everyElement(startsWith(dirUri)));
      expect(loads.last, endsWith('${recording.assetId}.m4a'));
      expect(
        fakes.player.calls,
        containsAllInOrder(['load:${loads.last}', 'play']),
      );
      final cached = File.fromUri(Uri.parse(loads.last));
      expect(cached.readAsBytesSync(), bytes);

      // ④ dispose: the services go with the container; the instances come back and the temp
      //    directory goes with the files in it
      container.dispose();
      fakes.dispose();
      disposed = true;
      expect(identical(RecordPlatform.instance, before.record), isTrue);
      expect(identical(JustAudioPlatform.instance, before.player), isTrue);
      expect(identical(ImagePickerPlatform.instance, before.picker), isTrue);
      expect(MediaTestHooks.directory, isNull);
      expect(cached.existsSync(), isFalse);
      expect(Directory(dir).existsSync(), isFalse);
    });

    test('micPermission: false → the real recorder reports permissionDenied and refuses to start', () async {
      final fakes = installFakeMediaPlatforms(micPermission: false);
      final store = core_testing.createFakeNoteStore();
      final container = ProviderContainer(
        overrides: [
          core.noteStoreProvider.overrideWithValue(store),
          ...mediaIoOverrides(),
        ],
      );
      addTearDown(() async {
        container.dispose();
        fakes.dispose();
        await store.close();
      });
      final recorder = container.read(core.audioRecorderServiceProvider);
      expect(await recorder.checkSupport(), core.AudioSupport.permissionDenied);
      final note = await store.library.createNote(title: 'n');
      await expectLater(
        recorder.start(recordingId: store.ids.newId(), noteId: note.id),
        throwsUnsupportedError,
      );
      expect(await store.recordingDrafts.listDrafts(), isEmpty);
      expect(fakes.record.calls.where((c) => c.startsWith('start(')), isEmpty);
    });

    testWidgets(
      'importImageForNote → an image asset (image_picker\'s platform is the fake)',
      (tester) async {
        final fakes = installFakeMediaPlatforms();
        addTearDown(fakes.dispose);
        final store = core_testing.createFakeNoteStore();
        addTearDown(store.close);
        late BuildContext context;
        await pumpOnIpad(
          tester,
          ProviderScope(
            overrides: [
              core.noteStoreProvider.overrideWithValue(store),
              ...mediaIoOverrides(),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (c) {
                    context = c;
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ),
        );
        final png = Uint8List.fromList(
          img.encodePng(img.Image(width: 120, height: 80)),
        );
        fakes.picker.enqueue(png, name: 'board.png');

        final image = await _settled(
          tester,
          importImageForNote(context, core.ImageImportSource.photos),
        );
        expect(fakes.picker.sources, [ImageSource.gallery]);
        expect(image, isNotNull);
        expect((image!.pixelWidth, image.pixelHeight), (120, 80));
        expect(image.asset.type, core.AssetType.image);
        expect(image.asset.mimeType, 'image/png');
        expect(image.asset.fileName, 'board.png');
        final assets = await _settled(tester, store.assets.listAssets());
        expect([for (final a in assets) a.id], [image.asset.id]);
        // an empty queue = the user cancelled: null, nothing stored
        expect(
          await _settled(
            tester,
            importImageForNote(context, core.ImageImportSource.photos),
          ),
          isNull,
        );
        expect(await _settled(tester, store.assets.listAssets()), hasLength(1));
      },
    );
  });
}
