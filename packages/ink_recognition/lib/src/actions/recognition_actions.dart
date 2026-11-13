// lib/src/actions/recognition_actions.dart — contract m5-7/00-overview 7.2.11
// (m5-7/05-library 4.4.4, 6.3, 6.13.6, 6.16).
//
// The editor actions INFRA wraps into EditorSelectionMenuItem /
// EditorInsertMenuItem (7.3.3), in the 4.4.4 order: recog.toText,
// recog.copyText, recog.toMath, recog.editMath / recog.mathPad.
//
// Every run (6.16):
// - captures, synchronously and before its first await, the provider
//   container (RecognitionActionScope.of — one ProviderScope.containerOf),
//   the ScaffoldMessenger and the Navigator (ActionRun.capture, 6.3); a direct
//   copy also STARTS Clipboard.setData there (contract 7.2.10 — the browser's
//   user-activation rule);
// - never lets an exception out (G-1): ReadOnlyNoteException → '읽기 전용 …',
//   anything unexpected → reportRecognitionError once + '실행하지 못했어요';
//   snack bars only while the editor body is mounted;
// - calls execute at most once (one undo step).
// isVisible reads only the target (one pass over the strokes, no provider)
// and never hides an action because no engine is available (7.4.2).
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../common/report_error.dart';
import '../l10n/recognition_strings.dart';
import '../ui/recognition_sheets.dart';
import 'action_scope.dart';
import 'object_builders.dart';

@immutable
final class RecognitionTarget {
  // same fields as EditorSelectionContext / EditorInsertContext
  const RecognitionTarget({
    required this.noteId,
    required this.pageId,
    required this.pageSize,
    this.strokes = const [],
    this.objects = const [],
    required this.areaPt,
    required this.execute,
    required this.done,
  });

  final String noteId, pageId;
  final core.PageSize pageSize;
  final List<core.Stroke> strokes;
  final List<core.PageObject> objects;

  /// selection bounds or visible rect
  final Rect areaPt;
  final void Function(core.EditCommand command) execute;

  /// clearSelection / selectObject wrapper
  final VoidCallback done;
}

@immutable
final class RecognitionAction {
  const RecognitionAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.run,
    this.isVisible,
    this.pinned = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final Future<void> Function(BuildContext context, RecognitionTarget target)
  run;

  /// (v2.1, CP-L5) Called on every menu build: cheap, reads no provider; never hides just because
  /// no engine is available (7.4.2 '보이되 안내').
  final bool Function(RecognitionTarget target)? isVisible;

  /// (text pen track) Always on the selection bar, before '⋯' (recog.toText:
  /// the way to turn handwriting into text must not hide behind ⋯).
  final bool pinned;
}

/// (v2.1, CP-L6) recog.copyText: strokes → recognized text (copy button in the sheet); no strokes
/// and one MathObject → its LaTeX, one TextBoxObject → its text (copied before the first await —
/// 7.2.10 rule).
// recog.toText, recog.copyText, recog.toMath, recog.editMath
List<RecognitionAction> recognitionSelectionActions() =>
    buildSelectionActions();

// recog.mathPad
List<RecognitionAction> recognitionInsertActions() => buildInsertActions();

/// (internal) Action ids (4.4.4 — INFRA S2-3 keeps this order).
abstract final class RecognitionActionIds {
  static const String toText = 'recog.toText';
  static const String copyText = 'recog.copyText';
  static const String toMath = 'recog.toMath';
  static const String editMath = 'recog.editMath';
  static const String mathPad = 'recog.mathPad';
}

/// (internal) The selection list with [sheets] (tests pass a recording fake).
List<RecognitionAction> buildSelectionActions({
  RecognitionSheets sheets = const DefaultRecognitionSheets(),
}) => [
  RecognitionAction(
    id: RecognitionActionIds.toText,
    label: RecognitionStrings.toText,
    icon: Icons.short_text,
    isVisible: hasRecognitionInk,
    pinned: true,
    run: (context, target) => runRecognitionAction(
      RecognitionActionIds.toText,
      context,
      target,
      (run) => _convert(run, sheets, copy: false),
    ),
  ),
  RecognitionAction(
    id: RecognitionActionIds.copyText,
    label: RecognitionStrings.copyText,
    icon: Icons.content_copy,
    isVisible: canCopyText,
    run: (context, target) => runRecognitionAction(
      RecognitionActionIds.copyText,
      context,
      target,
      (run) => _copyText(run, sheets),
    ),
  ),
  RecognitionAction(
    id: RecognitionActionIds.toMath,
    label: RecognitionStrings.toMath,
    icon: Icons.functions,
    isVisible: hasRecognitionInk,
    run: (context, target) => runRecognitionAction(
      RecognitionActionIds.toMath,
      context,
      target,
      (run) => _toMath(run, sheets),
    ),
  ),
  RecognitionAction(
    id: RecognitionActionIds.editMath,
    label: RecognitionStrings.editMath,
    icon: Icons.edit_note,
    isVisible: (target) => soleMathOf(target) != null,
    run: (context, target) => runRecognitionAction(
      RecognitionActionIds.editMath,
      context,
      target,
      (run) => _editMath(run, sheets),
    ),
  ),
];

/// (internal) The insert list with [sheets]. Insert items have no
/// visibility hook (01-infra Q10).
List<RecognitionAction> buildInsertActions({
  RecognitionSheets sheets = const DefaultRecognitionSheets(),
}) => [
  RecognitionAction(
    id: RecognitionActionIds.mathPad,
    label: RecognitionStrings.mathPad,
    icon: Icons.functions,
    run: (context, target) => runRecognitionAction(
      RecognitionActionIds.mathPad,
      context,
      target,
      sheets.mathPad,
    ),
  ),
];

// --- visibility (4.4.4 — the target only, O(strokes)) ---

/// recog.toText / recog.toMath: at least one recognition input stroke.
bool hasRecognitionInk(RecognitionTarget target) =>
    target.strokes.any(core.HandwritingText.isRecognitionInput);

/// The selection's only element when it is one object and no stroke.
core.PageObject? soleObjectOf(RecognitionTarget target) =>
    target.strokes.isEmpty && target.objects.length == 1
    ? target.objects.single
    : null;

/// recog.editMath: no strokes and one MathObject.
core.MathObject? soleMathOf(RecognitionTarget target) =>
    switch (soleObjectOf(target)) {
      final core.MathObject m => m,
      _ => null,
    };

/// recog.copyText: ink, or no strokes and one MathObject / TextBoxObject.
bool canCopyText(RecognitionTarget target) =>
    hasRecognitionInk(target) ||
    switch (soleObjectOf(target)) {
      core.MathObject() || core.TextBoxObject() => true,
      _ => false,
    };

// --- the run guard (6.3, 6.16) ---

/// (internal) Runs [body] for action [id]: captures the scope synchronously
/// (before any await), calls [body] synchronously, and turns every failure
/// into a report / a snack bar — the returned Future never fails.
Future<void> runRecognitionAction(
  String id,
  BuildContext context,
  RecognitionTarget target,
  Future<void> Function(ActionRun run) body,
) {
  final ActionRun run;
  try {
    run = ActionRun.capture(id, context, target);
  } catch (e, s) {
    // No ProviderScope above the editor body: a wiring bug (report it).
    reportRecognitionError(e, s, 'while running $id');
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text(RecognitionStrings.runFailed)),
      );
    }
    return Future<void>.value();
  }
  return _guarded(run, body);
}

Future<void> _guarded(
  ActionRun run,
  Future<void> Function(ActionRun run) body,
) async {
  try {
    await body(run);
  } on core.ReadOnlyNoteException {
    run.showSnackBar(RecognitionStrings.readOnly); // expected (6.22)
  } catch (e, s) {
    reportRecognitionError(e, s, 'while running ${run.actionId}');
    run.showSnackBar(RecognitionStrings.runFailed);
  }
}

// --- the runs (6.16) ---

Future<void> _convert(
  ActionRun run,
  RecognitionSheets sheets, {
  required bool copy,
}) {
  final inputs = recognitionInputsOf(run.target.strokes);
  if (inputs.isEmpty) return _nothingToConvert(run);
  return sheets.conversion(run, inputs: inputs, copy: copy);
}

Future<void> _copyText(ActionRun run, RecognitionSheets sheets) {
  if (hasRecognitionInk(run.target)) {
    return _convert(run, sheets, copy: true);
  }
  return switch (soleObjectOf(run.target)) {
    final core.MathObject m => copyDirect(run, m.latex),
    final core.TextBoxObject t => copyDirect(run, t.text),
    _ => _nothingToConvert(run),
  };
}

Future<void> _toMath(ActionRun run, RecognitionSheets sheets) {
  final inputs = recognitionInputsOf(run.target.strokes);
  if (inputs.isEmpty) return _nothingToConvert(run);
  return sheets.toMath(run, inputs: inputs);
}

Future<void> _editMath(ActionRun run, RecognitionSheets sheets) {
  final math = soleMathOf(run.target);
  if (math == null) return Future<void>.value(); // isVisible is false
  return sheets.latexEditor(run, math);
}

/// Called although isVisible is false (only highlighter strokes …).
Future<void> _nothingToConvert(ActionRun run) {
  run.showSnackBar(RecognitionStrings.noInk);
  return Future<void>.value();
}

/// (internal) 6.13.6: [text] to the clipboard with no sheet —
/// Clipboard.setData STARTS here, synchronously (the caller is still inside
/// the user's press), then '복사했어요' / '복사하지 못했어요' (an expected
/// failure, not reported — 6.22). The selection stays (no done()).
Future<void> copyDirect(ActionRun run, String text) async {
  final pending = Clipboard.setData(ClipboardData(text: text));
  try {
    await pending;
  } on PlatformException {
    run.showSnackBar(RecognitionStrings.copyFailed);
    return;
  } on MissingPluginException {
    run.showSnackBar(RecognitionStrings.copyFailed);
    return;
  }
  run.showSnackBar(RecognitionStrings.copied);
}
