// lib/src/record/recording_clock.dart — m5-7/06-pdf 6.7 (R-2, contract 7.4.8). Internal.
//
// A monotonic Stopwatch stopped and restarted on the recorder ENGINE's events (EngineStarted /
// EnginePaused — user or system — / EngineResumed), not when the user taps. package:clock is
// not used. elapsedMs is what offsetNowMs() reads at pen down: synchronous, no allocation.
import 'package:note_core/note_core.dart' as core;

final class RecordingClock {
  RecordingClock({Stopwatch Function() stopwatch = Stopwatch.new})
    : _watch = stopwatch();

  final Stopwatch _watch;

  /// EngineStarted: from 0, running.
  void start() {
    _watch
      ..reset()
      ..start();
  }

  /// EnginePaused (by the user, the system or a hidden tab): the paused span is not counted.
  void pause() => _watch.stop();

  /// EngineResumed.
  void resume() => _watch.start();

  /// Stops and returns the total active ms (pauses excluded).
  int stop() {
    _watch.stop();
    return _watch.elapsedMilliseconds;
  }

  /// Active ms so far; monotonic (never goes back while recording or paused).
  int get elapsedMs => _watch.elapsedMilliseconds;
}

/// AudioRecorderService.offsetNowMs (7.2.4, R-1): the clock while [phase] is recording, else
/// null.
int? offsetNowMsOf(core.RecorderPhase phase, RecordingClock clock) =>
    phase == core.RecorderPhase.recording ? clock.elapsedMs : null;
