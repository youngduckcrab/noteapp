// lib/src/ui/math_pad_sheet.dart — (internal) m5-7/05-library 6.14
// (recog.mathPad), 6.12, 6.22.
//
// [취소]                 수식 입력                 [넣기]
// (notice) 수식 인식 엔진이 연결되지 않아 LaTeX로 직접 입력해요.
// LaTeX: [ \frac{a}{b}                        ]
// preview: INK MathPreview(latex, 24, onSurface)   (error under it)
//
// L2-14 is the direct-input path (P-A): no engine (isAvailable false) → no
// handwriting area, the notice, the LaTeX field focused. The handwriting
// area, the 1 s pause recognition, the engine suggestions and the consent
// card are L2-17a; until then an available engine gets the same direct-input
// layout without the notice.
//
// [넣기] (6.14.6): disabled while the trimmed text is empty, invalid
// (InkMathRenderer.validate) or longer than 4,000 characters → one AddObjects
// (default MathStyle, centred in the insert context's visible rect, inside the
// page, engineId 'manual') → the sheet closes → target.done() (the insert
// context selects what was added — contract X30).
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../actions/action_scope.dart';
import '../actions/object_builders.dart';
import '../common/report_error.dart';
import '../l10n/recognition_strings.dart';
import '../ports/math_recognizer.dart';
import 'recognition_sheet.dart';

/// Appendix C keys.
const ValueKey<String> kMathPadSheetKey = ValueKey('recog.sheet.mathPad');
const ValueKey<String> kMathPadLatexKey = ValueKey('recog.pad.latex');
const ValueKey<String> kMathPadPreviewKey = ValueKey('recog.pad.preview');

/// The preview's font size (logical px — 6.14.1).
const double kMathPadPreviewFontSize = 24;

/// recog.mathPad: opens the pad before the first await; when a formula was
/// inserted and the editor body is still mounted, calls target.done().
Future<void> openMathPad(ActionRun run) async {
  final engine = run.scope.math; // read before the first await
  final inserted = await showRecognitionSheet<bool>(
    run.context,
    sheetKey: kMathPadSheetKey,
    builder: (_) =>
        MathPadSheet(engine: engine, onInsert: (latex) => _insert(run, latex)),
  );
  if (inserted == true && run.mounted) run.target.done();
}

String? _insert(ActionRun run, String latex) {
  final target = run.target;
  final math = buildInsertedMath(
    id: run.scope.newId(),
    pageId: target.pageId,
    nowMs: run.scope.nowMs(),
    latex: latex,
    engineId: kManualMathEngineId,
    areaPt: target.areaPt,
    pageSize: target.pageSize,
  );
  if (math == null) return RecognitionStrings.runFailed; // not laid out
  run.execute(addObjectCommand(target.pageId, math));
  return null;
}

class MathPadSheet extends StatefulWidget {
  const MathPadSheet({super.key, required this.engine, required this.onInsert});

  final MathRecognizer engine;

  /// Runs on [넣기] with the field's text: null → the sheet closes (popped
  /// with true); a string → shown as an error notice (the sheet stays).
  final String? Function(String latex) onInsert;

  @override
  State<MathPadSheet> createState() => _MathPadSheetState();
}

class _MathPadSheetState extends State<MathPadSheet> {
  final TextEditingController _latex = TextEditingController();
  String? _previewError;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _latex.addListener(_onChanged);
  }

  @override
  void dispose() {
    _latex.dispose();
    super.dispose();
  }

  String _lastText = '';

  void _onChanged() {
    if (_latex.text == _lastText) return; // selection-only change
    _lastText = _latex.text;
    setState(() {
      _previewError = null;
      _notice = null;
    });
  }

  bool get _canInsert => usableLatex(_latex.text) != null;

  void _onPreviewError(String message) {
    if (mounted) setState(() => _previewError = message);
  }

  void _insert() {
    if (!_canInsert) return;
    String? notice;
    try {
      notice = widget.onInsert(_latex.text);
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
      setState(() => _notice = notice);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final manualOnly = !widget.engine.isAvailable;
    final text = _latex.text.trim();
    final notice = _notice;
    final previewError = _previewError;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecognitionSheetHeader(
          title: RecognitionStrings.mathPadTitle,
          cancelLabel: RecognitionStrings.cancel,
          onCancel: () => Navigator.of(context).pop(false),
          primaryLabel: RecognitionStrings.insert,
          onPrimary: _canInsert ? _insert : null,
        ),
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
                  SheetNotice(text: notice, kind: SheetNoticeKind.error),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
