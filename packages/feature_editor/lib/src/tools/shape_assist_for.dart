// lib/src/tools/shape_assist_for.dart — m5-7/04-editor 6.10 (E2-15): the
// pen-down decision of the auto shape assist, one pure function (review M-1
// — the test seam; unit/shape_assist_for_test.dart compares the whole
// table). INK detects the hold, the fitter decides, EDITOR commits the
// resulting InkEdit(addShape) through the 1st-round commitInkEdit path.
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../state/settings/editor_settings.dart';

/// The pens that get the shape assist: not the highlighter (it has the
/// 1st-round straightening), the laser (never stored) or the tape (12.2 Q4);
/// (v2.11, C211-01) not the texture / decoration pens either — the snapped
/// ShapeObject is drawn with a plain outline and would lose the pen's look.
const Set<core.PenTool> _assistPens = {
  core.PenTool.ballpoint,
  core.PenTool.fountain,
  core.PenTool.pencil,
  core.PenTool.marker,
  core.PenTool.brush,
  core.PenTool.calligraphy,
  core.PenTool.dashed,
};

/// Whether [penType] can get the shape assist at all (the toggle rows show
/// only for these pens).
bool shapeAssistPen(core.PenTool penType) => _assistPens.contains(penType);

/// Whether a shape fitter is wired: ink_recognition's recognitionOverrides()
/// replaces INK's NoShapeFitter; a build without recognition keeps it (CD2-16)
/// — then the toggle rows are hidden and every stroke gets `off`.
bool shapeFitterAvailable(ink.InkShapeFitter fitter) =>
    fitter is! ink.NoShapeFitter;

/// 6.10: holdToSnap when the setting is on, a fitter is wired and [penType]
/// is one of the assist pens; else off. PenInteraction.start hands the value
/// to beginStroke(shapeAssist:).
ink.ShapeAssist shapeAssistFor(
  EditorSettings settings,
  core.PenTool penType,
  ink.InkShapeFitter fitter,
) =>
    settings.shapeAssist &&
        shapeFitterAvailable(fitter) &&
        shapeAssistPen(penType)
    ? ink.ShapeAssist.holdToSnap
    : ink.ShapeAssist.off;
