// Internal (not exported). Push debounce (6.5.1).
//
// Triggers: localChanges, right after connecting, a push that hit its entry limit
// (immediate), syncNow, going to the background (immediate), commitRepairs.
// First trigger t0, last trigger tl: the push runs at min(tl + debounce, t0 +
// maxBatchDelay) — a debounce timer restarted by every trigger and a max-delay timer
// started by the first one, whichever fires first. Triggers that arrive while a push
// runs open the next window by the same rule; if it is already due when the push
// ends, the next push starts at once (never two pushes at the same time). While the
// engine is not live, due pushes wait and run at once when it becomes live.
import 'dart:async';

final class PushScheduler {
  PushScheduler({
    required this._debounce,
    required this._maxBatchDelay,
    required this._run,
    this._onError,
    this._live = false,
  });

  final Duration _debounce, _maxBatchDelay;
  final Future<void> Function() _run;
  final void Function(Object error, StackTrace stack)? _onError;

  bool _live;
  bool _running = false;
  bool _due = false;
  bool _disposed = false;
  Timer? _debounceTimer;
  Timer? _maxTimer;
  final Set<Timer> _delayed = {};
  final List<Completer<void>> _idleWaiters = [];

  /// Pushes started so far.
  int get runCount => _runCount;
  int _runCount = 0;

  bool get isRunning => _running;
  bool get isLive => _live;

  /// A push is waiting: a debounce window is open, a push is due (also while
  /// not live) or a delayed trigger is set.
  bool get isPending => _due || _maxTimer != null || _delayed.isNotEmpty;

  /// Records a trigger. [immediate] skips the debounce: the push runs now, or
  /// right after the running one, or when the engine becomes live.
  void trigger({bool immediate = false}) {
    if (_disposed) return;
    if (immediate) {
      _fire();
      return;
    }
    _maxTimer ??= Timer(_maxBatchDelay, _fire);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _fire);
  }

  /// An immediate trigger after [delay] (backoff retry, held future records —
  /// 6.5.2 step 6). Earlier pushes do not cancel it; see [cancelDelayed].
  void triggerAfter(Duration delay) {
    if (_disposed) return;
    late final Timer timer;
    timer = Timer(delay, () {
      _delayed.remove(timer);
      trigger(immediate: true);
    });
    _delayed.add(timer);
  }

  void cancelDelayed() {
    for (final t in _delayed) {
      t.cancel();
    }
    _delayed.clear();
  }

  /// Phase is live (or not). Becoming live runs a waiting push at once.
  void setLive(bool live) {
    if (_disposed || _live == live) return;
    _live = live;
    if (live && (_due || _maxTimer != null)) {
      _fire();
    }
  }

  /// Runs what is waiting now (open window or due push) and completes when no
  /// push is running or due (background flush, 6.5.1). Delayed triggers stay.
  /// While not live, completes only after the engine became live and pushed.
  Future<void> flush() {
    if (_disposed) return Future.value();
    if (_maxTimer != null) _fire();
    return whenIdle();
  }

  /// Completes when no push is running, due or in an open window.
  Future<void> whenIdle() {
    if (_disposed || _isIdle) return Future.value();
    final waiter = Completer<void>();
    _idleWaiters.add(waiter);
    return waiter.future;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelWindow();
    cancelDelayed();
    _due = false;
    _completeIdle();
  }

  bool get _isIdle => !_running && !_due && _maxTimer == null;

  void _fire() {
    _cancelWindow();
    _due = true;
    _maybeRun();
  }

  void _cancelWindow() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _maxTimer?.cancel();
    _maxTimer = null;
  }

  void _maybeRun() {
    if (_disposed || !_due || _running || !_live) return;
    _due = false;
    _running = true;
    _runCount++;
    _runGuarded().whenComplete(() {
      _running = false;
      if (_due) {
        _maybeRun();
      } else if (_isIdle) {
        _completeIdle();
      }
    });
  }

  Future<void> _runGuarded() async {
    try {
      await _run();
    } catch (e, s) {
      final onError = _onError;
      if (onError == null) rethrow;
      onError(e, s);
    }
  }

  void _completeIdle() {
    final waiters = List.of(_idleWaiters);
    _idleWaiters.clear();
    for (final w in waiters) {
      w.complete();
    }
  }
}
