// lib/src/tools/selection.dart — 04-editor 6.6.5, 6.6.6; (v2) m5-7/04-editor
// 6.6.1 (elementIds = strokes AND objects, origin, vertexMode) and 6.6.7
// (revalidation by elementById) — E2-02. The selection rules that use them
// (priority (a′), mixed lasso, vertex editing) come in E2-06 / E2-08.
import 'dart:async';
import 'dart:ui' show Rect;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../document/mounted_pages.dart';
import '../scope/editor_scope.dart';
import '../viewport/viewport_controller.dart';
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
