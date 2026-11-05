/// Startup modules and the context they share (docs/plans/01-infra.md 4.5.4,
/// 6.4).
library;

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:note_core/note_core.dart' show OwnerId;

import '../errors/app_error_log.dart';
import '../runtime/build_info.dart';
import '../runtime/runtime_info.dart';
import '../web/web_platform.dart';
import 'startup_report.dart';

/// One unit of startup work, adapting one workspace package.
/// Implementations live in app/lib/src/modules/. Packages never see this type.
abstract class AppModule {
  const AppModule();

  /// Stable id for logs and the startup report, e.g. `core`.
  String get id;

  /// Korean label for the splash screen, e.g. `노트 저장소 여는 중`.
  String get label;

  /// Failure in [start] aborts startup when true (default).
  bool get critical => true;

  Duration get startTimeout => const Duration(seconds: 10);

  /// Async initialization. May publish values to [context] for later modules.
  Future<void> start(AppModuleContext context);

  /// Overrides for the root ProviderScope. Called once, after [start] succeeded.
  List<Override> overrides();

  /// App became hidden. Must finish within 500 ms (enforced by caller).
  Future<void> onAppHidden() async {}

  /// Release resources. Called in reverse start order on retry/shutdown.
  Future<void> stop() async {}

  /// Called by AppBootstrapper right after [start] exceeded [startTimeout].
  /// The start future is NOT cancelled and may still complete later; the
  /// returned future completes once that late result has been cleaned up
  /// (CoreModule: a late NoteStore is closed at once). AppBootstrapper.shutdown
  /// awaits it (at most 2 s) so a retry never runs next to a late resource.
  /// Must not throw; log failures to the context's errorLog.
  Future<void> onStartAbandoned() async {}

  /// Destructive last-resort recovery for the startup error screen
  /// ("이 기기 데이터 지우고 다시 시작"). Only CoreModule provides one.
  Future<void> Function()? get resetLocalData => null;

  /// Whether [resetLocalData] may be offered after [start] threw [error].
  bool canResetAfter(Object error) => false;
}

/// Overrides-only module (no async init), e.g. for tests and simple wiring.
final class StaticOverridesModule extends AppModule {
  StaticOverridesModule({
    required this.id,
    required this.label,
    required List<Override> overrides,
  }) : _overrides = List<Override>.unmodifiable(overrides);

  @override
  final String id;
  @override
  final String label;

  final List<Override> _overrides;

  @override
  Duration get startTimeout => const Duration(seconds: 1);

  @override
  Future<void> start(AppModuleContext context) async {}

  @override
  List<Override> overrides() => _overrides;
}

final class AppModuleContext {
  AppModuleContext({
    required this.buildInfo,
    required this.runtimeInfo,
    required this.web,
    required this.ownerId,
    required this.errorLog,
  });

  final BuildInfo buildInfo;
  final RuntimeInfo runtimeInfo;
  final WebPlatform web;

  /// Owner id handed to CORE as NoteStoreConfig.ownerId. It matters ONLY when
  /// CORE creates a NEW database: a persisted owner (e.g. after
  /// SyncStore.reassignOwner on first login) wins, and the effective owner is
  /// always NoteStore.ownerId. Until M4: kLocalOwnerId.
  final OwnerId ownerId;
  final AppErrorLog errorLog;

  final Map<Type, Object> _published = {};
  final Map<String, StartupStepOutcome> _outcomes = {};

  /// Makes [value] available to modules started later.
  /// Throws StateError when a value of type T was already published.
  void publish<T extends Object>(T value) {
    if (_published.containsKey(T)) {
      throw StateError('A value of type $T was already published.');
    }
    _published[T] = value;
  }

  /// Throws StateError when no value of type T was published.
  T require<T extends Object>() {
    final value = _published[T];
    if (value == null) {
      throw StateError('No value of type $T was published.');
    }
    return value as T;
  }

  T? maybe<T extends Object>() => _published[T] as T?;

  /// Outcome of a module that already ran in this attempt; null when it has
  /// not run (yet). FeatureWiringModule uses it to skip PDF overrides.
  StartupStepOutcome? outcomeOf(String moduleId) => _outcomes[moduleId];

  /// outcomeOf(moduleId) == StartupStepOutcome.ok.
  bool isStarted(String moduleId) =>
      outcomeOf(moduleId) == StartupStepOutcome.ok;

  /// Called by AppBootstrapper right after each module (never by modules).
  /// Throws StateError when [moduleId] already has an outcome.
  void recordOutcome(String moduleId, StartupStepOutcome outcome) {
    if (_outcomes.containsKey(moduleId)) {
      throw StateError('Module "$moduleId" already has an outcome.');
    }
    _outcomes[moduleId] = outcome;
  }
}
