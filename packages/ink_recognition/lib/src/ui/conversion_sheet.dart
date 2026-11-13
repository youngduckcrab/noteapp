// lib/src/ui/conversion_sheet.dart — (internal) m5-7/05-library 6.13
// (recog.toText, recog.copyText with strokes — F-10), 6.12, 6.7.4, 6.22.
//
// [취소]              텍스트로 변환               [텍스트 상자로]   ← copyText: [복사]
// 언어 ( 한국어 | English )
// status: 인식 중… 2/5줄 · model card · '다시' on a failure
// 1줄 [오늘 회의록을 정리했다          ]
//      (회의록을 정리했다) (오늘 회의록올 정리했다) …     ← up to 4 chips
// 2줄 [meeting notes                  ]
// '나머지 n줄은 …' (more than 20 lines)
// [복사]                                                   ← recog.toText only
//
// - The run groups the selection's input strokes into lines (groupIntoLines —
//   the indexer's function), keeps the first 20 and opens the sheet before its
//   first await. The sheet reads recog.language once (its own language after
//   that — the setting is not changed, 6.13.3) and recognizes the lines one
//   after another (preContext = the last 20 characters of the line before).
// - No engine (the web, desktops) → the fixed web sentence (contract 7.4.2) /
//   '이 기기에서는 …' and [닫기]. The model of the language not ready → the
//   model card (modelNeeded + RecognitionModelRow: [받기], the iPad two-press,
//   Android's 5 s Wi-Fi wait → [지금 셀룰러로 받기]); the sheet goes on when
//   the model is ready (modelChanges / the user download ending). Another
//   engine failure → '인식하지 못했어요 …' [다시] (expected — not reported).
// - A line card: its field (one line) and the line's other candidates as
//   chips (≤ 4 — five in all); a chip puts its text in the field. A line the
//   user edited or picked a chip for is 'touched': a language change
//   recognizes only the untouched lines again; answers are cached per
//   language (switching back is immediate).
// - [텍스트 상자로] (6.13.4): the joined text (trimmed lines, no empty ones,
//   '\n') → buildTextBox (INK's measure) → ONE CompositeCommand(
//   [RemoveElements(input strokes), AddObjects([box])], 'recog-to-text') →
//   the sheet closes → target.done(). Disabled above 10,000 characters.
// - [복사] (6.13.5): Clipboard.setData STARTS synchronously inside onPressed
//   (contract 7.2.10); a failure → '복사하지 못했어요' (the sheet stays, nothing
//   is written). Then store.flush() → content.loadPage (the strokes just
//   written count) → handwriting.update(mergeConfirmed(stored value, the
//   lines confirmed, rev, all)) — a failed write is reported once (the copy
//   is done) → the sheet closes → '복사했어요'. No command, no done().
// - ReadOnlyNoteException → '읽기 전용 …' (the sheet stays — copying still
//   works); anything unexpected → reported once + '실행하지 못했어요'.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../actions/action_scope.dart';
import '../actions/object_builders.dart';
import '../common/recognition_priority.dart';
import '../common/report_error.dart';
import '../indexer/handwriting_indexer.dart' show IndexerTuning, textTail;
import '../indexer/line_reuse.dart';
import '../l10n/recognition_strings.dart';
import '../lines/group_into_lines.dart';
import '../model/candidates.dart';
import '../model/failures.dart';
import '../model/handwriting_trace.dart';
import '../ports/handwriting_recognizer.dart';
import '../ports/model_admin.dart';
import '../settings/recognition_settings_keys.dart';
import 'model_downloads.dart';
import 'model_row.dart';
import 'recognition_sheet.dart';

/// Appendix C keys.
const ValueKey<String> kConversionSheetKey = ValueKey('recog.sheet.toText');

/// Line [i]'s field (appendix C `recog.sheet.line.<i>`).
ValueKey<String> conversionLineKey(int i) => ValueKey('recog.sheet.line.$i');

/// Line [i]'s chip [j] (appendix C `recog.sheet.chip.<i>.<j>`).
ValueKey<String> conversionChipKey(int i, int j) =>
    ValueKey('recog.sheet.chip.$i.$j');

/// The sheet's own keys (not appendix C).
const ValueKey<String> kConversionStatusKey = ValueKey(
  'recog.sheet.toText.status',
);
ValueKey<String> conversionLanguageKey(String tag) =>
    ValueKey('recog.sheet.language.$tag');

/// The model card's row: `'recog.sheet.model.<tag>'` (cellular button
/// `'….<tag>.cellular'`).
const String kConversionModelKeyPrefix = 'recog.sheet.model';

/// 6.13.2: lines recognized at once; chips per line (five candidates in all).
const int kMaxConversionLines = 20;
const int kMaxLineChips = 4;

/// What closed the sheet.
enum ConversionOutcome { textBox, copied }

/// Tests: the web's fixed sentence without a browser (null → kIsWeb).
abstract final class ConversionSheetDebug {
  @visibleForTesting
  static bool? isWeb;
}

/// One line of the selection (groupIntoLines order; strokes by first-sample
/// time).
@immutable
final class ConversionLineInput {
  ConversionLineInput(this.strokes)
    : traces = [for (final s in strokes) HandwritingTrace.fromStroke(s)],
      rect = strokes
          .map((s) => s.points.pointBounds)
          .reduce((a, b) => a.expandToInclude(b));

  final List<core.Stroke> strokes;
  final List<HandwritingTrace> traces;

  /// Union of the strokes' pointBounds (HandwritingLine.rect).
  final core.PageRect rect;

  List<core.ElementId> get strokeIds => [for (final s in strokes) s.id];
}

/// The lines of [inputs] (recognition input strokes, z order): every line,
/// in reading order (strokes without points are left out).
List<ConversionLineInput> conversionLinesOf(List<core.Stroke> inputs) {
  final traces = [for (final s in inputs) HandwritingTrace.fromStroke(s)];
  return [
    for (final group in groupTraceIndices(traces))
      ConversionLineInput([for (final i in group) inputs[i]]),
  ];
}

/// The engine input of [line] (the sheet's rule, shared with the text pen):
/// preContext = the last 20 characters of [previousText] (the line before),
/// writing area = the page width × max(line height × 1.5, the minimum).
HandwritingLineInput conversionLineInput(
  ConversionLineInput line, {
  required String previousText,
  required double pageWidth,
}) => HandwritingLineInput(
  line.traces,
  preContext: textTail(previousText, IndexerTuning.preContextChars),
  writingAreaPt: Size(
    pageWidth,
    math.max(
      line.rect.height * IndexerTuning.writingAreaLineFactor,
      IndexerTuning.minWritingAreaHeight,
    ),
  ),
);

/// The candidate texts of a line: trimmed, distinct, not blank, at most
/// kMaxLineAlternatives (engine order).
List<String> conversionCandidateTexts(List<TextCandidate> candidates) {
  final out = <String>[];
  for (final c in candidates) {
    if (out.length == kMaxLineAlternatives) break;
    final t = c.text.trim();
    if (t.isNotEmpty && !out.contains(t)) out.add(t);
  }
  return List.unmodifiable(out);
}

/// recog.toText ([copy] false) / recog.copyText with strokes ([copy] true):
/// opens the conversion sheet before the first await; completes when it
/// closes (text box → target.done(); copied → '복사했어요').
///
/// [linesOf] splits the inputs into lines (conversionLinesOf; the text pen
/// passes its own split so the sheet shows the bubble's lines).
Future<void> openConversion(
  ActionRun run, {
  required List<core.Stroke> inputs,
  required bool copy,
  List<ConversionLineInput> Function(List<core.Stroke> inputs) linesOf =
      conversionLinesOf,
}) async {
  final scope = run.scope;
  final engine = scope.handwriting;
  final downloads = scope.container.read(modelDownloadsProvider);
  final all = linesOf(inputs);
  final lines = all.take(kMaxConversionLines).toList();
  final shownIds = {
    for (final l in lines)
      for (final s in l.strokes) s.id,
  };
  // Every input stroke when nothing was cut (a pointless stroke goes too);
  // otherwise only the strokes of the lines in the sheet.
  final replaced = all.length > lines.length
      ? [
          for (final s in inputs)
            if (shownIds.contains(s.id)) s,
        ]
      : inputs;
  // (text pen track) while the sheet is open the indexer yields: its lines
  // go to the shared engine before any queued indexer line.
  final release = scope.container.read(recognitionPriorityProvider).hold();
  final ConversionOutcome? outcome;
  try {
    outcome = await showRecognitionSheet<ConversionOutcome>(
      run.context,
      sheetKey: kConversionSheetKey,
      builder: (_) => ConversionSheet(
        run: run,
        engine: engine,
        downloads: downloads,
        lines: lines,
        moreLines: all.length - lines.length,
        replaced: replaced,
        copy: copy,
      ),
    );
  } finally {
    release();
  }
  switch (outcome) {
    case ConversionOutcome.textBox:
      if (run.mounted) run.target.done();
    case ConversionOutcome.copied:
      run.showSnackBar(RecognitionStrings.copied);
    case null:
      break;
  }
}

enum _Phase {
  /// recog.language / modelState not known yet.
  starting,
  recognizing,
  ready,
  needsModel,
  failed,

  /// No engine (or the model is unsupported).
  unavailable,

  /// No line (every input stroke without points).
  noLines,
}

final class _Line {
  _Line(this.input);

  final ConversionLineInput input;
  final TextEditingController controller = TextEditingController();

  /// Candidate texts per language (engine order, distinct, ≤ 5).
  final Map<String, List<String>> byLang = {};

  /// The language whose candidates the field / chips show.
  String? shownLang;

  /// Edited or a chip picked — keeps its text across language changes.
  bool touched = false;
  String lastText = '';

  List<String> get candidates => byLang[shownLang] ?? const [];

  String get text => controller.text.trim();
}

class ConversionSheet extends StatefulWidget {
  const ConversionSheet({
    super.key,
    required this.run,
    required this.engine,
    required this.downloads,
    required this.lines,
    required this.moreLines,
    required this.replaced,
    required this.copy,
  });

  final ActionRun run;
  final HandwritingRecognizer engine;
  final ModelDownloads downloads;
  final List<ConversionLineInput> lines;

  /// Lines left out (more than [kMaxConversionLines]).
  final int moreLines;

  /// The strokes [텍스트 상자로] removes.
  final List<core.Stroke> replaced;

  /// recog.copyText: [복사] is the primary and there is no text box.
  final bool copy;

  @override
  State<ConversionSheet> createState() => _ConversionSheetState();
}

class _ConversionSheetState extends State<ConversionSheet> {
  late final List<_Line> _lines = [
    for (final input in widget.lines) _Line(input),
  ];
  _Phase _phase = _Phase.starting;
  String _lang = kRecognitionLanguages.first;
  bool _langPicked = false;
  int _generation = 0;
  (int, int)? _progress;
  bool _busy = false;
  bool _programmatic = false;
  ({String text, SheetNoticeKind kind})? _notice;
  StreamSubscription<String>? _modelChanges;

  HandwritingRecognizer get _engine => widget.engine;

  @override
  void initState() {
    super.initState();
    for (final line in _lines) {
      line.controller.addListener(() => _onEdited(line));
    }
    if (!_engine.isAvailable) {
      _phase = _Phase.unavailable;
      return;
    }
    if (_lines.isEmpty) {
      _phase = _Phase.noLines;
      return;
    }
    widget.downloads.addListener(_onModelEvent);
    if (_engine case final RecognizerModelAdmin admin) {
      _modelChanges = admin.modelChanges.listen((tag) {
        if (tag == _lang) _onModelEvent();
      });
    }
    unawaited(_start());
  }

  @override
  void dispose() {
    _generation++;
    widget.downloads.removeListener(_onModelEvent);
    unawaited(_modelChanges?.cancel()); // never awaited (fake_async)
    for (final line in _lines) {
      line.controller.dispose();
    }
    super.dispose();
  }

  void _set(VoidCallback change) {
    if (mounted) setState(change);
  }

  void _onEdited(_Line line) {
    final text = line.controller.text;
    if (text == line.lastText) return; // selection only
    line.lastText = text;
    if (!_programmatic) line.touched = true;
    _set(() {});
  }

  /// A value from the engine or a chip — not the user's typing.
  void _setText(_Line line, String text) {
    _programmatic = true;
    try {
      line.controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    } finally {
      _programmatic = false;
    }
  }

  void _show(_Line line, String lang) {
    line.shownLang = lang;
    final first = line.byLang[lang];
    _setText(line, first == null || first.isEmpty ? '' : first.first);
  }

  // --- recognition ------------------------------------------------------------

  Future<void> _start() async {
    String lang;
    try {
      lang = recognitionLanguageOf(
        await widget.run.scope.settings.get(RecognitionSettingsKeys.language),
      );
    } catch (e, s) {
      reportRecognitionError(e, s, 'reading recog.language');
      lang = kRecognitionLanguages.first;
    }
    if (!mounted) return;
    if (!_langPicked) _lang = lang;
    await _recognize();
  }

  /// The untouched lines without an answer in the sheet's language, one
  /// after another. A newer call (language change, retry) ends this one.
  Future<void> _recognize() async {
    final generation = ++_generation;
    final lang = _lang;
    bool current() => mounted && generation == _generation;
    _set(() {
      _phase = _Phase.starting;
      _progress = null;
    });
    try {
      final state = await _engine.modelState(lang);
      if (!current()) return;
      switch (state) {
        case RecognitionModelState.unsupported:
          _set(() => _phase = _Phase.unavailable);
          return;
        case RecognitionModelState.notDownloaded ||
            RecognitionModelState.downloading:
          _set(() => _phase = _Phase.needsModel);
          return;
        case RecognitionModelState.ready:
          break;
      }
      for (final line in _lines) {
        if (!line.touched && line.byLang.containsKey(lang)) _show(line, lang);
      }
      _set(() {}); // the cached answers
      final todo = [
        for (final (i, line) in _lines.indexed)
          if (!line.touched && !line.byLang.containsKey(lang)) i,
      ];
      for (final (k, i) in todo.indexed) {
        _set(() {
          _phase = _Phase.recognizing;
          _progress = (k + 1, todo.length);
        });
        final line = _lines[i];
        final candidates = await _engine.recognizeLine(
          _inputOf(i),
          languageTag: lang,
        );
        line.byLang[lang] = _textsOf(candidates);
        if (!current()) return;
        if (!line.touched) _show(line, lang);
        _set(() {});
      }
      _set(() {
        _phase = _Phase.ready;
        _progress = null;
      });
    } on ModelNotReady {
      if (current()) _set(() => _phase = _Phase.needsModel);
    } on RecognizerUnsupported {
      if (current()) _set(() => _phase = _Phase.unavailable);
    } on RecognitionFailure {
      if (current()) _set(() => _phase = _Phase.failed); // expected (6.22)
    } catch (e, s) {
      reportRecognitionError(e, s, 'recognizing handwriting lines');
      if (current()) _set(() => _phase = _Phase.failed);
    }
  }

  HandwritingLineInput _inputOf(int i) => conversionLineInput(
    _lines[i].input,
    previousText: i == 0 ? '' : _lines[i - 1].text,
    pageWidth: widget.run.target.pageSize.width,
  );

  static List<String> _textsOf(List<TextCandidate> candidates) =>
      conversionCandidateTexts(candidates);

  /// A download ended / the engine's model changed: go on once it is ready.
  void _onModelEvent() {
    if (_phase == _Phase.needsModel) unawaited(_checkModel());
  }

  Future<void> _checkModel() async {
    final generation = _generation;
    final RecognitionModelState state;
    try {
      state = await _engine.modelState(_lang);
    } catch (e, s) {
      reportRecognitionError(e, s, 'handwriting model $_lang state');
      return;
    }
    if (!mounted || generation != _generation) return;
    if (_phase == _Phase.needsModel && state == RecognitionModelState.ready) {
      unawaited(_recognize());
    }
  }

  void _setLanguage(String tag) {
    if (tag == _lang || _busy) return;
    setState(() {
      _lang = tag;
      _langPicked = true;
      _notice = null;
    });
    unawaited(_recognize());
  }

  void _retry() => unawaited(_recognize());

  void _pick(_Line line, String text) {
    line.touched = true;
    _setText(line, text);
    _set(() {});
  }

  // --- primary / copy ---------------------------------------------------------

  String get _joined => joinLineTexts([for (final l in _lines) l.text]);

  bool get _settled =>
      _phase != _Phase.starting &&
      _phase != _Phase.recognizing &&
      _phase != _Phase.unavailable &&
      _phase != _Phase.noLines;

  bool get _canCopy => _settled && !_busy && _joined.isNotEmpty;

  bool get _tooLong => isTextTooLong(_joined);

  bool get _canTextBox => _canCopy && !_tooLong;

  void _copy() {
    if (!_canCopy) return;
    // Started synchronously inside onPressed (contract 7.2.10).
    final pending = Clipboard.setData(ClipboardData(text: _joined));
    final confirmed = [
      for (final line in _lines)
        if (line.text.isNotEmpty)
          core.HandwritingLine(
            text: line.text,
            alternatives: line.candidates,
            rect: line.input.rect,
            strokeIds: line.input.strokeIds,
            languageTag: _lang,
            userConfirmed: true,
          ),
    ];
    final lang = _lang;
    setState(() {
      _busy = true;
      _notice = null;
    });
    unawaited(_finishCopy(pending, confirmed, lang));
  }

  Future<void> _finishCopy(
    Future<void> pending,
    List<core.HandwritingLine> confirmed,
    String lang,
  ) async {
    var copied = true;
    try {
      await pending;
    } on PlatformException {
      copied = false;
    } on MissingPluginException {
      copied = false;
    }
    if (!copied) {
      _set(() {
        _busy = false;
        _notice = (
          text: RecognitionStrings.copyFailed,
          kind: SheetNoticeKind.error,
        );
      });
      return;
    }
    await _saveConfirmed(confirmed, lang);
    if (mounted) Navigator.of(context).pop(ConversionOutcome.copied);
  }

  /// 6.13.5 steps 2–4 — never throws (a failure is reported once).
  Future<void> _saveConfirmed(
    List<core.HandwritingLine> confirmed,
    String lang,
  ) async {
    if (confirmed.isEmpty) return;
    final scope = widget.run.scope;
    final target = widget.run.target;
    try {
      await scope.store.flush();
      final content = await scope.content.loadPage(target.pageId);
      final inputs = recognitionInputsOf(content.strokes);
      final rev = core.HandwritingText.sourceRevOf(inputs);
      final inputIds = {for (final s in inputs) s.id};
      final converted = {for (final l in confirmed) ...l.strokeIds};
      final all =
          converted.length == inputIds.length &&
          inputIds.containsAll(converted);
      final engineId = '${_engine.engineId}:$lang';
      final nowMs = scope.nowMs();
      await scope.handwritingRepo.update(
        target.pageId,
        (current) => mergeConfirmed(
          current,
          confirmed,
          noteId: target.noteId,
          pageId: target.pageId,
          rev: rev,
          all: all,
          engineId: engineId,
          nowMs: nowMs,
        ),
      );
    } on core.EntityNotFoundException {
      return; // the page went meanwhile — nothing to confirm
    } catch (e, s) {
      reportRecognitionError(e, s, 'saving the confirmed lines');
    }
  }

  Future<void> _toTextBox() async {
    if (!_canTextBox) return;
    final run = widget.run;
    final text = _joined;
    setState(() {
      _busy = true;
      _notice = null;
    });
    String? notice;
    try {
      final box = await buildTextBox(
        id: run.scope.newId(),
        pageId: run.target.pageId,
        nowMs: run.scope.nowMs(),
        text: text,
        inputStrokes: widget.replaced,
        boundsPt: run.target.areaPt,
        pageSize: run.target.pageSize,
      );
      if (!mounted) return;
      run.execute(
        replaceStrokesCommand(
          pageId: run.target.pageId,
          strokes: widget.replaced,
          object: box,
          label: kToTextLabel,
        ),
      );
    } on core.ReadOnlyNoteException {
      notice = RecognitionStrings.readOnly; // expected (6.22)
    } catch (e, s) {
      reportRecognitionError(e, s, 'in the conversion sheet');
      notice = RecognitionStrings.runFailed;
    }
    if (!mounted) return;
    if (notice == null) {
      Navigator.of(context).pop(ConversionOutcome.textBox);
    } else {
      setState(() {
        _busy = false;
        _notice = (text: notice!, kind: SheetNoticeKind.error);
      });
    }
  }

  // --- build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final closed = _phase == _Phase.unavailable || _phase == _Phase.noLines;
    final copy = widget.copy;
    final notice = _notice;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecognitionSheetHeader(
          title: copy ? RecognitionStrings.copyText : RecognitionStrings.toText,
          cancelLabel: closed
              ? RecognitionStrings.close
              : RecognitionStrings.cancel,
          onCancel: () => Navigator.of(context).pop(),
          primaryLabel: closed
              ? null
              : copy
              ? RecognitionStrings.copy
              : RecognitionStrings.toTextBox,
          onPrimary: copy
              ? (_canCopy ? _copy : null)
              : (_canTextBox ? () => unawaited(_toTextBox()) : null),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!closed) _languageRow(),
                ..._statusParts(),
                if (!closed)
                  for (final (i, line) in _lines.indexed) _lineCard(i, line),
                if (!closed && widget.moreLines > 0)
                  SheetNotice(
                    text: RecognitionStrings.tooManyLines(widget.moreLines),
                  ),
                if (!closed && !copy && _tooLong)
                  const SheetNotice(
                    text: RecognitionStrings.textTooLong,
                    kind: SheetNoticeKind.error,
                  ),
                if (notice != null)
                  SheetNotice(text: notice.text, kind: notice.kind),
                if (!closed && !copy)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      key: kSheetSecondaryKey,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(64, 44),
                      ),
                      onPressed: _canCopy ? _copy : null,
                      icon: const Icon(Icons.content_copy),
                      label: const Text(RecognitionStrings.copy),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _languageRow() => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        const Text(RecognitionStrings.conversionLanguage),
        const SizedBox(width: 12),
        SegmentedButton<String>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(64, 44)),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          segments: [
            for (final tag in kRecognitionLanguages)
              ButtonSegment<String>(
                value: tag,
                label: Text(
                  RecognitionStrings.languageLabel(tag),
                  key: conversionLanguageKey(tag),
                ),
              ),
          ],
          selected: {_lang},
          onSelectionChanged: _busy
              ? null
              : (selected) => _setLanguage(selected.single),
        ),
      ],
    ),
  );

  List<Widget> _statusParts() {
    final web = ConversionSheetDebug.isWeb ?? kIsWeb;
    return switch (_phase) {
      _Phase.unavailable => [
        SheetNotice(
          key: kConversionStatusKey,
          text: web
              ? RecognitionStrings.webUnsupported
              : RecognitionStrings.unsupported,
        ),
      ],
      _Phase.noLines => const [
        SheetNotice(key: kConversionStatusKey, text: RecognitionStrings.noInk),
      ],
      _Phase.starting => const [
        SheetNotice(
          key: kConversionStatusKey,
          text: RecognitionStrings.recognizing,
        ),
      ],
      _Phase.recognizing => [
        SheetNotice(
          key: kConversionStatusKey,
          text: switch (_progress) {
            (final i, final n) =>
              '${RecognitionStrings.recognizing} '
                  '${RecognitionStrings.lineProgress(i, n)}',
            null => RecognitionStrings.recognizing,
          },
        ),
      ],
      _Phase.failed => [
        SheetNotice(
          key: kConversionStatusKey,
          text: RecognitionStrings.recognizeFailed,
          kind: SheetNoticeKind.error,
          actionLabel: RecognitionStrings.retry,
          onAction: _busy ? null : _retry,
        ),
      ],
      _Phase.needsModel => [
        SheetNotice(
          key: kConversionStatusKey,
          text: RecognitionStrings.modelNeeded(
            RecognitionStrings.languageName(_lang),
          ),
        ),
        RecognitionModelRow(
          key: ValueKey('$kConversionModelKeyPrefix.card.$_lang'),
          languageTag: _lang,
          keyPrefix: kConversionModelKeyPrefix,
        ),
      ],
      _Phase.ready => const [],
    };
  }

  Widget _lineCard(int i, _Line line) {
    final scheme = Theme.of(context).colorScheme;
    final chips = [
      for (final c in line.candidates)
        if (c != line.text) c,
    ].take(kMaxLineChips).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  RecognitionStrings.lineLabel(i + 1),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              Expanded(
                child: TextField(
                  key: conversionLineKey(i),
                  controller: line.controller,
                  enabled: !_busy,
                  maxLines: 1,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          if (chips.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 44, top: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final (j, chip) in chips.indexed)
                    ActionChip(
                      key: conversionChipKey(i, j),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      label: Text(chip),
                      onPressed: _busy ? null : () => _pick(line, chip),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
