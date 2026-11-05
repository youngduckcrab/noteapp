import 'package:flutter/foundation.dart';

/// Route paths of the app shell (docs/plans/01-infra.md 4.5.5, 6.6).
///
/// Feature screens never see these paths: the shell turns their callbacks
/// into navigation (D5).
abstract final class AppRoutes {
  static const String library = '/';
  static const String folderPattern = '/folders/:folderId';
  static const String notePattern = '/notes/:noteId';
  static const String settings = '/settings';
  static const String pageQueryKey = 'page';

  /// Shared page key of `/` and `/folders/:folderId`: the Navigator keeps ONE
  /// library route, so folder changes update LibraryScreen instead of
  /// recreating it (6.6).
  static const ValueKey<String> libraryPageKey = ValueKey<String>('library');

  /// `/folders/<encoded id>`
  static String folder(String folderId) =>
      '/folders/${Uri.encodeComponent(folderId)}';

  /// `/notes/<encoded id>` + `?page=<encoded pageId>` when given (계약 7.2.17).
  static String note(String noteId, {String? pageId}) {
    final path = '/notes/${Uri.encodeComponent(noteId)}';
    if (pageId == null) return path;
    return '$path?$pageQueryKey=${Uri.encodeQueryComponent(pageId)}';
  }
}

/// Arguments of the library routes `/` and `/folders/:folderId`.
@immutable
final class LibraryRouteArgs {
  const LibraryRouteArgs({this.folderId});
  final String? folderId; // null = root

  @override
  bool operator ==(Object other) =>
      other is LibraryRouteArgs && other.folderId == folderId;

  @override
  int get hashCode => folderId.hashCode;

  @override
  String toString() => 'LibraryRouteArgs(folderId: $folderId)';
}

/// Arguments of the editor route `/notes/:noteId?page=<pageId>`.
@immutable
final class EditorRouteArgs {
  const EditorRouteArgs({required this.noteId, this.initialPageId});
  final String noteId;
  final String? initialPageId;

  @override
  bool operator ==(Object other) =>
      other is EditorRouteArgs &&
      other.noteId == noteId &&
      other.initialPageId == initialPageId;

  @override
  int get hashCode => Object.hash(noteId, initialPageId);

  @override
  String toString() =>
      'EditorRouteArgs(noteId: $noteId, initialPageId: $initialPageId)';
}
