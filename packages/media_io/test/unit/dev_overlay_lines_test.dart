// The developer overlay lines (m5-7/06-pdf 6.14 — 8.2 T37): rec / enc / last / drafts / buf /
// web / play from media_io's recorder service (fake engine, CORE's fake store, fake time) and a
// scripted player; a status change changes the lines (the provider's ValueListenable notifies),
// the clock-difference warning past 150 ms, 'duration from clock', the recovered / stuck / dropped
// counts, the bit rate and its source, the error code, and only rec / play for a recorder that is
// not media_io's (CORE's FakeAudioRecorder).
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/media_io.dart';
import 'package:media_io/src/dev/dev_overlay_lines.dart';
import 'package:media_io/src/errors.dart';
import 'package:media_io/src/providers.dart';
import 'package:media_io/src/record/recorder_service.dart';
import 'package:media_io/src/record/recording_output.dart';
import 'package:media_io/src/record/recover_attempts.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import '../support/recorder_world.dart';

/// A player whose status the test sets.
final class ScriptedPlayback implements core.AudioPlaybackService {
  core.PlaybackStatus _status = const core.PlaybackStatus();
  int position = 0;
  final StreamController<core.PlaybackStatus> _ctrl =
      StreamController.broadcast(sync: true);

  void set(core.PlaybackStatus s, {int positionMs = 0}) {
    _status = s;
    position = positionMs;
    _ctrl.add(s);
  }

  @override
  core.PlaybackStatus get status => _status;

  @override
  Stream<core.PlaybackStatus> get statusStream async* {
    yield _status;
    yield* _ctrl.stream;
  }

  @override
  int positionMs() => position;

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Lines {
  _Lines(this.world, this.tab, {bool web = true}) {
    source = MediaDevLineSource(
      recorder: tab.service,
      playback: playback,
      onLines: (l) => latest = l,
      web: web,
    )..start();
    world.async.flushMicrotasks();
  }

  final RecorderWorld world;
  final RecorderTab tab;
  final ScriptedPlayback playback = ScriptedPlayback();
  late final MediaDevLineSource source;
  List<String> latest = const [];

  String line(String prefix) => latest.firstWhere(
    (l) => l.startsWith(prefix),
    orElse: () => fail('no "$prefix" line in $latest'),
  );

  bool has(String prefix) => latest.any((l) => l.startsWith(prefix));
}

void main() {
  group('formatting', () {
    test('clock mm:ss.d, sizes, speeds', () {
      expect(formatDevClock(0), '00:00.0');
      expect(formatDevClock(12345), '00:12.3');
      expect(formatDevClock(192400), '03:12.4');
      expect(formatDevClock(2700000), '45:00.0');
      expect(formatDevClock(7500000), '125:00.0');
      expect(formatDevClock(-5), '00:00.0');
      expect(formatDevBytes(0), '0 B');
      expect(formatDevBytes(1023), '1023 B');
      expect(formatDevBytes(96 * 1024), '96 KB');
      expect(formatDevBytes(172 * 1024 * 1024), '172 MB');
      expect(formatDevSpeed(1.5), '1.5');
      expect(formatDevSpeed(1.0), '1');
      expect(formatDevSpeed(0.75), '0.75');
      expect(formatDevSpeed(2), '2');
    });
  });

  group('media_io recorder (6.14)', () {
    test(
      'idle: rec, drafts, buf, play lines; enc / web only when the engine says',
      () {
        fakeAsync((async) {
          final world = RecorderWorld(async);
          final tab = RecorderTab(world);
          final lines = _Lines(world, tab);
          expect(lines.latest.first, 'rec: idle br=64k(config) bg=no intr=no');
          expect(
            lines.line('drafts:'),
            'drafts: 0 (0 chunks, 0 B) recovered=0 stuck=0 dropped=0 '
            'backlog=0 B unsaved=0 B locks=none',
          );
          expect(lines.line('buf:'), 'buf: peak=0 (0 B) now=0');
          expect(lines.latest.last, 'play: idle');
          expect(lines.has('enc:'), isFalse);
          expect(lines.has('web:'), isFalse);
          expect(lines.has('last:'), isFalse);

          tab.engine
            ..encoderNote = 'mp4a=no mp4=yes webm/opus=yes'
            ..developerNote = 'wakeLock=held watchdog=0 hidden-pauses=1';
          lines.playback.set(
            const core.PlaybackStatus(),
          ); // any status rebuilds
          expect(lines.line('enc:'), 'enc: mp4a=no mp4=yes webm/opus=yes');
          expect(
            lines.line('web:'),
            'web: wakeLock=held watchdog=0 hidden-pauses=1',
          );
        });
      },
    );

    test('recording → the rec line follows the status; drafts re-read on a new phase', () {
      fakeAsync((async) {
        final world = RecorderWorld(async);
        final tab = RecorderTab(world);
        final lines = _Lines(world, tab);
        tab.start(world.recordingId());
        expect(
          lines.latest.first,
          'rec: recording 00:00.0 audio/webm;codecs=opus br=64k(config) bg=no intr=no',
        );
        tab.record(const Duration(milliseconds: 12300));
        expect(lines.latest.first, startsWith('rec: recording 00:12.'));
        expect(lines.line('drafts:'), startsWith('drafts: 1 ('));

        tab.session.systemPause(MediaErrorCode.hiddenTab);
        async.flushMicrotasks();
        expect(
          lines.latest.first,
          'rec: paused 00:12.3 audio/webm;codecs=opus br=64k(config) bg=no '
          'intr=yes err=hiddenTab',
        );

        tab.wait(tab.service.resume());
        tab.record(const Duration(seconds: 1));
        tab.wait(tab.service.stop());
        async.flushMicrotasks();
        expect(lines.latest.first, 'rec: idle br=64k(config) bg=no intr=no');
        // the fake chunks are no WebM: the clock gave the length
        expect(
          lines.line('last:'),
          allOf(
            startsWith('last: audio/webm;codecs=opus file='),
            contains('src=clock'),
            contains('duration from clock'),
            contains('duration patch skipped'),
          ),
        );
        expect(lines.line('drafts:'), startsWith('drafts: 0 (0 chunks, 0 B)'));
        expect(lines.line('buf:'), startsWith('buf: peak=1 '));
      });
    });

    test(
      'the last line: diff sign, the > 150 ms warning, the timeline source',
      () {
        fakeAsync((async) {
          final world = RecorderWorld(async);
          final tab = RecorderTab(world);
          final playback = ScriptedPlayback();
          String last() => mediaDevLines(
            recorder: tab.service,
            playback: playback,
          ).firstWhere((l) => l.startsWith('last:'));

          tab.service.diagnostics.lastRecording = (
            mimeType: 'audio/webm',
            durationMs: 2040,
            source: DurationSource.webm,
            clockMs: 2001,
            patched: true,
          );
          expect(
            last(),
            'last: audio/webm file=2040ms clock=2001ms diff=+39ms src=webm',
          );
          tab.service.diagnostics.lastRecording = (
            mimeType: 'audio/mp4',
            durationMs: 1800,
            source: DurationSource.probe,
            clockMs: 2000,
            patched: false,
          );
          expect(
            last(),
            'last: audio/mp4 file=1800ms clock=2000ms diff=-200ms src=probe '
            'clock diff > 150 ms',
          );
          tab.service.diagnostics.lastRecording = (
            mimeType: 'audio/mp4',
            durationMs: 2150,
            source: DurationSource.mp4,
            clockMs: 2000,
            patched: false,
          );
          expect(
            last(),
            endsWith('diff=+150ms src=mp4'),
          ); // 150 is not past the limit
        });
      },
    );

    test('recovered / dropped from the diagnostics, stuck from media.recoverAttempts', () {
      fakeAsync((async) {
        final world = RecorderWorld(async);
        final tab = RecorderTab(world);
        final draft = world.wait(
          world.store.recordingDrafts.begin(
            recordingId: world.recordingId(),
            noteId: world.noteId,
            mimeType: 'audio/webm',
            startedAt: 1,
          ),
        );
        world.wait(
          world.store.recordingDrafts.append(
            draft.draftId,
            Uint8List(100),
            activeMs: 1000,
          ),
        );
        final attempts = RecoverAttempts(world.store.settings);
        world.wait(attempts.increment(draft.draftId));
        world.wait(attempts.increment(draft.draftId));
        final summary = world.wait(tab.service.draftsSummary());
        expect(summary, (count: 1, chunks: 1, bytes: 100, stuck: 1));
        tab.service.diagnostics
          ..recovered = 3
          ..dropped = 1;
        final lines = _Lines(world, tab);
        expect(
          lines.line('drafts:'),
          'drafts: 1 (1 chunks, 100 B) recovered=3 stuck=1 dropped=1 '
          'backlog=0 B unsaved=0 B locks=none',
        );
      });
    });

    test('bit rate: media.bitRate 96000 → br=96k(setting); out of range → config, setting ignored', () {
      fakeAsync((async) {
        final world = RecorderWorld(async);
        final tab = RecorderTab(world);
        final lines = _Lines(world, tab);
        world.wait(world.store.settings.set(MediaSettingKeys.bitRate, 96000));
        tab.start(world.recordingId());
        expect(lines.latest.first, contains(' br=96k(setting) '));
        tab.record(const Duration(seconds: 1));
        tab.wait(tab.service.stop());
        world.wait(world.store.settings.set(MediaSettingKeys.bitRate, 200000));
        tab.start(world.recordingId());
        expect(
          lines.latest.first,
          contains(' br=64k(config, setting ignored) '),
        );
        tab.wait(tab.service.cancel());
      });
    });

    test(
      'play line: phase, speed, position / length, the source (blob / file)',
      () {
        fakeAsync((async) {
          final world = RecorderWorld(async);
          final tab = RecorderTab(world);
          final web = _Lines(world, tab);
          web.playback.set(
            const core.PlaybackStatus(
              phase: core.PlaybackPhase.playing,
              recordingId: 'r1',
              durationMs: 2700000,
              speed: 1.5,
            ),
            positionMs: 192400,
          );
          expect(
            web.latest.last,
            'play: playing 1.5x 03:12.4/45:00.0 src=blob',
          );
          final native = _Lines(world, tab, web: false);
          native.playback.set(
            const core.PlaybackStatus(
              phase: core.PlaybackPhase.paused,
              recordingId: 'r1',
              durationMs: 60000,
            ),
            positionMs: 1000,
          );
          expect(
            native.latest.last,
            'play: paused 1x 00:01.0/01:00.0 src=file',
          );
        });
      },
    );
  });

  test('a recorder that is not media_io\'s: rec and play only', () async {
    final store = core_testing.createFakeNoteStore();
    final recorder = core_testing.FakeAudioRecorder(store: store);
    final lines = mediaDevLines(
      recorder: recorder,
      playback: core_testing.FakeAudioPlayback(),
    );
    expect(lines, ['rec: idle bg=no intr=no', 'play: idle']);
  });

  test('the provider: a ValueListenable that changes with the recorder; no store → drafts: ?', () {
    fakeAsync((async) {
      final world = RecorderWorld(async);
      final tab = RecorderTab(world);
      final container = ProviderContainer(
        overrides: [
          core.audioRecorderServiceProvider.overrideWithValue(tab.service),
          core.audioPlaybackServiceProvider.overrideWithValue(
            ScriptedPlayback(),
          ),
        ],
      );
      final listenable = container.read(mediaDevOverlayLinesProvider);
      async.flushMicrotasks();
      var notified = 0;
      listenable.addListener(() => notified++);
      expect(listenable.value.first, startsWith('rec: idle'));
      tab.start(world.recordingId());
      expect(listenable.value.first, startsWith('rec: recording'));
      expect(notified, greaterThan(0));
      tab.wait(tab.service.cancel());
      container.dispose();
    });
  });

  test(
    'the provider over mediaIoOverrides() without a store: no exception',
    () {
      final container = ProviderContainer(overrides: mediaIoOverrides());
      addTearDown(container.dispose);
      final listenable = container.read(mediaDevOverlayLinesProvider);
      expect(listenable.value.first, startsWith('rec: idle br=64k(config)'));
      expect(
        listenable.value.where((l) => l.startsWith('drafts:')).single,
        startsWith('drafts: ? recovered=0 stuck=? '),
      );
      expect(listenable.value.last, 'play: idle');
      expect(
        container.read(core.audioRecorderServiceProvider),
        isA<MediaRecorderService>(),
      );
    },
  );
}
