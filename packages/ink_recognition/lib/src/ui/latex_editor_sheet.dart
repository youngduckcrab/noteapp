// lib/src/ui/latex_editor_sheet.dart — (internal) m5-7/05-library 6.15
// (recog.editMath 6.15.1, recog.toMath 6.15.3), 6.12, 6.22.
//
// [취소] 수식 편집 / 수식으로 변환 [적용 / 수식으로 바꾸기]
// (recog.toMath) status · consent card · read-only strokes view
// [ LaTeX field                         ]   ← error text under the field
// 엔진 제안: (…) (…)                          (recog.toMath)
//   preview (INK MathPreview — the last valid value, dimmed while invalid)
// [LaTeX 복사]
//
// - 150 ms after the last change InkMathRenderer.validate runs (6.15.2); the
//   primary is disabled while the text is invalid or not checked yet.
// - [LaTeX 복사] STARTS Clipboard.setData inside onPressed (synchronously —
//   the browser's user-activation rule, contract 7.2.10); the result is a
//   notice line ('복사했어요.' / '복사하지 못했어요.').
// - The primary's callback ([LatexEditorSheet.onPrimary]) returns null when
//   the sheet may close (popped with true), or a notice to show.
//   ReadOnlyNoteException → '읽기 전용 …' (the sheet stays open — copying
//   still works); anything unexpected → reported once + '실행하지 못했어요.'
//   (6.22).
// - recog.toMath ([LatexEditorSheet.recognition]): the sheet opens at once
//   with '인식 중…' and asks the engine for the chosen strokes (6.11.3 input,
//   cancelled when the sheet closes — 6.11.6). The answer fills the field and
//   its alternatives become chips; once the user edits the field answers are
//   chips only (6.14.4). No engine / before consent / a failure → the 6.14.5
//   text (consent card, '다시' on a failure) and a small read-only view of the
//   chosen strokes to help typing. The primary is disabled on an empty field.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../actions/action_scope.dart';
import '../actions/object_builders.dart';
import '../common/report_error.dart';
import '../l10n/recognition_strings.dart';
import '../math/math_png.dart';
import '../model/failures.dart';
import '../model/handwriting_trace.dart';
import '../model/math_types.dart';
import '../ports/math_recognizer.dart';
import '../settings/recognition_settings_keys.dart';
import 'math_pad_canvas.dart';
import 'math_pad_sheet.dart' show kMathPadMaxAlternatives;
import 'recognition_sheet.dart';

/// Appendix C sheet key + the sheet's own fields.
const ValueKey<String> kLatexSheetKey = ValueKey('recog.sheet.latex');
const ValueKey<String> kLatexFieldKey = ValueKey('recog.sheet.latexField');
const ValueKey<String> kLatexPreviewKey = ValueKey('recog.sheet.latexPreview');

/// recog.toMath's status line (not appendix C).
const ValueKey<String> kLatexStatusKey = ValueKey('recog.sheet.status');

/// recog.toMath's suggestion chip [i] (not appendix C).
ValueKey<String> latexChipKey(int i) => ValueKey('recog.sheet.latexChip.$i');

/// 6.15.2: validation runs this long after the last change.
const Duration kLatexValidateDelay = Duration(milliseconds: 150);

/// The preview's font size (logical px).
const double kLatexPreviewFontSize = 24;

/// recog.editMath (6.15.1): the LaTeX editor on [math]. [적용]: unchanged →
/// close only; changed → one UpdateObjects with the formula laid out again
/// at its font size (centre and rotation kept, engineId 'manual'). The
/// selection stays (no done()). Opens before the first await; completes when
/// the sheet closes.
Future<void> openLatexEditor(ActionRun run, core.MathObject math) =>
    showRecognitionSheet<bool>(
      run.context,
      sheetKey: kLatexSheetKey,
      builder: (_) => LatexEditorSheet(
        title: RecognitionStrings.editMath,
        primaryLabel: RecognitionStrings.apply,
        initialLatex: math.latex,
        onPrimary: (latex, _) => _applyEdit(run, math, latex),
      ),
    );

String? _applyEdit(ActionRun run, core.MathObject math, String latex) {
  final text = latex.trim();
  if (text == math.latex) return null; // unchanged: close only
  final edited = relayoutMath(math, latex: text, nowMs: run.scope.nowMs());
  if (edited == null) return RecognitionStrings.runFailed; // not laid out
  run.execute(updateObjectCommand(run.target.pageId, edited));
  return null;
}

/// recog.toMath (6.15.3): the LaTeX editor that first asks the math engine
/// for [inputs] (the selection's recognition input strokes). [수식으로
/// 바꾸기] → ONE CompositeCommand([RemoveElements(inputs), AddObjects([math])],
/// label 'recog-to-math') — size from the selection bounds (target.areaPt),
/// colour of most inputs, engineId of the answer ('manual' when the user
/// edited the field or no engine answered) → closes → target.done() (the
/// selection clears). Closing the sheet cancels the request. Everything the
/// run needs is read before the first await.
Future<void> openToMath(
  ActionRun run, {
  required List<core.Stroke> inputs,
}) async {
  final scope = run.scope;
  final target = run.target;
  final engine = scope.math;
  final renderer = engine.isAvailable ? scope.renderer : null;
  final settings = scope.settings;
  final area = target.areaPt;
  final viewPageId = '$kMathPadPagePrefix${scope.newId()}';
  final nowMs = scope.nowMs();
  final view = mathAreaPage(
    inputs,
    areaPt: area,
    pageId: viewPageId,
    noteId: target.noteId,
    nowMs: nowMs,
  );
  Future<MathInput> input() async {
    final png = await renderMathPng(
      renderer,
      inputs,
      areaPt: area,
      pageId: viewPageId,
      noteId: target.noteId,
      nowMs: nowMs,
    );
    return MathInput(
      traces: [for (final s in inputs) HandwritingTrace.fromStroke(s)],
      png: png?.png,
      pngPxPerPt: png?.pxPerPt,
    );
  }

  final converted = await showRecognitionSheet<bool>(
    run.context,
    sheetKey: kLatexSheetKey,
    builder: (_) => LatexEditorSheet(
      title: RecognitionStrings.toMath,
      primaryLabel: RecognitionStrings.toMathPrimary,
      initialLatex: '',
      recognition: LatexRecognition(
        engine: engine,
        input: input,
        strokesPage: view?.page,
        strokes: view?.strokes ?? const [],
        onAgreeToConsent: () =>
            settings.set(RecognitionSettingsKeys.mathConsent, true),
      ),
      onPrimary: (latex, engineId) =>
          _replaceWithMath(run, inputs, latex, engineId),
    ),
  );
  if (converted == true && run.mounted) target.done();
}

String? _replaceWithMath(
  ActionRun run,
  List<core.Stroke> inputs,
  String latex,
  String engineId,
) {
  final target = run.target;
  final math = buildMathFromStrokes(
    id: run.scope.newId(),
    pageId: target.pageId,
    nowMs: run.scope.nowMs(),
    latex: latex,
    engineId: engineId,
    inputStrokes: inputs,
    boundsPt: target.areaPt,
  );
  if (math == null) return RecognitionStrings.runFailed; // not laid out
  run.execute(
    replaceStrokesCommand(
      pageId: target.pageId,
      strokes: inputs,
      object: math,
      label: kToMathLabel,
    ),
  );
  return null;
}

/// What recog.toMath adds to the LaTeX editor (6.15.3).
final class LatexRecognition {
  const LatexRecognition({
    required this.engine,
    required this.input,
    this.strokesPage,
    this.strokes = const [],
    this.onAgreeToConsent,
  });

  final MathRecognizer engine;

  /// The engine input (traces + the PNG when there is a page renderer).
  final Future<MathInput> Function() input;

  /// The read-only strokes view's temporary page and strokes (math_png.dart
  /// mathAreaPage); null → no view.
  final core.Page? strokesPage;
  final List<core.Stroke> strokes;

  /// [동의하고 쓰기] (sets recog.mathConsent = true).
  final Future<void> Function()? onAgreeToConsent;
}

class LatexEditorSheet extends StatefulWidget {
  const LatexEditorSheet({
    super.key,
    required this.title,
    required this.primaryLabel,
    required this.initialLatex,
    required this.onPrimary,
    this.recognition,
  });

  final String title;
  final String primaryLabel;
  final String initialLatex;

  /// Runs on the primary press with the field's text and the engine id the
  /// formula keeps ('manual' unless the field holds an engine answer the
  /// user did not edit): null → the sheet closes; a string → shown as an
  /// error notice (the sheet stays).
  final String? Function(String latex, String engineId) onPrimary;

  /// recog.toMath: ask the engine first (null for recog.editMath).
  final LatexRecognition? recognition;

  @override
  State<LatexEditorSheet> createState() => _LatexEditorSheetState();
}

class _LatexEditorSheetState extends State<LatexEditorSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialLatex,
  )..addListener(_onChanged);
  final FocusNode _focus = FocusNode();
  Timer? _timer;
  String _checked = '';
  String _lastText = '';
  String? _error;
  String _preview = '';
  ({String text, SheetNoticeKind kind})? _notice;

  // recog.toMath (6.15.3)
  Completer<void>? _cancel;
  int _generation = 0;
  bool _recognizing = false;
  bool _needsConsent = false;
  bool _agreeing = false;
  bool _typeOnly = false;
  String? _engineError;
  MathResult? _result;
  List<String> _chips = const [];
  bool _manualEdited = false;
  bool _programmatic = false;

  @override
  void initState() {
    super.initState();
    _lastText = _controller.text;
    _validateNow();
    final recognition = widget.recognition;
    if (recognition != null && recognition.engine.isAvailable) {
      unawaited(_recognize());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cancelRequest();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _checking => _checked != _controller.text;

  void _onChanged() {
    final text = _controller.text;
    if (text != _lastText) {
      _lastText = text;
      if (!_programmatic) _manualEdited = text.trim().isNotEmpty;
    }
    if (!_checking) return; // selection-only change
    _timer?.cancel();
    _timer = Timer(kLatexValidateDelay, () {
      if (mounted) setState(_validateNow);
    });
    setState(() {}); // the primary is disabled until checked
  }

  void _validateNow() {
    _checked = _controller.text;
    final text = _checked.trim();
    _error = ink.InkMathRenderer.validate(text);
    if (_error == null) _preview = text;
  }

  // --- recog.toMath -----------------------------------------------------------

  void _cancelRequest() {
    _generation++;
    final cancel = _cancel;
    _cancel = null;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
  }

  /// One request for the chosen strokes. Sets its flags before the first
  /// await (initState calls it — no setState until then).
  Future<void> _recognize() async {
    final recognition = widget.recognition!;
    _cancelRequest();
    final generation = ++_generation;
    final cancel = Completer<void>();
    _cancel = cancel;
    _recognizing = true;
    _engineError = null;
    bool current() => mounted && generation == _generation;
    try {
      final input = await recognition.input();
      if (!current()) return;
      final result = await recognition.engine.recognize(
        input,
        cancel: cancel.future,
      );
      if (!current()) return;
      _apply(result);
    } on RecognizerConsentRequired {
      if (current()) setState(() => _needsConsent = true);
    } on RecognitionFailure catch (failure) {
      if (current()) {
        setState(() => _engineError = RecognitionStrings.mathFailure(failure));
      }
    } catch (e, s) {
      reportRecognitionError(e, s, 'recognizing the formula');
      if (current()) {
        setState(() => _engineError = RecognitionStrings.mathFailed);
      }
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
      if (current()) setState(() => _recognizing = false);
    }
  }

  void _apply(MathResult result) {
    final alternatives = <String>{
      for (final a in result.alternatives)
        if (a.trim().isNotEmpty && a != result.latex) a,
    }.take(kMathPadMaxAlternatives);
    setState(() {
      _result = result;
      if (_manualEdited) {
        _chips = List.unmodifiable({result.latex, ...alternatives});
      } else {
        _setField(result.latex);
        _chips = List.unmodifiable(alternatives);
      }
    });
  }

  /// A value from the engine or a chip — not the user's edit (6.14.4).
  void _setField(String value) {
    _programmatic = true;
    try {
      _controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    } finally {
      _programmatic = false;
    }
  }

  void _pickChip(String value) {
    _setField(value);
    setState(() => _manualEdited = false);
  }

  void _retry() {
    setState(() => _engineError = null);
    unawaited(_recognize());
  }

  Future<void> _agree() async {
    final agree = widget.recognition?.onAgreeToConsent;
    setState(() => _agreeing = true);
    try {
      await agree?.call();
    } catch (e, s) {
      reportRecognitionError(e, s, 'saving the math consent');
      if (mounted) {
        setState(() {
          _agreeing = false;
          _engineError = RecognitionStrings.runFailed;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _agreeing = false;
      _needsConsent = false;
    });
    unawaited(_recognize());
  }

  void _typeInstead() {
    setState(() {
      _typeOnly = true;
      _needsConsent = false;
    });
    _focus.requestFocus();
  }

  String get _engineId {
    final result = _result;
    return _manualEdited || result == null
        ? kManualMathEngineId
        : result.engineId;
  }

  // --- primary / copy -----------------------------------------------------------

  bool get _canPrimary =>
      !_checking &&
      _error == null &&
      (widget.recognition == null || _controller.text.trim().isNotEmpty);

  void _primary() {
    if (!_canPrimary) return;
    String? notice;
    try {
      notice = widget.onPrimary(_controller.text, _engineId);
    } on core.ReadOnlyNoteException {
      notice = RecognitionStrings.readOnly; // expected (6.22)
    } catch (e, s) {
      reportRecognitionError(e, s, 'in the LaTeX editor');
      notice = RecognitionStrings.runFailed;
    }
    if (!mounted) return;
    if (notice == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _notice = (text: notice!, kind: SheetNoticeKind.error));
    }
  }

  Future<void> _copy() async {
    // Started synchronously inside onPressed (7.2.10).
    final pending = Clipboard.setData(
      ClipboardData(text: _controller.text.trim()),
    );
    var text = RecognitionStrings.copied;
    var kind = SheetNoticeKind.info;
    try {
      await pending;
    } on PlatformException {
      (text, kind) = (RecognitionStrings.copyFailed, SheetNoticeKind.error);
    } on MissingPluginException {
      (text, kind) = (RecognitionStrings.copyFailed, SheetNoticeKind.error);
    }
    if (mounted) setState(() => _notice = (text: text, kind: kind));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final invalid = _error != null;
    final notice = _notice;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecognitionSheetHeader(
          title: widget.title,
          cancelLabel: RecognitionStrings.cancel,
          onCancel: () => Navigator.of(context).pop(false),
          primaryLabel: widget.primaryLabel,
          onPrimary: _canPrimary ? _primary : null,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ..._recognitionParts(),
                TextField(
                  key: kLatexFieldKey,
                  controller: _controller,
                  focusNode: _focus,
                  autocorrect: false,
                  enableSuggestions: false,
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    labelText: RecognitionStrings.latexField,
                    errorText: _checking ? null : _error,
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_chips.isNotEmpty) _chipRow(scheme),
                const SizedBox(height: 12),
                SizedBox(
                  height: 72,
                  child: Center(
                    child: Opacity(
                      opacity: invalid || _checking ? 0.4 : 1,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: MathPreviewBox(
                          latex: _preview,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
                if (notice != null)
                  SheetNotice(text: notice.text, kind: notice.kind),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    key: kSheetSecondaryKey,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(64, 44),
                    ),
                    onPressed: () => unawaited(_copy()),
                    icon: const Icon(Icons.content_copy),
                    label: const Text(RecognitionStrings.copyLatex),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// recog.toMath: the status / consent / strokes view above the field.
  List<Widget> _recognitionParts() {
    final recognition = widget.recognition;
    if (recognition == null) return const [];
    final available = recognition.engine.isAvailable;
    final error = _engineError;
    final page = recognition.strokesPage;
    final showStrokes =
        page != null &&
        (!available || _needsConsent || error != null || _typeOnly);
    return [
      if (!available)
        const SheetNotice(
          key: kLatexStatusKey,
          text: RecognitionStrings.manualOnly,
        )
      else if (_recognizing)
        const SheetNotice(
          key: kLatexStatusKey,
          text: RecognitionStrings.recognizing,
        )
      else if (error != null)
        SheetNotice(
          key: kLatexStatusKey,
          text: error,
          kind: SheetNoticeKind.error,
          actionLabel: RecognitionStrings.retry,
          onAction: _retry,
        ),
      if (_needsConsent) ...[
        ConsentCard(
          title: RecognitionStrings.consentTitle,
          body: RecognitionStrings.consentBody,
          agreeLabel: RecognitionStrings.consentAgree,
          manualLabel: RecognitionStrings.typeInstead,
          onAgree: _agreeing ? null : _agree,
          onManual: _typeInstead,
        ),
        const SizedBox(height: 8),
      ],
      if (showStrokes) ...[
        MathStrokesView(
          page: page,
          strokes: recognition.strokes,
          height: kMathStrokesViewHeight,
        ),
        const SizedBox(height: 8),
      ],
    ];
  }

  Widget _chipRow(ColorScheme scheme) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          RecognitionStrings.engineSuggestion,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        for (final (i, chip) in _chips.indexed)
          ActionChip(
            key: latexChipKey(i),
            materialTapTargetSize: MaterialTapTargetSize.padded,
            label: Text(chip, style: const TextStyle(fontFamily: 'monospace')),
            onPressed: () => _pickChip(chip),
          ),
      ],
    ),
  );
}

/// INK MathPreview (keyed for the tests); nothing for an empty formula.
class MathPreviewBox extends StatelessWidget {
  const MathPreviewBox({super.key, required this.latex, required this.color});

  final String latex;
  final Color color;

  @override
  Widget build(BuildContext context) => latex.isEmpty
      ? const SizedBox.shrink()
      : ink.MathPreview(
          key: kLatexPreviewKey,
          latex: latex,
          fontSize: kLatexPreviewFontSize,
          color: color,
        );
}
