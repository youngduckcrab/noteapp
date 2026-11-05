// lib/src/model/location_label.dart — 05-library 6.14 ('홈 › A › B').
import 'package:note_core/note_core.dart' show FolderId, FolderTree;

import '../l10n/library_strings.dart';

/// Folder names shown before the label collapses to '홈 › … › parent › name'.
const int kLocationLabelMaxNames = 3;

/// null → '홈'; otherwise '홈 › A › B'. More than 3 folder names →
/// `'홈 › … › <parent> › <name>'`. Folder missing from tree → '홈'.
String locationLabel(FolderTree tree, FolderId? folderId) {
  if (folderId == null) return LibraryStrings.home;
  final names = [for (final f in tree.pathTo(folderId)) f.name];
  if (names.isEmpty) return LibraryStrings.home;
  final shown = names.length > kLocationLabelMaxNames
      ? [LibraryStrings.ellipsis, ...names.sublist(names.length - 2)]
      : names;
  return [LibraryStrings.home, ...shown].join(LibraryStrings.pathSeparator);
}
