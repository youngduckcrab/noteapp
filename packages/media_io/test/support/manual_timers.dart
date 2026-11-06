// Timers a test fires by hand (m5-7/06-pdf 8.2 T32b): the web recorder's StartTimer seam in Chrome,
// where real browser events and fake_async do not mix — no assertion waits for real time.
import 'dart:async';

final class ManualTimers {
  final List<ManualTimer> all = [];

  /// The StartTimer to inject.
  Timer create(Duration duration, void Function() callback) {
    final t = ManualTimer._(duration, callback);
    all.add(t);
    return t;
  }

  /// The active timers of [duration].
  List<ManualTimer> active(Duration duration) => [
    for (final t in all)
      if (t.isActive && t.duration == duration) t,
  ];

  /// Fires every active timer of [duration] (oldest first); returns how many fired.
  int fire(Duration duration) {
    final due = active(duration);
    for (final t in due) {
      t.fire();
    }
    return due.length;
  }
}

final class ManualTimer implements Timer {
  ManualTimer._(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}
