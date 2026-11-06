// lib/src/tools/selection.dart — 04-editor 6.6.5, 6.6.6; (v2) m5-7/04-editor
// 6.6.1 (elementIds = strokes AND objects, origin, vertexMode) and 6.6.7
// (revalidation by elementById) — E2-02. The selection rules that use them
// (priority (a′), mixed lasso, vertex editing) come in E2-06 / E2-08. (v2,
// E2-06) the frame as drawn (6.6.4): selectionFrameOnScreen. (E2-08) the
// handles of each single object kind (6.6.4 table), vertex mode and the
// image aspect unlock (6.6.5), the frame following an edge / vertex drag's
// preview copy.
import 'dart:async';
import 'dart:ui' show Offset, Rect;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../document/mounted_pages.dart';
import '../scope/editor_scope.dart';
import '../viewport/viewport_controller.dart';
import 'object_resize.dart';
import 'selection_hit_test.dart';
import 'tool_controller.dart';
import 'tool_state.dart';

/// (v2, review M-4) Where the selection came from — decides whether a body
/// drag moves it (6.6.2).
enum SelectionOrigin { lasso, paste, insert, drawn, tap }

/// EDITOR-side selection state (per note). Geometry lives in ink.InkSelection
/// (controller.selection); this only says which page/ids, where the selection
/// came from and whether a drag runs. The kind of each id (stroke / object)
/// is read from the INK selection when needed (sel.strokeIds, sel.objectIds).
@immutable
class EditorSelection {
  const EditorSelection({
    required this.pageId,
    required this.elementIds,
    this.origin = SelectionOrigin.lasso,
    this.isDragging = false,
    this.vertexMode = false,
    this.aspectUnlocked = false,
  });
  final String pageId;

  /// (v2) strokes AND objects (was strokeIds).
  final Set<String> elementIds;

  /// (v2) 6.6.3 table; kept by revalidation.
  final SelectionOrigin origin;
  final bool isDragging; // menu hidden while true

  /// (v2) single polyline shape: vertex handles shown (6.6.5).
  final bool vertexMode;

  /// (E2-08, 6.6.4) single image: '비율 고정 풀기' — the 4 edge handles
  /// shown (a free resize, UpdateObjects). Off again with a new selection.
  final bool aspectUnlocked;

  EditorSelection copyWith({
    Set<String>? elementIds,
    SelectionOrigin? origin,
    bool? isDragging,
    bool? vertexMode,
    bool? aspectUnlocked,
  }) => EditorSelection(
    pageId: pageId,
    elementIds: elementIds ?? this.elementIds,
    origin: origin ?? this.origin,
    isDragging: isDragging ?? this.isDragging,
    vertexMode: vertexMode ?? this.vertexMode,
    aspectUnlocked: aspectUnlocked ?? this.aspectUnlocked,
  );

  static const SetEquality<String> _ids = SetEquality<String>();

  @override
  bool operator ==(Object other) =>
      other is EditorSelection &&
      other.pageId == pageId &&
      other.origin == origin &&
      other.isDragging == isDragging &&
      other.vertexMode == vertexMode &&
      other.aspectUnlocked == aspectUnlocked &&
      _ids.equals(other.elementIds, elementIds);

  @override
  int get hashCode => Object.hash(
    pageId,
    origin,
    isDragging,
    vertexMode,
    aspectUnlocked,
    _ids.hash(elementIds),
  );

  @override
  String toString() =>
      'EditorSelection($pageId, $elementIds, ${origin.name}'
      '${isDragging ? ', dragging' : ''}${vertexMode ? ', vertices' : ''}'
      '${aspectUnlocked ? ', aspect unlocked' : ''})';
}

/// Per note (scoped). Mirrors controller.selection of the selected page.
///
/// Also cleared (6.6.6) when the tool changes to the pen or the eraser, when
/// the selected page leaves session.pagesStream (deleted) and when it is
/// unmounted (its INK controller, and with it the INK selection, is gone).
class EditorSelectionNotifier extends Notifier<EditorSelection?> {
  late MountedPages _pages;

  @override
  EditorSelection? build() {
    _pages = ref.watch(editorMountedPagesProvider);
    final session = ref.watch(editorSessionValueProvider);
    final pagesSub = session.pagesStream.listen((pages) {
      final s = state;
      if (s != null && !pages.any((p) => p.id == s.pageId)) clear();
    });
    void onMountsChanged() {
      final s = state;
      if (s != null && _pages[s.pageId] == null) state = null;
    }

    _pages.addListener(onMountsChanged);
    ref.listen(editorToolProvider.select((t) => t.activeTool), (_, tool) {
      if (tool != EditorTool.lasso) clear();
    });
    ref.onDispose(() {
      unawaited(pagesSub.cancel());
      _pages.removeListener(onMountsChanged);
    });
    return null;
  }

  ink.InkPageController? _controllerOf(String pageId) =>
      _pages[pageId]?.controller;

  /// controller.select(ids) and remember (pageId, the INK selection's
  /// allIds, [origin]). Empty ids → clear(). (E2-08) [vertexMode] and
  /// [aspectUnlocked] carry those modes over (the host re-selects the same
  /// ids after a handle drag) — kept only where they apply.
  void select(
    String pageId,
    Set<String> ids, {
    SelectionOrigin origin = SelectionOrigin.lasso,
    bool vertexMode = false,
    bool aspectUnlocked = false,
  }) {
    final old = state;
    if (old != null && old.pageId != pageId) {
      _controllerOf(old.pageId)?.clearSelection();
    }
    final controller = _controllerOf(pageId);
    if (ids.isEmpty || controller == null) {
      clear();
      return;
    }
    final selection = controller.select(ids);
    if (selection.isEmpty) {
      state = null;
      return;
    }
    final single = singleObjectOf(selection);
    state = EditorSelection(
      pageId: pageId,
      elementIds: Set.unmodifiable(selection.allIds),
      origin: origin,
      vertexMode: vertexMode && single != null && hasVertexMode(single),
      aspectUnlocked: aspectUnlocked && single is core.ImageObject,
    );
  }

  /// controller.clearSelection() on the page's controller (if mounted) and state = null.
  void clear() {
    final s = state;
    if (s == null) return;
    _controllerOf(s.pageId)?.clearSelection();
    state = null;
  }

  void setDragging(bool value) {
    final s = state;
    if (s == null || s.isDragging == value) return;
    state = s.copyWith(isDragging: value);
  }

  /// (v2) Vertex handles on / off — only for a single ShapeObject with
  /// PolylineGeometry (6.6.5); otherwise turning it on does nothing. (E2-08)
  /// Not for a line / an arrow (their end points are always vertex handles)
  /// nor a star (P-C — its many points' handles overlap): [hasVertexMode].
  void setVertexMode(bool value) {
    final s = state;
    if (s == null || s.vertexMode == value) return;
    if (value) {
      final sel = inkSelectionOf(_pages, s);
      final single = sel == null ? null : singleObjectOf(sel);
      if (single == null || !hasVertexMode(single)) return;
    }
    state = s.copyWith(vertexMode: value);
  }

  /// (E2-08, 6.6.4) '비율 고정 풀기' on / off — only for a single image;
  /// otherwise turning it on does nothing.
  void setAspectUnlocked(bool value) {
    final s = state;
    if (s == null || s.aspectUnlocked == value) return;
    if (value) {
      final sel = inkSelectionOf(_pages, s);
      if (sel == null || singleObjectOf(sel) is! core.ImageObject) return;
    }
    state = s.copyWith(aspectUnlocked: value);
  }

  /// 6.6.6 / (v2) 6.6.7: called from PageMount.onContentChanged (no CORE
  /// command inside). ids ∩ {content.elementById(id) != null} (strokes and
  /// objects): empty → clear(); fewer → controller.select(remaining), the
  /// origin kept. Ignored while a drag runs (its commit drops ids CORE no
  /// longer has).
  void revalidate(String pageId, core.PageContent content) {
    final s = state;
    if (s == null || s.pageId != pageId || s.isDragging) return;
    final remaining = {
      for (final id in s.elementIds)
        if (content.elementById(id) != null) id,
    };
    if (remaining.isEmpty) {
      clear();
      return;
    }
    if (remaining.length == s.elementIds.length) return;
    final controller = _controllerOf(pageId);
    if (controller == null) {
      state = null;
      return;
    }
    final current = controller.selection;
    if (current == null ||
        current.isDisposed ||
        !const SetEquality<String>().equals(current.allIds, remaining)) {
      controller.select(remaining);
    }
    state = s.copyWith(elementIds: Set.unmodifiable(remaining));
  }
}

final editorSelectionProvider =
    NotifierProvider<EditorSelectionNotifier, EditorSelection?>(
      EditorSelectionNotifier.new,
      dependencies: [
        editorNoteIdProvider,
        editorMountedPagesProvider,
        editorSessionValueProvider,
      ],
      name: 'editorSelectionProvider',
    );

/// The INK selection of [selection]'s page, when that page is mounted and
/// INK still holds a non-empty selection there.
ink.InkSelection? inkSelectionOf(
  MountedPages pages,
  EditorSelection? selection,
) {
  if (selection == null) return null;
  final sel = pages[selection.pageId]?.controller.selection;
  if (sel == null || sel.isDisposed || sel.isEmpty) return null;
  return sel;
}

/// The selection frame on screen: INK's previewBounds (page pt) through the
/// viewport. Null when there is no selection or its page is not laid out.
Rect? selectionRectOnScreen(
  ViewportController viewport,
  MountedPages pages,
  EditorSelection? selection,
) {
  final sel = inkSelectionOf(pages, selection);
  if (sel == null || viewport.viewportSize.isEmpty) return null;
  final index = viewport.pages.indexWhere((p) => p.id == selection!.pageId);
  if (index < 0) return null;
  final bounds = sel.previewBounds;
  return Rect.fromPoints(
    viewport.pageToScreen(index, bounds.topLeft),
    viewport.pageToScreen(index, bounds.bottomRight),
  );
}

/// (v2, 6.6.1) The single object of [sel] — no strokes and exactly one
/// object — or null.
core.PageObject? singleObjectOf(ink.InkSelection sel) {
  if (sel.strokeIds.isNotEmpty) return null;
  final objects = sel.objects;
  return objects.length == 1 ? objects.single : null;
}

/// (v2, 6.6.6) Whether [object]'s frame carries its rotation (text box,
/// image, ellipse, math): a rotate drag sets its absolute angle about the
/// frame centre. A polyline shape's frame is the points' box with rotation 0
/// (contract 7.2.2) — it rotates by the relative angle like a multi
/// selection; an unknown object does not rotate.
bool rotatesByFrame(core.PageObject object) => switch (object) {
  core.ShapeObject(:final geometry) => geometry is core.EllipseGeometry,
  core.TextBoxObject() || core.ImageObject() || core.MathObject() => true,
  core.UnknownObject() => false,
};

/// (v2) Whether nothing in [sel] can be transformed: only unknown objects
/// (TransformElements skips them — 6.6.4: no preview either).
bool isImmovableSelection(ink.InkSelection sel) =>
    sel.strokeIds.isEmpty &&
    sel.objects.isNotEmpty &&
    sel.objects.every((o) => o is core.UnknownObject);

/// (E2-08, 6.6.5) Whether [object] has a vertex mode ('꼭짓점 편집'): a
/// polyline shape that is neither a line / an arrow (their end points are
/// always vertex handles) nor a star (P-C).
bool hasVertexMode(core.PageObject object) =>
    object is core.ShapeObject &&
    object.geometry is core.PolylineGeometry &&
    !ObjectResize.isEndpointShape(object) &&
    object.shapeKind != core.ShapeKind.star;

/// (v2, 6.6.4) The selection frame as drawn on screen (viewport
/// coordinates): [quad], the resize [handles] shown, whether the rotate
/// handle is and (E2-08) the [vertices] handles.
@immutable
final class SelectionFrameShape {
  const SelectionFrameShape({
    required this.quad,
    required this.handles,
    required this.rotatable,
    this.vertices = const [],
    this.boxed = true,
  });

  /// The frame. (E2-08) A line / an arrow: (a, b, b, a) — the segment
  /// between its end points, its body the segment inflated in its own axes.
  final SelectionQuad quad;

  /// The resize handles drawn: corners and (E2-08) the edges of the object
  /// kind (6.6.4 table).
  final List<ink.SelectionHandle> handles;

  /// The rotate handle is drawn (and hit).
  final bool rotatable;

  /// (E2-08) Vertex handles (screen, by point index): a line's / an arrow's
  /// end points, a polygon's vertices in vertex mode.
  final List<Offset> vertices;

  /// (E2-08) false for a line / an arrow: the dashed line joins the end
  /// points, no box.
  final bool boxed;

  /// Every handle shown (resize + vertex + rotate).
  int get handleCount => handles.length + vertices.length + (rotatable ? 1 : 0);

  /// The axis-aligned box of the frame and its handles (the selection menu
  /// keeps clear of it).
  Rect get extent {
    var out = quad.bounds;
    if (handles.isNotEmpty || vertices.isNotEmpty) {
      out = out.inflate(SelectionHitTest.handleVisualRadius);
    }
    for (final v in vertices) {
      out = out.expandToInclude(
        Rect.fromCircle(center: v, radius: SelectionHitTest.handleVisualRadius),
      );
    }
    if (rotatable) {
      out = out.expandToInclude(
        Rect.fromCircle(
          center: quad.rotateHandlePosition,
          radius: SelectionHitTest.handleVisualRadius,
        ),
      );
    }
    return out;
  }

  /// The handle under [p] (the nearest within the hit radius), or null.
  FrameHandle? hitHandle(Offset p) => SelectionHitTest.hitFrameHandle(
    quad,
    p,
    handles: handles,
    rotatable: rotatable,
    vertices: vertices,
  );

  /// [p] on the body (the frame inflated by 8 px, in its own axes).
  bool hitBody(Offset p) => SelectionHitTest.hitQuadBody(quad, p);

  @override
  bool operator ==(Object other) =>
      other is SelectionFrameShape &&
      other.quad == quad &&
      other.rotatable == rotatable &&
      other.boxed == boxed &&
      const ListEquality<ink.SelectionHandle>().equals(
        other.handles,
        handles,
      ) &&
      const ListEquality<Offset>().equals(other.vertices, vertices);

  @override
  int get hashCode => Object.hash(
    quad,
    rotatable,
    boxed,
    const ListEquality<ink.SelectionHandle>().hash(handles),
    const ListEquality<Offset>().hash(vertices),
  );
}

/// (v2, 6.6.4) The selection frame on screen. Several elements (strokes,
/// mixed, objects): the axis-aligned `sel.bounds`, turned by the preview
/// (SelectionGeometry.transformedCorners — a rotation preview shows a rotated
/// rectangle), 4 corners + the rotate handle. One object: its own frame
/// (`object.frame.corners` — rotated for text, image, ellipse, math; the
/// points' box for a polyline) through the preview, with (E2-08) the
/// handles of its kind (6.6.4 table — [_singleHandles]); an unknown object:
/// its frame, no handles, never previewed. (E2-08) While an edge / vertex
/// drag shows an edited copy of the object (controller.previewObjects, same
/// id) the frame follows that copy. Null when there is no selection or its
/// page is not laid out.
SelectionFrameShape? selectionFrameOnScreen(
  ViewportController viewport,
  MountedPages pages,
  EditorSelection? selection,
) {
  final sel = inkSelectionOf(pages, selection);
  if (sel == null || viewport.viewportSize.isEmpty) return null;
  final index = viewport.pages.indexWhere((p) => p.id == selection!.pageId);
  if (index < 0) return null;
  final preview = sel.previewTransform;
  Offset screen(Offset page) => viewport.pageToScreen(index, page);
  final selected = singleObjectOf(sel);
  if (selected == null) {
    return SelectionFrameShape(
      quad: SelectionQuad.fromCorners([
        for (final c in ink.SelectionGeometry.transformedCorners(
          sel.bounds,
          preview,
        ))
          screen(c),
      ]),
      handles: SelectionHitTest.cornerHandles,
      rotatable: true,
    );
  }
  if (selected is core.UnknownObject) {
    return SelectionFrameShape(
      quad: SelectionQuad.fromCorners([
        for (final c in selected.frame.corners) screen(Offset(c.x, c.y)),
      ]),
      handles: const [],
      rotatable: false,
    );
  }
  final single =
      _editedCopyOf(pages[selection!.pageId]?.controller, selected) ?? selected;
  Offset through(core.PagePoint p) => screen(_apply(preview, p.x, p.y));
  if (single is core.ShapeObject) {
    final geometry = single.geometry;
    if (geometry is core.PolylineGeometry &&
        ObjectResize.isEndpointShape(single)) {
      final a = through(geometry.points[0]);
      final b = through(geometry.points[1]);
      return SelectionFrameShape(
        quad: SelectionQuad(a, b, b, a),
        handles: const [],
        rotatable: false,
        vertices: [a, b],
        boxed: false,
      );
    }
    if (geometry is core.PolylineGeometry && selection.vertexMode) {
      return SelectionFrameShape(
        quad: SelectionQuad.fromCorners([
          for (final c in single.frame.corners) through(c),
        ]),
        handles: const [],
        rotatable: false,
        vertices: [for (final p in geometry.points) through(p)],
      );
    }
  }
  return SelectionFrameShape(
    quad: SelectionQuad.fromCorners([
      for (final c in single.frame.corners) through(c),
    ]),
    handles: _singleHandles(single, selection),
    rotatable: true,
  );
}

/// (E2-08, 6.6.4 table) The resize handles of a single object (not a line /
/// an arrow, not in vertex mode, not unknown): a polyline shape and an
/// ellipse 4 corners + 4 edges, a text box 4 corners + left / right (its
/// width), an image 4 corners (+ 4 edges once its aspect is unlocked), a
/// math object 4 corners.
List<ink.SelectionHandle> _singleHandles(
  core.PageObject object,
  EditorSelection selection,
) => switch (object) {
  core.ShapeObject() => SelectionHitTest.allHandles,
  core.TextBoxObject() => _textHandles,
  core.ImageObject() =>
    selection.aspectUnlocked
        ? SelectionHitTest.allHandles
        : SelectionHitTest.cornerHandles,
  core.MathObject() || core.UnknownObject() => SelectionHitTest.cornerHandles,
};

const List<ink.SelectionHandle> _textHandles = [
  ink.SelectionHandle.topLeft,
  ink.SelectionHandle.topRight,
  ink.SelectionHandle.right,
  ink.SelectionHandle.bottomRight,
  ink.SelectionHandle.bottomLeft,
  ink.SelectionHandle.left,
];

/// (E2-08) The edited copy of [object] an edge / vertex drag shows
/// (controller.previewObjects — same id), or null.
core.PageObject? _editedCopyOf(
  ink.InkPageController? controller,
  core.PageObject object,
) {
  if (controller == null) return null;
  for (final o in controller.previewObjects) {
    if (o.id == object.id && o.runtimeType == object.runtimeType) return o;
  }
  return null;
}

Offset _apply(core.Affine2 m, double x, double y) {
  final (x2, y2) = m.apply(x, y);
  return Offset(x2, y2);
}
