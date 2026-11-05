// Internal: the fake store's single serial write queue (CORE 6.9 semantics without
// SQLite). Writes are grouped into commits after a microtask (or FakeNoteStoreFaults
// .commitDelay); a failed commit is retried after 100 ms → 400 ms → 1.6 s → 5 s (forever)
// and its Futures stay pending meanwhile (4.5 head). A write whose body throws (domain
// error) completes with that error and changes nothing; the other writes still commit.
import 'dart:async';

import 'package:clock/clock.dart';

import '../repo/status.dart';

/// Failure / latency injection for other areas' tests.
final class FakeNoteStoreFaults {
  FakeNoteStoreFaults();

  int _failing = 0;
  Object _error = const FormatException('injected');

  /// The next [count] commits fail with [error]; PersistenceStatus reports them and the
  /// in-memory state is kept (like the real WriteQueue retry).
  /// CORE: failed commits are retried on the 6.9 schedule; repository Futures complete after
  /// the successful commit (4.5 head). AssetStore.put's metadata write counts as one commit
  /// (pending while it is retried, 7.2.11 v1.2).
  void failNextCommits(
    int count, {
    Object error = const FormatException('injected'),
  }) {
    if (count < 0) throw ArgumentError.value(count, 'count', 'must be >= 0');
    _failing += count;
    _error = error;
  }

  /// Every commit completes after [delay] (use with fake_async).
  Duration commitDelay = Duration.zero;
}

final class _Job<T> {
  _Job(this.body, this.enqueuedAt);
  final T Function() body;
  final DateTime enqueuedAt;
  final Completer<T> completer = Completer<T>();
  T? _result;
  Object? _error;
  StackTrace? _stack;

  void run() {
    try {
      _result = body();
    } on Object catch (e, st) {
      _error = e;
      _stack = st;
    }
  }

  void complete() {
    if (_error != null) {
      completer.completeError(_error!, _stack);
    } else {
      completer.complete(_result as T);
    }
  }
}

final class FakeWriteQueue {
  FakeWriteQueue({
    required this.clock,
    required this.faults,
    required this.onCommitted,
  });

  final Clock clock;
  final FakeNoteStoreFaults faults;

  /// Called once after each successful commit, before the write Futures complete.
  final void Function() onCommitted;

  static const List<Duration> _backoff = [
    Duration(milliseconds: 100),
    Duration(milliseconds: 400),
    Duration(milliseconds: 1600),
    Duration(seconds: 5),
  ];

  final List<_Job<Object?>> _queue = [];
  List<_Job<Object?>> _inFlight = const [];
  bool _scheduled = false;
  bool _closed = false;

  PersistenceStatus _status = const PersistenceStatus(
    pendingOps: 0,
    isWriting: false,
  );
  final StreamController<PersistenceStatus> _statusCtrl =
      StreamController.broadcast();

  PersistenceStatus get status => _status;
  Stream<PersistenceStatus> get statusChanges => _statusCtrl.stream;

  /// Enqueues [body]; it runs inside the next commit.
  Future<T> run<T>(T Function() body) {
    if (_closed) return Future.error(StateError('The note store is closed'));
    final job = _Job<Object?>(body, clock.now());
    _queue.add(job);
    _setStatus(pendingOps: _pending);
    _schedule(Duration.zero);
    return job.completer.future.then((v) => v as T);
  }

  /// Every write queued before this call committed; pending while a commit is retried.
  Future<void> flush() {
    final jobs = [..._inFlight, ..._queue];
    if (jobs.isEmpty) return Future<void>.value();
    return Future.wait([
      for (final j in jobs)
        j.completer.future.then<void>((_) {}, onError: (_) {}),
    ]);
  }

  int get _pending => _queue.length + _inFlight.length;

  void _schedule(Duration delay) {
    if (_scheduled || _closed) return;
    if (_queue.isEmpty && _inFlight.isEmpty) return;
    _scheduled = true;
    final total = delay + faults.commitDelay;
    if (total == Duration.zero) {
      scheduleMicrotask(_attempt);
    } else {
      Timer(total, _attempt);
    }
    _setStatus(isWriting: true);
  }

  void _attempt() {
    _scheduled = false;
    if (_closed) return;
    if (_inFlight.isEmpty) {
      _inFlight = List.of(_queue);
      _queue.clear();
    }
    if (_inFlight.isEmpty) {
      _setStatus(isWriting: false);
      return;
    }
    if (faults._failing > 0) {
      faults._failing--;
      final failures = _status.consecutiveFailures + 1;
      _setStatus(
        isWriting: false,
        lastError: faults._error,
        lastErrorAt: clock.now().millisecondsSinceEpoch,
        consecutiveFailures: failures,
      );
      _schedule(_backoff[(failures - 1).clamp(0, _backoff.length - 1)]);
      return;
    }
    final batch = _inFlight;
    final started = batch.first.enqueuedAt;
    for (final j in batch) {
      j.run();
    }
    _inFlight = const [];
    final now = clock.now();
    _setStatus(
      pendingOps: _pending,
      isWriting: false,
      lastCommittedAt: now.millisecondsSinceEpoch,
      lastCommitLatency: now.difference(started),
      consecutiveFailures: 0,
    );
    onCommitted();
    for (final j in batch) {
      j.complete();
    }
    _schedule(Duration.zero);
  }

  void _setStatus({
    int? pendingOps,
    bool? isWriting,
    int? lastCommittedAt,
    Duration? lastCommitLatency,
    Object? lastError,
    int? lastErrorAt,
    int? consecutiveFailures,
  }) {
    final s = _status;
    final next = PersistenceStatus(
      pendingOps: pendingOps ?? s.pendingOps,
      isWriting: isWriting ?? s.isWriting,
      lastCommittedAt: lastCommittedAt ?? s.lastCommittedAt,
      lastCommitLatency: lastCommitLatency ?? s.lastCommitLatency,
      lastError: lastError ?? s.lastError,
      lastErrorAt: lastErrorAt ?? s.lastErrorAt,
      consecutiveFailures: consecutiveFailures ?? s.consecutiveFailures,
    );
    if (next == s) return;
    _status = next;
    _statusCtrl.add(next);
  }

  Future<void> close() async {
    _closed = true;
    await _statusCtrl.close();
  }
}
