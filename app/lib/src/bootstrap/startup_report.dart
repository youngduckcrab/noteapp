/// What happened during start-up (docs/plans/01-infra.md 4.5.4, 6.4).
///
/// Filled by `AppBootstrapper` (I5); shown in the about section and the
/// diagnostic report.
library;

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart';

enum StartupStepOutcome {
  ok,
  failedNonCritical,
  timedOut,
  failedCritical,
  skipped,
}

@immutable
final class StartupStep {
  const StartupStep({
    required this.id,
    required this.elapsed,
    required this.outcome,
    this.error,
  });
  final String id;
  final Duration elapsed;
  final StartupStepOutcome outcome;
  final Object? error;
}

@immutable
final class StartupReport {
  const StartupReport({
    required this.steps,
    required this.bootstrapElapsed,
    this.sinceNavigationStart,
    this.storage,
  });

  final List<StartupStep> steps;

  /// From AppBootstrapper.run() start to result.
  final Duration bootstrapElapsed;

  /// Web: performance.now() when bootstrap finished (page open → app ready).
  final Duration? sinceNavigationStart;

  /// CORE NoteStore.storageInfo right after open (includes persistGranted:
  /// CORE awaited persist() for at most 1 s). Null when CORE did not start.
  final StorageInfo? storage;
}
