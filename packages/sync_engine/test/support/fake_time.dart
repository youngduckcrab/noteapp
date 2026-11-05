// Drives a future to completion inside fakeAsync (test/ only).
import 'package:fake_async/fake_async.dart';

/// Elapses [async] in [step]s until [future] completes; returns its value or
/// rethrows its error. Throws StateError after [timeout] of virtual time.
T runFake<T>(
  FakeAsync async,
  Future<T> future, {
  Duration step = const Duration(milliseconds: 1),
  Duration timeout = const Duration(minutes: 10),
}) {
  var done = false;
  late T value;
  Object? error;
  StackTrace? stack;
  future.then(
    (v) {
      value = v;
      done = true;
    },
    onError: (Object e, StackTrace s) {
      error = e;
      stack = s;
      done = true;
    },
  );
  async.flushMicrotasks();
  final end = async.elapsed + timeout;
  while (!done) {
    if (async.elapsed >= end) {
      throw StateError('future not done after $timeout of virtual time');
    }
    async.elapse(step);
  }
  if (error != null) Error.throwWithStackTrace(error!, stack!);
  return value;
}

/// The error [future] completes with (StateError if it completes normally).
Object runFakeError(
  FakeAsync async,
  Future<Object?> future, {
  Duration step = const Duration(milliseconds: 1),
}) {
  try {
    runFake(async, future, step: step);
  } catch (e) {
    return e;
  }
  throw StateError('future completed without error');
}
