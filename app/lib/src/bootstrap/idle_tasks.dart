/// Idle-time work of the started modules (docs/plans/m5-7/01-infra.md 4.6.2,
/// 6.5.1; contract 7.3.3 (v2.1) '시점과 순서').
///
/// The leave guard runs right after the first frame; everything else runs
/// one at a time, data protection first, 3 s after the first frame and only
/// while the app is visible. Clean-up runs in reverse order when the root
/// ProviderScope goes away.
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../errors/app_error_log.dart';
import '../web/web_platform.dart';

/// (v2.1, contract 7.3.3 '시점과 순서') Lower runs first — data protection
/// before indexing.
abstract final class AppIdlePriority {
  /// media.recoverDrafts
  static const int dataProtection = 0;

  /// pdf.searchIndexer
  static const int searchIndex = 10;

  /// recognition.indexer
  static const int recognition = 20;
}

/// Work a module asks for once the app is on screen (6.5).
@immutable
final class AppIdleTask {
  const AppIdleTask({
    required this.id,
    required this.priority,
    required this.run,
    this.delay = const Duration(seconds: 3),
    this.immediate = false,
  });

  /// `'<moduleId>.<name>'`, unique (test).
  final String id;

  /// AppIdlePriority; ties keep module order.
  final int priority;

  /// From the first frame under the root scope.
  final Duration delay;

  /// true: runs right after the first frame, outside the one-at-a-time queue,
  /// without the lifecycle wait and without delay (media.leaveGuard — one
  /// cheap subscription, D2-14).
  final bool immediate;
  final Future<void> Function(AppIdleContext context) run;

  @override
  String toString() =>
      'AppIdleTask($id, priority: $priority${immediate ? ', immediate' : ''})';
}

abstract interface class AppIdleContext {
  /// Same as ProviderContainer.read on the root container.
  T read<T>(ProviderListenable<T> provider);

  /// Run in reverse registration order when the root ProviderScope is
  /// disposed (retry, app shutdown); each awaited ≤ 2 s; a throw is logged
  /// (source module) and the rest still run.
  void onDispose(FutureOr<void> Function() callback);
  bool get isDisposed;
  AppErrorLog get errorLog;
  WebPlatform get web;
}

/// Sits inside the root ProviderScope (BootstrapApp: ProviderScope →
/// AppLifecycleBridge → AppIdleTaskRunner → NoteApp). After the first frame:
/// immediate tasks at once; the others in priority order, one at a time, each
/// after its delay and only while the lifecycle state is resumed, inactive or
/// null (hidden / paused / detached → wait — the web sends inactive on window
/// blur, iPad shows system pickers as inactive). A task's throw → errorLog
/// (source module, summary `'idle task <id> failed'`), the next runs.
///
/// [cleanup] (app shell, J6): when given, the runner's dispose hands its
/// clean-up (the onDispose callbacks) to it, so the owner can wait for it
/// before it stops the modules or builds the next scope.
class AppIdleTaskRunner extends StatefulWidget {
  const AppIdleTaskRunner({
    super.key,
    required this.tasks,
    required this.errorLog,
    required this.web,
    required this.child,
    this.cleanup,
  });

  final List<AppIdleTask> tasks;
  final AppErrorLog errorLog;
  final WebPlatform web;
  final Widget child;
  final AppIdleCleanup? cleanup;

  @override
  State<AppIdleTaskRunner> createState() => _AppIdleTaskRunnerState();
}

/// The clean-ups of disposed [AppIdleTaskRunner]s that have not finished
/// (BootstrapApp, 6.5.1 ⑤ — the indexers' dispose ends before the modules
/// stop and before a new scope starts). Each clean-up is bounded (every
/// callback ≤ 2 s) and never throws.
final class AppIdleCleanup {
  final Set<Future<void>> _pending = {};

  /// Tracks [closing] until it completes.
  void add(Future<void> closing) {
    _pending.add(closing);
    unawaited(closing.whenComplete(() => _pending.remove(closing)));
  }

  /// No clean-up is running.
  bool get isIdle => _pending.isEmpty;

  /// Completes when every clean-up added so far has finished (at once when
  /// none is running).
  Future<void> get done async {
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
  }
}

/// How long one task may run before a note goes to the error log (it is
/// not cancelled — a draft being recovered is never cut off, 6.5.1 ④).
const Duration _slowTask = Duration(seconds: 30);

/// Limit for each onDispose callback.
const Duration _disposeTimeout = Duration(seconds: 2);

class _AppIdleTaskRunnerState extends State<AppIdleTaskRunner>
    with WidgetsBindingObserver {
  _IdleContext? _context;
  final List<Timer> _timers = [];
  Completer<void>? _visible;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onFirstFrame());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    // Wakes a queue waiting for visibility; it sees _disposed and stops.
    final visible = _visible;
    _visible = null;
    if (visible != null && !visible.isCompleted) visible.complete();
    final context = _context;
    if (context != null) {
      final closing = context.close();
      final cleanup = widget.cleanup;
      if (cleanup != null) {
        cleanup.add(closing);
      } else {
        unawaited(closing);
      }
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isVisible(state)) return;
    final visible = _visible;
    _visible = null;
    if (visible != null && !visible.isCompleted) visible.complete();
  }

  static bool _isVisible(AppLifecycleState? state) => switch (state) {
    null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
    AppLifecycleState.hidden ||
    AppLifecycleState.paused ||
    AppLifecycleState.detached => false,
  };

  void _onFirstFrame() {
    if (_disposed || !mounted) return;
    final context = _IdleContext(
      container: ProviderScope.containerOf(this.context, listen: false),
      errorLog: widget.errorLog,
      web: widget.web,
    );
    _context = context;
    final immediate = [
      for (final task in widget.tasks)
        if (task.immediate) task,
    ];
    // Stable: equal priorities keep the module order of the list.
    final queued =
        [
          for (final (index, task) in widget.tasks.indexed)
            if (!task.immediate) (index, task),
        ]..sort((a, b) {
          final byPriority = a.$2.priority.compareTo(b.$2.priority);
          return byPriority != 0 ? byPriority : a.$1.compareTo(b.$1);
        });
    for (final task in immediate) {
      unawaited(_run(task, context));
    }
    // Each delay counts from the first frame: a task whose delay already
    // passed while an earlier one ran starts at once.
    final due = [for (final (_, task) in queued) _dueAfter(task.delay)];
    unawaited(_runQueue([for (final (_, task) in queued) task], due, context));
  }

  Future<void> _dueAfter(Duration delay) {
    final completer = Completer<void>();
    _timers.add(Timer(delay, completer.complete));
    return completer.future;
  }

  Future<void> _runQueue(
    List<AppIdleTask> tasks,
    List<Future<void>> due,
    _IdleContext context,
  ) async {
    for (final (index, task) in tasks.indexed) {
      await due[index];
      if (_disposed) return;
      while (!_isVisible(WidgetsBinding.instance.lifecycleState)) {
        await (_visible ??= Completer<void>()).future;
        if (_disposed) return;
      }
      // Between frames, once no animation runs (the rule of Priority.idle).
      // Waited frame by frame rather than with SchedulerBinding.scheduleTask:
      // while any animation runs, an idle-priority entry re-arms a zero-delay
      // timer on every event loop turn (scheduler binding _runTasks) — a busy
      // loop on the device, and an endless one inside a widget test's
      // fake-async pump (the timer is due again before the frame that would
      // end the animation; seen in the V5 v2 smoke, 2nd round integration).
      final scheduler = SchedulerBinding.instance;
      do {
        await scheduler.endOfFrame;
        if (_disposed) return;
      } while (scheduler.transientCallbackCount > 0);
      await _run(task, context);
      if (_disposed) return;
    }
  }

  Future<void> _run(AppIdleTask task, _IdleContext context) async {
    final slow = Timer(_slowTask, () {
      widget.errorLog.add(
        AppErrorRecord(
          time: DateTime.now(),
          source: AppErrorSource.module,
          summary:
              'idle task ${task.id} still running after '
              '${_slowTask.inSeconds} s',
        ),
      );
    });
    try {
      await Future<void>.sync(() => task.run(context));
    } on Object catch (error, stackTrace) {
      _logFailure(
        widget.errorLog,
        'idle task ${task.id} failed',
        error,
        stackTrace,
      );
    } finally {
      slow.cancel();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

final class _IdleContext implements AppIdleContext {
  _IdleContext({
    required this._container,
    required this.errorLog,
    required this.web,
  });

  final ProviderContainer _container;
  @override
  final AppErrorLog errorLog;
  @override
  final WebPlatform web;
  final List<FutureOr<void> Function()> _callbacks = [];
  bool _disposed = false;

  @override
  bool get isDisposed => _disposed;

  @override
  T read<T>(ProviderListenable<T> provider) => _container.read(provider);

  /// After the scope went away (a run that registers late): called at once.
  @override
  void onDispose(FutureOr<void> Function() callback) {
    if (_disposed) {
      unawaited(_call(callback));
      return;
    }
    _callbacks.add(callback);
  }

  /// Reverse registration order, each ≤ 2 s. Never throws.
  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    while (_callbacks.isNotEmpty) {
      await _call(_callbacks.removeLast());
    }
  }

  Future<void> _call(FutureOr<void> Function() callback) async {
    try {
      await Future<void>.sync(callback).timeout(_disposeTimeout);
    } on Object catch (error, stackTrace) {
      _logFailure(errorLog, 'idle task clean-up failed', error, stackTrace);
    }
  }
}

void _logFailure(
  AppErrorLog errorLog,
  String what,
  Object error,
  StackTrace stackTrace,
) {
  final record = AppErrorRecord.fromError(
    error,
    stackTrace,
    source: AppErrorSource.module,
  );
  errorLog.add(
    AppErrorRecord(
      time: record.time,
      source: record.source,
      summary: '$what: ${record.summary}',
      stackTrace: record.stackTrace,
    ),
  );
}
