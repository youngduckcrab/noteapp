// lib/src/model/section.dart — 05-library 6.3.3 / 6.4. All value-equal
// (== / hashCode): sections are family keys (libraryContentProvider).
import 'package:flutter/foundation.dart' show immutable;
import 'package:note_core/note_core.dart' show FolderId;

@immutable
sealed class LibrarySection {
  const LibrarySection();
}

final class FolderSection extends LibrarySection {
  const FolderSection(this.folderId);

  /// null = 홈.
  final FolderId? folderId;

  @override
  bool operator ==(Object other) =>
      other is FolderSection && other.folderId == folderId;

  @override
  int get hashCode => Object.hash(FolderSection, folderId);

  @override
  String toString() => 'FolderSection(${folderId ?? 'home'})';
}

final class RecentSection extends LibrarySection {
  const RecentSection();

  @override
  bool operator ==(Object other) => other is RecentSection;

  @override
  int get hashCode => (RecentSection).hashCode;

  @override
  String toString() => 'RecentSection()';
}

final class FavoritesSection extends LibrarySection {
  const FavoritesSection();

  @override
  bool operator ==(Object other) => other is FavoritesSection;

  @override
  int get hashCode => (FavoritesSection).hashCode;

  @override
  String toString() => 'FavoritesSection()';
}

final class TrashSection extends LibrarySection {
  const TrashSection();

  @override
  bool operator ==(Object other) => other is TrashSection;

  @override
  int get hashCode => (TrashSection).hashCode;

  @override
  String toString() => 'TrashSection()';
}

final class SearchSection extends LibrarySection {
  const SearchSection(this.query, {required this.returnTo})
    : assert(returnTo is! SearchSection, 'returnTo is never a search');

  /// Trimmed, non-empty.
  final String query;

  /// Never a SearchSection.
  final LibrarySection returnTo;

  @override
  bool operator ==(Object other) =>
      other is SearchSection &&
      other.query == query &&
      other.returnTo == returnTo;

  @override
  int get hashCode => Object.hash(SearchSection, query, returnTo);

  @override
  String toString() => "SearchSection('$query', returnTo: $returnTo)";
}
