// lib/src/text_pen/text_pen.dart — (text pen, phase 1 — m5-7/05-library
// 6.24) recog's side of the editor's 텍스트 펜. The editor owns the tool, the
// strokes, the grouping and the bubble's frame; recog recognizes the group
// (debounced, line by line through the HandwritingRecognizer port — the
// conversion sheet's line rule), builds the bubble's content and converts
// with ONE command when the user taps the bubble. INFRA's app shell turns
// [RecognitionTextPen] into the editor's EditorTextPen
// (recognition_wiring.dart), like the math pen.
import 'package:material_ui/material_ui.dart';

import '../actions/recognition_actions.dart';
import '../math_pen/math_pen.dart';
import 'text_pen_session.dart';

/// What the editor gives the session (the math pen's context, shared).
typedef RecognitionPenContext = RecognitionMathPenContext;

/// The per-note recognition session behind the text pen. A group is a
/// RecognitionTarget: its strokes (z order), areaPt = their point bounds,
/// execute = the editor's. Nothing converts unless [convert] or [fix] runs.
abstract interface class RecognitionTextPenSession {
  /// The group's strokes changed: recognition runs again after
  /// kTextPenRecognizeDelay.
  void update(RecognitionTarget group);

  /// A new contact: the timer stops; only a newer answer counts.
  void interrupt();

  /// The group is gone (no conversion).
  void clear();

  /// The bubble tap: converts [group] into a text box with ONE execute
  /// (label 'recog-text-pen'); true when the box was added. Waits for the
  /// answer in flight; with no usable answer it opens the conversion sheet.
  Future<bool> convert(RecognitionTarget group);

  /// '고치기': the conversion sheet on [group]'s handwriting (per-line
  /// editing, candidates, the language); true when it made the text box.
  Future<bool> fix(RecognitionTarget group);

  /// Fires when the bubble's content changes.
  Listenable get changes;

  /// The bubble's content; [onConvert] converts, [onFix] opens the sheet.
  Widget buildBubble(
    BuildContext context,
    RecognitionTarget group,
    VoidCallback onConvert,
    VoidCallback onFix,
  );

  void dispose();
}

/// recog's text pen (one value; compares by identity).
@immutable
final class RecognitionTextPen {
  const RecognitionTextPen({required this.open});
  final RecognitionTextPenSession Function(RecognitionPenContext context) open;
}

/// The text pen with the app's handwriting engine
/// (handwritingRecognizerProvider — ML Kit on Android / iOS).
RecognitionTextPen recognitionTextPen() =>
    const RecognitionTextPen(open: TextPenSession.new);
