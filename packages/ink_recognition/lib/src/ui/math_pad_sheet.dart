// lib/src/ui/math_pad_sheet.dart — (internal) m5-7/05-library 6.14
// (recog.mathPad), 6.11.5, 6.11.6, 6.12, 6.22.
//
// [취소]                 수식 입력                 [넣기]
// ┌ handwriting area (math_pad_canvas.dart) — 40% of the sheet, ≥ 140 px ┐
// │                       (consent card over it before G-3 consent)       │
// └──────────────────────────────────────────────────────────────────────┘
// [되돌리기] [지우개] [모두 지우기]            상태: 멈추면 인식해요 · 인식 중…
// LaTeX: [ \frac{a}{b}                        ]
// 엔진 제안: (\frac{a}{6}) (…)
// preview: INK MathPreview(latex, 24, onSurface)   (error under it)
//
// - No engine (isAvailable false — L2-14): no handwriting area, the
//   'LaTeX로 직접 입력해요' notice, the LaTeX field focused.
// - 6.14.3: a pen-up, an erase or an undo / clear (re)starts a 1 s timer; a
//   new contact stops it and cancels the request in flight (6.11.6 — only the
//   newest answer counts). When it fires: no strokes → the suggestions go;
//   otherwise MathInput(traces of the area's strokes, png when the app shell
//   has a page renderer — 6.11.3) → engine.recognize(input, cancel:).
// - 6.14.4: once the user edits the field (manualEdited), engine answers only
//   show as '엔진 제안' chips (the answer + up to 3 alternatives); a chip
//   puts its value in the field and clears manualEdited; an empty field
//   clears it too. A value the engine put in does not set it.
// - 6.14.5: RecognizerConsentRequired → the consent card over the area:
//   [동의하고 쓰기] sets recog.mathConsent = true and recognizes again;
//   [직접 입력] hides the area (typing only). Offline / quota / auth / engine
//   errors → their 6.11.4 text on the status line, the area stays (the next
//   pause tries again). RecognitionFailures are expected (not reported);
//   anything else is reported once + '수식을 인식하지 못했어요'.
// - [넣기] (6.14.6): disabled while the trimmed text is empty, invalid
//   (InkMathRenderer.validate) or longer than 4,000 characters → one
//   AddObjects (default MathStyle, centred in the insert context's visible
//   rect, inside the page; engineId 'manual' when the user edited the field
//   or no engine answered, else the answer's engineId) → the sheet closes →
//   target.done() (the insert context selects what was added — contract X30).
// - The temporary page's strokes are never written anywhere (6.14.2).
// - (P-C, 6.14.7 — L2-22) The fixture mode (MathPadSheet.fixture, opened
//   from settings › 인식 › 품질 실험 [수식 고정 자료 만들기] on every platform,
//   the web included): the same area, tools, field and preview; the area
//   always shows (whatever the engine) and nothing is recognized (no pause,
//   no request, no consent card — nothing leaves the device). The field is
//   the answer. [고정 자료 복사] (recog.pad.exportFixture — disabled with no
//   stroke or an unusable field) puts the 07-sync 6.9.1 line
//   (math_fixture_export.dart) on the clipboard, started synchronously in
//   the press; once copied the area and the field are emptied for the next
//   sample and the sheet says '고정 자료를 복사했어요. …'. No note, no store,
//   no RecognitionTarget (temporary page 'mathfixture_<id>'); outside the
//   editor, so the sheet may take 90% of the screen height (like the lab).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../actions/action_scope.dart';
import '../actions/object_builders.dart';
import '../common/report_error.dart';
import '../l10n/recognition_strings.dart';
import '../math/math_fixture_export.dart';
import '../math/math_png.dart';
import '../model/failures.dart';
import '../model/handwriting_trace.dart';
import '../model/math_types.dart';
import '../ports/math_recognizer.dart';
import '../settings/recognition_settings_keys.dart';
import 'math_pad_canvas.dart';
import 'recognition_sheet.dart';

/// Appendix C keys.
const ValueKey<String> kMathPadSheetKey = ValueKey('recog.sheet.mathPad');
const ValueKey<String> kMathPadLatexKey = ValueKey('recog.pad.latex');
const ValueKey<String> kMathPadPreviewKey = ValueKey('recog.pad.preview');

/// The pad's own keys (not appendix C).
const ValueKey<String> kMathPadUndoKey = ValueKey('recog.pad.undo');
const ValueKey<String> kMathPadEraserKey = ValueKey('recog.pad.eraser');
const ValueKey<String> kMathPadClearKey = ValueKey('recog.pad.clear');
const ValueKey<String> kMathPadStatusKey = ValueKey('recog.pad.status');

/// The fixture mode (6.14.7): [고정 자료 복사] (appendix C) and the sheet's
/// own key (not appendix C).
const ValueKey<String> kMathPadExportFixtureKey = ValueKey(
  'recog.pad.exportFixture',
);
const ValueKey<String> kMathFixtureSheetKey = ValueKey(
  'recog.sheet.mathFixture',
);

/// The fixture mode's line of the pad's strokes (as HandwritingTrace) and
/// the trimmed field (math_fixture_export.dart buildMathFixtureJson).
typedef MathFixtureJson = String Function(
  List<HandwritingTrace> traces,
  String expected,
);

/// The suggestion chip [i] (0 = the first shown).
ValueKey<String> mathPadChipKey(int i) => ValueKey('recog.pad.chip.$i');

/// The preview's font size (logical px — 6.14.1).
const double kMathPadPreviewFontSize = 24;

/// 6.14.3: the pause after which the area is recognized.
const Duration kMathPadPause = Duration(seconds: 1);

/// 6.14.4: alternatives shown next to the answer.
const int kMathPadMaxAlternatives = 3;

/// recog.mathPad: opens the pad before the first await; when a formula was
/// inserted and the editor body is still mounted, calls target.done().
Future<void> openMathPad(ActionRun run) async {
  // read before the first await (6.3)
  final scope = run.scope;
  final engine = scope.math;
  final renderer = engine.isAvailable ? scope.renderer : null;
  final settings = scope.settings;
  final padPageId = '$kMathPadPagePrefix${scope.newId()}';
  final createdAt = scope.nowMs();
  final inserted = await showRecognitionSheet<bool>(
    run.context,
    sheetKey: kMathPadSheetKey,
    builder: (_) => MathPadSheet(
      engine: engine,
      padPageId: padPageId,
      noteId: run.target.noteId,
      createdAt: createdAt,
      renderer: renderer,
      onAgreeToConsent: () =>
          settings.set(RecognitionSettingsKeys.mathConsent, true),
      onInsert: (latex, engineId) => _insert(run, latex, engineId),
    ),
  );
  if (inserted == true && run.mounted) run.target.done();
}

/// Settings › 인식 › 품질 실험 [수식 고정 자료 만들기] (6.14.7): the pad in
/// its fixture mode, at most 90% of the screen height. Reads the clock and
/// the id generator of [context]'s ProviderScope.
Future<void> openMathFixturePad(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  final clock = container.read(core.clockProvider);
  final padPageId =
      '$kMathFixturePagePrefix${container.read(core.idGeneratorProvider).newId()}';
  final createdAt = clock.now().millisecondsSinceEpoch;
  final platform = mathFixturePlatform();
  return showRecognitionSheet<void>(
    context,
    sheetKey: kMathFixtureSheetKey,
    maxHeightFactor: kOutsideEditorSheetMaxHeightFactor,
    builder: (_) => MathPadSheet.fixture(
      padPageId: padPageId,
      createdAt: createdAt,
      fixtureJson: (traces, expected) => buildMathFixtureJson(
        traces,
        expected,
        now: clock.now(),
        platform: platform,
      ),
    ),
  );
}

String? _neverInserts(String latex, String engineId) =>
    RecognitionStrings.runFailed;

String? _insert(ActionRun run, String latex, String engineId) {
  final target = run.target;
  final math = buildInsertedMath(
    id: run.scope.newId(),
    pageId: target.pageId,
    nowMs: run.scope.nowMs(),
    latex: latex,
    engineId: engineId,
    areaPt: target.areaPt,
    pageSize: target.pageSize,
  );
  if (math == null) return RecognitionStrings.runFailed; // not laid out
  run.execute(addObjectCommand(target.pageId, math));
  return null;
}

class MathPadSheet extends StatefulWidget {
  const MathPadSheet({
    super.key,
    required this.engine,
    required this.onInsert,
    required this.padPageId,
    required this.noteId,
    required this.createdAt,
    this.renderer,
    this.onAgreeToConsent,
  }) : fixtureJson = null;

  /// The fixture mode (6.14.7): no engine, no insert — [고정 자료 복사]
  /// copies [fixtureJson] of the strokes and the field.
  const MathPadSheet.fixture({
    super.key,
    required this.padPageId,
    required this.createdAt,
    required MathFixtureJson this.fixtureJson,
  }) : engine = const ManualOnlyMathRecognizer(),
       onInsert = _neverInserts,
       noteId = kMathFixtureNoteId,
       renderer = null,
       onAgreeToConsent = null;

  final MathRecognizer engine;

  /// Runs on [넣기] with the field's text and the engine id the formula
  /// keeps: null → the sheet closes (popped with true); a string → shown as
  /// an error notice (the sheet stays).
  final String? Function(String latex, String engineId) onInsert;

  /// The temporary page of the handwriting area (`mathpad_<id>` — never
  /// stored) and the note it pretends to belong to.
  final String padPageId;
  final String noteId;
  final core.EpochMillis createdAt;

  /// pageThumbnailRendererProvider's value (null → no PNG, 6.11.3).
  final core.PageThumbnailRenderer? renderer;

  /// [동의하고 쓰기] (sets recog.mathConsent = true).
  final Future<void> Function()? onAgreeToConsent;

  /// Non-null → the fixture mode (6.14.7).
  final MathFixtureJson? fixtureJson;

  @override
  State<MathPadSheet> createState() => _MathPadSheetState();
}

class _MathPadSheetState extends State<MathPadSheet> {
  final TextEditingController _latex = TextEditingController();
  final FocusNode _focus = FocusNode();
  final MathPadInk _ink = MathPadInk();
  String? _previewError;
  String? _notice;
  SheetNoticeKind _noticeKind = SheetNoticeKind.error;
  String _lastText = '';

  // engine path (6.14.3–6.14.5)
  Timer? _pause;
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

  bool get _fixture => widget.fixtureJson != null;

  bool get _handwriting =>
      _fixture || (widget.engine.isAvailable && !_typeOnly);

  @override
  void initState() {
    super.initState();
    _latex.addListener(_onChanged);
    _ink.addListener(_onInk);
  }

  @override
  void dispose() {
    _stopPause();
    _cancelRequest(rebuild: false);
    _ink.dispose();
    _latex.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (_latex.text == _lastText) return; // selection-only change
    _lastText = _latex.text;
    if (!_programmatic) _manualEdited = _latex.text.trim().isNotEmpty;
    setState(() {
      _previewError = null;
      _notice = null;
    });
  }

  void _onInk() {
    if (mounted) setState(() {});
  }

  /// A value from the engine or a chip — not the user's edit (6.14.4).
  void _setField(String value) {
    _programmatic = true;
    try {
      _latex.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    } finally {
      _programmatic = false;
    }
  }

  // --- the pause and the request (6.14.3, 6.11.6) ---------------------------

  void _stopPause() {
    _pause?.cancel();
    _pause = null;
  }

  /// Ends the request in flight (its answer is dropped).
  void _cancelRequest({bool rebuild = true}) {
    _generation++;
    final cancel = _cancel;
    _cancel = null;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
    if (_recognizing) {
      _recognizing = false;
      if (rebuild && mounted) setState(() {});
    }
  }

  /// A pen (or finger) touched the area.
  void _onContact() {
    _stopPause();
    _cancelRequest();
  }

  /// The strokes changed (pen-up, erase, undo, clear): wait 1 s again (not
  /// in the fixture mode — it never recognizes).
  void _onEdited() {
    _stopPause();
    _cancelRequest();
    if (_fixture) return;
    _pause = Timer(kMathPadPause, _recognize);
  }

  Future<void> _recognize() async {
    _pause = null;
    if (!mounted || !_handwriting || _fixture) return;
    final strokes = _ink.strokes;
    if (strokes.isEmpty) {
      setState(() {
        _chips = const [];
        _engineError = null;
      });
      return;
    }
    final generation = ++_generation;
    final cancel = Completer<void>();
    _cancel = cancel;
    setState(() {
      _recognizing = true;
      _engineError = null;
    });
    bool current() => mounted && generation == _generation;
    try {
      MathPng? png;
      final renderer = widget.renderer;
      if (renderer != null) {
        png = await renderMathPng(
          renderer,
          strokes,
          areaPt: strokesAreaPt(strokes)!,
          pageId: widget.padPageId,
          noteId: widget.noteId,
          nowMs: widget.createdAt,
        );
        if (!current()) return;
      }
      final input = MathInput(
        traces: [for (final s in strokes) HandwritingTrace.fromStroke(s)],
        png: png?.png,
        pngPxPerPt: png?.pxPerPt,
      );
      final result = await widget.engine.recognize(
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
      reportRecognitionError(e, s, 'recognizing the math pad');
      if (current()) {
        setState(() => _engineError = RecognitionStrings.mathFailed);
      }
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
      if (current() && _recognizing) setState(() => _recognizing = false);
    }
  }

  void _apply(MathResult result) {
    final alternatives = <String>{
      for (final a in result.alternatives)
        if (a.trim().isNotEmpty && a != result.latex) a,
    }.take(kMathPadMaxAlternatives);
    setState(() {
      _result = result;
      _recognizing = false;
      if (_manualEdited) {
        _chips = List.unmodifiable({result.latex, ...alternatives});
      } else {
        _setField(result.latex);
        _chips = List.unmodifiable(alternatives);
      }
    });
  }

  void _pickChip(String value) {
    _setField(value);
    setState(() => _manualEdited = false);
  }

  Future<void> _agree() async {
    final agree = widget.onAgreeToConsent;
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
    _stopPause();
    _cancelRequest();
    unawaited(_recognize());
  }

  void _typeInstead() {
    _stopPause();
    _cancelRequest();
    setState(() {
      _typeOnly = true;
      _needsConsent = false;
    });
    _focus.requestFocus();
  }

  // --- tools ----------------------------------------------------------------

  void _undo() {
    if (_ink.undo()) _onEdited();
  }

  void _clear() {
    if (_ink.clear()) _onEdited();
  }

  void _toggleEraser() => _ink.erasing = !_ink.erasing;

  // --- insert (6.14.6) --------------------------------------------------------

  bool get _canInsert => usableLatex(_latex.text) != null;

  String get _engineId {
    final result = _result;
    return _manualEdited || result == null
        ? kManualMathEngineId
        : result.engineId;
  }

  void _onPreviewError(String message) {
    if (mounted) setState(() => _previewError = message);
  }

  void _insert() {
    if (!_canInsert) return;
    String? notice;
    try {
      notice = widget.onInsert(_latex.text, _engineId);
    } on core.ReadOnlyNoteException {
      notice = RecognitionStrings.readOnly; // expected (6.22)
    } catch (e, s) {
      reportRecognitionError(e, s, 'in the math pad');
      notice = RecognitionStrings.runFailed;
    }
    if (!mounted) return;
    if (notice == null) {
      Navigator.of(context).pop(true);
    } else {
      _setNotice(notice, SheetNoticeKind.error);
    }
  }

  void _setNotice(String text, SheetNoticeKind kind) {
    if (!mounted) return;
    setState(() {
      _notice = text;
      _noticeKind = kind;
    });
  }

  // --- the fixture mode (6.14.7) ----------------------------------------------

  bool get _canCopyFixture => !_ink.isEmpty && _canInsert;

  void _copyFixture() {
    final build = widget.fixtureJson;
    final expected = usableLatex(_latex.text);
    if (build == null || expected == null || _ink.isEmpty) return;
    final String json;
    try {
      json = build([
        for (final s in _ink.strokes) HandwritingTrace.fromStroke(s),
      ], expected);
    } on RecognitionFailure {
      // too large even thinned (math_payload.dart) — expected, not reported
      _setNotice(RecognitionStrings.copyFailed, SheetNoticeKind.error);
      return;
    } catch (e, s) {
      reportRecognitionError(e, s, 'building the math fixture');
      _setNotice(RecognitionStrings.copyFailed, SheetNoticeKind.error);
      return;
    }
    // Started synchronously inside onPressed (7.2.10 — the browser's user
    // activation).
    final pending = Clipboard.setData(ClipboardData(text: json));
    unawaited(
      pending.then<void>(
        (_) {
          if (!mounted) return;
          // empty for the next sample, then say so (an edit clears notices)
          _ink.clear();
          _latex.clear();
          _setNotice(
            RecognitionStrings.mathFixtureCopied,
            SheetNoticeKind.info,
          );
        },
        onError: (Object _) =>
            _setNotice(RecognitionStrings.copyFailed, SheetNoticeKind.error),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fixture = _fixture;
    final manualOnly = !fixture && !widget.engine.isAvailable;
    final handwriting = _handwriting;
    final text = _latex.text.trim();
    final notice = _notice;
    final previewError = _previewError;
    final canvasHeight = math.max(
      kMathPadCanvasMinHeight,
      MediaQuery.sizeOf(context).height *
          (fixture
              ? kOutsideEditorSheetMaxHeightFactor
              : kSheetMaxHeightFactor) *
          kMathPadCanvasHeightFactor,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fixture)
          RecognitionSheetHeader(
            title: RecognitionStrings.mathFixtureEntry,
            cancelLabel: RecognitionStrings.close,
            onCancel: () => Navigator.of(context).pop(),
            primaryLabel: RecognitionStrings.mathFixtureCopy,
            primaryKey: kMathPadExportFixtureKey,
            onPrimary: _canCopyFixture ? _copyFixture : null,
          )
        else
          RecognitionSheetHeader(
            title: RecognitionStrings.mathPadTitle,
            cancelLabel: RecognitionStrings.cancel,
            onCancel: () => Navigator.of(context).pop(false),
            primaryLabel: RecognitionStrings.insert,
            onPrimary: _canInsert ? _insert : null,
          ),
        if (handwriting) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Stack(
              children: [
                MathPadCanvas(
                  ink: _ink,
                  pageId: widget.padPageId,
                  noteId: widget.noteId,
                  createdAt: widget.createdAt,
                  height: canvasHeight,
                  onContact: _onContact,
                  onEdited: _onEdited,
                ),
                if (_needsConsent)
                  Positioned.fill(
                    child: ConsentCard(
                      title: RecognitionStrings.consentTitle,
                      body: RecognitionStrings.consentBody,
                      agreeLabel: RecognitionStrings.consentAgree,
                      manualLabel: RecognitionStrings.typeInstead,
                      onAgree: _agreeing ? null : _agree,
                      onManual: _typeInstead,
                    ),
                  ),
              ],
            ),
          ),
          _toolRow(scheme),
        ],
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (manualOnly)
                  const SheetNotice(text: RecognitionStrings.manualOnly),
                TextField(
                  key: kMathPadLatexKey,
                  controller: _latex,
                  focusNode: _focus,
                  autofocus: manualOnly,
                  autocorrect: false,
                  enableSuggestions: false,
                  minLines: 1,
                  maxLines: 3,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    labelText: RecognitionStrings.latexField,
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_chips.isNotEmpty) _chipRow(context),
                const SizedBox(height: 12),
                SizedBox(
                  height: 72,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: text.isEmpty
                          ? const SizedBox.shrink()
                          : ink.MathPreview(
                              key: kMathPadPreviewKey,
                              latex: text,
                              fontSize: kMathPadPreviewFontSize,
                              color: scheme.onSurface,
                              onError: _onPreviewError,
                            ),
                    ),
                  ),
                ),
                if (previewError != null && text.isNotEmpty)
                  Text(previewError, style: TextStyle(color: scheme.error)),
                if (notice != null)
                  SheetNotice(text: notice, kind: _noticeKind),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _toolRow(ColorScheme scheme) {
    final fixture = _fixture;
    final error = _engineError;
    final status =
        error ??
        RecognitionStrings.statusPrefix +
            (_recognizing
                ? RecognitionStrings.recognizing
                : RecognitionStrings.padPausePrompt);
    final hasInk = !_ink.isEmpty;
    const eraserIcon = Icon(Icons.auto_fix_normal);
    const eraserLabel = Text(RecognitionStrings.padEraser);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
      child: Row(
        children: [
          TextButton.icon(
            key: kMathPadUndoKey,
            style: kSheetMinTapStyle,
            onPressed: hasInk ? _undo : null,
            icon: const Icon(Icons.undo),
            label: const Text(RecognitionStrings.padUndo),
          ),
          if (_ink.erasing)
            FilledButton.tonalIcon(
              key: kMathPadEraserKey,
              style: kSheetMinTapStyle,
              onPressed: _toggleEraser,
              icon: eraserIcon,
              label: eraserLabel,
            )
          else
            TextButton.icon(
              key: kMathPadEraserKey,
              style: kSheetMinTapStyle,
              onPressed: _toggleEraser,
              icon: eraserIcon,
              label: eraserLabel,
            ),
          TextButton(
            key: kMathPadClearKey,
            style: kSheetMinTapStyle,
            onPressed: hasInk ? _clear : null,
            child: const Text(RecognitionStrings.padClear),
          ),
          const SizedBox(width: 8),
          if (fixture)
            const Spacer() // nothing is recognized: no status line
          else
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  status,
                  key: kMathPadStatusKey,
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: error != null
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chipRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
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
              key: mathPadChipKey(i),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              label: Text(
                chip,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              onPressed: () => _pickChip(chip),
            ),
        ],
      ),
    );
  }
}
