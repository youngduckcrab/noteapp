// lib/src/model/view_prefs.dart — 05-library 6.3.3 / 6.7.
import 'package:flutter/foundation.dart' show immutable;
import 'package:note_core/note_core.dart'
    show FolderId, LibraryQuery, LibrarySortField, SettingsSnapshot;

import '../settings/library_settings_keys.dart';

enum LibraryViewMode { grid, list }

@immutable
final class LibrarySort {
  const LibrarySort(this.field, {required this.descending});

  static const LibrarySort defaults = LibrarySort(
    LibrarySortField.updatedAt,
    descending: true,
  );

  final LibrarySortField field;

  /// Ignored for custom.
  final bool descending;

  /// Menu selection: same field → toggle direction (custom stays ascending);
  /// other field → name: ascending, createdAt/updatedAt: descending, custom.
  LibrarySort select(LibrarySortField newField) {
    if (newField == LibrarySortField.custom) {
      return const LibrarySort(LibrarySortField.custom, descending: false);
    }
    if (newField == field) return LibrarySort(field, descending: !descending);
    return LibrarySort(newField, descending: newField != LibrarySortField.name);
  }

  LibraryQuery queryFor(FolderId? folderId) =>
      LibraryQuery(folderId: folderId, sort: field, descending: descending);

  @override
  bool operator ==(Object other) =>
      other is LibrarySort &&
      other.field == field &&
      other.descending == descending;

  @override
  int get hashCode => Object.hash(field, descending);

  @override
  String toString() =>
      'LibrarySort(${field.name}, ${descending ? 'desc' : 'asc'})';
}

@immutable
final class LibraryViewPrefs {
  const LibraryViewPrefs({
    this.viewMode = LibraryViewMode.grid,
    this.sort = LibrarySort.defaults,
    this.sidebarVisible = true,
    this.isLoaded = false,
  });

  /// Reads the LIBRARY keys of [snapshot]; unknown strings → defaults
  /// (viewMode 'tiles' → grid, sortField 'size' → updatedAt). isLoaded: true.
  factory LibraryViewPrefs.fromSnapshot(SettingsSnapshot snapshot) {
    final mode = snapshot.get(LibrarySettingsKeys.viewMode);
    final field = snapshot.get(LibrarySettingsKeys.sortField);
    return LibraryViewPrefs(
      viewMode: _byName(LibraryViewMode.values, mode) ?? LibraryViewMode.grid,
      sort: LibrarySort(
        _byName(LibrarySortField.values, field) ?? LibrarySort.defaults.field,
        descending: snapshot.get(LibrarySettingsKeys.sortDescending),
      ),
      sidebarVisible: snapshot.get(LibrarySettingsKeys.sidebarVisible),
      isLoaded: true,
    );
  }

  final LibraryViewMode viewMode;
  final LibrarySort sort;

  /// Expanded size class only.
  final bool sidebarVisible;

  /// False until the first settings snapshot.
  final bool isLoaded;

  LibraryViewPrefs copyWith({
    LibraryViewMode? viewMode,
    LibrarySort? sort,
    bool? sidebarVisible,
  }) => LibraryViewPrefs(
    viewMode: viewMode ?? this.viewMode,
    sort: sort ?? this.sort,
    sidebarVisible: sidebarVisible ?? this.sidebarVisible,
    isLoaded: isLoaded,
  );

  @override
  bool operator ==(Object other) =>
      other is LibraryViewPrefs &&
      other.viewMode == viewMode &&
      other.sort == sort &&
      other.sidebarVisible == sidebarVisible &&
      other.isLoaded == isLoaded;

  @override
  int get hashCode => Object.hash(viewMode, sort, sidebarVisible, isLoaded);

  @override
  String toString() =>
      'LibraryViewPrefs(${viewMode.name}, $sort, sidebar: $sidebarVisible, '
      'loaded: $isLoaded)';
}

T? _byName<T extends Enum>(List<T> values, String name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}
