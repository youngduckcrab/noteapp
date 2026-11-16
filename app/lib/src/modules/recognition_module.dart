/// Recognition adapter (docs/plans/m5-7/01-infra.md 4.6.4, 6.4, 6.6, 6.7;
/// contract 7.2.11 / 7.3.3 rows X31 · X32).
library;

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ink_recognition/ink_recognition.dart'
    show
        RecognitionAction,
        RecognitionConfig,
        RecognitionSettingsSection,
        RecognitionMathPen,
        RecognitionTextPen,
        recognitionInsertActions,
        recognitionMathPen,
        recognitionTextPen,
        recognitionOverrides,
        recognitionSelectionActions;

import '../bootstrap/app_module.dart';
import '../bootstrap/idle_tasks.dart';
import '../errors/app_error_log.dart';
import '../features/app_features.dart';
import '../settings/settings_sections.dart' show SettingsSectionEntry;
import 'idle_indexers.dart';
import 'recognition_wiring.dart';

/// Handwriting / math recognition and the shape fitter (FEATURE_RECOGNITION
/// also turns off automatic shape correction — the shape fitter's only
/// override is recognitionOverrides(), X31).
final class RecognitionModule extends AppModule {
  RecognitionModule({
    this._overridesFor = recognitionOverrides,
    this._selectionActions = recognitionSelectionActions,
    this._insertActions = recognitionInsertActions,
    this._mathPen = recognitionMathPen,
    this._textPen = recognitionTextPen,
    this._indexer = readHandwritingIndexer,
    this._mathEndpoint = kMathEndpoint,
  });

  static const String moduleId = 'recognition';

  final List<Override> Function({RecognitionConfig config}) _overridesFor;
  final List<RecognitionAction> Function() _selectionActions;
  final List<RecognitionAction> Function() _insertActions;
  final RecognitionMathPen Function() _mathPen;
  final RecognitionTextPen Function() _textPen;
  final IndexerHandleReader _indexer;
  final String _mathEndpoint;

  RecognitionConfig _config = const RecognitionConfig();

  /// The config of the last successful start (tests).
  RecognitionConfig get config => _config;

  @override
  String get id => moduleId;

  @override
  String get label => '인식 준비 중';

  @override
  bool get critical => false;

  @override
  Duration get startTimeout => const Duration(seconds: 3);

  /// featureOn(recognition)
  @override
  Future<bool> isEnabled(AppModuleContext context) =>
      context.featureOn(AppFeature.recognition);

  /// config = RecognitionConfig(mathEndpoint: await
  /// context.featureOn(AppFeature.mathEngine) && mathEndpoint.isNotEmpty ?
  /// Uri.parse(mathEndpoint) : null) — idTokenProvider: null (실연결 뒤). A
  /// MATH_ENDPOINT that is not an absolute http(s) URL → null + one record.
  /// context.contribute(ShellContribution(moduleId: 'recognition',
  ///   selectionMenuItems: selectionActions().map(selectionMenuItemOf),
  ///   insertMenuItems: insertActions().map(insertMenuItemOf),
  ///   mathPen: editorMathPenOf(recognitionMathPen()),
  ///   libraryInkSearch: libraryInkSearchOf,
  ///   editorInkSearch: editorInkSearchOf,
  ///   textPen: editorTextPenOf(recognitionTextPen()),
  ///   devOverlaySections: [recognitionIndexerSection],
  ///   settingsSections: [SettingsSectionEntry(id: 'recog.settings',
  ///       title: '인식', builder: (_) => const RecognitionSettingsSection())]))
  @override
  Future<void> start(AppModuleContext context) async {
    final mathOn = await context.featureOn(AppFeature.mathEngine);
    _config = RecognitionConfig(
      mathEndpoint: mathOn && _mathEndpoint.isNotEmpty
          ? _endpointOrNull(_mathEndpoint, context.errorLog)
          : null,
    );
    context.contribute(
      ShellContribution(
        moduleId: moduleId,
        selectionMenuItems: List.unmodifiable(
          _selectionActions().map(selectionMenuItemOf),
        ),
        insertMenuItems: List.unmodifiable(
          _insertActions().map(insertMenuItemOf),
        ),
        // (math pen, phase 1) the 수식 펜 tool.
        mathPen: editorMathPenOf(_mathPen()),
        // (handwriting search) the library search's handwriting hint.
        libraryInkSearch: libraryInkSearchOf,
        // (v2.13-search) the in-note search's handwriting hint.
        editorInkSearch: editorInkSearchOf,
        // (text pen, phase 1) the 텍스트 펜 tool and '손글씨를 텍스트로'.
        textPen: editorTextPenOf(_textPen()),
        devOverlaySections: const [recognitionIndexerSection],
        settingsSections: [
          SettingsSectionEntry(
            id: 'recog.settings',
            title: '인식',
            builder: (_) => const RecognitionSettingsSection(),
          ),
        ],
      ),
    );
  }

  /// overridesFor(config: config) — X31 · X32.
  @override
  List<Override> overrides() => _overridesFor(config: _config);

  /// [AppIdleTask(id: 'recognition.indexer', priority:
  /// AppIdlePriority.recognition, run: (c) => runIndexerTask(c, indexer))] —
  /// the reader gives null on web / without a recognizer.
  @override
  List<AppIdleTask> idleTasks() => [
    AppIdleTask(
      id: 'recognition.indexer',
      priority: AppIdlePriority.recognition,
      run: (context) => runIndexerTask(context, _indexer),
    ),
  ];
}

Uri? _endpointOrNull(String value, AppErrorLog errorLog) {
  final uri = Uri.tryParse(value);
  if (uri != null &&
      (uri.isScheme('http') || uri.isScheme('https')) &&
      uri.host.isNotEmpty) {
    return uri;
  }
  errorLog.add(
    AppErrorRecord(
      time: DateTime.now(),
      source: AppErrorSource.module,
      summary: 'MATH_ENDPOINT is not an http(s) URL — math engine off',
      details: value,
    ),
  );
  return null;
}
