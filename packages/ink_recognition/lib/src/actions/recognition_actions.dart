// lib/src/actions/recognition_actions.dart — contract m5-7/00-overview 7.2.11
// (m5-7/05-library 4.4.4, 6.16).
//
// The editor actions INFRA wraps into EditorSelectionMenuItem /
// EditorInsertMenuItem (7.3.3). 2차 foundation step R2-B6 (contract 7.6.2):
// both lists are empty; LIBRARY L2-12 fills them in the 4.4.4 order
// (recog.toText, recog.copyText, recog.toMath, recog.editMath / recog.mathPad).
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

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
  });

  final String id;
  final String label;
  final IconData icon;
  final Future<void> Function(BuildContext context, RecognitionTarget target)
  run;

  /// (v2.1, CP-L5) Called on every menu build: cheap, reads no provider; never hides just because
  /// no engine is available (7.4.2 '보이되 안내').
  final bool Function(RecognitionTarget target)? isVisible;
}

/// (v2.1, CP-L6) recog.copyText: strokes → recognized text (copy button in the sheet); no strokes
/// and one MathObject → its LaTeX, one TextBoxObject → its text (copied before the first await —
/// 7.2.10 rule).
// recog.toText, recog.copyText, recog.toMath, recog.editMath
// R2-B6: empty (L2-12).
List<RecognitionAction> recognitionSelectionActions() => const [];

// recog.mathPad — R2-B6: empty (L2-12).
List<RecognitionAction> recognitionInsertActions() => const [];
