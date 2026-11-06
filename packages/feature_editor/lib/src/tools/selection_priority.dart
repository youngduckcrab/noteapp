// lib/src/tools/selection_priority.dart — m5-7/04-editor 6.6.2 (selection
// priority (a′), review M-4, Q8 answer) — E2-06.
//
// What a down does while a selection exists: the one pure rule
// InteractionHost.beginInteraction (6.3.6 step 5) and hitsSelection (the
// router's question for pen-only fingers) both use.
import 'selection.dart';
import 'tool_state.dart';

/// Where a down lands relative to the selection frame.
enum SelectionHitKind {
  /// a handle (corner, edge, rotation, vertex)
  handle,

  /// the frame inflated by SelectionHitTest.bodyInflate (8 px)
  body,

  /// anywhere else
  outside,
}

/// What the down does.
enum SelectionPriority {
  /// manipulate the selection by that handle (whatever the tool)
  handle,

  /// move the selection (after the 4 px move-start threshold)
  move,

  /// clear the selection and run the tool (a new stroke, shape, box, lasso)
  drop,
}

/// 6.6.2 table: a handle → [SelectionPriority.handle] for every tool; the
/// body → move with the lasso tool, or when the selection came from the
/// lasso, a paste or an insert (the user chose to handle these), else
/// (a shape just drawn, a tap with a drawing tool) drop; outside → drop.
SelectionPriority selectionPriority(
  SelectionOrigin origin,
  EditorTool tool,
  SelectionHitKind hit,
) => switch (hit) {
  SelectionHitKind.handle => SelectionPriority.handle,
  SelectionHitKind.outside => SelectionPriority.drop,
  SelectionHitKind.body =>
    tool == EditorTool.lasso || bodyMoves(origin)
        ? SelectionPriority.move
        : SelectionPriority.drop,
};

/// Whether a body drag moves a selection of [origin] with a drawing tool.
bool bodyMoves(SelectionOrigin origin) => switch (origin) {
  SelectionOrigin.lasso ||
  SelectionOrigin.paste ||
  SelectionOrigin.insert => true,
  SelectionOrigin.drawn || SelectionOrigin.tap => false,
};
