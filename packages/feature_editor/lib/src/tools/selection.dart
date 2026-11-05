// lib/src/tools/selection.dart — 04-editor 6.6.5, 6.6.6.
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

/// EDITOR-side selection state (per note). Geometry lives in ink.InkSelection
/// (controller.selection); this only says which page/ids and whether a drag runs.
@immutable
class EditorSelection {
  const EditorSelection({
    required this.pageId,
    required this.strokeIds,
    this.isDragging = false,
  });
  final String pageId;
  final Set<String> strokeIds;
  final bool isDragging; // menu hidden while true

  EditorSelection copyWith({Set<String>? strokeIds, bool? isDragging}) =>
      EditorSelection(
        pageId: pageId,
        strokeIds: strokeIds ?? this.strokeIds,
        isDragging: isDragging ?? this.isDragging,
      );

  static const SetEquality<String> _ids = SetEquality<String>();

  @override
  bool operator ==(Object other) =>
      other is EditorSelection &&
      other.pageId == pageId &&
      other.isDragging == isDragging &&
      _ids.equals(other.strokeIds, strokeIds);

  @override
  int get hashCode => Object.hash(pageId, isDragging, _ids.hash(strokeIds));

  @override
  String toString() =>
      'EditorSelection($pageId, $strokeIds${isDragging ? ', dragging' : ''})';
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

  /// controller.select(ids) and remember (pageId, ids). Empty ids → clear().
  void select(String pageId, Set<String> ids) {
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
      strokeIds: Set.unmodifiable(selection.strokeIds),
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

  /// 6.6.6: called from PageMount.onContentChanged (no CORE command inside).
  /// ids ∩ content ids: empty → clear(); fewer → controller.select(remaining).
  /// Ignored while a drag runs (its commit drops ids CORE no longer has).
  void revalidate(String pageId, core.PageContent content) {
    final s = state;
    if (s == null || s.pageId != pageId || s.isDragging) return;
    final remaining = {
      for (final id in s.strokeIds)
        if (content.strokeById(id) != null) id,
    };
    if (remaining.isEmpty) {
      clear();
      return;
    }
    if (remaining.length == s.strokeIds.length) return;
    final controller = _controllerOf(pageId);
    if (controller == null) {
      state = null;
      return;
    }
    final current = controller.selection;
    if (current == null ||
        current.isDisposed ||
        !const SetEquality<String>().equals(current.strokeIds, remaining)) {
      controller.select(remaining);
    }
    state = s.copyWith(strokeIds: Set.unmodifiable(remaining));
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
