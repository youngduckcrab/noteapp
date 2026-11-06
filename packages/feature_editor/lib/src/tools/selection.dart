// lib/src/tools/selection.dart — 04-editor 6.6.5, 6.6.6; (v2) m5-7/04-editor
// 6.6.1 (elementIds = strokes AND objects, origin, vertexMode) and 6.6.7
// (revalidation by elementById) — E2-02. The selection rules that use them
// (priority (a′), mixed lasso, vertex editing) come in E2-06 / E2-08. (v2,
// E2-06) the frame as drawn (6.6.4): selectionFrameOnScreen.
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
  });
  final String pageId;

  /// (v2) strokes AND objects (was strokeIds).
  final Set<String> elementIds;

  /// (v2) 6.6.3 table; kept by revalidation.
  final SelectionOrigin origin;
  final bool isDragging; // menu hidden while true

  /// (v2) single polyline shape: vertex handles shown (6.6.5).
  final bool vertexMode;

  EditorSelection copyWith({
    Set<String>? elementIds,
    SelectionOrigin? origin,
    bool? isDragging,
    bool? vertexMode,
  }) => EditorSelection(
    pageId: pageId,
    elementIds: elementIds ?? this.elementIds,
    origin: origin ?? this.origin,
    isDragging: isDragging ?? this.isDragging,
    vertexMode: vertexMode ?? this.vertexMode,
  );

  static const SetEquality<String> _ids = SetEquality<String>();

  @override
  bool operator ==(Object other) =>
      other is EditorSelection &&
      other.pageId == pageId &&
      other.origin == origin &&
      other.isDragging == isDragging &&
      other.vertexMode == vertexMode &&
      _ids.equals(other.elementIds, elementIds);

  @override
  int get hashCode => Object.hash(
    pageId,
    origin,
    isDragging,
    vertexMode,
    _ids.hash(elementIds),
  );

  @override
  String toString() =>
      'EditorSelection($pageId, $elementIds, ${origin.name}'
      '${isDragging ? ', dragging' : ''}${vertexMode ? ', vertices' : ''})';
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
  /// allIds, [origin]). Empty ids → clear().
  void select(
    String pageId,
    Set<String> ids, {
    SelectionOrigin origin = SelectionOrigin.lasso,
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
    state = EditorSelection(
      pageId: pageId,
      elementIds: Set.unmodifiable(selection.allIds),
      origin: origin,
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
  /// PolylineGeometry (6.6.5); otherwise turning it on does nothing.
  void setVertexMode(bool value) {
    final s = state;
    if (s == null || s.vertexMode == value) return;
    if (value) {
      final sel = inkSelectionOf(_pages, s);
      final objects = sel?.objects ?? const <core.PageObject>[];
      final single = sel != null && sel.strokeIds.isEmpty && objects.length == 1
          ? objects.single
          : null;
      if (single is! core.ShapeObject ||
          single.geometry is! core.PolylineGeometry) {
        return;
      }
    }
    state = s.copyWith(vertexMode: value);
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

/// (v2, 6.6.4) The selection frame as drawn on screen (viewport
/// coordinates): [quad], the resize [handles] shown and whether the rotate
/// handle is.
@immutable
final class SelectionFrameShape {
  const SelectionFrameShape({
    required this.quad,
    required this.handles,
    required this.rotatable,
  });

  final SelectionQuad quad;

  /// The resize handles drawn (E2-06: the 4 corners; edges come in E2-08).
  final List<ink.SelectionHandle> handles;

  /// The rotate handle is drawn (and hit).
  final bool rotatable;

  /// The axis-aligned box of the frame and its handles (the selection menu
  /// keeps clear of it).
  Rect get extent {
    var out = quad.bounds;
    if (handles.isNotEmpty) {
      out = out.inflate(SelectionHitTest.handleVisualRadius);
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
  );

  /// [p] on the body (the frame inflated by 8 px, in its own axes).
  bool hitBody(Offset p) => SelectionHitTest.hitQuadBody(quad, p);

  @override
  bool operator ==(Object other) =>
      other is SelectionFrameShape &&
      other.quad == quad &&
      other.rotatable == rotatable &&
      const ListEquality<ink.SelectionHandle>().equals(other.handles, handles);

  @override
  int get hashCode => Object.hash(
    quad,
    rotatable,
    const ListEquality<ink.SelectionHandle>().hash(handles),
  );
}

/// (v2, 6.6.4) The selection frame on screen. Several elements (strokes,
/// mixed, objects): the axis-aligned `sel.bounds`, turned by the preview
/// (SelectionGeometry.transformedCorners — a rotation preview shows a rotated
/// rectangle), 4 corners + the rotate handle. One object: its own frame
/// (`object.frame.corners` — rotated for text, image, ellipse, math; the
/// points' box for a polyline) through the preview, 4 corners + the rotate
/// handle; an unknown object: its frame, no handles, never previewed. Null
/// when there is no selection or its page is not laid out.
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
  final single = singleObjectOf(sel);
  final List<Offset> pageCorners;
  var handles = SelectionHitTest.cornerHandles;
  var rotatable = true;
  if (single == null) {
    pageCorners = ink.SelectionGeometry.transformedCorners(sel.bounds, preview);
  } else if (single is core.UnknownObject) {
    pageCorners = [for (final c in single.frame.corners) Offset(c.x, c.y)];
    handles = const [];
    rotatable = false;
  } else {
    pageCorners = [
      for (final c in single.frame.corners) _apply(preview, c.x, c.y),
    ];
  }
  return SelectionFrameShape(
    quad: SelectionQuad.fromCorners([
      for (final c in pageCorners) viewport.pageToScreen(index, c),
    ]),
    handles: handles,
    rotatable: rotatable,
  );
}

Offset _apply(core.Affine2 m, double x, double y) {
  final (x2, y2) = m.apply(x, y);
  return Offset(x2, y2);
}
