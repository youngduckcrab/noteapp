// FakeAppModule (docs/plans/01-infra.md 5.7): a scriptable AppModule.
import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:noteapp/src/bootstrap/app_module.dart';

/// An [AppModule] whose timing and failures are constructor arguments and
/// whose calls are counted. Every call is also appended to [events] (shared
/// between modules to check the order), e.g. `start:core`, `stop:core`.
final class FakeAppModule extends AppModule {
  FakeAppModule({
    required this.id,
    String? label,
    this.critical = true,
    this.startTimeout = const Duration(seconds: 10),
    this.startDelay = Duration.zero,
    this.startError,
    this.gate,
    this._overrides = const [],
    this.hiddenDelay = Duration.zero,
    this.hiddenError,
    this.stopDelay = Duration.zero,
    this.stopError,
    this.resetLocalData,
    this.resettable = false,
    this.abandonDelay = Duration.zero,
    this.onStart,
    List<String>? events,
  }) : label = label ?? '$id 준비하는 중',
       events = events ?? [];

  @override
  final String id;
  @override
  final String label;
  @override
  final bool critical;
  @override
  final Duration startTimeout;

  final Duration startDelay;
  final Object? startError;

  /// start() waits for this before [startDelay] and [startError].
  final Completer<void>? gate;

  final List<Override> _overrides;
  final Duration hiddenDelay;
  final Object? hiddenError;
  final Duration stopDelay;
  final Object? stopError;

  @override
  final Future<void> Function()? resetLocalData;

  /// canResetAfter's answer.
  final bool resettable;

  /// How long onStartAbandoned() takes (the late-result cleanup).
  final Duration abandonDelay;

  /// Runs at the beginning of start() (publish values, check the context).
  final void Function(AppModuleContext context)? onStart;

  final List<String> events;

  int started = 0;
  int stopped = 0;
  int hiddenCalls = 0;
  int abandonedCalls = 0;
  int overridesCalls = 0;

  /// Errors passed to canResetAfter.
  final List<Object> resetQueries = [];

  @override
  Future<void> start(AppModuleContext context) async {
    started++;
    events.add('start:$id');
    onStart?.call(context);
    if (gate != null) await gate!.future;
    if (startDelay > Duration.zero) await Future<void>.delayed(startDelay);
    if (startError case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    events.add('started:$id');
  }

  @override
  List<Override> overrides() {
    overridesCalls++;
    return _overrides;
  }

  @override
  Future<void> onAppHidden() async {
    hiddenCalls++;
    events.add('hidden:$id');
    if (hiddenDelay > Duration.zero) await Future<void>.delayed(hiddenDelay);
    if (hiddenError case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  @override
  Future<void> stop() async {
    stopped++;
    events.add('stop:$id');
    if (stopDelay > Duration.zero) await Future<void>.delayed(stopDelay);
    if (stopError case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  @override
  Future<void> onStartAbandoned() async {
    abandonedCalls++;
    events.add('abandon:$id');
    if (abandonDelay > Duration.zero) await Future<void>.delayed(abandonDelay);
    events.add('abandoned:$id');
  }

  @override
  bool canResetAfter(Object error) {
    resetQueries.add(error);
    return resettable;
  }
}
