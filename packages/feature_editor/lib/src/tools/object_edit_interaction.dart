// lib/src/tools/object_edit_interaction.dart — m5-7/04-editor 6.6.5 (E2-08):
// the edge, vertex and text width handles of a single object. Unlike the
// corners and the rotate handle (SelectionTransformInteraction → INK preview
// transform → TransformElements), these change the object's own geometry,
// so they preview an edited copy (controller.setPreviewObjects — same id,
// drawn in place of the original, I-3) and end in ONE core.UpdateObjects.
import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../commands/editor_commands.dart';
import '../input/input_sample.dart';
import '../input/input_targets.dart';
import '../viewport/viewport_controller.dart';
import 'object_resize.dart';
import 'selection_hit_test.dart';
import 'tool_interaction.dart';

/// Drags [handle] of [object] (the selection's single object on page
/// [pageId]): an edge → ObjectResize.resize (a text box's left / right →
/// resizeTextWidth with the height re-measured by
/// ink.InkTextLayout.measureSync — kept while the fonts are not loaded), a
/// vertex → ObjectResize.moveVertex (a line's / an arrow's angle snapped).
/// The delta is page pt from the down; every move sets
/// controller.setPreviewObjects([edited copy]).
///
/// The end (review S-1): first `session.pageIfLoaded(pageId)?.objectById(id)`
/// is checked synchronously — gone (a remote delete during the drag) → no
/// command, no notice, no report, the preview cleared. Otherwise, when the
/// copy differs from the object, EditorCommands.updateObjects (one step,
/// `_run`); the preview is cleared whether it was accepted or rejected (6.21
/// — a read-only race shows the 1st-round notice). [onSettled] runs after an
/// end (the host selects the same id again — or drops it when it is gone);
/// [onFinished] once at end or cancel. Cancel: the preview cleared, nothing
/// else.
final class ObjectEditInteraction extends ToolInteraction {
  ObjectEditInteraction._({
    required super.source,
    required super.startedAt,
    required this.controller,
    required this.pageId,
    required this.pageIndex,
    required this.object,
    required this.handle,
    required this._session,
    required this._viewport,
    required this._commands,
    required this._startPage,
    required this._onSettled,
    required this._onFinished,
    required Offset start,
  }) : _last = start;

  factory ObjectEditInteraction.start({
    required InputSample down,
    required InteractionSource source,
    required ink.InkPageController controller,
    required core.NoteSession session,
    required String pageId,
    required int pageIndex,
    required core.PageObject object,
    required FrameHandle handle,
    required ViewportController viewport,
    required EditorCommands commands,
    required void Function() onSettled,
    required void Function() onFinished,
  }) => ObjectEditInteraction._(
    source: source,
    startedAt: down.timeStamp,
    controller: controller,
    pageId: pageId,
    pageIndex: pageIndex,
    object: object,
    handle: handle,
    session: session,
    viewport: viewport,
    commands: commands,
    startPage: viewport.screenToPage(pageIndex, down.position),
    onSettled: onSettled,
    onFinished: onFinished,
    start: down.position,
  );

  /// Whether [handle] of [object] is dragged by this interaction (an edge or
  /// a vertex handle of a single object that is not unknown); corners and the
  /// rotate handle are SelectionTransformInteraction's.
  static bool handles(core.PageObject object, FrameHandle handle) {
    if (object is core.UnknownObject) return false;
    if (handle.isVertex) {
      return object is core.ShapeObject &&
          object.geometry is core.PolylineGeometry;
    }
    return handle.isEdge;
  }

  final ink.InkPageController controller;
  final String pageId;
  final int pageIndex;

  /// The object as it was at the down (the INK selection's — CORE's — copy).
  final core.PageObject object;
  final FrameHandle handle;
  final core.NoteSession _session;
  final ViewportController _viewport;
  final EditorCommands _commands;
  final Offset _startPage;
  final void Function() _onSettled;
  final void Function() _onFinished;
  Offset _last;
  double _travelled = 0;
  bool _done = false;

  /// The edited copy shown now (null before the first move).
  core.PageObject? _edited;

  @override
  double get travelled => _travelled;

  /// The edited copy previewed now, or null (tests).
  core.PageObject? get edited => _edited;

  void _update(Offset screen) {
    _travelled += (screen - _last).distance;
    _last = screen;
    final page = _viewport.screenToPage(pageIndex, screen);
    final edited = editedFor(page - _startPage);
    if (edited == null) return;
    _edited = edited;
    controller.setPreviewObjects([edited]);
  }

  /// [object] with [handle] dragged by [deltaPagePt], or null when the
  /// handle does not apply.
  core.PageObject? editedFor(Offset deltaPagePt) {
    final o = object;
    final vertex = handle.vertex;
    if (vertex != null) {
      return o is core.ShapeObject
          ? ObjectResize.moveVertex(o, vertex, deltaPagePt)
          : null;
    }
    final side = handle.resize;
    if (side == null) return null;
    if (o is core.TextBoxObject) {
      final wider = ObjectResize.resizeTextWidth(o, side, deltaPagePt);
      final size = ink.InkTextLayout.measureSync(
        wider.text,
        wider.style,
        widthPt: wider.frame.rect.width,
      );
      return size == null
          ? wider
          : ObjectResize.withMeasuredHeight(wider, size.height);
    }
    return ObjectResize.resize(o, side, deltaPagePt, keepAspect: false);
  }

  @override
  void move(InputSample sample) {
    if (_done) return;
    _update(sample.position);
  }

  @override
  void end(InputSample sample) {
    if (_done) return;
    _done = true;
    try {
      _update(sample.position);
      final edited = _edited;
      // (review S-1) checked synchronously before any command: a remote
      // delete during the drag ends it quietly.
      final current = _session.pageIfLoaded(pageId)?.objectById(object.id);
      if (edited != null && current != null && !_same(edited, object)) {
        _commands.updateObjects(pageId, [edited]);
      }
      controller.setPreviewObjects(const []);
      _onSettled();
    } finally {
      _onFinished();
    }
  }

  @override
  void cancel() {
    if (_done) return;
    _done = true;
    controller.setPreviewObjects(const []);
    _onFinished();
  }

  static bool _same(core.PageObject a, core.PageObject b) =>
      const DeepCollectionEquality().equals(a.toJson(), b.toJson());
}
