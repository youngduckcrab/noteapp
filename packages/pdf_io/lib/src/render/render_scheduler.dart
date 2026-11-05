// lib/src/render/render_scheduler.dart — 06-pdf 6.7.3 (PDF T8). Internal (not exported).
//
// The Dart render queue: four priority classes (visible preview → visible tile → thumbnail →
// prefetch tile), request order within a class, at most maxInflight renders at a time.
// Cancelling a queued job takes it out of the queue; cancelling a running one cancels its
// PdfRenderCancelToken, and an image that still arrives is disposed at once.
import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../engine/page_info.dart';
import '../tuning.dart';
import 'tile_math.dart';

/// Renders one image; the scheduler passes the job's cancel token.
typedef PdfRenderTask = Future<ui.Image?> Function(PdfRenderCancelToken token);

/// One queued or running render.
final class PdfRenderJob {
  PdfRenderJob._(this._scheduler, this.renderClass, this._task);

  final PdfRenderScheduler _scheduler;
  final PdfRenderClass renderClass;
  final PdfRenderTask _task;
  final Completer<ui.Image?> _result = Completer<ui.Image?>();
  final PdfRenderCancelToken _token = PdfRenderCancelToken();
  _JobState _state = _JobState.queued;

  /// The rendered image (the receiver owns it), or null when cancelled / the engine returned
  /// none. Completes with the engine's error when the render failed.
  Future<ui.Image?> get result => _result.future;

  bool get isCancelled => _token.isCancelled;
  bool get isDone => _state == _JobState.done;

  /// Idempotent. Queued: leaves the queue, result → null at once. Running: cancels the
  /// token; result → null when the engine returns (a late image is disposed).
  void cancel() => _scheduler._cancel(this);
}

enum _JobState { queued, running, done }

final class PdfRenderScheduler {
  PdfRenderScheduler({
    int maxInflight = PdfTuning.maxInflightRenders,
    this._onChanged,
  }) : _maxInflight = maxInflight < 1 ? 1 : maxInflight;

  final int _maxInflight;
  final VoidCallback? _onChanged;
  final List<Queue<PdfRenderJob>> _queues = [
    for (final _ in PdfRenderClass.values) Queue<PdfRenderJob>(),
  ];
  final Set<PdfRenderJob> _running = {};
  bool _disposed = false;

  int _rendered = 0;
  int _cancelled = 0;
  double _lastRenderMs = 0;

  /// The last PdfTuning.renderTimingSamples render times (ms), oldest first.
  final Queue<double> _timings = Queue<double>();

  int get queued => _queues.fold(0, (sum, q) => sum + q.length);
  int get inflight => _running.length;

  /// Renders that delivered an image.
  int get rendered => _rendered;

  /// Jobs cancelled while queued or running.
  int get cancelled => _cancelled;
  double get lastRenderMs => _lastRenderMs;

  /// 95th percentile of the recent render times (nearest rank).
  double get p95RenderMs {
    if (_timings.isEmpty) return 0;
    final sorted = _timings.toList()..sort();
    final rank = (sorted.length * 0.95).ceil();
    return sorted[(rank < 1 ? 1 : rank) - 1];
  }

  /// Queues [task] in [renderClass]. After dispose() the job is already cancelled.
  PdfRenderJob submit(PdfRenderClass renderClass, PdfRenderTask task) {
    final job = PdfRenderJob._(this, renderClass, task);
    if (_disposed) {
      job._token.cancel();
      job._state = _JobState.done;
      job._result.complete(null);
      return job;
    }
    _queues[renderClass.index].add(job);
    _pump();
    _onChanged?.call();
    return job;
  }

  /// Cancels every job; later submits are cancelled at once.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final queue in _queues) {
      for (final job in queue.toList()) {
        job.cancel();
      }
    }
    for (final job in _running.toList()) {
      job.cancel();
    }
  }

  void _cancel(PdfRenderJob job) {
    if (job._state == _JobState.done || job._token.isCancelled) return;
    job._token.cancel();
    _cancelled++;
    if (job._state == _JobState.queued) {
      _queues[job.renderClass.index].remove(job);
      job._state = _JobState.done;
      job._result.complete(null);
      _pump();
    }
    _onChanged?.call();
  }

  void _pump() {
    while (_running.length < _maxInflight) {
      final job = _next();
      if (job == null) return;
      _start(job);
    }
  }

  PdfRenderJob? _next() {
    for (final queue in _queues) {
      if (queue.isNotEmpty) return queue.removeFirst();
    }
    return null;
  }

  void _start(PdfRenderJob job) {
    job._state = _JobState.running;
    _running.add(job);
    final watch = Stopwatch()..start();
    // Future.sync: a synchronous throw of the task ends the job like an async one.
    Future<ui.Image?>.sync(() => job._task(job._token)).then(
      (image) {
        watch.stop();
        _finish(job);
        if (image != null && job._token.isCancelled) {
          image.dispose();
          job._result.complete(null);
        } else {
          if (image != null) {
            _rendered++;
            _record(watch.elapsedMicroseconds / 1000);
          }
          job._result.complete(image);
        }
        _afterFinish();
      },
      onError: (Object error, StackTrace stack) {
        _finish(job);
        if (job._token.isCancelled) {
          job._result.complete(null);
        } else {
          job._result.completeError(error, stack);
        }
        _afterFinish();
      },
    );
  }

  void _finish(PdfRenderJob job) {
    _running.remove(job);
    job._state = _JobState.done;
  }

  void _afterFinish() {
    if (!_disposed) _pump();
    _onChanged?.call();
  }

  void _record(double ms) {
    _lastRenderMs = ms;
    _timings.add(ms);
    while (_timings.length > PdfTuning.renderTimingSamples) {
      _timings.removeFirst();
    }
  }
}
