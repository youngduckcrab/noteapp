// lib/src/model/content.dart — 05-library 6.3.3 (libraryContentProvider).
import 'package:collection/collection.dart' show ListEquality;
import 'package:flutter/foundation.dart' show immutable;
import 'package:note_core/note_core.dart' show Folder, Note;

import 'item_key.dart';
import 'section.dart';

const ListEquality<Folder> _foldersEq = ListEquality<Folder>();
const ListEquality<Note> _notesEq = ListEquality<Note>();

/// What the content pane shows for one section (trash excluded: the trash
/// view reads trashItemsProvider itself).
@immutable
final class LibraryContent {
  const LibraryContent({
    required this.section,
    this.folders = const [],
    this.notes = const [],
    this.truncated = false,
  });

  final LibrarySection section;

  /// Empty for recent / favorites.
  final List<Folder> folders;
  final List<Note> notes;

  /// Search hit the 50 limit in a group.
  final bool truncated;

  bool get isEmpty => folders.isEmpty && notes.isEmpty;

  /// Folders then notes — display order of the whole pane.
  List<LibraryItemKey> get orderedKeys => [
    for (final f in folders) folderKey(f.id),
    for (final n in notes) noteKey(n.id),
  ];

  @override
  bool operator ==(Object other) =>
      other is LibraryContent &&
      other.section == section &&
      other.truncated == truncated &&
      _foldersEq.equals(other.folders, folders) &&
      _notesEq.equals(other.notes, notes);

  @override
  int get hashCode => Object.hash(
    section,
    truncated,
    _foldersEq.hash(folders),
    _notesEq.hash(notes),
  );

  @override
  String toString() =>
      'LibraryContent($section, ${folders.length} folders, '
      '${notes.length} notes${truncated ? ', truncated' : ''})';
}

/// State of a folder id that the active FolderTree does not contain (6.4).
enum FolderLookupState { active, trashed, missing }
