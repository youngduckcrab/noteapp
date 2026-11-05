// lib/src/model/page.dart — contract 00-overview 7.2.5 / CORE 4.2.3.
import 'package:meta/meta.dart';

import '../common/hlc.dart';
import '../common/ids.dart';
import '../common/json_read.dart';
import 'page_background.dart';
import 'page_size.dart';
import 'sync_entity.dart';

@immutable
final class Page implements SyncEntity {
  const Page({
    required this.id,
    required this.noteId,
    required this.sortKey,
    required this.size,
    required this.background,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.version,
    this.contentRevision = 0,
  });

  @override
  final PageId id;
  final NoteId noteId;
  final String sortKey;
  final PageSize size;
  final PageBackground background;
  final EpochMillis createdAt, updatedAt;
  @override
  final EpochMillis? deletedAt;
  @override
  final Hlc? version;

  /// Local only. Incremented on every content change of this page (local or
  /// remote). Used to validate thumbnails.
  final int contentRevision;

  @override
  EntityKind get kind => EntityKind.page;
  @override
  bool get isDeleted => deletedAt != null;

  Page copyWith({
    String? sortKey,
    PageSize? size,
    PageBackground? background,
    EpochMillis? updatedAt,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    Hlc? version,
    int? contentRevision,
  }) => Page(
    id: id,
    noteId: noteId,
    sortKey: sortKey ?? this.sortKey,
    size: size ?? this.size,
    background: background ?? this.background,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    version: version ?? this.version,
    contentRevision: contentRevision ?? this.contentRevision,
  );

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'noteId': noteId,
    'sortKey': sortKey,
    'size': size.toJson(),
    'background': background.toJson(),
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
    'version': version?.toString(),
  };

  /// contentRevision is local only: always 0 here (CORE 6.3).
  factory Page.fromJson(Map<String, Object?> json) => Page(
    id: readString(json, 'id'),
    noteId: readString(json, 'noteId'),
    sortKey: readString(json, 'sortKey'),
    size: PageSize.fromJson(json['size']),
    background: PageBackground.fromJson(readMap(json, 'background')),
    createdAt: readInt(json, 'createdAt'),
    updatedAt: readInt(json, 'updatedAt'),
    deletedAt: readIntOrNull(json, 'deletedAt'),
    version: readVersion(json),
  );

  @override
  bool operator ==(Object other) =>
      other is Page &&
      other.id == id &&
      other.noteId == noteId &&
      other.sortKey == sortKey &&
      other.size == size &&
      other.background == background &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt &&
      other.version == version &&
      other.contentRevision == contentRevision;

  @override
  int get hashCode => Object.hash(
    id,
    noteId,
    sortKey,
    size,
    background,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    contentRevision,
  );

  @override
  String toString() =>
      'Page($id, note: $noteId, key: $sortKey, rev: $contentRevision'
      '${isDeleted ? ', deleted' : ''})';
}
