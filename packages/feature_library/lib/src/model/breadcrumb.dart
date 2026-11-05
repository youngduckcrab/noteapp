// lib/src/model/breadcrumb.dart — 05-library 6.6.
import 'package:collection/collection.dart' show ListEquality;
import 'package:flutter/foundation.dart' show immutable;
import 'package:note_core/note_core.dart' show FolderId, FolderTree;

import '../l10n/library_strings.dart';

@immutable
final class BreadcrumbItem {
  const BreadcrumbItem({required this.folderId, required this.label});

  /// null = 홈.
  final FolderId? folderId;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is BreadcrumbItem &&
      other.folderId == folderId &&
      other.label == label;

  @override
  int get hashCode => Object.hash(folderId, label);

  @override
  String toString() => 'BreadcrumbItem(${folderId ?? 'home'} "$label")';
}

@immutable
sealed class BreadcrumbSlot {
  const BreadcrumbSlot();
}

final class BreadcrumbCrumb extends BreadcrumbSlot {
  const BreadcrumbCrumb(this.item, {required this.isCurrent});

  final BreadcrumbItem item;
  final bool isCurrent;

  @override
  bool operator ==(Object other) =>
      other is BreadcrumbCrumb &&
      other.item == item &&
      other.isCurrent == isCurrent;

  @override
  int get hashCode => Object.hash(BreadcrumbCrumb, item, isCurrent);

  @override
  String toString() =>
      'BreadcrumbCrumb(${item.label}${isCurrent ? ', current' : ''})';
}

final class BreadcrumbOverflow extends BreadcrumbSlot {
  const BreadcrumbOverflow(this.hidden);

  /// Shown in a popup menu, top → down.
  final List<BreadcrumbItem> hidden;

  static const ListEquality<BreadcrumbItem> _eq =
      ListEquality<BreadcrumbItem>();

  @override
  bool operator ==(Object other) =>
      other is BreadcrumbOverflow && _eq.equals(other.hidden, hidden);

  @override
  int get hashCode => Object.hash(BreadcrumbOverflow, _eq.hash(hidden));

  @override
  String toString() =>
      'BreadcrumbOverflow(${hidden.map((i) => i.label).join(', ')})';
}

/// [홈, ...tree.pathTo(folderId)]. A folder missing from [tree] → [홈].
List<BreadcrumbItem> breadcrumbPath(FolderTree tree, FolderId? folderId) => [
  const BreadcrumbItem(folderId: null, label: LibraryStrings.home),
  if (folderId != null)
    for (final f in tree.pathTo(folderId))
      BreadcrumbItem(folderId: f.id, label: f.name),
];

/// [path] = [홈, ...tree.pathTo(folderId)]; the last item is the current one.
/// If path.length <= maxVisible → every crumb. Otherwise:
///   head = maxVisible >= 3 ? [path.first] : []
///   tail = maxVisible >= 3 ? last (maxVisible - 2) : last 1
///   result = head + [Overflow(the rest, in order)] + tail
/// maxVisible: expanded 4, medium 3, compact 2.
List<BreadcrumbSlot> compressBreadcrumb(
  List<BreadcrumbItem> path, {
  required int maxVisible,
}) {
  assert(maxVisible >= 2, 'maxVisible must be at least 2');
  final last = path.length - 1;
  BreadcrumbCrumb crumbAt(int i) =>
      BreadcrumbCrumb(path[i], isCurrent: i == last);

  if (path.length <= maxVisible) {
    return [for (var i = 0; i < path.length; i++) crumbAt(i)];
  }
  final headCount = maxVisible >= 3 ? 1 : 0;
  final tailCount = maxVisible >= 3 ? maxVisible - 2 : 1;
  final tailStart = path.length - tailCount;
  return [
    for (var i = 0; i < headCount; i++) crumbAt(i),
    BreadcrumbOverflow(List.unmodifiable(path.sublist(headCount, tailStart))),
    for (var i = tailStart; i < path.length; i++) crumbAt(i),
  ];
}
