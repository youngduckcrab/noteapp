// lib/src/model/tree_rows.dart — 05-library 6.5 (sidebar folder tree).
import 'package:flutter/foundation.dart' show immutable;
import 'package:note_core/note_core.dart'
    show Folder, FolderId, FolderTree, LibrarySortField;

import 'view_prefs.dart';

/// One visible row of the sidebar folder tree.
@immutable
final class FolderTreeRow {
  const FolderTreeRow({
    required this.folder,
    required this.depth,
    required this.hasChildren,
    required this.isExpanded,
  });

  final Folder folder;

  /// 0 = top level.
  final int depth;
  final bool hasChildren;
  final bool isExpanded;

  /// folder.id, name, colorArgb, icon, depth, flags.
  @override
  bool operator ==(Object other) =>
      other is FolderTreeRow &&
      other.folder.id == folder.id &&
      other.folder.name == folder.name &&
      other.folder.colorArgb == folder.colorArgb &&
      other.folder.icon == folder.icon &&
      other.depth == depth &&
      other.hasChildren == hasChildren &&
      other.isExpanded == isExpanded;

  @override
  int get hashCode => Object.hash(
    folder.id,
    folder.name,
    folder.colorArgb,
    folder.icon,
    depth,
    hasChildren,
    isExpanded,
  );

  @override
  String toString() =>
      'FolderTreeRow(${folder.id} "${folder.name}", depth $depth'
      '${hasChildren ? (isExpanded ? ', expanded' : ', collapsed') : ''})';
}

enum FolderTreeOrder { name, custom }

/// custom when sort.field == custom, otherwise name.
FolderTreeOrder folderTreeOrderFor(LibrarySort sort) =>
    sort.field == LibrarySortField.custom
    ? FolderTreeOrder.custom
    : FolderTreeOrder.name;

final RegExp _spaces = RegExp(r'\s+');

String _nameKey(String name) =>
    name.trim().replaceAll(_spaces, ' ').toLowerCase();

/// trim → collapse whitespace → toLowerCase, then String.compareTo, then id.
int compareFolderNames(Folder a, Folder b) {
  final byName = _nameKey(a.name).compareTo(_nameKey(b.name));
  if (byName != 0) return byName;
  return a.id.compareTo(b.id);
}

/// Visible rows: pre-order DFS from tree.roots, children only for expanded
/// folders. Iterative (explicit stack) so depth is unlimited.
///
/// Folders that no root reaches (caught in a sync cycle, or below one —
/// `tree.folders`, contract 7.2.9) follow the rooted rows in name order, each
/// shown like a top-level folder. A stranded folder below one already shown
/// that way is not repeated at the top level; a folder never appears twice.
List<FolderTreeRow> flattenFolderTree(
  FolderTree tree, {
  required Set<FolderId> expanded,
  required FolderTreeOrder order,
}) {
  final rows = <FolderTreeRow>[];
  final visited = <FolderId>{};

  List<Folder> ordered(List<Folder> folders) => switch (order) {
    FolderTreeOrder.custom => folders,
    FolderTreeOrder.name => [...folders]..sort(compareFolderNames),
  };

  void emitFrom(Folder top) {
    final stack = <(Folder, int)>[(top, 0)];
    while (stack.isNotEmpty) {
      final (folder, depth) = stack.removeLast();
      if (!visited.add(folder.id)) continue;
      final children = tree.childrenOf(folder.id);
      final isExpanded = expanded.contains(folder.id);
      rows.add(
        FolderTreeRow(
          folder: folder,
          depth: depth,
          hasChildren: children.isNotEmpty,
          isExpanded: isExpanded,
        ),
      );
      if (isExpanded && children.isNotEmpty) {
        final next = ordered(children);
        for (var i = next.length - 1; i >= 0; i--) {
          stack.add((next[i], depth + 1));
        }
      }
    }
  }

  final roots = ordered(tree.roots);
  for (final root in roots) {
    emitFrom(root);
  }

  // Every folder reachable from a root, expanded or not.
  final reached = _reachableFrom(tree, roots);
  if (reached.length == tree.length) return rows;

  final stranded = [
    for (final f in tree.folders)
      if (!reached.contains(f.id)) f,
  ]..sort(compareFolderNames);
  for (final folder in stranded) {
    if (reached.contains(folder.id)) continue;
    reached.addAll(_reachableFrom(tree, [folder]));
    emitFrom(folder);
  }
  return rows;
}

Set<FolderId> _reachableFrom(FolderTree tree, Iterable<Folder> starts) {
  final out = <FolderId>{};
  final stack = <FolderId>[
    for (final f in starts)
      if (out.add(f.id)) f.id,
  ];
  while (stack.isNotEmpty) {
    for (final child in tree.childrenOf(stack.removeLast())) {
      if (out.add(child.id)) stack.add(child.id);
    }
  }
  return out;
}
