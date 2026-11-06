// lib/src/lab/recognition_lab_sheet.dart — (internal) the A-4 quality lab
// (m5-7/05-library 6.20, review S-10, S-14; contract 7.8 A-4 v2.1).
//
// Opened from the settings section ([인식 실험 열기] — only with a handwriting
// engine, never on the web). Outside the editor, so the sheet may take 90% of
// the screen height. Top to bottom:
//   ko · English model rows (the settings rows — RecognitionModelRow with
//   the 'recog.lab.model' keys: download, Wi-Fi wait, cellular) and, until
//   both are ready, a notice — [인식] stays disabled (S-10);
//   'i/30 · group' and the sentence to write; the handwriting area (the math
//   pad's temporary page — never stored) with undo / clear;
//   [이전] [다음] [인식];
//   the current sentence's result: per column the top text (lines joined
//   with a space), its CER and its time; the summary per group (CER of A =
//   ko, en, B = strategy B, A in page coordinates), the time median / max per
//   column, engine id · models · platform; [결과 JSON 복사].
// [인식] recognizes the same strokes with ko, en and ko again with the points
// in page coordinates (PageOriginLineRecognizer; other engines get page pt
// anyway) — line by line, lines from groupIntoLines (the conversion sheet's
// conversionLinesOf). B = pickMixedCandidates(ko, en) per line (no engine
// call; its time = ko + en). Times are Stopwatch ms with the line grouping.
// A RecognitionFailure ends that sentence's result with its text (not
// reported); anything unexpected is reported once. The JSON holds no strokes
// (U18) — only the fixed sentences, the texts read, rates and times.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../common/report_error.dart';
import '../engines/mixed_language.dart';
import '../indexer/handwriting_indexer.dart' show IndexerTuning, textTail;
import '../l10n/recognition_strings.dart';
import '../model/candidates.dart';
import '../model/failures.dart';
import '../model/handwriting_trace.dart';
import '../ports/handwriting_recognizer.dart';
import '../ports/line_origin.dart';
import '../ports/model_admin.dart';
import '../providers.dart';
import '../ui/conversion_sheet.dart' show conversionLinesOf;
import '../ui/math_pad_canvas.dart';
import '../ui/model_downloads.dart';
import '../ui/model_row.dart';
import '../ui/recognition_sheet.dart';
import 'char_error_rate.dart';
import 'lab_sentences.dart';

/// The lab's keys (not appendix C — the settings entry is
/// `recog.settings.lab`).
abstract final class RecognitionLabKeys {
  static const ValueKey<String> sheet = ValueKey('recog.lab');
  static const ValueKey<String> recognize = ValueKey('recog.lab.recognize');
  static const ValueKey<String> previous = ValueKey('recog.lab.previous');
  static const ValueKey<String> next = ValueKey('recog.lab.next');
  static const ValueKey<String> undo = ValueKey('recog.lab.undo');
  static const ValueKey<String> clear = ValueKey('recog.lab.clear');
  static const ValueKey<String> target = ValueKey('recog.lab.target');
  static const ValueKey<String> progress = ValueKey('recog.lab.progress');
  static const ValueKey<String> modelsNeeded = ValueKey(
    'recog.lab.modelsNeeded',
  );
  static const ValueKey<String> copyJson = ValueKey('recog.lab.copyJson');
  static const ValueKey<String> engineLine = ValueKey('recog.lab.engine');

  /// The model rows: `recog.lab.model.<tag>` (RecognitionModelRow keys).
  static const String modelPrefix = 'recog.lab.model';

  /// The current result's line of [mode].
  static ValueKey<String> result(LabMode mode) =>
      ValueKey('recog.lab.result.${mode.name}');

  /// The summary line of [group].
  static ValueKey<String> summary(LabGroup group) =>
      ValueKey('recog.lab.summary.${group.name}');

  /// The time line of [mode].
  static ValueKey<String> latency(LabMode mode) =>
      ValueKey('recog.lab.latency.${mode.name}');
}

/// The lab's models: ko and English (A-4 v2.1).
const List<String> kLabLanguages = ['ko', 'en'];

/// The handwriting area's height (logical px = pt on the temporary page).
const double kLabCanvasHeight = 180;

/// The temporary page's id prefix.
const String kLabPagePrefix = 'lab_';

/// The four result columns.
enum LabMode {
  /// A: ko, points moved to the line box's top-left (the app's way).
  ko,

  /// en.
  en,

  /// B: strategy B over ko and en (6.8).
  mixed,

  /// A with the points in page coordinates (6.4 S-14).
  koPage,
}

/// One sentence's recognition.
final class LabResult {
  const LabResult({
    required this.lines,
    required this.texts,
    required this.ms,
    this.error,
  });

  /// The lines groupIntoLines made of the strokes.
  final int lines;

  /// Per column: the top candidates of the lines joined with ' '.
  final Map<LabMode, String> texts;

  /// Per column: Stopwatch ms (the line grouping included).
  final Map<LabMode, int> ms;

  /// The failure that ended the run (no texts then).
  final String? error;

  bool get ok => error == null;
}

/// Recognizes [strokes] for every column (6.20). [pageWidth] is the
/// temporary page's width (the writing area's width, like the indexer).
Future<LabResult> runLabRecognition(
  HandwritingRecognizer engine,
  List<core.Stroke> strokes, {
  required double pageWidth,
}) async {
  final grouping = Stopwatch()..start();
  final lines = conversionLinesOf(strokes);
  grouping.stop();
  final groupingMs = grouping.elapsedMilliseconds;

  Future<List<List<TextCandidate>>> pass(
    String tag, {
    required bool pageOrigin,
  }) async {
    final out = <List<TextCandidate>>[];
    var written = '';
    for (final line in lines) {
      final input = HandwritingLineInput(
        line.traces,
        preContext: textTail(written, IndexerTuning.preContextChars),
        writingAreaPt: Size(
          pageWidth,
          math.max(
            line.rect.height * IndexerTuning.writingAreaLineFactor,
            IndexerTuning.minWritingAreaHeight,
          ),
        ),
      );
      final candidates = pageOrigin && engine is PageOriginLineRecognizer
          ? await (engine as PageOriginLineRecognizer)
                .recognizeLineInPageCoordinates(input, languageTag: tag)
          : await engine.recognizeLine(input, languageTag: tag);
      out.add(candidates);
      if (candidates.isNotEmpty) {
        final top = candidates.first.text;
        written = written.isEmpty ? top : '$written $top';
      }
    }
    return out;
  }

  final lists = <LabMode, List<List<TextCandidate>>>{};
  final ms = <LabMode, int>{};
  try {
    for (final (mode, tag, pageOrigin) in const [
      (LabMode.ko, 'ko', false),
      (LabMode.en, 'en', false),
      (LabMode.koPage, 'ko', true),
    ]) {
      final watch = Stopwatch()..start();
      lists[mode] = await pass(tag, pageOrigin: pageOrigin);
      watch.stop();
      ms[mode] = watch.elapsedMilliseconds + groupingMs;
    }
  } on RecognitionFailure catch (e) {
    return LabResult(
      lines: lines.length,
      texts: const {},
      ms: const {},
      error: '$e',
    );
  }
  final ko = lists[LabMode.ko]!;
  final en = lists[LabMode.en]!;
  lists[LabMode.mixed] = [
    for (var j = 0; j < lines.length; j++) pickMixedCandidates(ko[j], en[j]),
  ];
  ms[LabMode.mixed] = ms[LabMode.ko]! + ms[LabMode.en]! - groupingMs;
  String joined(List<List<TextCandidate>> perLine) => [
    for (final c in perLine)
      if (c.isNotEmpty) c.first.text,
  ].join(' ');
  return LabResult(
    lines: lines.length,
    texts: {for (final mode in LabMode.values) mode: joined(lists[mode]!)},
    ms: ms,
  );
}

/// The CER of [mode] over the recognized sentences of [group]: summed
/// distances ÷ summed target lengths; null before any.
double? labGroupCer(List<LabResult?> results, LabGroup group, LabMode mode) {
  var distance = 0, length = 0;
  for (var i = 0; i < kLabSentences.length && i < results.length; i++) {
    final r = results[i];
    if (r == null || !r.ok || kLabSentences[i].group != group) continue;
    final c = charErrorCounts(kLabSentences[i].text, r.texts[mode] ?? '');
    distance += c.distance;
    length += c.length;
  }
  return length == 0 ? null : distance / length;
}

/// The middle value (the mean of the two middle ones, rounded, for an even
/// count); null for none.
int? labMedian(List<int> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return ((sorted[mid - 1] + sorted[mid]) / 2).round();
}

List<int> _times(List<LabResult?> results, LabMode mode) => [
  for (final r in results)
    if (r != null && r.ok && r.ms[mode] != null) r.ms[mode]!,
];

double _rounded(double value) => (value * 10000).round() / 10000;

/// [결과 JSON 복사]'s object (6.20): no strokes.
Map<String, Object?> buildLabJson({
  required String engineId,
  required String platform,
  required Map<String, String?> models,
  required List<LabResult?> results,
}) => {
  'kind': 'recognition-lab',
  'version': 1,
  'engineId': engineId,
  'platform': platform,
  'models': models,
  'summary': {
    for (final group in LabGroup.values)
      group.name: {
        'sentences': [
          for (var i = 0; i < kLabSentences.length; i++)
            if (kLabSentences[i].group == group && (results[i]?.ok ?? false)) i,
        ].length,
        'cer': {
          for (final mode in LabMode.values)
            mode.name: switch (labGroupCer(results, group, mode)) {
              final double rate => _rounded(rate),
              null => null,
            },
        },
      },
    'latencyMs': {
      for (final mode in LabMode.values)
        mode.name: {
          'median': labMedian(_times(results, mode)),
          'max': _times(
            results,
            mode,
          ).fold<int?>(null, (a, b) => a == null || b > a ? b : a),
        },
    },
  },
  'sentences': [
    for (var i = 0; i < kLabSentences.length; i++)
      if (results[i] case final LabResult r)
        {
          'index': i + 1,
          'group': kLabSentences[i].group.name,
          'target': kLabSentences[i].text,
          'lines': r.lines,
          if (r.ok) ...{
            'text': {for (final m in LabMode.values) m.name: r.texts[m]},
            'cer': {
              for (final m in LabMode.values)
                m.name: _rounded(
                  charErrorRate(kLabSentences[i].text, r.texts[m] ?? ''),
                ),
            },
            'ms': {for (final m in LabMode.values) m.name: r.ms[m]},
          } else
            'error': r.error,
        },
  ],
};

/// Opens the lab (the settings entry). Call it from a press handler.
Future<void> openRecognitionLab(BuildContext context) =>
    showRecognitionSheet<void>(
      context,
      sheetKey: RecognitionLabKeys.sheet,
      maxHeightFactor: kOutsideEditorSheetMaxHeightFactor,
      builder: (_) => const RecognitionLabSheet(),
    );

class RecognitionLabSheet extends ConsumerStatefulWidget {
  const RecognitionLabSheet({super.key});

  @override
  ConsumerState<RecognitionLabSheet> createState() =>
      _RecognitionLabSheetState();
}

class _RecognitionLabSheetState extends ConsumerState<RecognitionLabSheet> {
  late final HandwritingRecognizer _engine;
  late final ModelDownloads _downloads;
  late final String _pageId;
  late final core.EpochMillis _createdAt;
  final MathPadInk _ink = MathPadInk();
  final List<LabResult?> _results = List<LabResult?>.filled(
    kLabSentences.length,
    null,
  );
  final Map<String, RecognitionModelState?> _models = {
    for (final tag in kLabLanguages) tag: null,
  };
  StreamSubscription<String>? _changes;
  int _index = 0;
  int _ask = 0;
  bool _running = false;
  double _pageWidth = 0;
  String? _notice;
  SheetNoticeKind _noticeKind = SheetNoticeKind.info;

  bool get _modelsReady =>
      _models.values.every((s) => s == RecognitionModelState.ready);

  bool get _canRecognize => _modelsReady && !_ink.isEmpty && !_running;

  @override
  void initState() {
    super.initState();
    _engine = ref.read(handwritingRecognizerProvider);
    _downloads = ref.read(modelDownloadsProvider)..addListener(_askModels);
    _pageId = '$kLabPagePrefix${ref.read(core.idGeneratorProvider).newId()}';
    _createdAt = ref.read(core.clockProvider).now().millisecondsSinceEpoch;
    _ink.addListener(_onInk);
    if (_engine case final RecognizerModelAdmin admin) {
      _changes = admin.modelChanges.listen((tag) {
        if (kLabLanguages.contains(tag)) _askModels();
      });
    }
    _askModels();
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel()); // never awaited (fake_async)
    _downloads.removeListener(_askModels);
    _ink
      ..removeListener(_onInk)
      ..dispose();
    super.dispose();
  }

  void _onInk() {
    if (mounted) setState(() {});
  }

  void _askModels() {
    final ask = ++_ask;
    for (final tag in kLabLanguages) {
      unawaited(
        _engine
            .modelState(tag)
            .then<void>(
              (state) {
                if (!mounted || ask != _ask) return;
                setState(() => _models[tag] = state);
              },
              onError: (Object _) {
                // The model row shows and reports the failure.
                if (mounted && ask == _ask) setState(() => _models[tag] = null);
              },
            ),
      );
    }
  }

  Future<void> _recognize() async {
    final index = _index;
    final strokes = _ink.strokes;
    setState(() {
      _running = true;
      _notice = null;
    });
    LabResult result;
    try {
      result = await runLabRecognition(_engine, strokes, pageWidth: _pageWidth);
    } on Object catch (e, s) {
      reportRecognitionError(e, s, 'recognition lab');
      result = LabResult(lines: 0, texts: const {}, ms: const {}, error: '$e');
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _results[index] = result;
    });
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= kLabSentences.length) return;
    setState(() {
      _index = next;
      _notice = null;
    });
    _ink.clear();
  }

  void _copyJson() {
    final text = const JsonEncoder.withIndent('  ').convert(
      buildLabJson(
        engineId: _engine.engineId,
        platform: defaultTargetPlatform.name,
        models: {for (final e in _models.entries) e.key: e.value?.name},
        results: _results,
      ),
    );
    // Started synchronously inside onPressed (7.2.10).
    final pending = Clipboard.setData(ClipboardData(text: text));
    unawaited(
      pending.then<void>(
        (_) => _setNotice(RecognitionStrings.labCopied, SheetNoticeKind.info),
        onError: (Object _) =>
            _setNotice(RecognitionStrings.copyFailed, SheetNoticeKind.error),
      ),
    );
  }

  void _setNotice(String text, SheetNoticeKind kind) {
    if (!mounted) return;
    setState(() {
      _notice = text;
      _noticeKind = kind;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sentence = kLabSentences[_index];
    final notice = _notice;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecognitionSheetHeader(
          title: RecognitionStrings.labTitle,
          cancelLabel: RecognitionStrings.close,
          onCancel: () => Navigator.of(context).pop(),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final tag in kLabLanguages)
                  RecognitionModelRow(
                    languageTag: tag,
                    keyPrefix: RecognitionLabKeys.modelPrefix,
                  ),
                if (!_modelsReady)
                  const SheetNotice(
                    key: RecognitionLabKeys.modelsNeeded,
                    text: RecognitionStrings.labModelsNeeded,
                  ),
                const SizedBox(height: 8),
                Text(
                  RecognitionStrings.labProgress(
                    _index + 1,
                    kLabSentences.length,
                    RecognitionStrings.labGroupName(sentence.group.name),
                  ),
                  key: RecognitionLabKeys.progress,
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Semantics(
                  hint: RecognitionStrings.labWritePrompt,
                  child: Text(
                    sentence.text,
                    key: RecognitionLabKeys.target,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    // The page is the area inside the 1 px border.
                    _pageWidth = math.max(0, constraints.maxWidth - 2);
                    return MathPadCanvas(
                      ink: _ink,
                      pageId: _pageId,
                      noteId: 'lab',
                      createdAt: _createdAt,
                      height: kLabCanvasHeight,
                    );
                  },
                ),
                _buttons(),
                if (notice != null)
                  SheetNotice(text: notice, kind: _noticeKind),
                _resultOf(theme),
                const Divider(height: 24),
                ..._summary(theme),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buttons() {
    final hasInk = !_ink.isEmpty;
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton.icon(
          key: RecognitionLabKeys.undo,
          style: kSheetMinTapStyle,
          onPressed: hasInk && !_running ? _ink.undo : null,
          icon: const Icon(Icons.undo),
          label: const Text(RecognitionStrings.padUndo),
        ),
        TextButton(
          key: RecognitionLabKeys.clear,
          style: kSheetMinTapStyle,
          onPressed: hasInk && !_running ? _ink.clear : null,
          child: const Text(RecognitionStrings.padClear),
        ),
        OutlinedButton(
          key: RecognitionLabKeys.previous,
          style: kSheetMinTapStyle,
          onPressed: _index > 0 && !_running ? () => _go(-1) : null,
          child: const Text(RecognitionStrings.labPrevious),
        ),
        OutlinedButton(
          key: RecognitionLabKeys.next,
          style: kSheetMinTapStyle,
          onPressed: _index < kLabSentences.length - 1 && !_running
              ? () => _go(1)
              : null,
          child: const Text(RecognitionStrings.labNext),
        ),
        FilledButton(
          key: RecognitionLabKeys.recognize,
          style: kSheetMinTapStyle,
          onPressed: _canRecognize ? _recognize : null,
          child: const Text(RecognitionStrings.labRecognize),
        ),
      ],
    );
  }

  Widget _resultOf(ThemeData theme) {
    if (_running) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(RecognitionStrings.recognizing),
      );
    }
    final result = _results[_index];
    if (result == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          RecognitionStrings.labNotYet,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    final error = result.error;
    if (error != null) {
      return SheetNotice(text: error, kind: SheetNoticeKind.error);
    }
    final target = kLabSentences[_index].text;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final mode in LabMode.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${RecognitionStrings.labCer(mode.name, charErrorRate(target, result.texts[mode] ?? ''))}'
                ' · ${RecognitionStrings.labMs(result.ms[mode] ?? 0)}'
                ' · ${result.texts[mode] ?? ''}',
                key: RecognitionLabKeys.result(mode),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _summary(ThemeData theme) {
    final scheme = theme.colorScheme;
    final models = [
      for (final tag in kLabLanguages) '$tag ${_models[tag]?.name ?? '—'}',
    ].join(' · ');
    return [
      Text(RecognitionStrings.labSummary, style: theme.textTheme.titleSmall),
      for (final group in LabGroup.values)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            [
              RecognitionStrings.labGroupLine(
                group.name,
                [
                  for (var i = 0; i < kLabSentences.length; i++)
                    if (kLabSentences[i].group == group &&
                        (_results[i]?.ok ?? false))
                      i,
                ].length,
                kLabSentences.where((s) => s.group == group).length,
              ),
              for (final mode in LabMode.values)
                RecognitionStrings.labCer(
                  mode.name,
                  labGroupCer(_results, group, mode),
                ),
            ].join(' · '),
            key: RecognitionLabKeys.summary(group),
          ),
        ),
      const SizedBox(height: 8),
      Text(RecognitionStrings.labLatency, style: theme.textTheme.labelLarge),
      for (final mode in LabMode.values)
        if (_times(_results, mode) case final times when times.isNotEmpty)
          Text(
            RecognitionStrings.labLatencyLine(
              mode.name,
              labMedian(times)!,
              times.reduce(math.max),
            ),
            key: RecognitionLabKeys.latency(mode),
          ),
      const SizedBox(height: 8),
      Text(
        '${_engine.engineId} · $models · ${defaultTargetPlatform.name}',
        key: RecognitionLabKeys.engineLine,
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: RecognitionLabKeys.copyJson,
          style: kSheetMinTapStyle,
          onPressed: _results.any((r) => r != null) ? _copyJson : null,
          icon: const Icon(Icons.copy),
          label: const Text(RecognitionStrings.labCopyJson),
        ),
      ),
    ];
  }
}
