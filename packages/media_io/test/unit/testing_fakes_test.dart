// The VM platform fakes of package:media_io/testing.dart (m5-7/06-pdf 4.3.2, 8.1 T30 — basic
// behaviour): plain `extends` so `XPlatform.instance = fake` passes the token check;
// installFakeMediaPlatforms installs the three fakes and media_io's hooks (a temp directory,
// no foreground service) and dispose() restores everything; the record fake's scripted
// permission / encoders / states and the file stop() finishes; the player's load / seek /
// speed / failure; the picker's queue.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:media_io/src/testing/test_hooks.dart';
import 'package:media_io/testing.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

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
}
