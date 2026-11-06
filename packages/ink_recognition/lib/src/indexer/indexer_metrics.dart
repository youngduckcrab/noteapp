// lib/src/indexer/indexer_metrics.dart — (internal, v2.1) the indexer's job
// timings for the developer overlay (m5-7/05-library 4.4.9, 6.9.7, review
// S-1). Not a contract field: HandwritingIndexerStatus stays as the contract
// declares it; recognitionDevOverlayLinesProvider (L2-11) reads these through
// metricsOf(indexer) (handwriting_indexer.dart).
//
// Only Stopwatch here — the times are for the developer line and the
// performance record, never for a decision (6.9.2: decisions use Timer only).
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

/// One page job that read its page (② of 6.9.3 onward).
@immutable
final class IndexerJobRecord {
  const IndexerJobRecord({
    required this.pageId,
    required this.ourMs,
    required this.lines,
    required this.recognizedLines,
    required this.longestSliceMs,
    required this.slices,
  });

  final core.PageId pageId;

  /// Our part of the job (read, convert, group, merge — no engine, no store
  /// wait), ms.
  final double ourMs;

  /// Lines of the page.
  final int lines;

  /// Lines sent to the engine.
  final int recognizedLines;

  /// The longest uninterrupted piece of our part, ms (6.9.7 target ≤ 8 ms).
  final double longestSliceMs;

  /// Uninterrupted pieces of our part (yields + awaits + 1).
  final int slices;

  @override
  String toString() =>
      'IndexerJobRecord($pageId, ${ourMs.toStringAsFixed(1)} ms, '
      'lines $lines, engine $recognizedLines, '
      'longest ${longestSliceMs.toStringAsFixed(2)} ms of $slices)';
}

/// What the indexer measured; [lastJob] notifies after every recorded job.
final class IndexerMetrics {
  /// The last page job that read its page; null before the first.
  final ValueNotifier<IndexerJobRecord?> lastJob =
      ValueNotifier<IndexerJobRecord?>(null);

  /// Recorded jobs since start().
  int jobs = 0;

  void record(IndexerJobRecord job) {
    jobs++;
    lastJob.value = job;
  }
}

/// Times our part of one job: [run] pauses the clock while a store, engine
/// or yield future is pending.
final class JobClock {
  final Stopwatch _total = Stopwatch();
  final Stopwatch _slice = Stopwatch();
  double _longestMs = 0;
  int _slices = 0;

  void start() {
    _total.start();
    _slice
      ..reset()
      ..start();
  }

  void _pause() {
    _total.stop();
    _slice.stop();
    _slices++;
    _longestMs = math.max(_longestMs, _slice.elapsedMicroseconds / 1000);
  }

  /// Calls [outside] with the clock paused (its synchronous part too — a
  /// store's body runs before its first await).
  Future<T> run<T>(Future<T> Function() outside) async {
    _pause();
    try {
      return await outside();
    } finally {
      start();
    }
  }

  /// Ends the measurement.
  void stop() {
    if (_total.isRunning) _pause();
  }

  double get totalMs => _total.elapsedMicroseconds / 1000;
  double get longestSliceMs => _longestMs;
  int get slices => _slices;
}
