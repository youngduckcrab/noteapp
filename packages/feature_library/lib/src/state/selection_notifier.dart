// lib/src/state/selection_notifier.dart — 05-library 6.3.3 / 6.9.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' show FolderId;

import '../model/item_key.dart';
import '../model/selection.dart';
import 'providers.dart' show librarySectionProvider;

class LibrarySelectionNotifier extends Notifier<LibrarySelection> {
  LibrarySelectionNotifier(this.routeFolderId);

  final FolderId? routeFolderId;

  /// Starts as none; ref.listen(librarySectionProvider(routeFolderId)) →
  /// state = none on every section change.
  @override
  LibrarySelection build() {
    ref.listen(librarySectionProvider(routeFolderId), (previous, next) {
      if (previous != next) state = LibrarySelection.none;
    });
    return LibrarySelection.none;
  }

  /// active = true (+ [first]); keeps keys already selected.
  void begin([LibraryItemKey? first]) =>
      state = LibrarySelection.activeWith([...state.keys, ?first]);

  /// Selection mode off.
  void end() => state = LibrarySelection.none;

  /// Stays active when it becomes empty.
  void toggle(LibraryItemKey key) => state = LibrarySelection.activeWith(
    state.contains(key)
        ? state.keys.where((k) => k != key)
        : [...state.keys, key],
  );

  /// Used when a drag starts on an unselected item.
  void add(LibraryItemKey key) {
    if (state.active && state.contains(key)) return;
    state = LibrarySelection.activeWith([...state.keys, key]);
  }

  void selectAll(List<LibraryItemKey> keys) =>
      state = LibrarySelection.activeWith(keys);

  /// Active stays true.
  void clearKeys() => state = LibrarySelection.activeWith(const []);

  /// Drops keys that are no longer visible (deleted/moved by another device).
  void retainVisible(Set<LibraryItemKey> visible) {
    if (!state.active) return;
    if (state.keys.every(visible.contains)) return;
    state = LibrarySelection.activeWith(state.keys.where(visible.contains));
  }
}
