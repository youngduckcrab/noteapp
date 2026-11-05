// Internal (not exported). The engine's single serial executor (6.1): one task at a
// time in submission order — one push commit round, one batch of received chunks,
// repair writes, one compaction step. Listener events and timers only enqueue.
import 'dart:async';
import 'dart:collection';

final class SerialExecutor {
  SerialExecutor();

  final Queue<_Task<Object?>> _queue = Queue();
  _Task<Object?>? _current;
  bool _closed = false;
  Completer<void>? _idle;

  /// A task is running.
  bool get isBusy => _current != null;

  /// Tasks waiting to start (the running one excluded).
  int get queueLength => _queue.length;

  /// Label of the running task (debugging, status).
  String? get currentLabel => _current?.label;

  bool get isClosed => _closed;

  /// Runs [task] after every task submitted before it has finished. The
  /// returned future completes with the task's result or error; an error does
  /// not stop later tasks. Throws StateError after [close].
  Future<T> run<T>(Future<T> Function() task, {String? label}) {
    if (_closed) throw StateError('SerialExecutor is closed');
    final entry = _Task<T>(task, label);
    _queue.add(entry);
    if (_current == null) _pump();
    return entry.completer.future;
  }

  /// Completes when no task is running or waiting (at once if idle now).
  Future<void> get idle {
    if (_current == null && _queue.isEmpty) return Future.value();
    return (_idle ??= Completer<void>()).future;
  }

  /// Rejects new tasks. Waiting tasks complete with StateError without
  /// running; the running task finishes normally.
  void close() {
    if (_closed) return;
    _closed = true;
    while (_queue.isNotEmpty) {
      _queue.removeFirst().completer.completeError(
        StateError('SerialExecutor closed before the task started'),
      );
    }
    if (_current == null) _completeIdle();
  }

  void _pump() {
    if (_queue.isEmpty) {
      _current = null;
      _completeIdle();
      return;
    }
    final task = _current = _queue.removeFirst();
    // Start on a fresh microtask so a task submitted from inside another
    // task's synchronous part never runs re-entrantly.
    scheduleMicrotask(() async {
      try {
        task.completer.complete(await task.body());
      } catch (e, s) {
        task.completer.completeError(e, s);
      }
      _pump();
    });
  }

  void _completeIdle() {
    final idle = _idle;
    _idle = null;
    idle?.complete();
  }
}

final class _Task<T> {
  _Task(this.body, this.label);
  final Future<T> Function() body;
  final String? label;
  final Completer<T> completer = Completer<T>();
}
