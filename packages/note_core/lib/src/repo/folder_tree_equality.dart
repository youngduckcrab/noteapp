// Internal: content equality of two FolderTrees (watchFolderTree emits only when the
// active folders changed, C-1). Shared by the fake and the SQLite store.
import 'package:collection/collection.dart';

import '../model/folder.dart';
import 'folder_tree.dart';

const SetEquality<Folder> _folderSetEq = SetEquality<Folder>();

/// Whether [a] and [b] hold the same active folders (same values).
bool sameFolderTree(FolderTree a, FolderTree b) =>
    identical(a, b) ||
    (a.length == b.length &&
        _folderSetEq.equals(a.folders.toSet(), b.folders.toSet()));
