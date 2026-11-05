// lib/src/model/folder.dart — contract 00-overview 7.2.6 / CORE 4.2.4.
import 'package:meta/meta.dart';

import '../common/hlc.dart';
import '../common/ids.dart';
import '../common/json_read.dart';
import 'sync_entity.dart';

@immutable
final class Folder implements SyncEntity {
  const Folder({
    required this.id,
    required this.ownerId,
    this.parentId,
    required this.name,
    this.colorArgb,
    this.icon,
    required this.sortKey,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.trashRootId,
    this.version,
  });

  @override
  final FolderId id;
  final OwnerId ownerId;
  final FolderId? parentId; // null = top level
  final String name; // trimmed, 1..200 chars
  final int? colorArgb;
  final String? icon; // icon key defined by LIBRARY, <= 32 chars
  final String sortKey;
  final EpochMillis createdAt, updatedAt;
  @override
  final EpochMillis? deletedAt;
  final String? trashRootId; // id of the folder/note the user trashed (6.8)
  @override
  final Hlc? version;
  @override
  EntityKind get kind => EntityKind.folder;
  @override
  bool get isDeleted => deletedAt != null;

  Folder copyWith({
    OwnerId? ownerId,
    FolderId? parentId,
    bool clearParentId = false,
    String? name,
    int? colorArgb,
    bool clearColor = false,
    String? icon,
    bool clearIcon = false,
    String? sortKey,
    EpochMillis? updatedAt,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    String? trashRootId,
    bool clearTrashRootId = false,
    Hlc? version,
  }) => Folder(
    id: id,
    ownerId: ownerId ?? this.ownerId,
    parentId: clearParentId ? null : parentId ?? this.parentId,
    name: name ?? this.name,
    colorArgb: clearColor ? null : colorArgb ?? this.colorArgb,
    icon: clearIcon ? null : icon ?? this.icon,
    sortKey: sortKey ?? this.sortKey,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    trashRootId: clearTrashRootId ? null : trashRootId ?? this.trashRootId,
    version: version ?? this.version,
  );

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'ownerId': ownerId,
    'parentId': parentId,
    'name': name,
    'color': colorArgb,
    'icon': icon,
    'sortKey': sortKey,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
    'trashRootId': trashRootId,
    'version': version?.toString(),
  };

  factory Folder.fromJson(Map<String, Object?> json) => Folder(
    id: readString(json, 'id'),
    ownerId: readString(json, 'ownerId'),
    parentId: readStringOrNull(json, 'parentId'),
    name: readString(json, 'name'),
    colorArgb: readIntOrNull(json, 'color'),
    icon: readStringOrNull(json, 'icon'),
    sortKey: readString(json, 'sortKey'),
    createdAt: readInt(json, 'createdAt'),
    updatedAt: readInt(json, 'updatedAt'),
    deletedAt: readIntOrNull(json, 'deletedAt'),
    trashRootId: readStringOrNull(json, 'trashRootId'),
    version: readVersion(json),
  );

  @override
  bool operator ==(Object other) =>
      other is Folder &&
      other.id == id &&
      other.ownerId == ownerId &&
      other.parentId == parentId &&
      other.name == name &&
      other.colorArgb == colorArgb &&
      other.icon == icon &&
      other.sortKey == sortKey &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt &&
      other.trashRootId == trashRootId &&
      other.version == version;

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    parentId,
    name,
    colorArgb,
    icon,
    sortKey,
    createdAt,
    updatedAt,
    deletedAt,
    trashRootId,
    version,
  );

  @override
  String toString() =>
      'Folder($id, "$name", parent: $parentId${isDeleted ? ', deleted' : ''})';
}
