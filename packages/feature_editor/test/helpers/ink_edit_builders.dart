// test/helpers/ink_edit_builders.dart — m5-7/04-editor 5.5, 8.2 E2-00.
//
// INK has no fake (its controllers and sessions are final classes), so tests
// that need an edit the real R2-B3 INK does not produce yet build the
// InkEdit value here and commit it through the 1st-round commitInkEdit path
// (E2-09: the auto-shape commit — 5.1.2 '자동 도형 보정 확정').
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

/// What StrokeSession.end() returns when the auto-shape snap was taken
/// (contract 7.2.9): no stroke, one shape. toCommand() == AddObjects.
ink.InkEdit addShapeEdit(core.PageId pageId, core.ShapeObject shape) =>
    ink.InkEdit(
      kind: ink.InkEditKind.addShape,
      pageId: pageId,
      addedObjects: [shape],
    );

/// A stroke eraser edit that also removes shapes (7.2.9 (v2.1), U22):
/// removedIds holds every removed id, removedObjectIds the objects among them.
ink.InkEdit eraseStrokesEdit(
  core.PageId pageId, {
  Set<String> strokeIds = const {},
  Set<String> objectIds = const {},
}) => ink.InkEdit(
  kind: ink.InkEditKind.eraseStrokes,
  pageId: pageId,
  removedIds: {...strokeIds, ...objectIds},
  removedObjectIds: objectIds,
);
