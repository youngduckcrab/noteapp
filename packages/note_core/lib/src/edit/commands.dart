// lib/src/edit/commands.dart — user intent. Resolved to an AppliedEdit (6.5).
// Contract 00-overview 7.2.7 / CORE 4.3. Change: StrokeEraseSession removed (INK
// EraserSession turns one gesture into one command).
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

final class ClearPage extends EditCommand {
  const ClearPage({required this.pageId, this.filter = StrokeFilter.all});
  final PageId pageId;
  final StrokeFilter filter;
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

final class CompositeCommand extends EditCommand {
  // e.g. paste = insert + add
  const CompositeCommand(this.commands, {this.label = 'composite'});
  final List<EditCommand> commands;
  @override
  final String label;
}
