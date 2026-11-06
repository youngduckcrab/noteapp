// lib/src/ui/latex_editor_sheet.dart — (internal) m5-7/05-library 6.15
// (recog.editMath; recog.toMath reuses the sheet in L2-17b), 6.12, 6.22.
//
// [취소] 수식 편집 [적용]
// [ LaTeX field                         ]   ← error text under the field
//   preview (INK MathPreview — the last valid value, dimmed while invalid)
// [LaTeX 복사]
//
// - 150 ms after the last change InkMathRenderer.validate runs (6.15.2); the
//   primary is disabled while the text is invalid or not checked yet.
// - [LaTeX 복사] STARTS Clipboard.setData inside onPressed (synchronously —
//   the browser's user-activation rule, contract 7.2.10); the result is a
//   notice line ('복사했어요.' / '복사하지 못했어요.').
// - The primary's callback ([LatexEditorSheet.onPrimary]) returns null when
//   the sheet may close, or a notice to show. ReadOnlyNoteException →
//   '읽기 전용 …' (the sheet stays open — copying still works); anything
//   unexpected → reported once + '실행하지 못했어요.' (6.22).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../actions/action_scope.dart';
import '../actions/object_builders.dart';
import '../common/report_error.dart';
import '../l10n/recognition_strings.dart';
import 'recognition_sheet.dart';

/// Appendix C sheet key + the sheet's own fields.
const ValueKey<String> kLatexSheetKey = ValueKey('recog.sheet.latex');
const ValueKey<String> kLatexFieldKey = ValueKey('recog.sheet.latexField');
const ValueKey<String> kLatexPreviewKey = ValueKey('recog.sheet.latexPreview');

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
    showRecognitionSheet<void>(
      run.context,
      sheetKey: kLatexSheetKey,
      builder: (_) => LatexEditorSheet(
        title: RecognitionStrings.editMath,
        primaryLabel: RecognitionStrings.apply,
        initialLatex: math.latex,
        onPrimary: (latex) => _applyEdit(run, math, latex),
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

class LatexEditorSheet extends StatefulWidget {
  const LatexEditorSheet({
    super.key,
    required this.title,
    required this.primaryLabel,
    required this.initialLatex,
    required this.onPrimary,
  });

  final String title;
  final String primaryLabel;
  final String initialLatex;

  /// Runs on the primary press with the field's text: null → the sheet
  /// closes; a string → shown as an error notice (the sheet stays).
  final String? Function(String latex) onPrimary;

  @override
  State<LatexEditorSheet> createState() => _LatexEditorSheetState();
}

class _LatexEditorSheetState extends State<LatexEditorSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialLatex,
  )..addListener(_onChanged);
  Timer? _timer;
  String _checked = '';
  String? _error;
  String _preview = '';
  ({String text, SheetNoticeKind kind})? _notice;

  @override
  void initState() {
    super.initState();
    _validateNow();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool get _checking => _checked != _controller.text;

  void _onChanged() {
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

  void _primary() {
    if (_checking || _error != null) return;
    String? notice;
    try {
      notice = widget.onPrimary(_controller.text);
    } on core.ReadOnlyNoteException {
      notice = RecognitionStrings.readOnly; // expected (6.22)
    } catch (e, s) {
      reportRecognitionError(e, s, 'in the LaTeX editor');
      notice = RecognitionStrings.runFailed;
    }
    if (!mounted) return;
    if (notice == null) {
      Navigator.of(context).pop();
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
          onCancel: () => Navigator.of(context).pop(),
          primaryLabel: widget.primaryLabel,
          onPrimary: _checking || invalid ? null : _primary,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: kLatexFieldKey,
                  controller: _controller,
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
