// FakeAudioPlayback (m5-7/02-core 6.8.4): phases, clamps, the calls record. Web-safe.
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

void main() {
  const recording = Recording(
    id: 'rec-1',
    noteId: 'n1',
    assetId: 'a',
    durationMs: 10000,
    startedAt: 0,
    createdAt: 0,
    updatedAt: 0,
  );

  test(
    'open → ready; play / pause; seek and positions clamped; close → idle',
    () async {
      final p = FakeAudioPlayback();
      final phases = <PlaybackPhase>[];
      final sub = p.statusStream.listen((s) => phases.add(s.phase));
      addTearDown(sub.cancel);
      expect(p.status, const PlaybackStatus());
      expect(p.positionMs(), 0);
      await p.open(recording);
      expect(p.status.phase, PlaybackPhase.ready);
      expect(p.status.recordingId, 'rec-1');
      expect(p.status.durationMs, 10000);
      await p.play();
      expect(p.status.phase, PlaybackPhase.playing);
      await p.pause();
      expect(p.status.phase, PlaybackPhase.paused);
      await p.seekMs(20000);
      expect(p.positionMs(), 10000);
      await p.seekMs(-5);
      expect(p.positionMs(), 0);
      p.setPositionMs(4321);
      expect(p.positionMs(), 4321);
      await p.setSpeed(3);
      expect(p.status.speed, 2.0);
      await p.setSpeed(0.1);
      expect(p.status.speed, 0.5);
      await p.close();
      expect(p.status.phase, PlaybackPhase.idle);
      expect(p.status.recordingId, isNull);
      expect(phases, [
        PlaybackPhase.idle,
        PlaybackPhase.loading,
        PlaybackPhase.ready,
        PlaybackPhase.playing,
        PlaybackPhase.paused,
        PlaybackPhase.paused,
        PlaybackPhase.paused,
        PlaybackPhase.idle,
      ]);
    },
  );

  test('calls: in order, the seek argument before clamping, setPositionMs not recorded', () async {
    final p = FakeAudioPlayback();
    await p.open(recording);
    await p.play();
    await p.seekMs(99999);
    p.setPositionMs(10);
    await p.setSpeed(1.5);
    await p.pause();
    await p.close();
    expect(p.calls.take(4), [
      'open:rec-1',
      'play',
      'seek:99999',
      isA<String>(),
    ]);
    final speed = p.calls[3];
    expect(speed, startsWith('speed:'));
    expect(double.parse(speed.substring('speed:'.length)), 1.5);
    expect(p.calls.skip(4), ['pause', 'close']);
    expect(() => p.calls.add('x'), throwsUnsupportedError);
  });

  test('nothing open: play / pause / seek change no phase; open again resets the position', () async {
    final p = FakeAudioPlayback();
    await p.play();
    expect(p.status.phase, PlaybackPhase.idle);
    await p.pause();
    expect(p.status.phase, PlaybackPhase.idle);
    await p.seekMs(500);
    expect(p.positionMs(), 0, reason: 'durationMs 0 while nothing is open');
    await p.open(recording);
    await p.seekMs(5000);
    await p.play();
    await p.open(
      const Recording(
        id: 'rec-2',
        noteId: 'n1',
        assetId: 'a',
        durationMs: 3000,
        startedAt: 0,
        createdAt: 0,
        updatedAt: 0,
      ),
    );
    expect(p.status.phase, PlaybackPhase.ready);
    expect(p.status.recordingId, 'rec-2');
    expect(p.status.durationMs, 3000);
    expect(p.positionMs(), 0);
    expect(p.calls.last, 'open:rec-2');
  });
}
