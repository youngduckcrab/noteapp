// The native recorder engine (m5-7/06-pdf 6.9.1, 6.9.2, 6.9.5 — 8.2 T33) under the real
// MediaRecorderService, on FakeRecordPlatform (installFakeMediaPlatforms — the temp directory
// stands in for the app support directory, no foreground service) and CORE's fake store:
// the record config (AAC-LC, mono, 64k / media.bitRate, pause on interruptions), the file path
// `<support>/media_io/rec/<id>.m4a`, the draft as a row only (0 chunks), a system pause →
// bySystem (interrupted, no automatic resume), stop → the file bytes become the asset with the
// decoder's length, permission refused → permissionDenied, a failed record.start, cancel, the
// abandoned file recovered on the next start-up (decoder length > 0) or deleted (length 0),
// orphan files deleted on the first pendingDrafts().
//
// Real async (dart:io file reads do not finish inside fake_async); the recording clock is a
// FakeStopwatch moved by hand and the store's clock a FakeAsync clock moved by hand, so nothing
// reads the wall clock.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/config.dart';
import 'package:media_io/src/errors.dart';
import 'package:media_io/src/providers.dart';
import 'package:media_io/src/record/recorder_engine_native.dart';
import 'package:media_io/src/record/recording_output.dart';
import 'package:media_io/src/tuning.dart';
import 'package:media_io/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:record_platform_interface/record_platform_interface.dart';

import '../support/native_world.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NativeWorld w;
  setUp(() async {
    w = NativeWorld();
    await w.init();
  });
  tearDown(() => w.dispose());

  group('start (6.9.1)', () {
    test('AAC-LC mono 64k, pause on interruptions, the support-directory file, a row-only draft', () async {
      final s = w.service();
      final id = w.store.ids.newId();
      await s.start(recordingId: id, noteId: w.noteId);

      expect(s.status.phase, core.RecorderPhase.recording);
      expect(
        w.record.calls,
        contains('start(aacLc, 64000, 44100, 1, ${w.pathOf(id)})'),
      );
      expect(w.pathOf(id), endsWith('/media_io/rec/$id.m4a'));
      final config = w.record.lastConfig!;
      expect(config.audioInterruption, AudioInterruptionMode.pause);
      expect(config.iosConfig.categoryOptions, [
        IosAudioCategoryOption.defaultToSpeaker,
        IosAudioCategoryOption.allowBluetooth,
        IosAudioCategoryOption.allowBluetoothA2DP,
      ]);
      expect(s.status.mimeType, 'audio/mp4');
      expect(s.status.crossPlatformPlayable, isTrue);
      // Android (the test default) without the service: foreground only
      expect(s.status.backgroundCapable, isFalse);

      final drafts = await w.store.recordingDrafts.listDrafts();
      expect(drafts, hasLength(1));
      expect(drafts.single.recordingId, id);
      expect(drafts.single.mimeType, 'audio/mp4');
      expect(drafts.single.chunkCount, 0);
    });

    test('media.bitRate and the config sample rate reach record', () async {
      await w.store.settings.set(MediaSettingKeys.bitRate, 96000);
      final s = w.service(config: const MediaIoConfig(sampleRate: 48000));
      final id = w.store.ids.newId();
      await s.start(recordingId: id, noteId: w.noteId);
      expect(
        w.record.calls,
        contains('start(aacLc, 96000, 48000, 1, ${w.pathOf(id)})'),
      );
    });

    test('the config the device applied shows on the developer note', () async {
      w.record.appliedConfig = const RecordConfig(
        bitRate: 48000,
        numChannels: 1,
      );
      final engine = NativeRecorderEngine();
      final s = w.service(engine: engine);
      expect(engine.developerNote, isNull);
      await s.start(recordingId: w.store.ids.newId(), noteId: w.noteId);
      expect(engine.appliedConfig?.bitRate, 48000);
      expect(engine.developerNote, contains('config applied: aacLc 48000 bps'));
    });

    test(
      'record.start fails → engineFailed, the draft discarded, no file',
      () async {
        w.record.startError = StateError('no microphone');
        final s = w.service();
        final id = w.store.ids.newId();
        await expectLater(
          s.start(recordingId: id, noteId: w.noteId),
          throwsA(
            isA<MediaIoException>().having(
              (e) => e.code,
              'code',
              MediaErrorCode.engineFailed,
            ),
          ),
        );
        expect(s.status.phase, core.RecorderPhase.idle);
        expect(await w.store.recordingDrafts.listDrafts(), isEmpty);
        expect(File(w.pathOf(id)).existsSync(), isFalse);
        // the next start works
        w.record.fileBytes = fileOf(10);
        await s.start(recordingId: w.store.ids.newId(), noteId: w.noteId);
        expect(s.status.phase, core.RecorderPhase.recording);
      },
    );
  });

  group('support (4.2.3)', () {
    test('permission refused → permissionDenied; start throws UnsupportedError and records nothing', () async {
      w.record.permission = false;
      final s = w.service();
      expect(await s.checkSupport(), core.AudioSupport.permissionDenied);
      expect(
        await s.checkSupport(requestPermission: true),
        core.AudioSupport.permissionDenied,
      );
      expect(w.record.calls, contains('hasPermission(request: true)'));
      await expectLater(
        s.start(recordingId: w.store.ids.newId(), noteId: w.noteId),
        throwsUnsupportedError,
      );
      expect(w.record.calls.where((c) => c.startsWith('start(')), isEmpty);
      expect(await w.store.recordingDrafts.listDrafts(), isEmpty);
      w.record.permission = true;
      expect(await s.checkSupport(), core.AudioSupport.supported);
    });

    test('no AAC encoder → unsupported', () async {
      final fake = FakeRecordPlatform(encoders: const {AudioEncoder.opus});
      RecordPlatform.instance = fake; // fakes.dispose() restores the original
      final s = w.service();
      expect(await s.checkSupport(), core.AudioSupport.unsupported);
      expect(fake.calls, contains('isEncoderSupported(aacLc)'));
    });
  });

  group('state events (6.9.2)', () {
    test('a pause nobody asked for → paused + interrupted (systemInterruption), no automatic resume', () async {
      final s = w.service();
      await s.start(recordingId: w.store.ids.newId(), noteId: w.noteId);
      w.record.emitState(RecordState.pause); // a call / Siri / audio focus lost
      await pumpEventQueue();
      expect(s.status.phase, core.RecorderPhase.paused);
      expect(s.status.interrupted, isTrue);
      expect(
        (s.status.error! as MediaIoException).code,
        MediaErrorCode.systemInterruption,
      );
      expect(w.record.calls, isNot(contains('resume')));

      await s.resume(); // the user taps [이어서 녹음]
      await pumpEventQueue();
      expect(w.record.calls.last, 'resume');
      expect(s.status.phase, core.RecorderPhase.recording);
      expect(s.status.interrupted, isFalse);
      expect(s.status.error, isNull);
    });

    test('the user pause / resume are not system events (their state events are expected)', () async {
      final s = w.service();
      await s.start(recordingId: w.store.ids.newId(), noteId: w.noteId);
      await s.pause();
      await pumpEventQueue();
      expect(s.status.phase, core.RecorderPhase.paused);
      expect(s.status.interrupted, isFalse);
      await s.resume();
      await s.pause();
      await s.resume();
      await pumpEventQueue();
      expect(s.status.phase, core.RecorderPhase.recording);
      expect(s.status.interrupted, isFalse);
      expect(w.record.calls.where((c) => c == 'pause' || c == 'resume'), [
        'pause',
        'resume',
        'pause',
        'resume',
      ]);
    });

    test('a stop nobody asked for → engineFailed (stop only); stop still saves the file', () async {
      final s = w.service();
      await s.start(recordingId: w.store.ids.newId(), noteId: w.noteId);
      w.recorded = const Duration(seconds: 1);
      w.record.emitState(RecordState.stop);
      await pumpEventQueue();
      expect(s.status.phase, core.RecorderPhase.paused);
      expect(s.status.interrupted, isTrue);
      expect(
        (s.status.error! as MediaIoException).code,
        MediaErrorCode.engineFailed,
      );
      w.record.fileBytes = fileOf(64);
      expect((await s.stop())?.durationMs, 2000);
    });
  });

  group('stop · cancel (6.9.1, 6.6.3)', () {
    test('stop → the file bytes are the asset (audio/mp4), length from the decoder, draft and file gone', () async {
      final s = w.service();
      final id = w.store.ids.newId();
      await s.start(recordingId: id, noteId: w.noteId);
      final bytes = fileOf(4096);
      w.record.fileBytes = bytes;
      w.recorded = const Duration(milliseconds: 2100);
      // the decoder's length (FakeJustAudioPlatform) — not the clock
      w.fakes.player.durations[Uri.file(w.pathOf(id))
          .toString()] = const Duration(
        milliseconds: 1980,
      );

      final recording = await s.stop();
      expect(recording, isNotNull);
      expect(recording!.id, id);
      expect(recording.durationMs, 1980);
      expect(await w.store.assets.readBytes(recording.assetId), bytes);
      expect(
        (await w.store.assets.getAsset(recording.assetId))!.mimeType,
        'audio/mp4',
      );
      expect(await w.store.recordingDrafts.listDrafts(), isEmpty);
      expect(File(w.pathOf(id)).existsSync(), isFalse);
      expect(s.status.phase, core.RecorderPhase.idle);
      expect(s.diagnostics.lastRecording?.source, DurationSource.probe);
    });

    test('the decoder cannot read the length → the clock', () async {
      final s = w.service();
      final id = w.store.ids.newId();
      await s.start(recordingId: id, noteId: w.noteId);
      w.record.fileBytes = fileOf(100);
      w.recorded = const Duration(milliseconds: 1500);
      w.fakes.player.durations[Uri.file(w.pathOf(id)).toString()] =
          Duration.zero;
      final recording = await s.stop();
      expect(recording!.durationMs, 1500);
      expect(s.diagnostics.lastRecording?.source, DurationSource.clock);
    });

    test(
      'cancel → no recording, the file deleted, the draft discarded',
      () async {
        final s = w.service();
        final id = w.store.ids.newId();
        await s.start(recordingId: id, noteId: w.noteId);
        File(w.pathOf(id))
            .writeAsBytesSync(fileOf(10)); // what record wrote so far
        await s.cancel();
        expect(w.record.calls.last, 'cancel');
        expect(File(w.pathOf(id)).existsSync(), isFalse);
        expect(await w.store.recordingDrafts.listDrafts(), isEmpty);
        expect(await w.store.recordings.recordingsOf(w.noteId), isEmpty);
      },
    );
  });

  group('the next start-up (6.9.5)', () {
    Future<core.RecordingId> abandonOne(Uint8List bytes) async {
      final s = w.service();
      final id = w.store.ids.newId();
      await s.start(recordingId: id, noteId: w.noteId);
      w.record.fileBytes = bytes;
      w.recorded = const Duration(seconds: 3);
      await s.dispose(); // the app goes away: record stops, the file and the row stay
      expect(w.record.calls.sublist(w.record.calls.length - 2), [
        'stop',
        'dispose',
      ]);
      expect(File(w.pathOf(id)).existsSync(), isTrue);
      final drafts = await w.store.recordingDrafts.listDrafts();
      expect(drafts.single.recordingId, id);
      expect(drafts.single.chunkCount, 0);
      w.time.elapse(
        const Duration(seconds: 20),
      ); // past the recent-draft window
      return id;
    }

    test('a leftover file the decoder reads → asset + recording 복구된 녹음, file deleted', () async {
      final bytes = fileOf(2048);
      final id = await abandonOne(bytes);
      final next = w.service();
      final pending = await next.pendingDrafts();
      expect(pending, hasLength(1));
      final recording = await next.recoverDraft(pending.single.draftId);
      expect(recording, isNotNull);
      expect(recording!.id, id);
      expect(recording.title, MediaTuning.recoveredTitle);
      expect(recording.durationMs, 2000); // FakeJustAudioPlatform default
      expect(await w.store.assets.readBytes(recording.assetId), bytes);
      expect(File(w.pathOf(id)).existsSync(), isFalse);
      expect(await w.store.recordingDrafts.listDrafts(), isEmpty);
    });

    test('a leftover file the decoder cannot open (length 0) → file and draft deleted, null', () async {
      final id = await abandonOne(fileOf(512));
      w.fakes.player.durations[Uri.file(w.pathOf(id)).toString()] =
          Duration.zero;
      final next = w.service();
      final pending = await next.pendingDrafts();
      expect(await next.recoverDraft(pending.single.draftId), isNull);
      expect(File(w.pathOf(id)).existsSync(), isFalse);
      expect(await w.store.recordingDrafts.listDrafts(), isEmpty);
      expect(await w.store.recordings.recordingsOf(w.noteId), isEmpty);
    });

    test('no leftover file → the draft is dropped, null', () async {
      final id = await abandonOne(fileOf(16));
      File(w.pathOf(id)).deleteSync();
      final next = w.service();
      final pending = await next.pendingDrafts();
      expect(await next.recoverDraft(pending.single.draftId), isNull);
      expect(await w.store.recordingDrafts.listDrafts(), isEmpty);
    });

    test('files without a draft row are deleted on the first pendingDrafts(); files with one stay', () async {
      final kept = w.store.ids.newId();
      await w.store.recordingDrafts.begin(
        recordingId: kept,
        noteId: w.noteId,
        mimeType: 'audio/mp4',
        startedAt: 0,
      );
      Directory(w.recDir).createSync(recursive: true);
      File(w.pathOf(kept)).writeAsBytesSync(fileOf(8));
      final orphan = File('${w.recDir}/${nativeRecordingFileName('gone')}')
        ..writeAsBytesSync(fileOf(8));
      final s = w.service();
      await s.pendingDrafts();
      expect(orphan.existsSync(), isFalse);
      expect(File(w.pathOf(kept)).existsSync(), isTrue);
      // once per service: a later orphan waits for the next start-up
      orphan.writeAsBytesSync(fileOf(8));
      await s.pendingDrafts();
      expect(orphan.existsSync(), isTrue);
    });

    test('leftoverFile is null while that recording runs; the active file is never an orphan', () async {
      final engine = NativeRecorderEngine();
      final s = w.service(engine: engine);
      final id = w.store.ids.newId();
      await s.start(recordingId: id, noteId: w.noteId);
      File(w.pathOf(id)).writeAsBytesSync(fileOf(8));
      expect(await engine.leftoverFile(id), isNull);
      await engine.deleteOrphanFiles(const {});
      expect(File(w.pathOf(id)).existsSync(), isTrue);
    });
  });
}
