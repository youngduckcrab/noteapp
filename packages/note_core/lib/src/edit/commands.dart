// lib/src/edit/commands.dart — user intent. Resolved to an AppliedEdit (6.5).
// Contract 00-overview 7.2.7 / CORE 4.3. Change: StrokeEraseSession removed (INK
// EraserSession turns one gesture into one command). (v2.0) AddObjects, UpdateObjects,
// RemoveElements, ClearPage.includeObjects — 2nd-round contract 7.2.3 / 02-core 4.4, 6.4.
import '../common/geometry.dart';
import '../common/ids.dart';
import '../model/page_background.dart';
import '../model/page_size.dart';
import '../model/pen_style.dart';
import '../model/stroke.dart';
import 'page_draft.dart';

enum StrokeFilter { all, highlighterOnly, exceptHighlighter }

sealed class EditCommand {
  const EditCommand();
  String get label; // for debugging / developer overlay
}

final class AddStrokes extends EditCommand {
  const AddStrokes({required this.pageId, required this.strokes});
  final PageId pageId;
  final List<Stroke> strokes; // version must be null; pageId must match
  @override
  String get label => 'add-strokes';
}

final class RemoveStrokes extends EditCommand {
  // stroke eraser, lasso delete
  const RemoveStrokes({required this.pageId, required this.strokeIds});
  final PageId pageId;
  final List<ElementId> strokeIds;
  @override
  String get label => 'remove-strokes';
}

final class SplitStrokes extends EditCommand {
  // partial eraser (one gesture)
  const SplitStrokes({
    required this.pageId,
    required this.removedIds,
    required this.added,
  });
  final PageId pageId;
  final List<ElementId> removedIds;
  final List<Stroke> added; // fragments, created via Stroke.fragment
  @override
  String get label => 'split-strokes';
}

final class TransformElements extends EditCommand {
  // lasso move/scale/rotate
  const TransformElements({
    required this.pageId,
    required this.elementIds,
    required this.transform,
    this.scaleStrokeWidth = true,
  });
  final PageId pageId;
  final List<ElementId> elementIds;
  final Affine2 transform;
  final bool scaleStrokeWidth;
  @override
  String get label => 'transform';
}

final class RestyleStrokes extends EditCommand {
  // lasso color/width change
  const RestyleStrokes({
    required this.pageId,
    required this.strokeIds,
    required this.patch,
  });
  final PageId pageId;
  final List<ElementId> strokeIds;
  final StrokeStylePatch patch;
  @override
  String get label => 'restyle';
}

// (v2.0, 2nd-round contract 7.2.3) TransformElements({pageId, elementIds, transform,
//   scaleStrokeWidth = true}): strokes as v1.4 (Stroke.transformed(m, scaleWidth:) — (v2.1)
//   calligraphy nib angle turns with it, C2-38) AND objects via
//   PageObject.transformed(m, scaleWidth: scaleStrokeWidth) — the single rule (7.2.2).
// ClearPage({pageId, filter = StrokeFilter.all, includeObjects = false}) — 추가 (named, optional):
//   includeObjects removes every PageObject too (filter applies to strokes only).
// InsertPages / DuplicatePages: PageDraft.objects copied with new ids.
// DeletePages / note purge / note copy / backup: objects follow strokes (CORE 동작 계약).
final class ClearPage extends EditCommand {
  const ClearPage({
    required this.pageId,
    this.filter = StrokeFilter.all,
    this.includeObjects = false,
  });
  final PageId pageId;
  final StrokeFilter filter;
  final bool includeObjects;
  @override
  String get label => 'clear-page';
}

final class InsertPages extends EditCommand {
  const InsertPages({required this.drafts, required this.position});
  final List<PageDraft> drafts; // non-empty
  final PagePosition position;
  @override
  String get label => 'insert-pages';
}

final class DeletePages extends EditCommand {
  const DeletePages({required this.pageIds});
  final List<PageId> pageIds;
  @override
  String get label => 'delete-pages';
}

final class DuplicatePages extends EditCommand {
  // each copy right after its source
  const DuplicatePages({required this.pageIds});
  final List<PageId> pageIds;
  @override
  String get label => 'duplicate-pages';
}

final class MovePages extends EditCommand {
  const MovePages({required this.pageIds, required this.position});
  final List<PageId> pageIds; // keeps their relative order
  final PagePosition position;
  @override
  String get label => 'move-pages';
}

final class SetPageBackground extends EditCommand {
  const SetPageBackground({required this.pageIds, required this.background});
  final List<PageId> pageIds;
  final PageBackground background;
  @override
  String get label => 'set-background';
}

final class ResizePages extends EditCommand {
  // size / orientation
  const ResizePages({required this.pageIds, required this.size});
  final List<PageId> pageIds;
  final PageSize size;
  @override
  String get label => 'resize-pages';
}

// (v2.1, CP-1) new commands in the v1.4 command shape — const, named arguments, label.
// EditCommand is sealed; the only exhaustive switch is CORE's resolver.
/// objects: new ids, version == null, pageId == this.pageId. ≤ PageObjectLimits.maxObjectsPerPage.
final class AddObjects extends EditCommand {
  const AddObjects({required this.pageId, required this.objects});
  final PageId pageId;
  final List<PageObject> objects;
  @override
  String get label => 'add-objects';
}

/// Replace by id (same id, same type). UnknownObject or a missing id → ArgumentError before any
/// change. Only JSON keys whose value changed get a new field version (1차 7.2.10, C-11).
final class UpdateObjects extends EditCommand {
  const UpdateObjects({required this.pageId, required this.objects});
  final PageId pageId;
  final List<PageObject> objects;
  @override
  String get label => 'update-objects';
}

/// Removes strokes AND objects by id; unknown / already deleted / repeated ids ignored (like
/// RemoveStrokes). (v2.1) A List like every v1.4 id list (RemoveStrokes.strokeIds,
/// TransformElements.elementIds) — callers write [id], not {id}.
final class RemoveElements extends EditCommand {
  const RemoveElements({required this.pageId, required this.elementIds});
  final PageId pageId;
  final List<ElementId> elementIds;
  @override
  String get label => 'remove-elements';
}

final class CompositeCommand extends EditCommand {
  // e.g. paste = insert + add
  const CompositeCommand(this.commands, {this.label = 'composite'});
  final List<EditCommand> commands;
  @override
  final String label;
}
