// lib/src/repo/trash_repository.dart — contract 00-overview 7.2.9 / CORE 4.5.
import 'package:meta/meta.dart';

import '../common/ids.dart';
import '../model/folder.dart';
import '../model/note.dart';
import 'library_types.dart';

@immutable
sealed class TrashItem {
  const TrashItem();
  LibraryItemRef get ref;
  String get name;
  EpochMillis get deletedAt;
  EpochMillis get expiresAt; // deletedAt + retention
}

final class TrashedFolder extends TrashItem {
  const TrashedFolder({
    required this.folder,
    required this.folderCount,
    required this.noteCount,
    required this.expiresAt,
  });

  final Folder folder;
  final int folderCount; // descendants trashed with it
  final int noteCount;
  @override
  final EpochMillis expiresAt;

  // ref/name/deletedAt derive from folder
  @override
  LibraryItemRef get ref => FolderRef(folder.id);
  @override
  String get name => folder.name;
  @override
  EpochMillis get deletedAt => folder.deletedAt ?? 0;

  @override
  bool operator ==(Object other) =>
      other is TrashedFolder &&
      other.folder == folder &&
      other.folderCount == folderCount &&
      other.noteCount == noteCount &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(folder, folderCount, noteCount, expiresAt);
}

final class TrashedNote extends TrashItem {
  const TrashedNote({required this.note, required this.expiresAt});

  final Note note;
  @override
  final EpochMillis expiresAt;

  @override
  LibraryItemRef get ref => NoteRef(note.id);
  @override
  String get name => note.title;
  @override
  EpochMillis get deletedAt => note.deletedAt ?? 0;

  @override
  bool operator ==(Object other) =>
      other is TrashedNote &&
      other.note == note &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(note, expiresAt);
}

abstract interface class TrashRepository {
  Stream<List<TrashItem>> watchTrash(); // top-level trashed items, newest first
  Future<void> restore(List<LibraryItemRef> items);
  Future<void> purge(List<LibraryItemRef> items); // permanent
  Future<void> emptyTrash();

  /// Purges groups older than retention. Returns purged group count.
  Future<int> purgeExpired();
}
