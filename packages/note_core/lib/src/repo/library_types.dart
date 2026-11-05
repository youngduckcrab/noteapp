// lib/src/repo/library_types.dart — all value types (==/hashCode), usable as family keys
// Contract 00-overview 7.2.9 / CORE 4.5.
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../common/ids.dart';
import '../model/folder.dart';
import '../model/note.dart';

const ListEquality<Folder> _foldersEq = ListEquality<Folder>();
const ListEquality<Note> _notesEq = ListEquality<Note>();

@immutable
sealed class LibraryItemRef {
  const LibraryItemRef();
  String get id;
}

final class FolderRef extends LibraryItemRef {
  const FolderRef(this.id);
  @override
  final FolderId id;

  @override
  bool operator ==(Object other) => other is FolderRef && other.id == id;
  @override
  int get hashCode => Object.hash('folder', id);
  @override
  String toString() => 'FolderRef($id)';
}

final class NoteRef extends LibraryItemRef {
  const NoteRef(this.id);
  @override
  final NoteId id;

  @override
  bool operator ==(Object other) => other is NoteRef && other.id == id;
  @override
  int get hashCode => Object.hash('note', id);
  @override
  String toString() => 'NoteRef($id)';
}

enum LibrarySortField { name, createdAt, updatedAt, custom }

@immutable
final class LibraryQuery {
  // value equality (Riverpod family key)
  const LibraryQuery({
    this.folderId,
    this.sort = LibrarySortField.updatedAt,
    this.descending = true,
  });

  final FolderId? folderId; // null = top level
  final LibrarySortField sort;
  final bool descending; // ignored for custom

  @override
  bool operator ==(Object other) =>
      other is LibraryQuery &&
      other.folderId == folderId &&
      other.sort == sort &&
      other.descending == descending;

  @override
  int get hashCode => Object.hash(folderId, sort, descending);

  @override
  String toString() =>
      'LibraryQuery(folder: $folderId, ${sort.name}, '
      '${descending ? 'desc' : 'asc'})';
}

@immutable
final class LibraryListing {
  const LibraryListing({
    required this.folderId,
    required this.folders,
    required this.notes,
  });

  final FolderId? folderId;
  final List<Folder> folders; // folders first in UI
  final List<Note> notes;

  @override
  bool operator ==(Object other) =>
      other is LibraryListing &&
      other.folderId == folderId &&
      _foldersEq.equals(other.folders, folders) &&
      _notesEq.equals(other.notes, notes);

  @override
  int get hashCode =>
      Object.hash(folderId, _foldersEq.hash(folders), _notesEq.hash(notes));

  @override
  String toString() =>
      'LibraryListing($folderId, ${folders.length} folders, ${notes.length} notes)';
}

@immutable
final class LibrarySearchResult {
  const LibrarySearchResult({
    required this.query,
    required this.folders,
    required this.notes,
  });

  final String query;
  final List<Folder> folders;
  final List<Note> notes;

  @override
  bool operator ==(Object other) =>
      other is LibrarySearchResult &&
      other.query == query &&
      _foldersEq.equals(other.folders, folders) &&
      _notesEq.equals(other.notes, notes);

  @override
  int get hashCode =>
      Object.hash(query, _foldersEq.hash(folders), _notesEq.hash(notes));
}
