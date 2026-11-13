// lib/src/math_pen/math_pen.dart — (math pen, phase 1 —
// docs/plans/m5-7/research/math-pen-phase1.md 11.1) recog's side of the
// editor's 수식 펜. The editor owns the tool, the strokes, the grouping and
// the bubble's frame; recog recognizes the group (debounced, off the UI
// thread through the MathRecognizer port), builds the bubble's content and
// converts with ONE command. INFRA's app shell turns [RecognitionMathPen]
// into the editor's EditorMathPen (recognition_wiring.dart) — the same road
// as the selection / insert items; no package depends on the other.
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../actions/recognition_actions.dart';
import 'math_pen_session.dart';

/// What the editor gives the session (once per note screen — no `==`).
@immutable
final class RecognitionMathPenContext {
  const RecognitionMathPenContext({
    required this.noteId,
    required this.execute,
    required this.liveStrokes,
    required this.bodyContext,
  });
  final String noteId;

  /// ONE command (one undo step); throws like NoteSession.execute.
  final void Function(core.EditCommand command) execute;

  /// The current strokes [ids] of [pageId], or null when any is gone.
  final List<core.Stroke>? Function(String pageId, List<String> ids)
  liveStrokes;

  /// The editor body's context while it is mounted.
  final BuildContext? Function() bodyContext;
}

/// The per-note recognition session behind the math pen. A group is a
/// RecognitionTarget: its strokes (z order), areaPt = their point bounds,
/// execute = the editor's.
abstract interface class RecognitionMathPenSession {
  /// The group's strokes changed: recognition runs again after
  /// kMathPenRecognizeDelay. [reopenedFrom] — the formula the group was
  /// reopened from — answers for the strokes [reopenedStrokeIds] at once.
  void update(
    RecognitionTarget group, {
    core.MathObject? reopenedFrom,
    Set<String> reopenedStrokeIds,
  });

  /// A new contact: the timer stops, the request in flight is cancelled
  /// (only the newest answer counts).
  void interrupt();

  /// The group is gone (no conversion).
  void clear();

  /// Converts [group] with ONE execute; true when the formula was added.
  /// [interactive] (the bubble tap) may wait for the answer and open the
  /// LaTeX editor; otherwise only a usable answer converts (waiting at most
  /// kMathPenBackgroundTimeout for one in flight) and nothing opens.
  /// [stillWanted] (background only) is asked right before the execute:
  /// false → nothing converts. A background conversion never converts
  /// strokes over the ink limits (the formula would lose its handwriting);
  /// the bubble tap asks first.
  Future<bool> convert(
    RecognitionTarget group, {
    required bool interactive,
    bool Function()? stillWanted,
  });

  /// '고치기': the LaTeX editor (with the symbol row) on the one MathObject
  /// of [formula] — one UpdateObjects, its handwriting kept.
  Future<void> fix(RecognitionTarget formula);

  /// Fires when the bubble's content changes.
  Listenable get changes;

  /// The bubble's content; [onConvert] converts (the 'LaTeX로 입력' button).
  Widget buildBubble(
    BuildContext context,
    RecognitionTarget group,
    VoidCallback onConvert,
  );

  void dispose();
}

/// recog's math pen (one value; compares by identity).
@immutable
final class RecognitionMathPen {
  const RecognitionMathPen({required this.open});
  final RecognitionMathPenSession Function(RecognitionMathPenContext context)
  open;
}

/// The math pen with the app's engines (mathRecognizerProvider: on-device →
/// server → none).
RecognitionMathPen recognitionMathPen() =>
    const RecognitionMathPen(open: MathPenSession.new);
