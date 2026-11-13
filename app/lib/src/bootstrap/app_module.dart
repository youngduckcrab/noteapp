/// Startup modules and the context they share (docs/plans/01-infra.md 4.5.4,
/// 6.4; 2nd round docs/plans/m5-7/01-infra.md 4.6.2, 6.4).
library;

import 'package:feature_editor/feature_editor.dart'
    show
        DevOverlaySection,
        EditorInsertMenuItem,
        EditorMathPen,
        EditorPanelBuilder,
        EditorSelectionMenuItem,
        EditorTextPen;
import 'package:feature_library/feature_library.dart' show LibraryInkSearch;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:note_core/note_core.dart' show NoteStore, OwnerId;

import '../errors/app_error_log.dart';
import '../features/app_features.dart';
import '../runtime/build_info.dart';
import '../runtime/runtime_info.dart';
import '../settings/settings_sections.dart' show SettingsSectionEntry;
import '../web/web_platform.dart';
import 'idle_tasks.dart';
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

  /// false → skipped: no start(), no overrides(), no contribution, no idle
  /// tasks (D2-3). Called by AppBootstrapper right before start(); its own
  /// time limit is 1 s (timeout → skipped is NOT used: a timeout counts as
  /// enabled = true so a slow settings read never hides a feature).
  Future<bool> isEnabled(AppModuleContext context) async => true;

  /// Idle-time work after a successful start (6.5). Called once, after
  /// overrides().
  List<AppIdleTask> idleTasks() => const [];

  /// Contribution kept INSTEAD of the module's own when start() failed or
  /// timed out (non-critical). Default null. MediaModule: the recording panel
  /// only (계약 7.3.3: '녹음할 수 없어요').
  ShellContribution? fallbackContribution() => null;
}

/// What one module adds to INFRA-assembled slots (6.7).
@immutable
final class ShellContribution {
  const ShellContribution({
    required this.moduleId,
    this.selectionMenuItems = const [],
    this.insertMenuItems = const [],
    this.recordingPanel,
    this.mathPen,
    this.libraryInkSearch,
    this.textPen,
    this.devOverlaySections = const [],
    this.settingsSections = const [],
  });

  final String moduleId;
  final List<EditorSelectionMenuItem> selectionMenuItems;
  final List<EditorInsertMenuItem> insertMenuItems;
  final EditorPanelBuilder? recordingPanel;

  /// (math pen, phase 1) recog's 수식 펜 (RecognitionModule).
  final EditorMathPen? mathPen;

  /// (handwriting search) the library search's handwriting hint
  /// (RecognitionModule) — read in the provider that overrides
  /// libraryInkSearchProvider.
  final LibraryInkSearch? Function(Ref ref)? libraryInkSearch;

  /// (text pen, phase 1) recog's 텍스트 펜 (RecognitionModule).
  final EditorTextPen? textPen;
  // (v2.1, D2-15) no imageImporter: image import is wired by
  // FeatureWiringModule itself, outside FEATURE_MEDIA and independent of
  // MediaModule's start.
  final List<DevOverlaySection Function(Ref ref)> devOverlaySections;
  final List<SettingsSectionEntry> settingsSections;

  /// Whether it fills an editor slot (selection / insert items, panel).
  bool get hasEditorItems =>
      selectionMenuItems.isNotEmpty ||
      insertMenuItems.isNotEmpty ||
      recordingPanel != null ||
      mathPen != null ||
      textPen != null;

  @override
  String toString() =>
      'ShellContribution($moduleId: ${selectionMenuItems.length} selection, '
      '${insertMenuItems.length} insert, '
      'panel ${recordingPanel == null ? 'no' : 'yes'}, '
      'math pen ${mathPen == null ? 'no' : 'yes'}, '
      'ink search ${libraryInkSearch == null ? 'no' : 'yes'}, '
      'text pen ${textPen == null ? 'no' : 'yes'}, '
      '${devOverlaySections.length} dev, ${settingsSections.length} settings)';
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
    this.compileTimeFeatures = AppFeatures.all,
  });

  /// How long resolveFeatures() waits for the three settings reads.
  static const Duration featureReadTimeout = Duration(milliseconds: 500);

  final BuildInfo buildInfo;
  final RuntimeInfo runtimeInfo;
  final WebPlatform web;

  /// Owner id handed to CORE as NoteStoreConfig.ownerId. It matters ONLY when
  /// CORE creates a NEW database: a persisted owner (e.g. after
  /// SyncStore.reassignOwner on first login) wins, and the effective owner is
  /// always NoteStore.ownerId. Until M4: kLocalOwnerId.
  final OwnerId ownerId;
  final AppErrorLog errorLog;

  /// The build's switches (AppFeatures.compileTime in runNoteApp).
  final AppFeatures compileTimeFeatures;

  final Map<Type, Object> _published = {};
  final Map<String, StartupStepOutcome> _outcomes = {};

  /// By moduleId, in contribution order (= module order).
  final Map<String, ShellContribution> _contributions = {};
  final Set<String> _lateLogged = {};
  Future<AppFeatures>? _features;

  /// compileTimeFeatures AND the developer-menu settings of the NoteStore
  /// published by CoreModule (all three keys read once, ≤ 500 ms, cached).
  /// No store / read failure → compileTimeFeatures (failure logged, source
  /// module). A call before CoreModule published the store is not cached:
  /// the first call after it reads the settings.
  Future<AppFeatures> resolveFeatures() {
    final store = maybe<NoteStore>();
    if (store == null && _features == null) {
      return Future.value(compileTimeFeatures);
    }
    return _features ??= _readFeatures(store!);
  }

  Future<AppFeatures> _readFeatures(NoteStore store) async {
    try {
      final values = await Future.wait([
        for (final feature in AppFeature.values)
          store.settings.get(AppFeatureKeys.of(feature)),
      ]).timeout(featureReadTimeout);
      final menu = AppFeatures(
        media: values[AppFeature.media.index],
        recognition: values[AppFeature.recognition.index],
        mathEngine: values[AppFeature.mathEngine.index],
      );
      return compileTimeFeatures.and(menu);
    } on Object catch (error, stackTrace) {
      _log(
        error,
        stackTrace,
        'feature switches not read — the build values are used',
      );
      return compileTimeFeatures;
    }
  }

  /// (await resolveFeatures()).isOn(feature)
  Future<bool> featureOn(AppFeature feature) async =>
      (await resolveFeatures()).isOn(feature);

  /// Shell contributions of the modules started so far (6.7). Throws
  /// StateError for a second contribution of the same moduleId. (v2.1,
  /// C21-20) Once the bootstrapper has recorded an outcome for that module
  /// (failed / timed out → abandoned), a late call is ignored and logged once
  /// (`'late contribution of <moduleId> ignored'`, source module) — it never
  /// joins FeatureWiringModule's assembly or doubles the fallback
  /// contribution.
  void contribute(ShellContribution contribution) {
    final moduleId = contribution.moduleId;
    if (_outcomes.containsKey(moduleId)) {
      if (_lateLogged.add(moduleId)) {
        errorLog.add(
          AppErrorRecord(
            time: DateTime.now(),
            source: AppErrorSource.module,
            summary: 'late contribution of $moduleId ignored',
            details:
                'outcome ${_outcomes[moduleId]!.name} was recorded before '
                'contribute()',
          ),
        );
      }
      return;
    }
    if (_contributions.containsKey(moduleId)) {
      throw StateError('Module "$moduleId" already contributed.');
    }
    _contributions[moduleId] = contribution;
  }

  /// Module order, recorded outcomes only: the contribution of a module that
  /// started, or the fallback contribution of one that failed.
  List<ShellContribution> get contributions => List.unmodifiable([
    for (final MapEntry(:key, :value) in _contributions.entries)
      if (_outcomes.containsKey(key)) value,
  ]);

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
  ///
  /// Any outcome but ok drops what the module contributed during start();
  /// [fallback] (its fallbackContribution() — failed or timed out only)
  /// takes that place.
  void recordOutcome(
    String moduleId,
    StartupStepOutcome outcome, {
    ShellContribution? fallback,
  }) {
    if (_outcomes.containsKey(moduleId)) {
      throw StateError('Module "$moduleId" already has an outcome.');
    }
    assert(
      fallback == null || fallback.moduleId == moduleId,
      'fallback contribution of "${fallback.moduleId}" recorded for '
      '"$moduleId"',
    );
    _outcomes[moduleId] = outcome;
    if (outcome == StartupStepOutcome.ok) return;
    _contributions.remove(moduleId);
    if (fallback != null) _contributions[moduleId] = fallback;
  }

  void _log(Object error, StackTrace stackTrace, String details) {
    final record = AppErrorRecord.fromError(
      error,
      stackTrace,
      source: AppErrorSource.module,
    );
    errorLog.add(
      AppErrorRecord(
        time: record.time,
        source: record.source,
        summary: record.summary,
        details: details,
        stackTrace: record.stackTrace,
      ),
    );
  }
}
