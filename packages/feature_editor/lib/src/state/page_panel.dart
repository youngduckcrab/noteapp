// lib/src/state/page_panel.dart — 04-editor 6.11.1, 6.11.2 (page panel
// state, per note).
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../scope/editor_scope.dart';

@immutable
class PagePanelState {
  const PagePanelState({
    this.isOpen = false,
    this.isSelecting = false,
    this.selectedIds = const <String>{},
  });
  final bool isOpen;
  final bool isSelecting;
  final Set<String> selectedIds;

  /// selectedIds in note order (EditorMenuContext.selectedPageIds).
  List<String> orderedSelection(List<String> pageIdsInNoteOrder) => [
    for (final id in pageIdsInNoteOrder)
      if (selectedIds.contains(id)) id,
  ];

  PagePanelState copyWith({
    bool? isOpen,
    bool? isSelecting,
    Set<String>? selectedIds,
  }) => PagePanelState(
    isOpen: isOpen ?? this.isOpen,
    isSelecting: isSelecting ?? this.isSelecting,
    selectedIds: selectedIds ?? this.selectedIds,
  );

  static const SetEquality<String> _ids = SetEquality<String>();

  @override
  bool operator ==(Object other) =>
      other is PagePanelState &&
      other.isOpen == isOpen &&
      other.isSelecting == isSelecting &&
      _ids.equals(other.selectedIds, selectedIds);

  @override
  int get hashCode => Object.hash(isOpen, isSelecting, _ids.hash(selectedIds));

  @override
  String toString() =>
      'PagePanelState(open: $isOpen, selecting: $isSelecting, '
      '$selectedIds)';
}

/// Per note (scoped). The selection lives only in the selection mode: leaving
/// it (완료 · Esc · closing the panel) empties it. Pages that leave
/// session.pagesStream (deleted locally or remotely) leave the selection
/// (retainExisting — subscribed here, so it holds with the panel closed too).
class PagePanelNotifier extends Notifier<PagePanelState> {
  @override
  PagePanelState build() {
    final session = ref.watch(editorSessionValueProvider);
    final sub = session.pagesStream.listen(
      (pages) => retainExisting({for (final p in pages) p.id}),
    );
    ref.onDispose(() => unawaited(sub.cancel()));
    return const PagePanelState();
  }

  /// Opens / closes the panel; closing also leaves the selection mode.
  void toggleOpen() {
    state = state.isOpen
        ? const PagePanelState()
        : state.copyWith(isOpen: true);
  }

  /// false clears selectedIds.
  void setSelecting(bool value) {
    if (value == state.isSelecting && (value || state.selectedIds.isEmpty)) {
      return;
    }
    state = value
        ? state.copyWith(isSelecting: true)
        : state.copyWith(isSelecting: false, selectedIds: const {});
  }

  void toggleSelected(String pageId) {
    final ids = {...state.selectedIds};
    if (!ids.remove(pageId)) ids.add(pageId);
    state = state.copyWith(selectedIds: ids);
  }

  void selectAll(List<String> pageIds) {
    state = state.copyWith(selectedIds: {...pageIds});
  }

  void clearSelection() {
    if (state.selectedIds.isEmpty) return;
    state = state.copyWith(selectedIds: const {});
  }

  /// Called when pagesStream emits: drops ids that no longer exist.
  void retainExisting(Set<String> pageIds) {
    final selected = state.selectedIds;
    if (selected.every(pageIds.contains)) return;
    state = state.copyWith(
      selectedIds: selected.where(pageIds.contains).toSet(),
    );
  }
}

final editorPagePanelProvider =
    NotifierProvider<PagePanelNotifier, PagePanelState>(
      PagePanelNotifier.new,
      dependencies: [editorNoteIdProvider, editorSessionValueProvider],
      name: 'editorPagePanelProvider',
    );
