// Audio port value types (2nd-round contract 7.2.4, m5-7/02-core 4.5): isActive, ==, copyWith
// with clearRecording / clearError. Web-safe.
import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

void main() {
  test('RecorderStatus.isActive: recording or paused', () {
    expect(
      {
        for (final p in RecorderPhase.values)
          p: RecorderStatus(phase: p).isActive,
      },
      {
        RecorderPhase.idle: false,
        RecorderPhase.starting: false,
        RecorderPhase.recording: true,
        RecorderPhase.paused: true,
        RecorderPhase.finishing: false,
      },
    );
  });

  test('RecorderStatus.copyWith', () {
    const s = RecorderStatus(
      phase: RecorderPhase.recording,
      recordingId: 'r1',
      noteId: 'n1',
      activeMs: 1000,
      mimeType: 'audio/webm',
      crossPlatformPlayable: false,
      error: 'e',
    );
    expect(s.copyWith(), s);
    expect(s.copyWith(activeMs: 2000).activeMs, 2000);
    expect(s.copyWith(activeMs: 2000).recordingId, 'r1');
    final cleared = s.copyWith(phase: RecorderPhase.idle, clearRecording: true);
    expect(cleared.recordingId, isNull);
    expect(cleared.noteId, isNull);
    expect(cleared.mimeType, isNull);
    expect(cleared.activeMs, 1000);
    expect(cleared.error, 'e');
    expect(s.copyWith(clearError: true).error, isNull);
    expect(
      s.copyWith(interrupted: true, backgroundCapable: true),
      const RecorderStatus(
        phase: RecorderPhase.recording,
        recordingId: 'r1',
        noteId: 'n1',
        activeMs: 1000,
        mimeType: 'audio/webm',
        crossPlatformPlayable: false,
        error: 'e',
        interrupted: true,
        backgroundCapable: true,
      ),
    );
    expect(s.copyWith().hashCode, s.hashCode);
  });

  test('PlaybackStatus.copyWith', () {
    const s = PlaybackStatus(
      phase: PlaybackPhase.playing,
      recordingId: 'r1',
      durationMs: 5000,
      speed: 1.5,
      error: 'x',
    );
    expect(s.copyWith(), s);
    expect(s.copyWith(speed: 2).speed, 2);
    expect(s.copyWith(clearRecording: true).recordingId, isNull);
    expect(s.copyWith(clearRecording: true).durationMs, 5000);
    expect(s.copyWith(clearError: true).error, isNull);
    expect(
      s.copyWith(phase: PlaybackPhase.paused, unsupportedFormat: true),
      const PlaybackStatus(
        phase: PlaybackPhase.paused,
        recordingId: 'r1',
        durationMs: 5000,
        speed: 1.5,
        unsupportedFormat: true,
        error: 'x',
      ),
    );
  });
}
